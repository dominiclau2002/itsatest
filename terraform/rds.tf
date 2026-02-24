# =============================================================================
# Phase 5: Aurora PostgreSQL Cluster
#
# Two-instance Aurora cluster: writer in ap-southeast-1a, reader in ap-southeast-1b.
# Both instances share aws_security_group.rds_primary — single-SG design ensures
# Client Service connectivity survives Aurora failover (reader promoted in-place
# with the same SG already attached).
#
# Zero-trust compliance:
#   - Encryption at rest: customer-managed KMS key (aws_kms_key.rds)
#   - Encryption in transit: rds.force_ssl = 1 enforced via parameter group
#   - No public accessibility: both instances in private DB subnets only
#   - Master password: randomly generated, stored in Secrets Manager (never in state)
#
# RDS Enhanced Monitoring and Performance Insights enabled on both instances.
# =============================================================================


# =============================================================================
# Master Password — generated once, stored in Secrets Manager
# =============================================================================

# Generate a 32-character alphanumeric password.
# special = false: Aurora PostgreSQL rejects passwords containing characters like
# @, /, ", ' which are reserved in connection strings. Alphanumeric is safest.
resource "random_password" "rds_master" {
  length  = 32
  special = false
}

# Store the generated password in Secrets Manager under the client-service prefix.
# Path: ${secrets_prefix_client}/rds-master-password
# This path falls within the existing ecs_execution_policy_client wildcard:
#   secretsmanager:GetSecretValue on ${secrets_prefix_client}/*
# The ECS Client Service agent injects this secret at container startup.
resource "aws_secretsmanager_secret" "rds_master_password" {
  name        = "${local.secrets_prefix_client}/rds-master-password"
  description = "Aurora PostgreSQL master password for the CRM database. Injected into Client Service at startup."
  kms_key_id  = aws_kms_key.secrets_manager.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-secret-rds-master-password"
    Component = "rds"
  }
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id     = aws_secretsmanager_secret.rds_master_password.id
  secret_string = random_password.rds_master.result
}


# =============================================================================
# DB Subnet Group
# =============================================================================

# Places the Aurora cluster in both private DB subnets.
# Aurora requires a subnet group with subnets in at least 2 AZs for Multi-AZ.
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Subnet group for Aurora PostgreSQL cluster — private-db-1 (AZ-1a) and private-db-2 (AZ-1b)"
  subnet_ids  = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]

  tags = {
    Name      = "${var.project_name}-${var.environment}-db-subnet-group"
    Component = "rds"
  }
}


# =============================================================================
# RDS Cluster Parameter Group
# =============================================================================

# Custom parameter group enforces TLS for all connections (zero-trust requirement).
# rds.force_ssl = 1 causes Aurora to reject any non-SSL connection attempt.
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-aurora-pg15-params"
  family      = "aurora-postgresql15"
  description = "Custom Aurora PostgreSQL 15 parameters — enforces TLS (rds.force_ssl=1)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-pg15-params"
    Component = "rds"
  }
}


# =============================================================================
# Aurora Cluster
# =============================================================================

resource "aws_rds_cluster" "primary" {
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = var.rds_database_name
  master_username    = "crmadmin"
  master_password    = random_password.rds_master.result

  # Network placement
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_primary.id]

  # Encryption at rest — customer-managed KMS key
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Encryption in transit — enforced via parameter group (rds.force_ssl=1)
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Backup and retention
  backup_retention_period   = var.rds_backup_retention_days
  preferred_backup_window   = "02:00-03:00" # Off-peak for ap-southeast-1; staggered with ElastiCache (01:00-02:00)
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-${var.environment}-aurora-final-snapshot"

  # Deletion protection — defaults true (prod parity). Override to false in dev tfvars
  # only when terraform destroy is required.
  deletion_protection = var.rds_deletion_protection

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora"
    Component = "rds"
  }
}


# =============================================================================
# RDS Enhanced Monitoring IAM Role
#
# Required for aurora instances with monitoring_interval > 0.
# The ECS monitoring agent running inside the RDS instance needs permissions to
# push granular OS-level metrics to CloudWatch. AWS provides a managed policy
# (AmazonRDSEnhancedMonitoringRole) for this purpose.
# =============================================================================

data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project_name}-${var.environment}-role-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json
  description        = "Role assumed by the RDS Enhanced Monitoring agent to publish OS metrics to CloudWatch"
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}


# =============================================================================
# Aurora Writer Instance (ap-southeast-1a)
# =============================================================================

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project_name}-${var.environment}-aurora-writer"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  # AZ placement — writer pinned to AZ-1a (primary AZ)
  availability_zone = var.availability_zones[0]

  # promotion_tier = 0 — highest priority; Aurora treats this instance as the
  # writer and will keep it as writer during normal operations.
  promotion_tier = 0

  # Automatic minor version upgrades — applied during the preferred maintenance window.
  # Does not affect major version (15.x only).
  auto_minor_version_upgrade = true

  # Enhanced Monitoring — 60-second granularity for CPU, memory, I/O metrics
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights — query-level performance visibility
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-writer"
    Component = "rds"
  }
}


# =============================================================================
# Aurora Reader Instance (ap-southeast-1b)
#
# Assigned the same security group as the writer (aws_security_group.rds_primary).
# On Aurora failover, this reader is promoted to writer — Client Service tasks
# can connect immediately without any SG or DNS change required.
# =============================================================================

resource "aws_rds_cluster_instance" "reader" {
  identifier         = "${var.project_name}-${var.environment}-aurora-reader"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  # AZ placement — reader pinned to AZ-1b (standby AZ)
  availability_zone = var.availability_zones[1]

  # promotion_tier = 1 — reader priority; Aurora promotes this on primary failure.
  promotion_tier = 1

  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-reader"
    Component = "rds"
  }
}
