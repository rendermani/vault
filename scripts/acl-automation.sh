#!/usr/bin/env bash
# ACL Automation Script
# Configures proper ACLs for Consul and Nomad with secure token policies
#
# This script addresses HIGH findings:
# - Missing ACL configurations for Consul and Nomad
# - Improper access controls and service isolation
# - Weak authentication and authorization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/cloudya-security"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-https://consul.cloudya.net:8500}"
NOMAD_ADDR="${NOMAD_ADDR:-https://nomad.cloudya.net:4646}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[ACL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/acl-automation.log"
}

log_success() {
    echo -e "${GREEN}[ACL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/acl-automation.log"
}

log_error() {
    echo -e "${RED}[ACL-AUTOMATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/acl-automation.log" >&2
}

# Generate secure UUIDs for tokens
generate_secure_uuid() {
    python3 -c "import uuid; print(uuid.uuid4())"
}

# Configure Consul ACLs
configure_consul_acls() {
    log_info "Configuring Consul ACL system..."
    
    # Bootstrap ACL system (if not already done)
    if ! consul acl bootstrap 2>/dev/null > /tmp/consul-bootstrap.json; then
        log_info "Consul ACL system already bootstrapped"
    else
        log_success "Consul ACL system bootstrapped"
        
        # Extract and store bootstrap token
        local bootstrap_token=$(jq -r '.SecretID' /tmp/consul-bootstrap.json)
        vault kv put secret/cloudya/consul/bootstrap token="$bootstrap_token"
        export CONSUL_HTTP_TOKEN="$bootstrap_token"
        
        rm /tmp/consul-bootstrap.json
    fi
    
    # Get bootstrap token from Vault if not set
    if [[ -z "${CONSUL_HTTP_TOKEN:-}" ]]; then
        export CONSUL_HTTP_TOKEN=$(vault kv get -field=token secret/cloudya/consul/bootstrap)
    fi
    
    # Create Consul policies
    create_consul_policies
    
    # Create Consul tokens
    create_consul_tokens
    
    log_success "Consul ACL configuration completed"
}

