# Nomad Server Bootstrap Policy
# This policy provides the necessary permissions for Nomad servers during the bootstrap phase
# and ongoing token management operations

# =============================================================================
# TOKEN MANAGEMENT CAPABILITIES
# =============================================================================

# Create tokens for Nomad workloads using the nomad-cluster role
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

# Read the token role configuration
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

# Self-token operations - critical for token renewal
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Look up tokens by accessor (for management purposes)
path "auth/token/lookup" {
  capabilities = ["update"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

# Revoke tokens by accessor (cleanup operations)
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# Check capabilities (used by Nomad for policy validation)
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# =============================================================================
# SECRETS ACCESS FOR NOMAD WORKLOADS
# =============================================================================

# Allow Nomad to read KV secrets for all namespaces
# This enables workloads to access their designated secrets
path "kv/data/+/+/*" {
  capabilities = ["read"]
}

path "kv/metadata/+/+/*" {
  capabilities = ["read", "list"]
}

# Environment-specific secret access
path "kv/data/{{identity.entity.metadata.environment}}/*" {
  capabilities = ["read"]
}

path "kv/metadata/{{identity.entity.metadata.environment}}/*" {
  capabilities = ["read", "list"]
}

# =============================================================================
# DYNAMIC SECRETS MANAGEMENT
# =============================================================================

# Database credentials for workloads
path "database/creds/+/*" {
  capabilities = ["read"]
}

path "database/config/+" {
  capabilities = ["read"]
}

# PKI certificate issuance for workloads
path "pki_int/issue/+" {
  capabilities = ["update"]
}

path "pki_int/certs" {
  capabilities = ["list"]
}

# AWS dynamic credentials (if configured)
path "aws/creds/+" {
  capabilities = ["read"]
}

# =============================================================================
# NOMAD-SPECIFIC OPERATIONS
# =============================================================================

# Health and status checks
path "sys/health" {
  capabilities = ["read"]
}

path "sys/seal-status" {
  capabilities = ["read"]
}

# Metrics for monitoring integration
path "sys/metrics" {
  capabilities = ["read"]
}

# =============================================================================
# AUDIT AND COMPLIANCE
# =============================================================================

# Read audit device configuration (for compliance checks)
path "sys/audit" {
  capabilities = ["read", "list"]
}

# Create audit hashes for log integrity verification
path "sys/audit-hash/*" {
  capabilities = ["create", "update"]
}

# =============================================================================
# MOUNT AND AUTH METHOD INFORMATION
# =============================================================================

# Read mounted secret engines (for workload routing)
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Read authentication methods (for policy validation)
path "sys/auth" {
  capabilities = ["read", "list"]
}

# =============================================================================
# RESTRICTED OPERATIONS (EXPLICIT DENIALS)
# =============================================================================

# Deny access to root token operations
path "auth/token/create-orphan" {
  capabilities = ["deny"]
}

# Deny access to system configuration changes
path "sys/config/*" {
  capabilities = ["deny"]
}

# Deny unseal operations (should be handled separately)
path "sys/unseal" {
  capabilities = ["deny"]
}

path "sys/seal" {
  capabilities = ["deny"]
}

# Deny policy modifications
path "sys/policies/*" {
  capabilities = ["deny"]
}