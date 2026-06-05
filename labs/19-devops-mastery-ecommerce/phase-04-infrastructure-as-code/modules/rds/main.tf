module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 8.0"

  name           = "${var.project}-${var.environment}"
  engine         = "aurora-postgresql"
  engine_version = "15.4"
  instance_class = var.environment == "production" ? "db.r6g.large" : "db.t4g.medium"
  instances = {
    writer = {}
    reader = {}
  }

  vpc_id               = var.vpc_id
  db_subnet_group_name = var.db_subnet_group_name
  security_group_rules = {
    vpc_ingress = {
      cidr_blocks = var.private_subnet_cidrs
    }
  }

  storage_encrypted   = true
  apply_immediately   = var.environment != "production"
  monitoring_interval = 60

  enabled_cloudwatch_logs_exports = ["postgresql"]

  backup_retention_period = var.environment == "production" ? 35 : 7
  preferred_backup_window = "03:00-04:00"

  deletion_protection = var.environment == "production"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