# Create Consul policies
create_consul_policies() {
    log_info "Creating Consul ACL policies..."
    
    # Nomad Server policy
    cat > /tmp/nomad-server-policy.hcl << 'EOF'
# Nomad server policy
agent_prefix "" {
  policy = "write"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}

acl = "write"

key_prefix "_rexec" {
  policy = "write"
}

key_prefix "nomad-" {
  policy = "write"
}

session_prefix "" {
  policy = "write"
}
EOF

    consul acl policy create \
        -name "nomad-server" \
        -description "Policy for Nomad servers" \
        -rules @/tmp/nomad-server-policy.hcl 2>/dev/null || \
        consul acl policy update \
        -name "nomad-server" \
        -description "Policy for Nomad servers" \
        -rules @/tmp/nomad-server-policy.hcl
    
    # Nomad Client policy
    cat > /tmp/nomad-client-policy.hcl << 'EOF'
# Nomad client policy
agent_prefix "" {
  policy = "write"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}

key_prefix "_rexec" {
  policy = "write"
}
EOF

    consul acl policy create \
        -name "nomad-client" \
        -description "Policy for Nomad clients" \
        -rules @/tmp/nomad-client-policy.hcl 2>/dev/null || \
        consul acl policy update \
        -name "nomad-client" \
        -description "Policy for Nomad clients" \
        -rules @/tmp/nomad-client-policy.hcl
    
    # Vault policy
    cat > /tmp/vault-policy.hcl << 'EOF'
# Vault service policy
service_prefix "vault" {
  policy = "write"
}

key_prefix "vault/" {
  policy = "write"
}

session_prefix "" {
  policy = "write"
}
EOF

    consul acl policy create \
        -name "vault-service" \
        -description "Policy for Vault service" \
        -rules @/tmp/vault-policy.hcl 2>/dev/null || \
        consul acl policy update \
        -name "vault-service" \
        -description "Policy for Vault service" \
        -rules @/tmp/vault-policy.hcl
    
    # Traefik policy
    cat > /tmp/traefik-policy.hcl << 'EOF'
# Traefik service policy
service_prefix "traefik" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

key_prefix "traefik/" {
  policy = "write"
}
EOF

    consul acl policy create \
        -name "traefik-service" \
        -description "Policy for Traefik service" \
        -rules @/tmp/traefik-policy.hcl 2>/dev/null || \
        consul acl policy update \
        -name "traefik-service" \
        -description "Policy for Traefik service" \
        -rules @/tmp/traefik-policy.hcl
    
    # Monitoring policy (Prometheus)
    cat > /tmp/monitoring-policy.hcl << 'EOF'
# Monitoring services policy
service_prefix "prometheus" {
  policy = "write"
}

service_prefix "grafana" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

key_prefix "monitoring/" {
  policy = "write"
}
EOF

    consul acl policy create \
        -name "monitoring-service" \
        -description "Policy for monitoring services" \
        -rules @/tmp/monitoring-policy.hcl 2>/dev/null || \
        consul acl policy update \
        -name "monitoring-service" \
        -description "Policy for monitoring services" \
        -rules @/tmp/monitoring-policy.hcl
    
    # Cleanup
    rm -f /tmp/*-policy.hcl
    
    log_success "Consul ACL policies created"
}

# Create Consul tokens
create_consul_tokens() {
    log_info "Creating Consul ACL tokens..."
    
    # Nomad Server token
    local nomad_server_token=$(consul acl token create \
        -description "Nomad Server Token" \
        -policy-name "nomad-server" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/consul/tokens/nomad-server \
        token="$nomad_server_token" \
        description="Token for Nomad server operations"
    
    # Nomad Client token
    local nomad_client_token=$(consul acl token create \
        -description "Nomad Client Token" \
        -policy-name "nomad-client" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/consul/tokens/nomad-client \
        token="$nomad_client_token" \
        description="Token for Nomad client operations"
    
    # Vault token
    local vault_token=$(consul acl token create \
        -description "Vault Service Token" \
        -policy-name "vault-service" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/consul/tokens/vault-service \
        token="$vault_token" \
        description="Token for Vault service registration"
    
    # Traefik token
    local traefik_token=$(consul acl token create \
        -description "Traefik Service Token" \
        -policy-name "traefik-service" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/consul/tokens/traefik-service \
        token="$traefik_token" \
        description="Token for Traefik service discovery"
    
    # Monitoring token
    local monitoring_token=$(consul acl token create \
        -description "Monitoring Services Token" \
        -policy-name "monitoring-service" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/consul/tokens/monitoring-service \
        token="$monitoring_token" \
        description="Token for monitoring services"
    
    log_success "Consul ACL tokens created and stored in Vault"
}

# Configure Nomad ACLs
configure_nomad_acls() {
    log_info "Configuring Nomad ACL system..."
    
    # Bootstrap Nomad ACL system
    if ! nomad acl bootstrap 2>/dev/null > /tmp/nomad-bootstrap.json; then
        log_info "Nomad ACL system already bootstrapped"
    else
        log_success "Nomad ACL system bootstrapped"
        
        # Extract and store bootstrap token
        local bootstrap_token=$(jq -r '.SecretID' /tmp/nomad-bootstrap.json)
        vault kv put secret/cloudya/nomad/bootstrap token="$bootstrap_token"
        export NOMAD_TOKEN="$bootstrap_token"
        
        rm /tmp/nomad-bootstrap.json
    fi
    
    # Get bootstrap token from Vault if not set
    if [[ -z "${NOMAD_TOKEN:-}" ]]; then
        export NOMAD_TOKEN=$(vault kv get -field=token secret/cloudya/nomad/bootstrap)
    fi
    
    # Create Nomad policies
    create_nomad_policies
    
    # Create Nomad tokens
    create_nomad_tokens
    
    log_success "Nomad ACL configuration completed"
}

# Create Nomad policies
create_nomad_policies() {
    log_info "Creating Nomad ACL policies..."
    
    # Vault integration policy
    cat > /tmp/vault-integration-policy.hcl << 'EOF'
namespace "*" {
  policy       = "write"
  capabilities = ["submit-job", "dispatch-job", "read-logs", "read-job"]
  
  variables {
    path "*" {
      capabilities = ["write", "read", "destroy"]
    }
  }
}

agent {
  policy = "write"
}

node {
  policy = "write"
}

quota {
  policy = "write"
}
EOF

    nomad acl policy apply \
        -description "Policy for Vault integration" \
        vault-integration /tmp/vault-integration-policy.hcl
    
    # Traefik workload policy
    cat > /tmp/traefik-workload-policy.hcl << 'EOF'
namespace "default" {
  policy       = "write"
  capabilities = ["submit-job", "read-job", "list-jobs"]
}

namespace "system" {
  policy       = "read"
  capabilities = ["list-jobs", "read-job"]
}

agent {
  policy = "read"
}

node {
  policy = "read"
}
EOF

    nomad acl policy apply \
        -description "Policy for Traefik workloads" \
        traefik-workload /tmp/traefik-workload-policy.hcl
    
    # Monitoring workload policy
    cat > /tmp/monitoring-workload-policy.hcl << 'EOF'
namespace "default" {
  policy       = "write"
  capabilities = ["submit-job", "read-job", "list-jobs", "read-logs"]
}

namespace "system" {
  policy       = "read"
  capabilities = ["list-jobs", "read-job"]
}

agent {
  policy = "read"
}

node {
  policy = "read"
}
EOF

    nomad acl policy apply \
        -description "Policy for monitoring workloads" \
        monitoring-workload /tmp/monitoring-workload-policy.hcl
    
    # Developer policy (limited access)
    cat > /tmp/developer-policy.hcl << 'EOF'
namespace "dev" {
  policy       = "write"
  capabilities = ["submit-job", "dispatch-job", "read-logs", "read-job"]
  
  variables {
    path "nomad/jobs/dev/*" {
      capabilities = ["write", "read", "destroy", "list"]
    }
  }
}

namespace "staging" {
  policy       = "read"
  capabilities = ["read-job", "list-jobs"]
}

agent {
  policy = "read"
}

node {
  policy = "read"
}
EOF

    nomad acl policy apply \
        -description "Policy for developers" \
        developer /tmp/developer-policy.hcl
    
    # Operations policy
    cat > /tmp/operations-policy.hcl << 'EOF'
namespace "*" {
  policy       = "write"
  capabilities = ["submit-job", "dispatch-job", "read-logs", "read-job", "list-jobs"]
  
  variables {
    path "*" {
      capabilities = ["write", "read", "destroy", "list"]
    }
  }
}

agent {
  policy = "write"
}

node {
  policy = "write"
}

quota {
  policy = "write"
}
EOF

    nomad acl policy apply \
        -description "Policy for operations team" \
        operations /tmp/operations-policy.hcl
    
    # Cleanup
    rm -f /tmp/*-policy.hcl
    
    log_success "Nomad ACL policies created"
}

# Create Nomad tokens
create_nomad_tokens() {
    log_info "Creating Nomad ACL tokens..."
    
    # Vault integration token
    local vault_integration_token=$(nomad acl token create \
        -name="vault-integration" \
        -policy="vault-integration" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/nomad/tokens/vault-integration \
        token="$vault_integration_token" \
        description="Token for Vault integration"
    
    # Traefik workload token
    local traefik_token=$(nomad acl token create \
        -name="traefik-workload" \
        -policy="traefik-workload" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/nomad/tokens/traefik-workload \
        token="$traefik_token" \
        description="Token for Traefik workloads"
    
    # Monitoring workload token
    local monitoring_token=$(nomad acl token create \
        -name="monitoring-workload" \
        -policy="monitoring-workload" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/nomad/tokens/monitoring-workload \
        token="$monitoring_token" \
        description="Token for monitoring workloads"
    
    # Developer token
    local developer_token=$(nomad acl token create \
        -name="developer" \
        -policy="developer" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/nomad/tokens/developer \
        token="$developer_token" \
        description="Token for developers"
    
    # Operations token
    local operations_token=$(nomad acl token create \
        -name="operations" \
        -policy="operations" \
        -format json | jq -r '.SecretID')
    
    vault kv put secret/cloudya/nomad/tokens/operations \
        token="$operations_token" \
        description="Token for operations team"
    
    log_success "Nomad ACL tokens created and stored in Vault"
}

# Configure Vault-Consul integration
configure_vault_consul_integration() {
    log_info "Configuring Vault-Consul integration..."
    
    # Enable Consul secrets engine in Vault
    vault secrets enable -path=consul consul 2>/dev/null || log_info "Consul secrets engine already enabled"
    
    # Get Consul management token
    local consul_mgmt_token=$(vault kv get -field=token secret/cloudya/consul/bootstrap)
    
    # Configure Consul secrets engine
    vault write consul/config/access \
        address="$CONSUL_HTTP_ADDR" \
        token="$consul_mgmt_token" \
        scheme=https
    
    # Create Consul role for dynamic token generation
    vault write consul/roles/nomad-server \
        policies="nomad-server" \
        ttl=1h \
        max_ttl=24h
    
    vault write consul/roles/traefik-service \
        policies="traefik-service" \
        ttl=1h \
        max_ttl=24h
    
    vault write consul/roles/monitoring-service \
        policies="monitoring-service" \
        ttl=1h \
        max_ttl=24h
    
    log_success "Vault-Consul integration configured"
}

# Configure Vault-Nomad integration
configure_vault_nomad_integration() {
    log_info "Configuring Vault-Nomad integration..."
    
    # Enable Nomad secrets engine in Vault
    vault secrets enable -path=nomad nomad 2>/dev/null || log_info "Nomad secrets engine already enabled"
    
    # Get Nomad management token
    local nomad_mgmt_token=$(vault kv get -field=token secret/cloudya/nomad/bootstrap)
    
    # Configure Nomad secrets engine
    vault write nomad/config/access \
        address="$NOMAD_ADDR" \
        token="$nomad_mgmt_token"
    
    # Create Nomad roles for dynamic token generation
    vault write nomad/role/developer \
        policies="developer" \
        type="client" \
        ttl=1h \
        max_ttl=24h
    
    vault write nomad/role/operations \
        policies="operations" \
        type="management" \
        ttl=1h \
        max_ttl=24h
    
    log_success "Vault-Nomad integration configured"
}

# Update configuration files with ACL settings
update_configuration_files() {
    log_info "Updating configuration files with ACL settings..."
    
    # Update Consul configuration
    local consul_config="$PROJECT_ROOT/infrastructure/config/consul.hcl"
    if [[ -f "$consul_config" ]]; then
        # Backup original
        cp "$consul_config" "${consul_config}.backup"
        
        # Add ACL configuration if not present
        if ! grep -q "acl = {" "$consul_config"; then
            cat >> "$consul_config" << 'EOF'

# ACL Configuration
acl = {
  enabled        = true
  default_policy = "deny"
  enable_token_persistence = true
}
EOF
        fi
        
        log_success "Updated Consul configuration with ACL settings"
    fi
    
    # Update Nomad configuration
    local nomad_config="$PROJECT_ROOT/infrastructure/config/nomad.hcl"
    if [[ -f "$nomad_config" ]]; then
        # Backup original
        cp "$nomad_config" "${nomad_config}.backup"
        
        # Add ACL configuration if not present
        if ! grep -q "acl {" "$nomad_config"; then
            cat >> "$nomad_config" << 'EOF'

# ACL Configuration
acl {
  enabled = true
}
EOF
        fi
        
        log_success "Updated Nomad configuration with ACL settings"
    fi
}

# Create ACL management scripts
create_acl_management_scripts() {
    log_info "Creating ACL management scripts..."
    
    mkdir -p "$PROJECT_ROOT/automation/acl-scripts"
    
    # Token rotation script
    cat > "$PROJECT_ROOT/automation/acl-scripts/rotate-tokens.sh" << 'EOF'
#!/usr/bin/env bash
# ACL Token Rotation Script
# Rotates Consul and Nomad tokens periodically

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Rotate Consul tokens
rotate_consul_tokens() {
    log_info "Rotating Consul tokens..."
    
    # Get current bootstrap token
    export CONSUL_HTTP_TOKEN=$(vault kv get -field=token secret/cloudya/consul/bootstrap)
    
    # Create new Nomad server token
    local new_nomad_token=$(consul acl token create \
        -description "Nomad Server Token (rotated $(date))" \
        -policy-name "nomad-server" \
        -format json | jq -r '.SecretID')
    
    # Update Vault with new token
    vault kv put secret/cloudya/consul/tokens/nomad-server \
        token="$new_nomad_token" \
        description="Token for Nomad server operations (rotated)"
    
    log_info "Consul tokens rotated successfully"
}

# Rotate Nomad tokens
rotate_nomad_tokens() {
    log_info "Rotating Nomad tokens..."
    
    # Get current bootstrap token
    export NOMAD_TOKEN=$(vault kv get -field=token secret/cloudya/nomad/bootstrap)
    
    # Create new developer token
    local new_dev_token=$(nomad acl token create \
        -name="developer-$(date +%s)" \
        -policy="developer" \
        -format json | jq -r '.SecretID')
    
    # Update Vault with new token
    vault kv put secret/cloudya/nomad/tokens/developer \
        token="$new_dev_token" \
        description="Token for developers (rotated)"
    
    log_info "Nomad tokens rotated successfully"
}

# Main execution
main() {
    rotate_consul_tokens
    rotate_nomad_tokens
    log_info "Token rotation completed"
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/acl-scripts/rotate-tokens.sh"
    
    # ACL health check script
    cat > "$PROJECT_ROOT/automation/acl-scripts/acl-health-check.sh" << 'EOF'
#!/usr/bin/env bash
# ACL Health Check Script
# Validates ACL configuration and token health

set -euo pipefail

CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-https://consul.cloudya.net:8500}"
NOMAD_ADDR="${NOMAD_ADDR:-https://nomad.cloudya.net:4646}"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Check Consul ACLs
check_consul_acls() {
    log_info "Checking Consul ACL health..."
    
    export CONSUL_HTTP_TOKEN=$(vault kv get -field=token secret/cloudya/consul/bootstrap)
    
    if consul acl policy list >/dev/null 2>&1; then
        log_info "Consul ACL system is healthy"
        return 0
    else
        log_error "Consul ACL system has issues"
        return 1
    fi
}

# Check Nomad ACLs
check_nomad_acls() {
    log_info "Checking Nomad ACL health..."
    
    export NOMAD_TOKEN=$(vault kv get -field=token secret/cloudya/nomad/bootstrap)
    
    if nomad acl policy list >/dev/null 2>&1; then
        log_info "Nomad ACL system is healthy"
        return 0
    else
        log_error "Nomad ACL system has issues"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0
    
    check_consul_acls || exit_code=1
    check_nomad_acls || exit_code=1
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "All ACL systems are healthy"
    else
        log_error "Some ACL systems have issues"
    fi
    
    exit $exit_code
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/automation/acl-scripts/acl-health-check.sh"
    
    log_success "ACL management scripts created"
}

# Main execution
main() {
    log_info "Starting ACL automation..."
    
    # Configure Consul ACLs
    configure_consul_acls
    
    # Configure Nomad ACLs
    configure_nomad_acls
    
    # Configure integrations
    configure_vault_consul_integration
    configure_vault_nomad_integration
    
    # Update configuration files
    update_configuration_files
    
    # Create management scripts
    create_acl_management_scripts
    
    log_success "ACL automation completed successfully!"
    log_info "ACL tokens have been created and stored in Vault"
    log_info "Configuration files have been updated"
    log_info "Management scripts created in automation/acl-scripts/"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi