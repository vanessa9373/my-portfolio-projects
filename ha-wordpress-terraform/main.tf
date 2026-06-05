terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "vanessa-terraform-state"
    key            = "ha-wordpress/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = "Vanessa Awo"
      ManagedBy   = "Terraform"
      CostCenter  = "Engineering"
    }
  }
}

# Second provider for us-east-1 (required for ACM certs used with CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = "Vanessa Awo"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ─── MODULES ──────────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

module "compute" {
  source = "./modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.security.alb_sg_id
  ec2_security_group_id = module.security.ec2_sg_id
  instance_type         = var.instance_type
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity
  certificate_arn       = module.security.acm_cert_arn
  db_host               = module.database.db_endpoint
  db_name               = var.db_name
  db_secret_arn         = module.database.db_secret_arn
  s3_bucket_name        = module.cdn.s3_bucket_name
  key_name              = var.ec2_key_pair_name
  account_id            = data.aws_caller_identity.current.account_id
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  environment           = var.environment
  database_subnet_ids   = module.vpc.database_subnet_ids
  db_security_group_id  = module.security.db_sg_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_instance_class     = var.db_instance_class
  multi_az              = true
  deletion_protection   = var.environment == "prod" ? true : false
  backup_retention_days = var.environment == "prod" ? 30 : 7
  kms_key_id            = module.security.kms_key_id
}

module "cdn" {
  source = "./modules/cdn"

  project_name     = var.project_name
  environment      = var.environment
  alb_dns_name     = module.compute.alb_dns_name
  alb_zone_id      = module.compute.alb_zone_id
  domain_name      = var.domain_name
  certificate_arn  = module.security.acm_cert_arn
  waf_acl_arn      = module.security.waf_acl_arn
  account_id       = data.aws_caller_identity.current.account_id
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name       = var.project_name
  environment        = var.environment
  alb_arn_suffix     = module.compute.alb_arn_suffix
  asg_name           = module.compute.asg_name
  db_identifier      = module.database.db_identifier
  alert_email        = var.alert_email
  account_id         = data.aws_caller_identity.current.account_id
  region             = data.aws_region.current.name
}
