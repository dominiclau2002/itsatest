# =============================================================================
# CDN Module
#
# Contains: CloudFront Origin Access Control (OAC), WAF Web ACL (CLOUDFRONT
# scope — must be in us-east-1), CloudFront distribution (dual-origin: S3
# static frontend + ALB API), S3 bucket policy granting OAC read access,
# and optional Route 53 alias records when a custom domain is provided.
#
# Provider aliases required:
#   aws           — default provider (ap-southeast-1) for S3 bucket policy + Route 53
#   aws.us_east_1 — WAF Web ACL scope=CLOUDFRONT must be created in us-east-1
#
# Architecture: CloudFront sits in front of both the React SPA (S3) and the
# backend API (ALB). Path-based routing: /api/* → ALB, default → S3.
# WAF protects against common exploits, SQLi, known bad inputs, and rate abuse.
# SPA routing: S3 returns 403 for missing objects in private buckets (not 404),
# so both 403 and 404 are mapped to /index.html for client-side routing.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.40"
      configuration_aliases = [aws.us_east_1]
    }
  }
}


# =============================================================================
# CloudFront Origin Access Control
#
# OAC replaces the legacy Origin Access Identity (OAI). It signs requests from
# CloudFront to S3 using SigV4, allowing S3 to validate that requests originate
# from this specific distribution and reject direct S3 URL access.
# =============================================================================

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-${var.environment}-oac-frontend"
  description                       = "OAC for CRM frontend S3 bucket — restricts S3 access to this CloudFront distribution only via SigV4 signing"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" # Sign every request; never pass unsigned requests to S3
  signing_protocol                  = "sigv4"
}


# =============================================================================
# WAF Web ACL — CloudFront Scope
#
# Must be created in us-east-1 (provider = aws.us_east_1) — CloudFront WAF
# associations only support Web ACLs in us-east-1, regardless of the
# CloudFront distribution's region. Using the default ap-southeast-1 provider
# here is a hard API error.
#
# Rules:
#   Priority 10: AWS Common Rule Set — blocks known exploit patterns (XSS, RFI, etc.)
#   Priority 20: Known Bad Inputs   — blocks Log4Shell, Spring4Shell, etc.
#   Priority 30: SQL Injection      — blocks SQLi patterns in request components
#   Priority 40: IP Rate Limit      — blocks IPs exceeding 2000 req/5min window
#
# Managed rule groups use override_action { none {} } (not action {}) — they
# have their own built-in actions per rule; override_action overrides those.
# Rate-based rules use action { block {} } since they are custom (not managed).
# =============================================================================

resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "${var.project_name}-${var.environment}-waf-cloudfront"
  description = "WAF Web ACL protecting CRM CloudFront distribution — Common rules, Known bad inputs, SQLi, IP rate limiting"
  scope       = "CLOUDFRONT" # Must match provider region (us-east-1)

  default_action {
    allow {
      # Allow by default; individual rules below block specific threats
    }
  }

  # Priority 10: AWS Common Rule Set — blocks OWASP Top 10 patterns
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {} # Respect per-rule actions within the managed group
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Priority 20: Known Bad Inputs — blocks Log4Shell, SSRF, Spring4Shell probes
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Priority 30: SQL Injection — blocks SQLi patterns in URI, query strings, body
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Priority 40: IP Rate Limit — blocks IPs sending more than 2000 requests per 5-minute window
  # Custom rule (not managed), so uses action { block {} } rather than override_action
  rule {
    name     = "IPRateLimit"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf-cloudfront"
    sampled_requests_enabled   = true
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-waf-cloudfront"
    Component = "waf"
  }
}


