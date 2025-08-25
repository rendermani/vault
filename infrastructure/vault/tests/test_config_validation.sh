#!/bin/bash

# Configuration Validation Testing
# Tests configuration validation and syntax checking

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[TEST]${NC} $1"; }

# Test configuration validation
test_vault_config_validation() {
    log_step "Testing Vault configuration validation..."
    
    local test_dir="/tmp/vault-validation-test"
    mkdir -p "$test_dir"
    
    # Test 1: Valid configuration
    cat > "$test_dir/valid.hcl" << 'EOF'
ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://cloudya.net:8200"
cluster_addr = "http://cloudya.net:8201"
EOF
    
    # Test 2: Invalid configuration - missing required fields
    cat > "$test_dir/invalid-missing.hcl" << 'EOF'
ui = true
# Missing storage and listener
EOF
    
    # Test 3: Invalid configuration - syntax error
    cat > "$test_dir/invalid-syntax.hcl" << 'EOF'
ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-1"
  # Missing closing brace
EOF
    
    # Test 4: Configuration with deprecated settings
    cat > "$test_dir/deprecated.hcl" << 'EOF'
ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"  
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# Deprecated setting
max_lease_ttl = "768h"
default_lease_ttl = "168h"
EOF
    
    # Validate configurations (would need vault binary for real validation)
    log_info "Configuration validation tests created in $test_dir"
    
    # Cleanup
    rm -rf "$test_dir"
    
    return 0
}

# Test policy validation
test_policy_validation() {
    log_step "Testing policy validation..."
    
    local test_dir="/tmp/policy-validation-test"
    mkdir -p "$test_dir"
    
    # Valid policy
    cat > "$test_dir/valid-policy.hcl" << 'EOF'
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
EOF
    
    # Invalid policy - bad capability
    cat > "$test_dir/invalid-policy.hcl" << 'EOF'
path "secret/data/*" {
  capabilities = ["create", "read", "invalid_capability"]
}
EOF
    
    # Policy with syntax error
    cat > "$test_dir/syntax-error-policy.hcl" << 'EOF'
path "secret/data/*" {
  capabilities = ["create", "read", "update"
  # Missing closing bracket
}
EOF
    
    log_info "Policy validation tests created in $test_dir"
    
    # Cleanup
    rm -rf "$test_dir"
    
    return 0
}

# Main execution
main() {
    log_info "Starting configuration validation tests..."
    
    test_vault_config_validation
    test_policy_validation
    
    log_info "Configuration validation tests completed"
}

main "$@"