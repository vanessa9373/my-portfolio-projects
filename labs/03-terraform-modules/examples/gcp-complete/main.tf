# ============================================================
# GCP Complete Example — Using All GCP Modules Together
# Author: Jenella Awo
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  tags = {
    project     = var.project_name
    environment = var.environment
    managed-by  = "terraform"
  }
}

# --- Networking ---
module "vpc" {
  source       = "../../modules/gcp/vpc"
  project_name = var.project_name
  project_id   = var.project_id
  region       = var.region
  subnets = [
    {
      name   = "gke"
      cidr   = "10.0.0.0/20"
      region = var.region
      secondary_ranges = [
        { range_name = "gke-pods",     ip_cidr_range = "10.4.0.0/14" },
        { range_name = "gke-services", ip_cidr_range = "10.8.0.0/20" },
      ]
    },
    {
      name             = "database"
      cidr             = "10.0.16.0/24"
      region           = var.region
      secondary_ranges = []
    },
    {
      name             = "serverless"
      cidr             = "10.0.17.0/24"
      region           = var.region
      secondary_ranges = []
    },
  ]
  enable_nat     = true
  enable_flow_logs = true
  tags           = local.tags
}

# --- GKE Cluster ---
module "gke" {
  source             = "../../modules/gcp/gke"
  project_name       = var.project_name
  project_id         = var.project_id
  region             = var.region
  network            = module.vpc.network_self_link
  subnetwork         = module.vpc.subnet_self_links["gke"]
  pods_range_name    = "gke-pods"
  services_range_name = "gke-services"
  master_cidr        = "172.16.0.0/28"
  release_channel    = "REGULAR"
  enable_private_nodes = true
  node_pools = [
    {
      name         = "system"
      machine_type = "e2-standard-4"
      min_count    = 1
      max_count    = 3
      disk_size    = 100
      preemptible  = false
      labels       = { role = "system" }
    },
    {
      name         = "workload"
      machine_type = "e2-standard-8"
      min_count    = 2
      max_count    = 10
      disk_size    = 200
      preemptible  = false
      labels       = { role = "workload" }
    },
    {
      name         = "batch"
      machine_type = "e2-standard-4"
      min_count    = 0
      max_count    = 20
      disk_size    = 100
      preemptible  = true
      labels       = { role = "batch" }
    },
  ]
  tags = local.tags
}

# --- Cloud SQL ---
module "cloud_sql" {
  source            = "../../modules/gcp/cloud-sql"
  project_name      = var.project_name
  project_id        = var.project_id
  region            = var.region
  database_version  = "POSTGRES_15"
  tier              = "db-custom-4-16384"
  disk_size         = 50
  availability_type = "REGIONAL"
  enable_private_ip = true
  network           = module.vpc.network_self_link
  backup_enabled    = true
  pitr_enabled      = true
  database_flags = {
    "log_checkpoints"       = "on"
    "log_connections"       = "on"
    "log_disconnections"    = "on"
    "log_min_duration_statement" = "1000"
  }
  tags = local.tags
}

# --- Cloud Storage ---
module "cloud_storage" {
  source          = "../../modules/gcp/cloud-storage"
  project_name    = var.project_name
  project_id      = var.project_id
  bucket_name     = "${var.project_name}-assets"
  location        = "US"
  storage_class   = "STANDARD"
  enable_versioning = true
  uniform_access  = true
  lifecycle_rules = [
    {
      action    = { type = "SetStorageClass", storage_class = "NEARLINE" }
      condition = { age = 30 }
    },
    {
      action    = { type = "SetStorageClass", storage_class = "COLDLINE" }
      condition = { age = 90 }
    },
    {
      action    = { type = "Delete" }
      condition = { age = 365 }
    },
  ]
  tags = local.tags
}

