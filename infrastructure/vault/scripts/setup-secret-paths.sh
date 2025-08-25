#!/bin/bash

# Setup Vault Secret Paths for Traefik and Multi-Environment Support
# This script creates the necessary secret paths and initializes default secrets

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
ENVIRONMENTS=("develop" "staging" "production")

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Vault is initialized and unsealed
check_vault_status() {
    log_info "Checking Vault status..."
    
    if ! vault status >/dev/null 2>&1; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
    
    if vault status | grep -q "Sealed.*true"; then
        log_error "Vault is sealed. Please unseal it first."
        return 1
    fi
    
    log_success "Vault is accessible and unsealed"
    return 0
}

# Enable secrets engine if not already enabled
enable_secrets_engine() {
    log_info "Checking if KV secrets engine is enabled..."
    
    if vault secrets list | grep -q "secret/"; then
        log_success "KV secrets engine already enabled"
    else
        log_info "Enabling KV secrets engine..."
        vault secrets enable -path=secret kv-v2
        log_success "KV secrets engine enabled"
    fi
}

# Create Traefik dashboard credentials
setup_traefik_dashboard_secrets() {
    log_info "Setting up Traefik dashboard secrets..."
    
    # Generate random password if not provided
    DASHBOARD_USER="${DASHBOARD_USER:-admin}"
    DASHBOARD_PASS="${DASHBOARD_PASS:-$(openssl rand -base64 32)}"
    
    # Create dashboard credentials
    vault kv put secret/traefik/dashboard/credentials \
        username="$DASHBOARD_USER" \
        password="$DASHBOARD_PASS"
    
    log_success "Traefik dashboard credentials created"
    log_info "Dashboard User: $DASHBOARD_USER"
    log_warning "Dashboard Password: $DASHBOARD_PASS (store this securely!)"
}

# Setup certificate paths
setup_certificate_paths() {
    log_info "Setting up certificate storage paths..."
    
    # Create certificate directories in Vault
    for env in "${ENVIRONMENTS[@]}"; do
        vault kv put "secret/traefik/certificates/$env/letsencrypt" \
            cert_type="letsencrypt" \
            environment="$env" \
            managed_by="traefik"
        
        vault kv put "secret/traefik/certificates/$env/custom" \
            cert_type="custom" \
            environment="$env" \
            managed_by="manual"
    done
    
    log_success "Certificate paths initialized"
}

# Setup environment-specific secrets
setup_environment_secrets() {
    log_info "Setting up environment-specific secrets..."
    
    for env in "${ENVIRONMENTS[@]}"; do
        log_info "Setting up secrets for $env environment..."
        
        # Traefik environment-specific configs
        vault kv put "secret/traefik/environments/$env/config" \
            environment="$env" \
            log_level="$([ "$env" = "production" ] && echo "WARN" || echo "DEBUG")" \
            metrics_enabled="true" \
            api_dashboard="$([ "$env" = "production" ] && echo "false" || echo "true")"
        
        # Database credentials placeholders
        vault kv put "secret/database/$env/credentials" \
            host="db-$env.local" \
            port="5432" \
            database="app_$env" \
            username="app_user_$env"
        
        # Service configuration
        vault kv put "secret/services/$env/config" \
            environment="$env" \
            debug_mode="$([ "$env" = "production" ] && echo "false" || echo "true")" \
            log_level="$([ "$env" = "production" ] && echo "info" || echo "debug")"
    done
    
    log_success "Environment-specific secrets initialized"
}

# Setup monitoring secrets
setup_monitoring_secrets() {
    log_info "Setting up monitoring secrets..."
    
    # Prometheus metrics
    vault kv put secret/monitoring/prometheus \
        retention="30d" \
        scrape_interval="15s"
    
    # Grafana dashboard credentials
    vault kv put secret/monitoring/grafana \
        admin_user="admin" \
        admin_password="$(openssl rand -base64 24)"
    
    log_success "Monitoring secrets initialized"
}

# Apply Vault policies
apply_policies() {
    log_info "Applying Vault policies..."
    
    local policy_dir="../policies"
    
    # Main policies
    for policy_file in "$policy_dir"/*.hcl; do
        if [[ -f "$policy_file" ]]; then
            policy_name=$(basename "$policy_file" .hcl)
            vault policy write "$policy_name" "$policy_file"
            log_success "Applied policy: $policy_name"
        fi
    done
    
    # Environment-specific policies
    for policy_file in "$policy_dir"/environments/*.hcl; do
        if [[ -f "$policy_file" ]]; then
            policy_name=$(basename "$policy_file" .hcl)
            vault policy write "$policy_name" "$policy_file"
            log_success "Applied environment policy: $policy_name"
        fi
    done
}

# Create service tokens
create_service_tokens() {
    log_info "Creating service tokens..."
    
    # Traefik service token
    TRAEFIK_TOKEN=$(vault write -field=token auth/token/create \
        policies="traefik-policy" \
        ttl="24h" \
        renewable=true \
        display_name="traefik-service")
    
    vault kv put secret/traefik/auth/service_token \
        token="$TRAEFIK_TOKEN" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        policies="traefik-policy"
    
    log_success "Service tokens created and stored"
}

# Validation function
validate_setup() {
    log_info "Validating setup..."
    
    # Check if secrets are accessible
    vault kv get secret/traefik/dashboard/credentials >/dev/null 2>&1 && \
        log_success "Dashboard credentials accessible" || \
        log_error "Dashboard credentials not accessible"
    
    # Check policies
    vault policy list | grep -q "traefik-policy" && \
        log_success "Traefik policy exists" || \
        log_error "Traefik policy missing"
    
    # Check environment policies
    for env in "${ENVIRONMENTS[@]}"; do
        vault policy list | grep -q "$env-policy" && \
            log_success "$env environment policy exists" || \
            log_warning "$env environment policy missing"
    done
}

# Main execution
main() {
    log_info "Starting Vault secret paths setup..."
    
    check_vault_status || exit 1
    enable_secrets_engine
    setup_traefik_dashboard_secrets
    setup_certificate_paths
    setup_environment_secrets
    setup_monitoring_secrets
    apply_policies
    create_service_tokens
    validate_setup
    
    log_success "Vault secret paths setup completed!"
    log_info "Next steps:"
    echo "  1. Store the dashboard credentials securely"
    echo "  2. Configure Traefik to use the service token"
    echo "  3. Update application configs to use environment-specific secrets"
    echo "  4. Test secret access with the created policies"
}

# Execute main function
main "$@"