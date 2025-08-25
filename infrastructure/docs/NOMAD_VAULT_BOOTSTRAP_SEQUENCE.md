# Nomad-Vault Integration Bootstrap Sequence

## Executive Summary

This document defines the exact bootstrap sequence for integrating Nomad and Vault in the Cloudya infrastructure. Based on analysis of the current codebase, it provides a comprehensive guide covering environment variables, phase detection, policies, and validation procedures.

## Overview: Two-Phase Bootstrap Pattern

The Nomad-Vault integration follows a secure two-phase bootstrap pattern to resolve the "chicken and egg" dependency problem:

1. **Phase 1**: Bootstrap with temporary tokens and basic setup
2. **Phase 2**: Migration to production-grade authentication (AppRole/Workload Identity)

---

## Phase Detection Environment Variables

### Core Environment Variables for Phase Detection

```bash
# Environment designation (critical for phase logic)
ENVIRONMENT=develop|staging|production
NODE_ENV=development|production

# Phase detection flags
VAULT_BOOTSTRAP_PHASE=1|2
NOMAD_VAULT_INTEGRATION_READY=false|true

# Bootstrap state tracking
VAULT_INITIALIZED=false|true
VAULT_UNSEALED=false|true
NOMAD_ACL_BOOTSTRAP_DONE=false|true
```

### Vault-Specific Environment Variables

```bash
# Core Vault configuration
VAULT_ADDR=http://127.0.0.1:8200  # or https for production
VAULT_API_ADDR=https://vault.cloudya.net
VAULT_CLUSTER_ADDR=https://vault.cloudya.net:8201
VAULT_LOG_LEVEL=INFO|WARN        # WARN for production
VAULT_LOG_FORMAT=json

# Storage and data paths
VAULT_DATA_PATH=/opt/cloudya-data/vault/data
VAULT_CONFIG_PATH=/opt/cloudya-data/vault/config
VAULT_LOG_PATH=/var/log/cloudya/vault.log

# TLS Configuration
VAULT_CERT_PATH=/opt/cloudya-data/vault/certs/vault.crt
VAULT_KEY_PATH=/opt/cloudya-data/vault/certs/vault.key
VAULT_CA_PATH=/opt/cloudya-data/vault/certs/ca.crt

# Security settings
VAULT_STORAGE_TYPE=file|raft
VAULT_HA_ENABLED=false|true
VAULT_PERFORMANCE_STANDBY=false|true

# Auto-unseal (production)
VAULT_SEAL_TYPE=awskms|transit
VAULT_AWS_REGION=us-west-2
VAULT_KMS_KEY_ID=alias/vault-production-unseal
```

### Nomad-Specific Environment Variables

```bash
# Core Nomad configuration
NOMAD_ADDR=http://localhost:4646
NOMAD_DATACENTER=dc1
NOMAD_REGION=global
NOMAD_LOG_LEVEL=INFO
NOMAD_LOG_JSON=true

# Data and configuration paths
NOMAD_DATA_PATH=/opt/cloudya-data/nomad/data
NOMAD_CONFIG_PATH=/opt/cloudya-data/nomad/config
NOMAD_LOG_PATH=/var/log/cloudya/nomad.log

# Cluster configuration
NOMAD_BOOTSTRAP_EXPECT=1|3|5     # Number of servers
NOMAD_ENCRYPT_KEY=base64-key     # Generated encryption key

# ACL and security
NOMAD_ACL_ENABLED=true
NOMAD_TOKEN=                     # Bootstrap token (Phase 1 only)
```

### Integration-Specific Environment Variables

```bash
# Vault-Nomad integration state
VAULT_NOMAD_TOKEN_ROLE=nomad-cluster
VAULT_NOMAD_POLICY=nomad-server
VAULT_NOMAD_AUTH_METHOD=token|approle|workload-identity

# Token management
NOMAD_VAULT_TOKEN=               # Temporary integration token (Phase 1)
VAULT_TOKEN_TTL=1h
VAULT_TOKEN_MAX_TTL=4h

# Service discovery
CONSUL_ADDR=127.0.0.1:8500
CONSUL_TOKEN=                    # If ACL enabled
```

---

## Phase 1: Bootstrap Sequence

### Step 1: Infrastructure Preparation

