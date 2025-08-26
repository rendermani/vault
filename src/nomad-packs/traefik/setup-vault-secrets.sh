#!/usr/bin/env bash
# Vault Secrets Setup for Traefik Nomad Pack
# Initialize all required secrets and policies for Traefik deployment

set -euo pipefail

# Color coding
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERACTIVE="${INTERACTIVE:-true}"

# Verify Vault connection
verify_vault() {
    log_info "Verifying Vault connection..."
    
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault"
        echo "Please ensure Vault is running and VAULT_ADDR is set"
        exit 1
    fi
    
    # Check if authenticated
    if ! vault token lookup &> /dev/null; then
        log_error "Not authenticated with Vault"
        echo "Please authenticate with: vault auth -method=..."
        exit 1
    fi
    
    log_success "Vault connection verified"
}

# Setup KV secrets engine
setup_kv_engine() {
    log_info "Setting up KV v2 secrets engine..."
    
    if vault secrets list | grep -q "kv/"; then
        log_success "KV v2 engine already enabled at kv/"
    else
        log_info "Enabling KV v2 secrets engine..."
        vault secrets enable -path=kv kv-v2
        log_success "KV v2 engine enabled"
    fi
}

# Generate secure password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Generate bcrypt hash for basic auth
generate_bcrypt_hash() {
    local password="$1"
    # Use htpasswd if available, otherwise Python
    if command -v htpasswd &> /dev/null; then
        htpasswd -nbB admin "$password" | cut -d: -f2
    elif command -v python3 &> /dev/null; then
        python3 -c "import bcrypt; print(bcrypt.hashpw('$password'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))"
    else
        log_error "Neither htpasswd nor python3 available for password hashing"
        exit 1
    fi
}

# Setup Cloudflare credentials
setup_cloudflare_credentials() {
    log_info "Setting up Cloudflare credentials..."
    
    if vault kv get kv/cloudflare &> /dev/null; then
        log_success "Cloudflare credentials already exist"
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "Update existing Cloudflare credentials? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 0
            fi
        fi
    fi
    
    local cf_email cf_api_key
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "Enter Cloudflare email: " cf_email
        read -s -p "Enter Cloudflare API key: " cf_api_key
        echo
    else
        cf_email="${CF_EMAIL:-}"
        cf_api_key="${CF_API_KEY:-}"
        
        if [[ -z "$cf_email" || -z "$cf_api_key" ]]; then
            log_error "CF_EMAIL and CF_API_KEY environment variables required in non-interactive mode"
            exit 1
        fi
    fi
    
    # Validate inputs
    if [[ -z "$cf_email" || -z "$cf_api_key" ]]; then
        log_error "Both email and API key are required"
        exit 1
    fi
    
    # Store in Vault
    vault kv put kv/cloudflare \
        email="$cf_email" \
        api_key="$cf_api_key"
    
    log_success "Cloudflare credentials stored in kv/cloudflare"
}

# Setup dashboard credentials
setup_dashboard_credentials() {
    log_info "Setting up Traefik dashboard credentials..."
    
    if vault kv get kv/traefik/dashboard &> /dev/null; then
        log_success "Dashboard credentials already exist"
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "Update existing dashboard credentials? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 0
            fi
        fi
    fi
    
    local admin_password
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "Generate random dashboard password? (Y/n): " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            read -s -p "Enter dashboard password: " admin_password
            echo
        else
            admin_password=$(generate_password)
            log_info "Generated password: $admin_password"
        fi
    else
        admin_password="${DASHBOARD_PASSWORD:-$(generate_password)}"
        log_info "Using password: $admin_password"
    fi
    
    # Generate bcrypt hash
    local bcrypt_hash
    bcrypt_hash=$(generate_bcrypt_hash "$admin_password")
    
    # Store in Vault
    vault kv put kv/traefik/dashboard \
        username="admin" \
        password="$admin_password" \
        basic_auth="admin:$bcrypt_hash"
    
    log_success "Dashboard credentials stored in kv/traefik/dashboard"
}

# Setup monitoring credentials
setup_monitoring_credentials() {
    log_info "Setting up monitoring system credentials..."
    
    local prometheus_password grafana_password
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        prometheus_password=$(generate_password)
        grafana_password=$(generate_password)
    else
        prometheus_password="${PROMETHEUS_PASSWORD:-$(generate_password)}"
        grafana_password="${GRAFANA_PASSWORD:-$(generate_password)}"
    fi
    
    # Prometheus credentials
    vault kv put kv/monitoring/prometheus \
        username="prometheus" \
        password="$prometheus_password"
    
    # Grafana credentials
    vault kv put kv/monitoring/grafana \
        username="admin" \
        password="$grafana_password"
    
    log_success "Monitoring credentials stored"
}

# Setup TLS certificates (if using Vault PKI)
setup_pki_engine() {
    log_info "Setting up PKI secrets engine..."
    
    if vault secrets list | grep -q "pki/"; then
        log_success "PKI engine already enabled"
        return 0
    fi
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "Enable Vault PKI for certificate management? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Enable PKI secrets engine
    vault secrets enable pki
    
    # Configure PKI
    vault secrets tune -max-lease-ttl=87600h pki
    
    # Generate root CA (for internal use)
    vault write -field=certificate pki/root/generate/internal \
        common_name="Cloudya Internal CA" \
        ttl=87600h > ca.crt
    
    # Configure URLs
    vault write pki/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
    
    # Create a role for Traefik
    vault write pki/roles/traefik \
        allowed_domains="cloudya.net" \
        allow_subdomains=true \
        max_ttl="720h"
    
    log_success "PKI engine configured"
    log_info "Root CA certificate saved to ca.crt"
}

