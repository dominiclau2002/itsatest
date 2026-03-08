# =============================================================================
# CDN Module — Input Variables
# =============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (ap-southeast-1) — used for tagging context"
  type        = string
}

variable "s3_frontend_bucket_id" {
  description = "Frontend S3 bucket ID (name) — used in OAC bucket association"
  type        = string
}

variable "s3_frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN — scopes the OAC bucket policy"
  type        = string
}

variable "s3_frontend_bucket_domain_name" {
  description = "Frontend S3 bucket regional domain name (bucket_regional_domain_name) — required for OAC; do NOT use bucket_domain_name (global form causes 403)"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name — used as CloudFront API origin domain"
  type        = string
}

variable "alb_zone_id" {
  description = "ALB Route 53 hosted zone ID — not used in CDN module but passed through for root-level alias records"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Custom domain name for CloudFront (e.g. crm.example.com). Empty string disables custom domain, aliases, and ACM cert attachment."
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class controlling which edge locations serve content. PriceClass_All = global, PriceClass_200 = excl. South America & Australia, PriceClass_100 = NA + EU only."
  type        = string
  default     = "PriceClass_All"
}

variable "acm_cert_cloudfront_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront HTTPS. Required when domain_name is set. Empty string uses CloudFront default certificate."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for apex + www alias records. Required when domain_name is set."
  type        = string
  default     = ""
}