```bash
#!/bin/bash
# Infrastructure preparation script

# Set phase detection
export VAULT_BOOTSTRAP_PHASE=1
export NOMAD_VAULT_INTEGRATION_READY=false

# Create required directories
sudo mkdir -p ${VAULT_DATA_PATH}
sudo mkdir -p ${VAULT_CONFIG_PATH}  
sudo mkdir -p ${NOMAD_DATA_PATH}
sudo mkdir -p ${NOMAD_CONFIG_PATH}

# Set appropriate permissions
sudo chown -R vault:vault ${VAULT_DATA_PATH}
sudo chown -R nomad:nomad ${NOMAD_DATA_PATH}
```

### Step 2: Nomad ACL Bootstrap

```bash
#!/bin/bash
# Nomad ACL bootstrap

log_info "Bootstrapping Nomad ACL system..."

# Start Nomad servers
systemctl start nomad

# Wait for Nomad to be ready
wait_for_endpoint "http://localhost:4646/v1/status/leader" 200 300

# Bootstrap ACL system
NOMAD_BOOTSTRAP_RESPONSE=$(curl -X POST \
  http://localhost:4646/v1/acl/bootstrap 2>/dev/null)

# Extract bootstrap token
export NOMAD_TOKEN=$(echo $NOMAD_BOOTSTRAP_RESPONSE | jq -r '.SecretID')

# Store bootstrap token securely
echo $NOMAD_TOKEN > /root/.nomad/bootstrap-token
chmod 600 /root/.nomad/bootstrap-token

# Mark ACL bootstrap complete
export NOMAD_ACL_BOOTSTRAP_DONE=true

log_success "Nomad ACL bootstrap completed"
```

### Step 3: Vault Deployment on Nomad

```bash
#!/bin/bash
# Deploy Vault as Nomad job

log_info "Deploying Vault on Nomad..."

# Select appropriate Vault job file based on environment
VAULT_JOB_FILE="/vault/jobs/${ENVIRONMENT}/vault.nomad"

# Validate job file
nomad job validate $VAULT_JOB_FILE

# Deploy Vault job
nomad job run $VAULT_JOB_FILE

# Wait for Vault to be running
wait_for_nomad_job_healthy "vault-${ENVIRONMENT}" 600

log_success "Vault deployed on Nomad successfully"
```

### Step 4: Vault Initialization

```bash
#!/bin/bash
# Initialize Vault cluster

log_info "Initializing Vault..."

export VAULT_ADDR="${VAULT_ADDR}"

# Wait for Vault to be accessible
wait_for_endpoint "$VAULT_ADDR/v1/sys/health" 200 300

# Check if already initialized
if vault status | grep "Initialized.*false"; then
    # Initialize Vault with 5 key shares, threshold of 3
    VAULT_INIT_OUTPUT=$(vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json)
    
    # Store initialization data securely
    echo $VAULT_INIT_OUTPUT > /root/.vault/init-${ENVIRONMENT}.json
    chmod 600 /root/.vault/init-${ENVIRONMENT}.json
    
    # Extract root token
    ROOT_TOKEN=$(echo $VAULT_INIT_OUTPUT | jq -r '.root_token')
    
    # Auto-unseal with first 3 keys (development/staging only)
    if [[ "$ENVIRONMENT" != "production" ]]; then
        for i in {0..2}; do
            KEY=$(echo $VAULT_INIT_OUTPUT | jq -r ".unseal_keys_b64[$i]")
            vault operator unseal $KEY
        done
    fi
    
    export VAULT_INITIALIZED=true
    export VAULT_UNSEALED=true  # if auto-unsealed
    
    log_success "Vault initialized successfully"
else
    log_info "Vault already initialized"
fi
```

### Step 5: Basic Vault Configuration

```bash
#!/bin/bash
# Basic Vault configuration for Nomad integration

export VAULT_TOKEN=$ROOT_TOKEN

log_info "Configuring Vault for Nomad integration..."

# Enable audit logging
vault audit enable file file_path=/var/log/vault/audit.log

# Create Nomad server policy
vault policy write nomad-server - <<EOF
# Token management capabilities
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/lookup" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
EOF

# Create token role for Nomad
vault write auth/token/roles/nomad-cluster \
    allowed_policies=nomad-server \
    orphan=true \
    renewable=true \
    explicit_max_ttl=0

# Generate integration token
NOMAD_VAULT_TOKEN=$(vault write -field=token auth/token/create \
    policies=nomad-server \
    orphan=true \
    renewable=true \
    ttl=72h)

# Store integration token
echo $NOMAD_VAULT_TOKEN > /root/.nomad/vault-integration-token
chmod 600 /root/.nomad/vault-integration-token

export NOMAD_VAULT_TOKEN=$NOMAD_VAULT_TOKEN

log_success "Vault configured for Nomad integration"
```

