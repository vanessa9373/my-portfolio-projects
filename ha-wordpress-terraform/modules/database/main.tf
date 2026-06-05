locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── DATABASE CREDENTIALS ─────────────────────────────────────────────────────

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name        = "${local.name_prefix}/rds/credentials"
  description = "WordPress RDS MySQL credentials"
  kms_key_id  = var.kms_key_id

  recovery_window_in_days = var.deletion_protection ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 3306
    dbname   = var.db_name
  })
}

# ─── RDS PARAMETER GROUP ──────────────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  name   = "${local.name_prefix}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "log_queries_not_using_indexes"
    value = "1"
  }

  parameter {
    name  = "max_connections"
    value = "500"
  }

  parameter {
    name  = "innodb_buffer_pool_size"
    value = "{DBInstanceClassMemory*3/4}"  # Use 75% of memory for InnoDB buffer
  }

  tags = { Name = "${local.name_prefix}-mysql8-params" }
}

# ─── RDS OPTION GROUP ─────────────────────────────────────────────────────────

resource "aws_db_option_group" "main" {
  name                     = "${local.name_prefix}-mysql8"
  option_group_description = "WordPress MySQL 8.0 options"
  engine_name              = "mysql"
  major_engine_version     = "8.0"

  tags = { Name = "${local.name_prefix}-mysql8-options" }
}

# ─── RDS SUBNET GROUP ─────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = { Name = "${local.name_prefix}-db-subnet-group" }
}

# ─── RDS MYSQL MULTI-AZ ───────────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"

  # Engine
  engine               = "mysql"
  engine_version       = "8.0.39"
  instance_class       = var.db_instance_class
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Storage — gp3 is cheaper and faster than gp2
  allocated_storage     = 50
  max_allocated_storage = 500  # Auto-scaling storage up to 500 GB
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  # High Availability
  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_security_group_id]

  # Backup & Recovery
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"        # 3 AM UTC — low traffic
  maintenance_window      = "sun:04:00-sun:05:00" # Sunday 4 AM UTC
  copy_tags_to_snapshot   = true

  # Monitoring
  monitoring_interval          = 60  # Enhanced monitoring every 60s
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  # Protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${local.name_prefix}-final-snapshot" : null

  # Upgrades
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  tags = { Name = "${local.name_prefix}-mysql" }
}

# ─── RDS ENHANCED MONITORING ROLE ────────────────────────────────────────────

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─── AUTOMATED BACKUPS WITH AWS BACKUP ───────────────────────────────────────

resource "aws_backup_vault" "main" {
  name        = "${local.name_prefix}-backup-vault"
  kms_key_arn = var.kms_key_id
}

resource "aws_backup_plan" "main" {
  name = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily-backup-30-day-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM UTC daily

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = {
      BackupType = "Automated"
    }
  }

  rule {
    rule_name         = "weekly-backup-3-month-retention"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)"  # Sunday 3 AM UTC

    lifecycle {
      delete_after = 90
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "rds" {
  name         = "${local.name_prefix}-rds-backup"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.main.id

  resources = [aws_db_instance.main.arn]
}