# Setup JWT authentication
setup_jwt_auth() {
    log_info "Setting up JWT authentication for Nomad workloads..."
    
    if vault auth list | grep -q "jwt/"; then
        log_success "JWT auth method already enabled"
    else
        log_info "Enabling JWT auth method..."
        vault auth enable jwt
    fi
    
    # Configure JWT auth method for Nomad
    vault write auth/jwt/config \
        bound_issuer="nomad" \
        jwks_url="http://nomad.service.consul:4646/.well-known/jwks.json"
    
    log_success "JWT auth configured for Nomad"
}

# Create Traefik policy
create_traefik_policy() {
    log_info "Creating Traefik Vault policy..."
    
    local policy_file="$SCRIPT_DIR/templates/vault-policy.hcl.tpl"
    
    if [[ -f "$policy_file" ]]; then
        # Remove template syntax for policy creation
        sed 's/\[\[.*\]\]//g' "$policy_file" > /tmp/traefik-policy.hcl
        vault policy write traefik-policy /tmp/traefik-policy.hcl
        rm -f /tmp/traefik-policy.hcl
        log_success "Traefik policy created"
    else
        log_warn "Policy template not found, creating basic policy..."
        
        cat <<EOF | vault policy write traefik-policy -
# Basic Traefik policy
path "kv/data/cloudflare" {
  capabilities = ["read"]
}

path "kv/data/traefik/dashboard" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
        log_success "Basic Traefik policy created"
    fi
}

# Create JWT role for Traefik
create_jwt_role() {
    log_info "Creating JWT role for Traefik..."
    
    vault write auth/jwt/role/traefik \
        bound_audiences="nomad" \
        bound_claims='{"nomad_job_name":"traefik"}' \
        user_claim="nomad_job_id" \
        role_type="jwt" \
        policies="traefik-policy" \
        ttl=1h \
        max_ttl=24h
    
    log_success "JWT role created for Traefik"
}

# Setup additional secrets
setup_additional_secrets() {
    log_info "Setting up additional secrets..."
    
    # Database credentials (example)
    vault kv put kv/database/postgres \
        username="app_user" \
        password="$(generate_password)" \
        host="postgres.service.consul" \
        port="5432"
    
    # Redis credentials (example)
    vault kv put kv/database/redis \
        password="$(generate_password)" \
        host="redis.service.consul" \
        port="6379"
    
    log_success "Additional secrets configured"
}

# Verify setup
verify_setup() {
    log_info "Verifying secrets setup..."
    
    local checks=(
        "kv/cloudflare"
        "kv/traefik/dashboard"
        "kv/monitoring/prometheus"
        "kv/monitoring/grafana"
    )
    
    for secret in "${checks[@]}"; do
        if vault kv get "$secret" &> /dev/null; then
            log_success "✓ $secret"
        else
            log_error "✗ $secret"
        fi
    done
    
    # Check policy
    if vault policy read traefik-policy &> /dev/null; then
        log_success "✓ traefik-policy"
    else
        log_error "✗ traefik-policy"
    fi
    
    # Check JWT role
    if vault read auth/jwt/role/traefik &> /dev/null; then
        log_success "✓ JWT role: traefik"
    else
        log_error "✗ JWT role: traefik"
    fi
    
    log_success "Setup verification completed"
}

# Show summary
show_summary() {
    log_info "=== Setup Summary ==="
    echo
    echo "Secrets created:"
    echo "  • kv/cloudflare - Cloudflare DNS challenge credentials"
    echo "  • kv/traefik/dashboard - Dashboard authentication"
    echo "  • kv/monitoring/* - Monitoring system credentials"
    echo
    echo "Policies created:"
    echo "  • traefik-policy - Vault policy for Traefik"
    echo
    echo "Authentication:"
    echo "  • JWT auth method configured"
    echo "  • JWT role 'traefik' created"
    echo
    echo "Next steps:"
    echo "  1. Deploy Traefik with: ./deploy.sh"
    echo "  2. Verify deployment: nomad job status traefik"
    echo "  3. Access dashboard: https://traefik.cloudya.net"
    echo
    log_success "Traefik secrets setup completed! 🚀"
}

# Main execution
main() {
    log_info "Starting Vault secrets setup for Traefik..."
    
    verify_vault
    setup_kv_engine
    setup_cloudflare_credentials
    setup_dashboard_credentials
    setup_monitoring_credentials
    setup_pki_engine
    setup_jwt_auth
    create_traefik_policy
    create_jwt_role
    setup_additional_secrets
    verify_setup
    show_summary
}

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h        Show this help"
        echo "  --non-interactive Run without prompts"
        echo ""
        echo "Environment variables (non-interactive mode):"
        echo "  CF_EMAIL          Cloudflare email"
        echo "  CF_API_KEY        Cloudflare API key"
        echo "  DASHBOARD_PASSWORD Traefik dashboard password"
        echo "  PROMETHEUS_PASSWORD Prometheus password"
        echo "  GRAFANA_PASSWORD   Grafana password"
        exit 0
        ;;
    "--non-interactive")
        INTERACTIVE="false"
        ;;
esac

# Execute main function
main