### Step 6: Nomad-Vault Integration Setup

```bash
#!/bin/bash
# Configure Nomad to use Vault

log_info "Configuring Nomad-Vault integration..."

# Update Nomad configuration with Vault settings
cat >> /etc/nomad.d/nomad.hcl <<EOF

# Vault integration
vault {
  enabled = true
  address = "${VAULT_ADDR}"
  token   = "${NOMAD_VAULT_TOKEN}"
  
  create_from_role = "nomad-cluster"
}
EOF

# Reload Nomad configuration
systemctl reload nomad

# Wait for integration to be established
sleep 30

# Verify integration
if nomad server members | grep -q alive; then
    export NOMAD_VAULT_INTEGRATION_READY=true
    log_success "Nomad-Vault integration established"
else
    log_error "Nomad-Vault integration failed"
    exit 1
fi
```

---

## Phase 2: Production Migration

### Step 1: AppRole Setup

```bash
#!/bin/bash
# Setup AppRole authentication method

log_info "Setting up AppRole authentication..."

# Enable AppRole auth method
vault auth enable approle

# Create AppRole for Nomad servers
vault write auth/approle/role/nomad-servers \
    token_policies=nomad-server \
    token_ttl=1h \
    token_max_ttl=24h \
    secret_id_ttl=720h \
    secret_id_num_uses=0 \
    bind_secret_id=true

# Get Role ID
NOMAD_ROLE_ID=$(vault read -field=role_id auth/approle/role/nomad-servers/role-id)

# Generate Secret ID
NOMAD_SECRET_ID=$(vault write -field=secret_id auth/approle/role/nomad-servers/secret-id)

# Store AppRole credentials
cat > /etc/nomad.d/approle-credentials <<EOF
NOMAD_VAULT_ROLE_ID=$NOMAD_ROLE_ID
NOMAD_VAULT_SECRET_ID=$NOMAD_SECRET_ID
EOF
chmod 600 /etc/nomad.d/approle-credentials

export VAULT_BOOTSTRAP_PHASE=2

log_success "AppRole configured for Nomad"
```

### Step 2: Workload Identity (Modern Approach)

```bash
#!/bin/bash
# Configure Workload Identity (Nomad 1.7+)

log_info "Setting up Workload Identity..."

# Enable JWT auth method
vault auth enable -path=nomad-workloads jwt

# Configure JWT auth backend
vault write auth/nomad-workloads/config \
    bound_issuer="https://nomad.cloudya.net:4646" \
    jwt_validation_pubkeys=@/etc/nomad.d/nomad-jwt.pub

# Create role for workload authentication
vault write auth/nomad-workloads/role/nomad-workloads \
    bound_audiences="vault.io" \
    bound_claims='{"nomad_namespace": "default"}' \
    user_claim="sub" \
    role_type="jwt" \
    policies="nomad-server" \
    ttl=1h \
    max_ttl=2h

log_success "Workload Identity configured"
```

### Step 3: Token Migration and Cleanup

```bash
#!/bin/bash
# Migrate from temporary tokens to production authentication

log_info "Migrating to production authentication..."

# Update Nomad configuration for AppRole
cat > /etc/nomad.d/vault-integration.hcl <<EOF
vault {
  enabled = true
  address = "${VAULT_ADDR}"
  
  # Remove temporary token
  # token = ""
  
  # Use AppRole authentication
  auth_method = "approle"
  role_id = "${NOMAD_VAULT_ROLE_ID}"
  secret_id = "${NOMAD_VAULT_SECRET_ID}"
  
  create_from_role = "nomad-servers"
}
EOF

# Restart Nomad to pick up new configuration
systemctl restart nomad

# Wait for Nomad to reconnect with new auth
sleep 60

# Revoke temporary integration token
vault token revoke $NOMAD_VAULT_TOKEN

# Clean up temporary files
rm -f /root/.nomad/vault-integration-token

export NOMAD_VAULT_INTEGRATION_READY=true

log_success "Migration to production authentication completed"
```

