# ============================================================
# Complete Example — Using All Modules Together
# Author: Jenella Awo
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source       = "../../modules/vpc"
  project_name = "demo-app"
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 2
}

module "eks" {
  source        = "../../modules/eks"
  project_name  = "demo-app"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.private_subnet_ids
  desired_nodes = 2
  max_nodes     = 5
}

output "vpc_id" { value = module.vpc.vpc_id }
output "eks_endpoint" { value = module.eks.cluster_endpoint }
