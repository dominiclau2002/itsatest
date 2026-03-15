# =============================================================================
# Compute Module
#
# Contains: ECR repositories, CloudWatch log groups, ECS cluster, ALB,
# target groups, listener + rules, ECS task definitions, ECS services.
#
# Architecture: Single shared ECS cluster, two services (Account + Client),
# each running primary (AZ-1a) and secondary (AZ-1b) tasks behind one ALB.
# Path-based routing: /api/accounts/* → Account Service, /api/clients/* → Client.
# =============================================================================


# =============================================================================
# Module-Level Locals
#
# Recomputed from project_name + environment (same formulas as root locals.tf).
# Modules do not inherit root locals  -  must be defined locally.
# =============================================================================

locals {
  ecr_repo_account_name = "${var.project_name}-${var.environment}-account-service"
  ecr_repo_client_name  = "${var.project_name}-${var.environment}-client-service"
  log_group_ecs_account = "/ecs/${var.project_name}-${var.environment}-account-service"
  log_group_ecs_client  = "/ecs/${var.project_name}-${var.environment}-client-service"
  ecs_cluster_name      = "${var.project_name}-${var.environment}-ecs-cluster"
  alb_name              = "${var.project_name}-${var.environment}-alb"
}


# =============================================================================
# ECR Repositories
#
# One repository per service. Images are immutable  -  once a tag is pushed it
# cannot be overwritten, preventing accidental rollback-via-retag. Lifecycle
# policy trims untagged layers to bound storage costs.
# =============================================================================

# Account Service container image registry
resource "aws_ecr_repository" "account_service" {
  name                 = local.ecr_repo_account_name
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting tagged images; forces new tag per deploy

  image_scanning_configuration {
    scan_on_push = true # Vulnerability scan on every push; findings visible in ECR console
  }

  encryption_configuration {
    # KMS encryption using the shared S3 CMK  -  ECR stores image layers as S3 objects under the hood;
    # reusing the S3 KMS key avoids an extra key while satisfying CKV_AWS_136 (KMS requirement).
    encryption_type = "KMS"
    kms_key         = var.kms_s3_arn
  }

  force_delete = false # Prevent accidental repo deletion when images exist

  tags = {
    Name      = local.ecr_repo_account_name
    Component = "ecr"
  }
}

# Client Service container image registry
resource "aws_ecr_repository" "client_service" {
  name                 = local.ecr_repo_client_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_s3_arn
  }

  force_delete = false

  tags = {
    Name      = local.ecr_repo_client_name
    Component = "ecr"
  }
}


# =============================================================================
# ECR Lifecycle Policies
#
# Retains last 10 untagged image layers and expires older ones automatically.
# Tagged images (production releases) are never expired by this rule.
# =============================================================================

# Lifecycle policy for Account Service ECR repository
resource "aws_ecr_lifecycle_policy" "account_service" {
  repository = aws_ecr_repository.account_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 10 count"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lifecycle policy for Client Service ECR repository
resource "aws_ecr_lifecycle_policy" "client_service" {
  repository = aws_ecr_repository.client_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 10 count"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


# =============================================================================
# CloudWatch Log Groups
#
# Pre-created with explicit retention. ECS task definitions reference these
# log group names via awslogs driver. Without pre-creation, Fargate would
# auto-create groups with no retention policy (unbounded log accumulation).
# =============================================================================

# Log group for Account Service container stdout/stderr
resource "aws_cloudwatch_log_group" "ecs_account" {
  name              = local.log_group_ecs_account
  retention_in_days = var.ecs_log_retention_days
  kms_key_id        = var.kms_cloudwatch_arn # Encrypts log data at rest with CMK (CKV_AWS_158)

  tags = {
    Name      = local.log_group_ecs_account
    Component = "ecs-logs"
  }
}

# Log group for Client Service container stdout/stderr
resource "aws_cloudwatch_log_group" "ecs_client" {
  name              = local.log_group_ecs_client
  retention_in_days = var.ecs_log_retention_days
  kms_key_id        = var.kms_cloudwatch_arn

  tags = {
    Name      = local.log_group_ecs_client
    Component = "ecs-logs"
  }
}


# =============================================================================
# ECS Cluster
#
# Single shared cluster for all CRM services (Account + Client). Container
# Insights enabled for service-level metrics (CPU, memory, network) visible
# in CloudWatch without custom metric instrumentation.
# =============================================================================

# Shared ECS Fargate cluster for Account and Client services
resource "aws_ecs_cluster" "main" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled" # Enables per-task CPU/memory/network metrics in CloudWatch
  }

  tags = {
    Name      = local.ecs_cluster_name
    Component = "ecs"
  }
}

