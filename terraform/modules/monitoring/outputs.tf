# =============================================================================
# Monitoring Module  -  Outputs
#
# Exposes SNS topic ARN (for alarm notifications), CloudTrail ARN (for
# compliance reference), and ALB access logs bucket ID (passed back to root
# so root can enable access_logs on the ALB when enable_alb_access_logs=true).
# =============================================================================

output "sns_alarms_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail for management event auditing"
  value       = aws_cloudtrail.main.arn
}

