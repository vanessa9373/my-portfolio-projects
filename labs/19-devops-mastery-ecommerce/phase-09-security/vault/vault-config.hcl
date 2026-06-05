# =============================================================================
# HashiCorp Vault Server Configuration
# E-Commerce Platform — Production Deployment
# =============================================================================
# This configuration defines a production-grade Vault server with:
#   - Consul storage backend for HA
#   - TLS-encrypted TCP listener
#   - AWS KMS auto-unseal
#   - Prometheus telemetry
#   - File-based audit logging
# =============================================================================

# ---------------------------------------------------------------------------
# Cluster Identity
# ---------------------------------------------------------------------------
cluster_name = "ecommerce-vault-cluster"
log_level    = "info"
ui           = true

# Disable the built-in memory lock warning; assumes mlock is configured at
# the OS level via systemd LimitMEMLOCK=infinity.
disable_mlock = false

# Maximum request duration before Vault cancels the request.
max_lease_ttl     = "768h"
default_lease_ttl = "768h"

# API address advertised to clients.
api_addr     = "https://vault.ecommerce.internal:8200"
cluster_addr = "https://vault.ecommerce.internal:8201"

# ---------------------------------------------------------------------------
# Storage Backend — Consul
# ---------------------------------------------------------------------------
# Consul provides the durable storage layer and is the recommended backend
# for production HA deployments. Every Vault node stores encrypted data in
# Consul's KV store under the configured path.
# ---------------------------------------------------------------------------
storage "consul" {
  address      = "consul.ecommerce.internal:8500"
  scheme       = "https"
  path         = "vault/"
  token        = ""  # Populated via VAULT_CONSUL_TOKEN env var at runtime
  service      = "vault"
  service_tags = "ecommerce,production"

  # TLS settings for Consul communication
  tls_ca_file   = "/etc/vault/tls/consul-ca.pem"
  tls_cert_file = "/etc/vault/tls/consul-cert.pem"
  tls_key_file  = "/etc/vault/tls/consul-key.pem"

  # Session and consistency tuning
  consistency_mode  = "strong"
  session_ttl       = "30s"
  lock_wait_time    = "15s"
  max_parallel      = 128
}

# ---------------------------------------------------------------------------
# Listener — TCP with TLS
# ---------------------------------------------------------------------------
# Primary API listener on port 8200. TLS is mandatory in production; the
# certificate and key are managed by the platform team and rotated via a
# sidecar process.
# ---------------------------------------------------------------------------
listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  # TLS configuration — never disable in production
  tls_disable     = false
  tls_cert_file   = "/etc/vault/tls/vault-cert.pem"
  tls_key_file    = "/etc/vault/tls/vault-key.pem"
  tls_min_version = "tls13"

  # Client certificate authentication (mTLS) — optional but recommended for
  # internal service-to-service communication.
  tls_require_and_verify_client_cert = false
  tls_client_ca_file                 = "/etc/vault/tls/vault-ca.pem"

  # Request limits
  max_request_size    = 33554432  # 32 MB
  max_request_duration = "90s"

  # Telemetry headers for Prometheus scraping
  telemetry {
    unauthenticated_metrics_access = true
  }
}

# ---------------------------------------------------------------------------
# Seal — AWS KMS Auto-Unseal
# ---------------------------------------------------------------------------
# Auto-unseal eliminates the need for manual unseal key holders during Vault
# restarts. The KMS key ARN, region, and credentials are supplied below.
# IAM credentials should be provided via the instance profile or environment
# variables (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) rather than being
# hardcoded.
# ---------------------------------------------------------------------------
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = ""  # Populated via VAULT_AWSKMS_SEAL_KEY_ID env var
  endpoint   = ""  # Leave empty to use the default AWS KMS endpoint

  # When migrating from Shamir to auto-unseal, set disabled = true on the
  # old seal stanza. This is left here as documentation.
  # disabled = false
}

# ---------------------------------------------------------------------------
# Telemetry — Prometheus Metrics
# ---------------------------------------------------------------------------
# Vault exposes an extensive set of runtime metrics. These are scraped by
# Prometheus via the /v1/sys/metrics endpoint (unauthenticated access is
# enabled on the listener above).
# ---------------------------------------------------------------------------
telemetry {
  # Prometheus retention window — Vault keeps a rolling window of metrics
  # in memory for Prometheus to scrape.
  prometheus_retention_time = "30s"

  # StatsD forwarding (optional secondary sink)
  statsd_address = ""  # e.g., "statsd.ecommerce.internal:8125"

  # Disable hostname prefix to keep metric names clean in multi-node setups.
  disable_hostname = true

  # Usage gauge period — how often Vault recalculates in-memory gauges.
  usage_gauge_period = "10m"

  # Enable additional lease metrics for capacity planning.
  enable_hostname_label = false
}

# ---------------------------------------------------------------------------
# Audit — File Audit Device
# ---------------------------------------------------------------------------
# Every request and response is logged to a local file for compliance and
# forensics. In production this file is shipped to a central SIEM via
# Fluentd / Fluent Bit. Two audit devices are configured for redundancy;
# Vault will block requests if ALL audit devices fail.
# ---------------------------------------------------------------------------

# Primary audit log
audit "file" "primary" {
  path = "/var/log/vault/audit.log"

  options = {
    file_path  = "/var/log/vault/audit.log"
    log_raw    = false
    hmac_accessor = true
    mode       = "0600"
    format     = "json"
    prefix     = ""
  }
}

# Secondary audit log — written to a separate volume for resilience
audit "file" "secondary" {
  path = "/var/log/vault/audit-secondary.log"

  options = {
    file_path  = "/var/log/vault/audit-secondary.log"
    log_raw    = false
    hmac_accessor = true
    mode       = "0600"
    format     = "json"
    prefix     = ""
  }
}

# ---------------------------------------------------------------------------
# High Availability
# ---------------------------------------------------------------------------
# HA is enabled implicitly through the Consul storage backend. The settings
# below fine-tune leader election and redirect behaviour.
# ---------------------------------------------------------------------------

# Redirect client requests to the active node rather than forwarding them
# through the standby. This reduces latency at the cost of exposing the
# active node's address to clients.
# Set to empty string to enable request forwarding instead.
# api_addr is set at the top of this file.

# Performance standby nodes can serve read-only requests (Enterprise only).
# performance_standby_count = 2

# ---------------------------------------------------------------------------
# Service Registration — Consul
# ---------------------------------------------------------------------------
# Vault registers itself as a Consul service so that clients can discover it
# via DNS (vault.service.consul) or the Consul API.
# ---------------------------------------------------------------------------
service_registration "consul" {
  address = "consul.ecommerce.internal:8500"
  scheme  = "https"
  token   = ""  # Populated via VAULT_CONSUL_TOKEN env var

  tls_ca_file   = "/etc/vault/tls/consul-ca.pem"
  tls_cert_file = "/etc/vault/tls/consul-cert.pem"
  tls_key_file  = "/etc/vault/tls/consul-key.pem"
}

# ---------------------------------------------------------------------------
# Entropy Augmentation (optional, Enterprise)
# ---------------------------------------------------------------------------
# entropy "seal" {
#   mode = "augmentation"
# }