# Attach FARGATE capacity provider to the cluster as the sole and default provider.
# FARGATE_SPOT deliberately excluded  -  spot interruptions are incompatible with
# the HA and zero-trust requirements of the CRM system.
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}


# =============================================================================
# Application Load Balancer
#
# Internet-facing ALB in public subnets. Receives traffic from CloudFront
# (Phase 9) restricted via CloudFront managed prefix list on the ALB SG.
# HTTP only for now  -  HTTPS listener with ACM certificate added in Phase 9.
# =============================================================================

# Internet-facing ALB serving as the single ingress point for ECS services
resource "aws_lb" "main" {
  name               = local.alb_name
  internal           = false # Internet-facing; CloudFront sits in front (Phase 9)
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = [var.public_subnet_1_id, var.public_subnet_2_id]

  enable_deletion_protection = var.alb_deletion_protection # Set true in prod tfvars

  # CKV_AWS_91: ALB access logs delivered to the pre-created S3 bucket in the storage module.
  # Bucket is created in storage (not monitoring) to avoid a circular dependency:
  # monitoring depends on compute for alarm dimensions; compute cannot depend on monitoring.
  access_logs {
    bucket  = var.alb_logs_bucket_name
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name      = local.alb_name
    Component = "alb"
  }
}


# =============================================================================
# ALB Target Groups
#
# One target group per service. target_type = "ip" is required for Fargate
# awsvpc networking  -  tasks register their ENI IP directly (not the host EC2 IP).
# Names are abbreviated to stay within the 32-character AWS limit.
# =============================================================================

# Target group for Account Service tasks  -  all primary + secondary tasks share one TG
resource "aws_lb_target_group" "account" {
  name        = "${var.project_name}-${var.environment}-tg-acct"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip" # Required for Fargate awsvpc  -  tasks register ENI IPs
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-tg-acct"
    Component = "alb"
  }
}

# Target group for Client Service tasks  -  all primary + secondary tasks share one TG
resource "aws_lb_target_group" "client" {
  name        = "${var.project_name}-${var.environment}-tg-clnt"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-tg-clnt"
    Component = "alb"
  }
}


# =============================================================================
# ALB Listener  -  HTTP
#
# HTTP:80 listener with a default 404 fixed response. All valid traffic is
# matched by path-based rules below. HTTPS listener (port 443 with ACM cert)
# will replace this as the primary listener in Phase 9 when CloudFront and
# Route 53 are configured. This listener will then become a redirect to HTTPS.
# =============================================================================

# HTTP listener  -  default action returns 404 for unmatched paths
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # When no domain configured: return 404 for all unmatched paths
  # When domain configured: redirect all HTTP traffic to HTTPS (301 permanent)
  dynamic "default_action" {
    for_each = var.domain_name == "" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.domain_name != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-http-listener"
    Component = "alb"
  }
}

# HTTPS listener  -  created only when a custom domain + ACM cert are provided.
# Uses TLS 1.3-preferred policy (also supports TLS 1.2). Default action returns
# 404 for unmatched paths; path-based rules below route to correct targets.
resource "aws_lb_listener" "https" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_alb_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-https-listener"
    Component = "alb"
  }
}


# =============================================================================
# ALB Listener Rules  -  Path-Based Routing
#
# Routes API traffic to the correct service target group by path prefix.
# Priority ordering: Account (100) evaluated before Client (200).
# Any path not matching either rule falls through to the listener default (404).
# =============================================================================

# Route /api/accounts/* traffic to Account Service  -  HTTP listener rule
# (renamed from aws_lb_listener_rule.account; requires terraform state mv before apply)
resource "aws_lb_listener_rule" "account_http" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/accounts/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.account.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-account-http"
    Component = "alb"
  }
}

# Route /api/accounts/* traffic to Account Service  -  HTTPS listener rule (when domain configured)
resource "aws_lb_listener_rule" "account_https" {
  count        = var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api/accounts/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.account.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-account-https"
    Component = "alb"
  }
}