---

## Vault Policy Templates

### Nomad Server Policy

```hcl
# /vault/policies/nomad-server.hcl
# Policy for Nomad servers to manage tokens

# Token creation and management
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/lookup" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Allow reading own token properties
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow renewing own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
```

### Nomad Workload Policy Template

```hcl
# /vault/policies/nomad-workload-template.hcl
# Template for workload-specific policies

# Read secrets for specific application
path "kv/data/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}/*" {
  capabilities = ["read"]
}

path "kv/metadata/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}/*" {
  capabilities = ["read", "list"]
}

# Database dynamic credentials (if needed)
path "database/creds/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["read"]
}

# PKI certificates (if needed)
path "pki_int/issue/{{identity.entity.aliases.AUTH_METHOD_ACCESSOR.metadata.nomad_job_id}}" {
  capabilities = ["update"]
}

# Self-token management
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
```

### Environment-Specific Policies

```hcl
# /vault/policies/environments/production-nomad.hcl
# Production-specific restrictions

# Restricted token creation - shorter TTLs
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
  allowed_parameters = {
    "ttl" = ["1h", "2h"]
    "policies" = ["nomad-workload-*"]
  }
}

# Enhanced audit requirements
path "sys/audit-hash/*" {
  capabilities = ["create", "update"]
}

# Production secret paths only
path "kv/data/production/*" {
  capabilities = ["read"]
}

path "kv/metadata/production/*" {
  capabilities = ["read", "list"]
}

# No access to development/staging secrets
path "kv/data/develop/*" {
  capabilities = ["deny"]
}

path "kv/data/staging/*" {
  capabilities = ["deny"]
}
```

---

## Validation Tests

### Bootstrap Phase Validation

```bash
#!/bin/bash
# /tests/bootstrap/nomad_vault_bootstrap_test.sh

test_phase_1_bootstrap() {
    log_info "Testing Phase 1 bootstrap..."
    
    # Test environment variables
    assert_env_var_set "VAULT_BOOTSTRAP_PHASE"
    assert_env_var_set "NOMAD_TOKEN"
    assert_env_var_set "VAULT_ADDR"
    
    # Test Nomad ACL bootstrap
    assert_command_success "nomad acl token self" "Nomad ACL not bootstrapped"
    
    # Test Vault deployment
    assert_http_status "$VAULT_ADDR/v1/sys/health" 200 "Vault not accessible"
    
    # Test Vault initialization
    vault_status=$(vault status -format=json)
    assert_equals "true" $(echo $vault_status | jq -r '.initialized') "Vault not initialized"
    
    # Test integration token
    assert_file_exists "/root/.nomad/vault-integration-token" "Integration token not stored"
    
    log_success "Phase 1 bootstrap validation passed"
}

test_phase_2_migration() {
    log_info "Testing Phase 2 migration..."
    
    # Test AppRole configuration
    assert_command_success "vault read auth/approle/role/nomad-servers" "AppRole not configured"
    
    # Test workload identity (if enabled)
    if vault auth list | grep -q nomad-workloads; then
        assert_command_success "vault read auth/nomad-workloads/config" "Workload identity not configured"
    fi
    
    # Test token cleanup
    assert_file_not_exists "/root/.nomad/vault-integration-token" "Temporary token not cleaned up"
    
    # Test Nomad-Vault integration
    nomad_status=$(nomad server members -json)
    assert_contains "$nomad_status" "alive" "Nomad servers not healthy"
    
    log_success "Phase 2 migration validation passed"
}
```

### Token Lifecycle Validation

