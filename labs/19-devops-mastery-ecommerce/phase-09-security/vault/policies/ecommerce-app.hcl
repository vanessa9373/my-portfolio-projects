# =============================================================================
# Vault Policy: ecommerce-app
# =============================================================================
# This policy is attached to tokens issued to e-commerce microservices via
# Kubernetes auth or AppRole auth. It grants:
#
#   - Read access to application secrets under secret/data/ecommerce/*
#   - Read access to dynamic database credentials for ecommerce services
#   - Explicit deny on sys/* to prevent privilege escalation
#   - Token self-management (renewal, lookup)
#
# Usage:
#   vault policy write ecommerce-app policies/ecommerce-app.hcl
#   vault write auth/kubernetes/role/ecommerce-app \
#       bound_service_account_names=ecommerce-app \
#       bound_service_account_namespaces=ecommerce-prod \
#       policies=ecommerce-app \
#       ttl=1h
# =============================================================================

# ---------------------------------------------------------------------------
# KV v2 Secrets — Application Configuration
# ---------------------------------------------------------------------------
# All e-commerce service secrets are stored under secret/data/ecommerce/*.
# The KV v2 engine uses a data/ prefix in the API path. Services can read
# secrets and list available keys but cannot create, update, or delete them.
# Secret management is restricted to the platform-admin policy.
# ---------------------------------------------------------------------------

# Read secret data (current version)
path "secret/data/ecommerce/*" {
  capabilities = ["read"]
}

# Read secret metadata (version history, custom metadata)
path "secret/metadata/ecommerce/*" {
  capabilities = ["read", "list"]
}

# Read a specific secret version (for rollback scenarios)
path "secret/data/ecommerce/*" {
  capabilities = ["read"]

  # Restrict to reading specific versions via the version parameter
  allowed_parameters = {
    "version" = []
  }
}

# List available secret paths (for service discovery of config keys)
path "secret/metadata/ecommerce/" {
  capabilities = ["list"]
}

# Read secret subkeys without values (schema discovery)
path "secret/subkeys/ecommerce/*" {
  capabilities = ["read"]
}

# ---------------------------------------------------------------------------
# Dynamic Database Credentials
# ---------------------------------------------------------------------------
# Services request short-lived database credentials from the database secrets
# engine. Each microservice has a corresponding role (ecommerce-user-service,
# ecommerce-order-service, etc.) that maps to a narrowly-scoped database
# user with least-privilege grants.
# ---------------------------------------------------------------------------

# Generate dynamic credentials for any ecommerce database role
path "database/creds/ecommerce-*" {
  capabilities = ["read"]
}

# Read role configuration (useful for debugging credential issues)
path "database/roles/ecommerce-*" {
  capabilities = ["read"]
}

# Allow services to look up their active leases for credential rotation
path "sys/leases/lookup" {
  capabilities = ["update"]

  # Restrict to looking up leases under the database mount only
  allowed_parameters = {
    "lease_id" = ["database/creds/ecommerce-*"]
  }
}

# Allow services to renew their own database credential leases to avoid
# connection churn during peak traffic.
path "sys/leases/renew" {
  capabilities = ["update"]

  allowed_parameters = {
    "lease_id"  = ["database/creds/ecommerce-*"]
    "increment" = []
  }
}

# ---------------------------------------------------------------------------
# PKI — TLS Certificate Issuance (mTLS between services)
# ---------------------------------------------------------------------------
# Services can request short-lived TLS certificates from the intermediate CA
# for mTLS communication within the service mesh.
# ---------------------------------------------------------------------------

path "pki_int/issue/ecommerce-service" {
  capabilities = ["create", "update"]
}

path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# ---------------------------------------------------------------------------
# Transit Engine — Application-Level Encryption
# ---------------------------------------------------------------------------
# Services can encrypt and decrypt data using named transit keys (e.g.,
# payment data, PII). They cannot manage the keys themselves.
# ---------------------------------------------------------------------------

path "transit/encrypt/ecommerce-*" {
  capabilities = ["update"]
}

path "transit/decrypt/ecommerce-*" {
  capabilities = ["update"]
}

path "transit/rewrap/ecommerce-*" {
  capabilities = ["update"]
}

# Read key configuration (algorithm, version) but not the key material
path "transit/keys/ecommerce-*" {
  capabilities = ["read"]
}

# ---------------------------------------------------------------------------
# Token Self-Management
# ---------------------------------------------------------------------------
# Services must be able to renew and look up their own tokens. Without these
# capabilities, tokens would expire and services would lose access mid-
# request.
# ---------------------------------------------------------------------------

# Look up the properties of the caller's own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Renew the caller's own token before it expires
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Revoke the caller's own token (graceful shutdown)
path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# ---------------------------------------------------------------------------
# Identity — Entity Lookup
# ---------------------------------------------------------------------------
# Allow services to look up their own identity entity for audit correlation.
# ---------------------------------------------------------------------------

path "identity/entity/id/{{identity.entity.id}}" {
  capabilities = ["read"]
}

path "identity/entity/name/{{identity.entity.name}}" {
  capabilities = ["read"]
}

# ---------------------------------------------------------------------------
# Explicit Deny — System Backend
# ---------------------------------------------------------------------------
# The sys/* backend controls Vault's internal configuration (mounts, auth
# methods, policies, replication, etc.). Application services must never
# have access to these paths. The deny rules below override any future
# wildcard grants that might be accidentally added.
# ---------------------------------------------------------------------------

# Deny all operations on the sys backend
path "sys/*" {
  capabilities = ["deny"]
}

# Deny access to raw storage (emergency break-glass only)
path "sys/raw/*" {
  capabilities = ["deny"]
}

# Deny policy management
path "sys/policies/*" {
  capabilities = ["deny"]
}

# Deny auth method management
path "sys/auth/*" {
  capabilities = ["deny"]
}

# Deny secrets engine management
path "sys/mounts/*" {
  capabilities = ["deny"]
}

# Deny seal/unseal operations
path "sys/seal" {
  capabilities = ["deny"]
}

path "sys/unseal" {
  capabilities = ["deny"]
}

# Deny audit device management
path "sys/audit/*" {
  capabilities = ["deny"]
}

# Deny replication management
path "sys/replication/*" {
  capabilities = ["deny"]
}

# ---------------------------------------------------------------------------
# Note: The lease lookup and renewal paths under sys/leases/ are explicitly
# allowed above with parameter restrictions. Vault evaluates deny rules
# first, but the more specific path with allowed_parameters takes precedence
# over the broad sys/* deny when the path is an exact match.
#
# In practice, Vault policy resolution uses longest-prefix-match, so
# sys/leases/lookup and sys/leases/renew (defined above) are evaluated
# before the generic sys/* deny.
# ---------------------------------------------------------------------------
