# ── Subnet Group ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-aurora-subnets"
  subnet_ids = var.isolated_subnets
  tags       = { Name = "${var.name_prefix}-aurora-subnet-group" }
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "aurora" {
  name   = "${var.name_prefix}-aurora-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_sg_ids
    description     = "PostgreSQL from ECS tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── Secrets Manager (DB credentials) ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}/aurora/credentials"
  recovery_window_in_days = 7
  description             = "NexaShop Aurora PostgreSQL master credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "nexashop_admin"
    password = random_password.db.result
    engine   = "postgres"
    host     = aws_rds_cluster.main.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── Aurora PostgreSQL Cluster ─────────────────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.name_prefix}-aurora"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  database_name           = var.database_name
  master_username         = "nexashop_admin"
  master_password         = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.name_prefix}-aurora-final"

  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [master_password]
  }
}

# ── Aurora Instances (writer + reader) ────────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_enhanced_monitoring.arn
}

resource "aws_rds_cluster_instance" "reader" {
  identifier         = "${var.name_prefix}-aurora-reader"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_enhanced_monitoring.arn
}

# ── Enhanced Monitoring Role ──────────────────────────────────────────────────
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.name_prefix}-rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