```bash
#!/bin/bash
# /tests/integration/token_lifecycle_test.sh

test_token_creation() {
    log_info "Testing token creation..."
    
    # Test Nomad can create tokens via Vault
    test_token=$(nomad operator api -method POST /v1/acl/token -data '{"Name":"test-token"}')
    assert_not_empty "$test_token" "Failed to create token via Nomad"
    
    log_success "Token creation test passed"
}

test_token_renewal() {
    log_info "Testing token renewal..."
    
    # Create short-lived token
    short_token=$(vault write -field=token auth/token/create ttl=60s)
    
    # Test renewal
    renewed_info=$(VAULT_TOKEN=$short_token vault token renew -format=json)
    new_ttl=$(echo $renewed_info | jq -r '.auth.lease_duration')
    
    assert_true "$((new_ttl > 60))" "Token renewal failed"
    
    # Cleanup
    vault token revoke $short_token
    
    log_success "Token renewal test passed"
}

test_token_revocation() {
    log_info "Testing token revocation..."
    
    # Create test token
    test_token=$(vault write -field=token auth/token/create ttl=1h)
    
    # Verify token works
    assert_command_success "VAULT_TOKEN=$test_token vault token lookup-self" "Test token not functional"
    
    # Revoke token
    vault token revoke $test_token
    
    # Verify token is revoked
    assert_command_failure "VAULT_TOKEN=$test_token vault token lookup-self" "Token not properly revoked"
    
    log_success "Token revocation test passed"
}
```

---

## Environment-Specific Configurations

### Development Environment

```bash
# Development-specific variables
ENVIRONMENT=develop
VAULT_ADDR=http://localhost:8200
VAULT_LOG_LEVEL=DEBUG
VAULT_DEV_MODE=true
NOMAD_BOOTSTRAP_EXPECT=1
```

### Staging Environment

```bash
# Staging-specific variables
ENVIRONMENT=staging
VAULT_ADDR=https://vault-staging.cloudya.net
VAULT_LOG_LEVEL=INFO
VAULT_HA_ENABLED=true
NOMAD_BOOTSTRAP_EXPECT=3
```

### Production Environment

```bash
# Production-specific variables
ENVIRONMENT=production
VAULT_ADDR=https://vault.cloudya.net
VAULT_LOG_LEVEL=WARN
VAULT_HA_ENABLED=true
VAULT_PERFORMANCE_STANDBY=true
VAULT_SEAL_TYPE=awskms
NOMAD_BOOTSTRAP_EXPECT=5
```

---

## Security Considerations

### Critical Security Points

1. **Token Storage**: All bootstrap tokens must be stored with 600 permissions and cleaned up after use
2. **Network Security**: TLS must be enabled for production environments
3. **Audit Logging**: Enable comprehensive audit logging before any token operations
4. **Time-Bounded Tokens**: All temporary tokens must have explicit TTLs
5. **Principle of Least Privilege**: Policies must grant minimum required permissions

### Emergency Procedures

```bash
#!/bin/bash
# Emergency seal procedure
emergency_seal() {
    log_warning "EMERGENCY: Sealing Vault cluster"
    
    # Seal all Vault instances
    vault operator seal
    
    # Stop Nomad-Vault integration
    systemctl stop nomad
    
    # Alert security team
    alert_security_team "Vault sealed due to security incident"
}

# Emergency token revocation
emergency_revoke_all_tokens() {
    log_warning "EMERGENCY: Revoking all tokens"
    
    # Revoke all tokens (requires root token)
    vault write sys/leases/revoke-prefix prefix=auth/token/
    
    # Disable token auth temporarily
    vault auth disable token
    
    log_success "All tokens revoked"
}
```

---

## Troubleshooting Guide

### Common Issues and Solutions

1. **Vault Not Accessible**
   - Check Nomad job status: `nomad job status vault-${ENVIRONMENT}`
   - Verify network connectivity: `curl ${VAULT_ADDR}/v1/sys/health`
   - Check container logs: `nomad alloc logs <alloc-id> vault`

2. **Token Creation Failures**
   - Verify Nomad-Vault integration: `nomad server members`
   - Check token role configuration: `vault read auth/token/roles/nomad-cluster`
   - Review audit logs: `tail /var/log/vault/audit.log`

3. **Phase Detection Issues**
   - Verify environment variables: `env | grep VAULT_BOOTSTRAP_PHASE`
   - Check phase state files: `ls -la /root/.{vault,nomad}/`
   - Review bootstrap logs: `journalctl -u nomad -u vault`

---

## Conclusion

This bootstrap sequence provides a secure, scalable approach to integrating Nomad and Vault. The two-phase approach ensures security while maintaining operational simplicity. Regular validation and monitoring ensure the integration remains healthy and secure over time.

For production deployments, always follow the security hardening guidelines and ensure proper backup and disaster recovery procedures are in place.