# --- IAM ---
module "app_service_account" {
  source               = "../../modules/gcp/iam"
  project_name         = var.project_name
  project_id           = var.project_id
  service_account_name = "app-workload"
  display_name         = "Application Workload Identity"
  roles = [
    "roles/cloudsql.client",
    "roles/storage.objectViewer",
    "roles/secretmanager.secretAccessor",
  ]
  tags = local.tags
}

# --- Artifact Registry ---
module "artifact_registry" {
  source          = "../../modules/gcp/artifact-registry"
  project_name    = var.project_name
  project_id      = var.project_id
  region          = var.region
  repository_name = "docker"
  format          = "DOCKER"
  iam_members = [
    { role = "roles/artifactregistry.reader", member = "serviceAccount:${module.app_service_account.service_account_email}" },
  ]
  tags = local.tags
}

# --- Memorystore (Redis) ---
module "redis" {
  source              = "../../modules/gcp/memorystore"
  project_name        = var.project_name
  project_id          = var.project_id
  region              = var.region
  tier                = "STANDARD_HA"
  memory_size_gb      = 2
  authorized_network  = module.vpc.network_self_link
  auth_enabled        = true
  transit_encryption  = true
  tags                = local.tags
}

# --- Cloud DNS ---
module "dns" {
  source       = "../../modules/gcp/cloud-dns"
  project_name = var.project_name
  project_id   = var.project_id
  domain_name  = var.domain_name
  enable_dnssec = true
  records = [
    { name = "app", type = "A",     ttl = 300, rrdatas = ["34.120.0.1"] },
    { name = "api", type = "CNAME", ttl = 300, rrdatas = ["api.${var.domain_name}."] },
  ]
  tags = local.tags
}

# --- Cloud Run ---
module "api_service" {
  source        = "../../modules/gcp/cloud-run"
  project_name  = var.project_name
  project_id    = var.project_id
  region        = var.region
  service_name  = "api"
  image         = "${var.region}-docker.pkg.dev/${var.project_id}/${module.artifact_registry.repository_name}/api:latest"
  cpu           = "2"
  memory        = "1Gi"
  min_instances = 1
  max_instances = 50
  environment_variables = {
    DB_HOST     = module.cloud_sql.private_ip
    REDIS_HOST  = module.redis.host
    ENVIRONMENT = var.environment
  }
  service_account_email = module.app_service_account.service_account_email
  allow_unauthenticated = false
  tags                  = local.tags
}

# --- Pub/Sub ---
module "events" {
  source       = "../../modules/gcp/pub-sub"
  project_name = var.project_name
  project_id   = var.project_id
  topic_name   = "app-events"
  subscriptions = [
    {
      name              = "worker"
      push_endpoint     = null
      ack_deadline      = 60
      message_retention = "604800s"
      retry_policy = {
        minimum_backoff = "10s"
        maximum_backoff = "600s"
      }
    },
  ]
  enable_dead_letter = true
  tags               = local.tags
}

# --- Load Balancer ---
module "lb" {
  source       = "../../modules/gcp/load-balancer"
  project_name = var.project_name
  project_id   = var.project_id
  domain_name  = var.domain_name
  backends = [
    {
      name              = "web"
      group             = module.gke.cluster_id
      port              = 80
      protocol          = "HTTP"
      health_check_path = "/healthz"
    },
  ]
  enable_cdn = true
  tags       = local.tags
}

# --- Variables ---
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "demo-app"
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Domain name"
  type        = string
  default     = "example.com"
}

# --- Outputs ---
output "gke_cluster_name"    { value = module.gke.cluster_name }
output "gke_endpoint"        { value = module.gke.cluster_endpoint }
output "cloud_sql_ip"        { value = module.cloud_sql.private_ip }
output "storage_bucket"      { value = module.cloud_storage.bucket_url }
output "registry_url"        { value = module.artifact_registry.repository_url }
output "redis_host"          { value = module.redis.host }
output "api_service_url"     { value = module.api_service.service_url }
output "lb_ip_address"       { value = module.lb.lb_ip_address }
