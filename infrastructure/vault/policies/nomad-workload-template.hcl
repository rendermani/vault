# Nomad Workload Policy Template
# This is a template policy for individual Nomad workloads using Workload Identity
# Replace {{JOB_ID}} and {{NAMESPACE}} with actual job and namespace values

# =============================================================================
# APPLICATION-SPECIFIC SECRET ACCESS
# =============================================================================

# Read secrets specific to this job
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}/*" {
  capabilities = ["read"]
}

path "kv/metadata/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}/*" {
  capabilities = ["read", "list"]
}

# Environment-specific secrets
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/shared/*" {
  capabilities = ["read"]
}

path "kv/metadata/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/shared/*" {
  capabilities = ["read", "list"]
}

# Global configuration secrets (read-only)
path "kv/data/global/config/*" {
  capabilities = ["read"]
}

# =============================================================================
# DYNAMIC CREDENTIALS
# =============================================================================

# Database credentials for this specific application
path "database/creds/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["read"]
}

path "database/creds/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}-readonly" {
  capabilities = ["read"]
}

# AWS credentials for this application (if configured)
path "aws/creds/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["read"]
}

# =============================================================================
# PKI CERTIFICATES
# =============================================================================

# Issue certificates for this specific workload
path "pki_int/issue/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["update"]
}

# Issue certificates with common naming pattern
path "pki_int/issue/nomad-workload" {
  capabilities = ["update"]
  allowed_parameters = {
    "common_name" = ["{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}.service.consul"]
    "alt_names" = ["{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}.{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}.nomad"]
    "ttl" = ["24h", "168h"]
  }
}

# Read CA certificate for validation
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# =============================================================================
# TRANSIT ENCRYPTION (if enabled)
# =============================================================================

# Encrypt/decrypt using job-specific key
path "transit/encrypt/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["update"]
}

path "transit/decrypt/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["update"]
}

# Generate data keys for envelope encryption
path "transit/datakey/plaintext/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["update"]
}

# =============================================================================
# TOKEN SELF-MANAGEMENT
# =============================================================================

# Self-token operations
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# Check own capabilities
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# =============================================================================
# LOGGING AND MONITORING
# =============================================================================

# Health checks (for service monitoring)
path "sys/health" {
  capabilities = ["read"]
}

# Create audit hashes for log integrity (if needed)
path "sys/audit-hash/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["create", "update"]
}

# =============================================================================
# RESTRICTED OPERATIONS (EXPLICIT DENIALS)
# =============================================================================

# Deny access to other applications' secrets
path "kv/data/+/+/*" {
  capabilities = ["deny"]
}

# Allow access only to own namespace
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/*" {
  capabilities = ["read"]
}

# Deny system-level operations
path "sys/config/*" {
  capabilities = ["deny"]
}

path "sys/policies/*" {
  capabilities = ["deny"]
}

path "sys/auth/*" {
  capabilities = ["deny"]
}

path "sys/mounts/*" {
  capabilities = ["deny"]
}

# Deny access to other auth methods
path "auth/approle/*" {
  capabilities = ["deny"]
}

path "auth/userpass/*" {
  capabilities = ["deny"]
}

# Deny token creation (workloads should not create tokens)
path "auth/token/create*" {
  capabilities = ["deny"]
}

# =============================================================================
# CONDITIONAL ACCESS (Environment-based)
# =============================================================================

# Production restrictions - no debug/admin secrets
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/debug/*" {
  capabilities = ["deny"]
  conditions = {
    "{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.environment}}" = ["production"]
  }
}

# Development allowances - broader secret access
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_namespace}}/debug/*" {
  capabilities = ["read"]
  conditions = {
    "{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.environment}}" = ["develop", "staging"]
  }
}