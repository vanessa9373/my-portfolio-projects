# ============================================================
# ElastiCache Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name suffix for the ElastiCache cluster (combined with project_name)"
  type        = string
}

variable "engine" {
  description = "Cache engine: redis or memcached"
  type        = string
  default     = "redis"

  validation {
    condition     = contains(["redis", "memcached"], var.engine)
    error_message = "engine must be either 'redis' or 'memcached'."
  }
}

variable "engine_version" {
  description = "Version number of the cache engine"
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "Instance type for cache nodes"
  type        = string
  default     = "cache.r7g.large"
}

variable "num_cache_nodes" {
  description = "Number of cache nodes (Memcached only)"
  type        = number
  default     = 2
}

variable "num_node_groups" {
  description = "Number of node groups (shards) for Redis cluster mode"
  type        = number
  default     = 1
}

variable "replicas_per_node_group" {
  description = "Number of replica nodes in each node group (Redis only)"
  type        = number
  default     = 1
}

variable "subnet_ids" {
  description = "List of subnet IDs for the cache subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the cache cluster"
  type        = list(string)
}

variable "at_rest_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "transit_encryption" {
  description = "Enable encryption in transit (Redis only)"
  type        = bool
  default     = true
}

variable "auth_token" {
  description = "Auth token for Redis (requires transit encryption; 16-128 characters)"
  type        = string
  default     = null
  sensitive   = true
}

variable "parameter_group_family" {
  description = "ElastiCache parameter group family (e.g., redis7, memcached1.6)"
  type        = string
  default     = "redis7"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
