# =============================================================================
# CDN Module  -  Outputs
# =============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID  -  for cache invalidation (CI/CD) and console lookup"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN  -  for WAF association (already attached) and monitoring"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (e.g. d1234.cloudfront.net)  -  use for DNS alias target or direct access"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN (us-east-1)  -  for monitoring and Phase 10 CloudWatch metrics"
  value       = aws_wafv2_web_acl.cloudfront.arn
}