# =============================================================================
# CloudFront Distribution
#
# Dual-origin setup:
#   s3-frontend: serves the React SPA static assets from the private S3 bucket
#     via OAC (SigV4 signed requests).
#   alb-api: proxies /api/* requests to the ALB. Uses http-only when no custom
#     domain is configured, https-only when a domain (and ALB HTTPS listener)
#     is set up.
#
# Cache behaviour:
#   Default (→ S3): CachingOptimized managed policy — caches all S3 responses;
#     assets should be fingerprinted (e.g. main.abc123.js) for cache busting.
#   /api/* (→ ALB): CachingDisabled + AllViewerExceptHostHeader — no caching
#     for API responses; passes all headers except Host to the ALB (Host header
#     from CloudFront edge would cause ALB routing issues).
#
# SPA routing: S3 returns 403 AccessDenied (not 404 NoSuchKey) for missing
#   objects in private buckets. Both 403 and 404 map to /index.html so the
#   React Router can handle the path client-side.
# =============================================================================

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment} CRM frontend + API distribution"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  # Custom domain aliases — empty when no domain configured (uses CloudFront default cert)
  aliases = var.domain_name != "" ? [var.domain_name, "www.${var.domain_name}"] : []

  # --- Origin 1: S3 Frontend ---
  # OAC signs all requests; S3 bucket policy (below) validates the OAC ARN
  origin {
    origin_id                = "s3-frontend"
    domain_name              = var.s3_frontend_bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # --- Origin 2: ALB API ---
  # Custom origin config required for ALB (not S3). Protocol matches listener:
  # http-only until domain + ACM cert configured, then https-only.
  origin {
    origin_id   = "alb-api"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.domain_name != "" ? "https-only" : "http-only"
      # TLS 1.2+ enforced when using HTTPS origin (ALB uses TLS13-1-2-2021-06 policy)
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  # --- Default Cache Behaviour: S3 Frontend ---
  # CachingOptimized (AWS managed) caches S3 responses with compression.
  # redirect-to-https ensures all HTTP traffic is upgraded at the edge.
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    # CachingOptimized managed policy — optimised for static assets
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true # Gzip/Brotli compression at the edge for eligible content types
  }

  # --- Ordered Cache Behaviour: ALB API (/api/*) ---
  # Priority 0 (first ordered_cache_behavior) — evaluated before the default.
  # CachingDisabled + AllViewerExceptHostHeader: no caching; forward all viewer
  # headers except Host (CloudFront's Host header would override the ALB's
  # routing rules, causing 400/503 errors).
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    # CachingDisabled managed policy — all API responses bypass CloudFront cache
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # AllViewerExceptHostHeader — forwards all request headers/cookies/query strings
    # except Host; prevents CloudFront's synthetic Host from reaching the ALB
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

    compress = false # API responses are typically JSON; compression benefit is minimal
  }

  # --- SPA Error Handling ---
  # S3 returns 403 AccessDenied (not 404) for non-existent objects in private buckets.
  # Both error codes are remapped to /index.html so React Router handles the path.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  # --- Viewer Certificate ---
  # Single block using null-conditional attributes:
  #   No domain: cloudfront_default_certificate = true (CloudFront *.cloudfront.net cert)
  #   With domain: acm_certificate_arn set; TLS 1.2+ minimum; SNI only (no dedicated IP)
  viewer_certificate {
    cloudfront_default_certificate = var.domain_name == "" ? true : null
    acm_certificate_arn            = var.domain_name != "" && var.acm_cert_cloudfront_arn != "" ? var.acm_cert_cloudfront_arn : null
    ssl_support_method             = var.domain_name != "" ? "sni-only" : null
    minimum_protocol_version       = var.domain_name != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # No geo-blocking — global bank serves international clients
    }
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-cloudfront"
    Component = "cloudfront"
  }
}


# =============================================================================
# S3 Frontend Bucket Policy — OAC Access Grant
#
# Grants the CloudFront distribution read access to the frontend S3 bucket via
# OAC. The condition key "AWS:SourceArn" (capital AWS) is required — lowercase
# "aws:SourceArn" silently fails to match the OAC condition and blocks all
# CloudFront access. Resource includes trailing /* to scope to objects only
# (bucket-level actions are not needed by CloudFront for serving content).
# =============================================================================

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.s3_frontend_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOACRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.s3_frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            # "AWS:SourceArn" — capital AWS required; lowercase silently mismatches OAC condition
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}


# =============================================================================
# Route 53 Alias Records — Conditional on Custom Domain
#
# Created only when both domain_name and route53_zone_id are provided.
# Apex (bare domain) and www subdomain both point to the CloudFront distribution.
# CloudFront's hosted_zone_id (Z2FDTNDATAQYW2) is a fixed AWS constant.
# =============================================================================

resource "aws_route53_record" "apex" {
  count   = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count   = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