# Route /api/clients/*/verify to Verification Lambda  -  HTTP listener rule (priority 150, before /api/clients/*)
resource "aws_lb_listener_rule" "verification_http" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 150

  condition {
    path_pattern {
      values = ["/api/clients/*/verify"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.verification_lambda.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-verification-http"
    Component = "alb"
  }
}

# Route /api/clients/*/verify to Verification Lambda  -  HTTPS listener rule (when domain configured)
resource "aws_lb_listener_rule" "verification_https" {
  count        = var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 150

  condition {
    path_pattern {
      values = ["/api/clients/*/verify"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.verification_lambda.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-verification-https"
    Component = "alb"
  }
}

# Route /api/clients/* traffic to Client Service  -  HTTP listener rule (priority 200, after verification at 150)
# (renamed from aws_lb_listener_rule.client; requires terraform state mv before apply)
resource "aws_lb_listener_rule" "client_http" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  condition {
    path_pattern {
      values = ["/api/clients/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-client-http"
    Component = "alb"
  }
}

# Route /api/clients/* traffic to Client Service  -  HTTPS listener rule (when domain configured)
resource "aws_lb_listener_rule" "client_https" {
  count        = var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  condition {
    path_pattern {
      values = ["/api/clients/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.client.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-client-https"
    Component = "alb"
  }
}

# Route /api/users/* traffic to User Lambda  -  HTTP listener rule (priority 300)
resource "aws_lb_listener_rule" "user_http" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  condition {
    path_pattern {
      values = ["/api/users/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_lambda.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-user-http"
    Component = "alb"
  }
}

# Route /api/users/* traffic to User Lambda  -  HTTPS listener rule (when domain configured)
resource "aws_lb_listener_rule" "user_https" {
  count        = var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 300

  condition {
    path_pattern {
      values = ["/api/users/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.user_lambda.arn
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-rule-user-https"
    Component = "alb"
  }
}


# =============================================================================
# ALB Lambda Target Groups  -  Phase 9
#
# Lambda target groups route ALB requests directly to Lambda functions without
# going through ECS. target_type = "lambda" means no vpc_id, port, or protocol
# are needed. Each Lambda must grant the ALB (via aws_lambda_permission) the
# right to invoke it, scoped to the specific target group ARN.
#
# Target group name limits: 32 characters
#   verification: ${project}-${env}-tg-vrfy (31 chars max for itsa-testing-setup-dev)
#   user:         ${project}-${env}-tg-user (30 chars max for itsa-testing-setup-dev)
# =============================================================================

# Lambda target group for Verification Lambda  -  handles /api/clients/*/verify
resource "aws_lb_target_group" "verification_lambda" {
  name        = "${var.project_name}-${var.environment}-tg-vrfy"
  target_type = "lambda" # No vpc_id/port/protocol for Lambda targets

  tags = {
    Name      = "${var.project_name}-${var.environment}-tg-vrfy"
    Component = "alb"
  }
}

# Register Verification Lambda as the target (by ARN, not IP)
resource "aws_lb_target_group_attachment" "verification" {
  target_group_arn = aws_lb_target_group.verification_lambda.arn
  target_id        = var.lambda_verification_arn
  depends_on       = [aws_lambda_permission.alb_invoke_verification]
}

# Grant ALB permission to invoke Verification Lambda.
# source_arn scopes to the specific target group ARN  -  prevents other ALBs or
# target groups from invoking this Lambda without explicit permission.
resource "aws_lambda_permission" "alb_invoke_verification" {
  statement_id  = "AllowALBInvokeVerification"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_verification_arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.verification_lambda.arn
}

# Lambda target group for User Lambda  -  handles /api/users/*
resource "aws_lb_target_group" "user_lambda" {
  name        = "${var.project_name}-${var.environment}-tg-user"
  target_type = "lambda"

  tags = {
    Name      = "${var.project_name}-${var.environment}-tg-user"
    Component = "alb"
  }
}

# Register User Lambda as the target
resource "aws_lb_target_group_attachment" "user" {
  target_group_arn = aws_lb_target_group.user_lambda.arn
  target_id        = var.lambda_user_arn
  depends_on       = [aws_lambda_permission.alb_invoke_user]
}

# Grant ALB permission to invoke User Lambda
resource "aws_lambda_permission" "alb_invoke_user" {
  statement_id  = "AllowALBInvokeUser"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_user_arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.user_lambda.arn
}


# =============================================================================
# ECS Task Definitions
#
# Fargate task definitions are immutable  -  each apply creates a new revision.
# Environment variables carry non-sensitive config; Secrets Manager ARNs supply
# sensitive values via the `secrets` block (injected at container start by the
# ECS agent, never exposed in task definition JSON in plaintext).
#
# SQS_QUEUE_LOGGING_URL is a Phase 8 placeholder  -  left empty so containers
# can start now; the application must handle an empty value gracefully.
# =============================================================================

# Account Service task definition  -  DynamoDB + Redis, no RDS access
resource "aws_ecs_task_definition" "account" {
  family                   = "${var.project_name}-${var.environment}-account-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # Required for Fargate; each task gets its own ENI
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = var.iam_role_ecs_account_execution_arn # ECR pull + Secrets Manager inject
  task_role_arn            = var.iam_role_ecs_account_task_arn      # DynamoDB + SQS permissions at runtime

  container_definitions = jsonencode([
    {
      name      = "account-service"
      image     = var.container_image_account
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      # Non-sensitive configuration injected as environment variables
      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "APP_PORT", value = tostring(var.app_port) },
        { name = "COGNITO_USER_POOL_ID", value = var.cognito_user_pool_id },
        { name = "DYNAMODB_TABLE_ACCOUNTS", value = var.dynamodb_table_accounts_name },
        { name = "DYNAMODB_TABLE_TRANSACTIONS", value = var.dynamodb_table_transactions_name },
        { name = "REDIS_ENDPOINT", value = var.elasticache_account_endpoint },
        { name = "REDIS_PORT", value = tostring(var.elasticache_account_port) },
        { name = "REDIS_TLS_ENABLED", value = "true" },
        # SQS Logging queue URL from serverless module (Phase 8)
        { name = "SQS_QUEUE_LOGGING_URL", value = var.sqs_queue_logging_url }
      ]

      # Sensitive values fetched from Secrets Manager at container start by ECS agent
      secrets = [
        { name = "REDIS_AUTH_TOKEN", valueFrom = var.secret_redis_account_auth_arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_ecs_account
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name      = "${var.project_name}-${var.environment}-account-service"
    Component = "ecs-task"
  }
}

# Client Service task definition  -  RDS + Redis, no DynamoDB access
resource "aws_ecs_task_definition" "client" {
  family                   = "${var.project_name}-${var.environment}-client-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = var.iam_role_ecs_client_execution_arn # ECR pull + Secrets Manager inject
  task_role_arn            = var.iam_role_ecs_client_task_arn      # SQS permissions at runtime

  container_definitions = jsonencode([
    {
      name      = "client-service"
      image     = var.container_image_client
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = concat(
        [
          { name = "ENVIRONMENT", value = var.environment },
          { name = "AWS_REGION", value = var.aws_region },
          { name = "APP_PORT", value = tostring(var.app_port) },
          { name = "COGNITO_USER_POOL_ID", value = var.cognito_user_pool_id },
          { name = "REDIS_ENDPOINT", value = var.elasticache_client_endpoint },
          { name = "REDIS_PORT", value = tostring(var.elasticache_client_port) },
          { name = "REDIS_TLS_ENABLED", value = "true" },
          # SQS Logging queue URL from serverless module (Phase 8)
          { name = "SQS_QUEUE_LOGGING_URL", value = var.sqs_queue_logging_url },
        ],
        # Only inject RDS env vars when cluster exists (null when create_rds_cluster = false)
        var.rds_cluster_endpoint != null ? [
          { name = "RDS_ENDPOINT", value = var.rds_cluster_endpoint },
          { name = "RDS_PORT", value = tostring(var.rds_cluster_port) },
          { name = "RDS_DATABASE_NAME", value = var.rds_database_name },
          { name = "RDS_USERNAME", value = var.rds_master_username },
        ] : []
      )

      # RDS password and Redis AUTH token fetched from Secrets Manager at container start
      secrets = [
        { name = "RDS_PASSWORD", valueFrom = var.secret_rds_master_password_arn },
        { name = "REDIS_AUTH_TOKEN", valueFrom = var.secret_redis_client_auth_arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_ecs_client
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name      = "${var.project_name}-${var.environment}-client-service"
    Component = "ecs-task"
  }
}


# =============================================================================
# ECS Services
#
# Four services: primary + secondary for each of Account and Client.
# Primary tasks run in AZ-1a (private_app_subnet_1); secondary in AZ-1b
# (private_app_subnet_2). Both primary and secondary register into the same
# target group per service  -  the ALB distributes requests across all healthy
# tasks regardless of AZ.
#
# desired_count = 1 per service instance is intentional for dev; scale up
# via tfvars or autoscaling policy in prod.
#
# depends_on = [aws_lb_listener.http] ensures the listener and its default
# action exist before ECS attempts to register targets. Without this, the
# service may fail to stabilize during first apply.
# =============================================================================

# Account Service  -  primary task in AZ-1a
resource "aws_ecs_service" "account_primary" {
  name                 = "${var.project_name}-${var.environment}-account-primary"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.account.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true # Ensures task replacement on task definition revision change

  network_configuration {
    subnets          = [var.private_app_subnet_1_id] # AZ-1a only
    security_groups  = [var.sg_ecs_account_primary_id]
    assign_public_ip = false # Tasks in private subnets reach internet via NAT Gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.account.arn
    container_name   = "account-service"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https] # HTTP always; HTTPS when domain configured

  tags = {
    Name      = "${var.project_name}-${var.environment}-account-primary"
    Component = "ecs-service"
  }
}

# Account Service  -  secondary task in AZ-1b for HA
resource "aws_ecs_service" "account_secondary" {
  name                 = "${var.project_name}-${var.environment}-account-secondary"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.account.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = [var.private_app_subnet_2_id] # AZ-1b only
    security_groups  = [var.sg_ecs_account_secondary_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.account.arn
    container_name   = "account-service"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]

  tags = {
    Name      = "${var.project_name}-${var.environment}-account-secondary"
    Component = "ecs-service"
  }
}

# Client Service  -  primary task in AZ-1a
resource "aws_ecs_service" "client_primary" {
  name                 = "${var.project_name}-${var.environment}-client-primary"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.client.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = [var.private_app_subnet_1_id] # AZ-1a only
    security_groups  = [var.sg_ecs_client_primary_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.client.arn
    container_name   = "client-service"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]

  tags = {
    Name      = "${var.project_name}-${var.environment}-client-primary"
    Component = "ecs-service"
  }
}

# Client Service  -  secondary task in AZ-1b for HA
resource "aws_ecs_service" "client_secondary" {
  name                 = "${var.project_name}-${var.environment}-client-secondary"
  cluster              = aws_ecs_cluster.main.id
  task_definition      = aws_ecs_task_definition.client.arn
  desired_count        = 1
  launch_type          = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = [var.private_app_subnet_2_id] # AZ-1b only
    security_groups  = [var.sg_ecs_client_secondary_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.client.arn
    container_name   = "client-service"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]

  tags = {
    Name      = "${var.project_name}-${var.environment}-client-secondary"
    Component = "ecs-service"
  }
}


# =============================================================================
# ECS Application Auto Scaling  -  Phase 10
#
# Adds target-tracking scaling policies (CPU 60% target) to all 4 ECS services.
# Each service scales independently between ecs_min_capacity and ecs_max_capacity.
# Target-tracking is preferred over step scaling for ECS because AWS manages the
# scale-out and scale-in thresholds automatically.
#
# scale_in_cooldown = 300s: wait 5 min before scaling in after a spike subsides,
# preventing flapping when load oscillates around the threshold.
# scale_out_cooldown = 60s: scale out quickly (1 min) to absorb sudden load.
#
# resource_id format must be "service/<cluster-name>/<service-name>" exactly  - 
# any deviation causes silent scaling failure without a Terraform error.
# =============================================================================

# --- Account Service Primary (AZ-1a) ---

resource "aws_appautoscaling_target" "account_primary" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.account_primary.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.account_primary]
}

resource "aws_appautoscaling_policy" "account_primary_cpu" {
  name               = "${var.project_name}-${var.environment}-asp-account-primary"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.account_primary.resource_id
  scalable_dimension = aws_appautoscaling_target.account_primary.scalable_dimension
  service_namespace  = aws_appautoscaling_target.account_primary.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# --- Account Service Secondary (AZ-1b) ---

resource "aws_appautoscaling_target" "account_secondary" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.account_secondary.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.account_secondary]
}

resource "aws_appautoscaling_policy" "account_secondary_cpu" {
  name               = "${var.project_name}-${var.environment}-asp-account-secondary"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.account_secondary.resource_id
  scalable_dimension = aws_appautoscaling_target.account_secondary.scalable_dimension
  service_namespace  = aws_appautoscaling_target.account_secondary.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# --- Client Service Primary (AZ-1a) ---

resource "aws_appautoscaling_target" "client_primary" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.client_primary.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.client_primary]
}

resource "aws_appautoscaling_policy" "client_primary_cpu" {
  name               = "${var.project_name}-${var.environment}-asp-client-primary"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.client_primary.resource_id
  scalable_dimension = aws_appautoscaling_target.client_primary.scalable_dimension
  service_namespace  = aws_appautoscaling_target.client_primary.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# --- Client Service Secondary (AZ-1b) ---

resource "aws_appautoscaling_target" "client_secondary" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.client_secondary.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  depends_on         = [aws_ecs_service.client_secondary]
}

resource "aws_appautoscaling_policy" "client_secondary_cpu" {
  name               = "${var.project_name}-${var.environment}-asp-client-secondary"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.client_secondary.resource_id
  scalable_dimension = aws_appautoscaling_target.client_secondary.scalable_dimension
  service_namespace  = aws_appautoscaling_target.client_secondary.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
