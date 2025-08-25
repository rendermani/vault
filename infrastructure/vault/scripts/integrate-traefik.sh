#!/bin/bash

# Integrate Traefik with Vault
# This script configures Traefik to use Vault for secret management

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
TRAEFIK_CONFIG_DIR="${TRAEFIK_CONFIG_DIR:-../../../traefik/config}"
ENVIRONMENT="${ENVIRONMENT:-develop}"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if vault command is available
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault CLI not found. Please install Vault."
        return 1
    fi
    
    # Check if Vault is accessible
    if ! vault status >/dev/null 2>&1; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
    
    # Check if Traefik config directory exists
    if [[ ! -d "$TRAEFIK_CONFIG_DIR" ]]; then
        log_error "Traefik config directory not found: $TRAEFIK_CONFIG_DIR"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Setup Traefik-specific secrets
setup_traefik_secrets() {
    log_info "Setting up Traefik-specific secrets..."
    
    # Create API key for Traefik API access
    local api_key
    api_key=$(openssl rand -base64 32)
    
    vault kv put "secret/traefik/environments/$ENVIRONMENT/api" \
        api_key="$api_key" \
        api_enabled="true" \
        insecure_api="$([ "$ENVIRONMENT" = "develop" ] && echo "true" || echo "false")"
    
    # Create middleware secrets
    vault kv put "secret/traefik/environments/$ENVIRONMENT/middleware" \
        basic_auth_users="admin:\$2y\$10\$example.hash.here" \
        rate_limit_average="100" \
        rate_limit_burst="50"
    
    # Create Let's Encrypt configuration
    local le_email="admin@cloudya.net"
    local le_server="$([ "$ENVIRONMENT" = "production" ] && echo "https://acme-v02.api.letsencrypt.org/directory" || echo "https://acme-staging-v02.api.letsencrypt.org/directory")"
    
    vault kv put "secret/traefik/environments/$ENVIRONMENT/acme" \
        email="$le_email" \
        ca_server="$le_server" \
        key_type="EC256" \
        storage_path="/etc/traefik/acme/$ENVIRONMENT.json"
    
    log_success "Traefik secrets configured for $ENVIRONMENT environment"
}

# Generate Traefik service token
generate_service_token() {
    log_info "Generating Traefik service token..."
    
    # Create a long-lived token for Traefik service
    local service_token
    service_token=$(vault write -field=token auth/token/create \
        policies="traefik-policy" \
        ttl="24h" \
        renewable=true \
        display_name="traefik-$ENVIRONMENT" \
        meta="environment=$ENVIRONMENT,service=traefik")
    
    # Store the token securely in Vault
    vault kv put "secret/traefik/environments/$ENVIRONMENT/auth" \
        service_token="$service_token" \
        token_created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        token_ttl="24h" \
        environment="$ENVIRONMENT"
    
    log_success "Service token generated and stored"
    log_info "Token: $service_token"
    log_warning "Store this token securely - it won't be displayed again!"
    
    return 0
}

# Create Traefik Vault plugin configuration
create_vault_plugin_config() {
    log_info "Creating Traefik Vault plugin configuration..."
    
    local plugin_config="$TRAEFIK_CONFIG_DIR/vault-plugin.yml"
    
    cat > "$plugin_config" << EOF
# Traefik Vault Plugin Configuration
experimental:
  plugins:
    vault:
      moduleName: "github.com/traefik/traefik-vault-plugin"
      version: "v1.0.0"

# Vault provider configuration
providers:
  vault:
    endpoints:
      - "$VAULT_ADDR"
    token: "{{ .Env.VAULT_TOKEN }}"
    pollInterval: "30s"
    exposedByDefault: false
    rootKey: "traefik/environments/$ENVIRONMENT"

# Vault-backed middleware
http:
  middlewares:
    vault-auth:
      plugin:
        vault:
          secretPath: "secret/traefik/environments/$ENVIRONMENT/middleware"
          key: "basic_auth_users"
    
    vault-rate-limit:
      plugin:
        vault:
          secretPath: "secret/traefik/environments/$ENVIRONMENT/middleware"
          averageKey: "rate_limit_average"
          burstKey: "rate_limit_burst"

# TLS configuration from Vault
tls:
  options:
    vault-tls:
      minVersion: "VersionTLS12"
      sslProtocols:
        - "TLSv1.2"
        - "TLSv1.3"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
EOF
    
    log_success "Vault plugin configuration created: $plugin_config"
}

# Update Traefik dynamic configuration for Vault
update_traefik_dynamic_config() {
    log_info "Updating Traefik dynamic configuration for Vault integration..."
    
    local services_config="$TRAEFIK_CONFIG_DIR/dynamic/services.yml"
    
    # Backup existing configuration
    if [[ -f "$services_config" ]]; then
        cp "$services_config" "$services_config.backup.$(date +%s)"
        log_info "Backed up existing services configuration"
    fi
    
    # Add Vault-integrated services
    cat >> "$services_config" << EOF

# Vault-integrated services
http:
  services:
    vault-dashboard:
      loadBalancer:
        servers:
          - url: "http://vault:8200"
        healthCheck:
          path: "/v1/sys/health"
          interval: "30s"
          timeout: "5s"
    
    vault-metrics:
      loadBalancer:
        servers:
          - url: "http://vault:8200"
        healthCheck:
          path: "/v1/sys/metrics"
          interval: "60s"
          timeout: "10s"

  routers:
    vault-dashboard:
      rule: "Host(\`vault-$ENVIRONMENT.cloudya.net\`)"
      service: "vault-dashboard"
      middlewares:
        - "vault-auth@file"
        - "vault-rate-limit@file"
      tls:
        certResolver: "letsencrypt"
        options: "vault-tls@file"
    
    vault-metrics:
      rule: "Host(\`vault-$ENVIRONMENT.cloudya.net\`) && Path(\`/metrics\`)"
      service: "vault-metrics"
      middlewares:
        - "vault-auth@file"
      tls:
        certResolver: "letsencrypt"
EOF
    
    log_success "Updated Traefik dynamic configuration"
}

# Create environment file for Traefik
create_traefik_env_file() {
    log_info "Creating Traefik environment file..."
    
    local env_file="$TRAEFIK_CONFIG_DIR/../.env.$ENVIRONMENT"
    
    # Get the service token
    local vault_token
    vault_token=$(vault kv get -field=service_token "secret/traefik/environments/$ENVIRONMENT/auth")
    
    cat > "$env_file" << EOF
# Traefik Environment Configuration for $ENVIRONMENT
VAULT_ADDR=$VAULT_ADDR
VAULT_TOKEN=$vault_token
ENVIRONMENT=$ENVIRONMENT

# Let's Encrypt Configuration
LE_EMAIL=$(vault kv get -field=email "secret/traefik/environments/$ENVIRONMENT/acme")
LE_SERVER=$(vault kv get -field=ca_server "secret/traefik/environments/$ENVIRONMENT/acme")

# API Configuration
TRAEFIK_API_KEY=$(vault kv get -field=api_key "secret/traefik/environments/$ENVIRONMENT/api")
TRAEFIK_API_INSECURE=$(vault kv get -field=insecure_api "secret/traefik/environments/$ENVIRONMENT/api")
EOF
    
    chmod 600 "$env_file"
    log_success "Created environment file: $env_file"
    log_warning "Environment file contains sensitive data - protect it accordingly!"
}

# Setup automatic token renewal
setup_token_renewal() {
    log_info "Setting up automatic token renewal..."
    
    local renewal_script="$TRAEFIK_CONFIG_DIR/../scripts/renew-vault-token.sh"
    
    mkdir -p "$(dirname "$renewal_script")"
    
    cat > "$renewal_script" << 'EOF'
#!/bin/bash

# Automatic Vault Token Renewal for Traefik
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-develop}"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
ENV_FILE="${ENV_FILE:-$(dirname "$0")/../.env.$ENVIRONMENT}"

# Load current environment
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Check token status
if vault token lookup >/dev/null 2>&1; then
    TTL=$(vault token lookup -format=json | jq -r '.data.ttl')
    
    # Renew token if TTL is less than 6 hours (21600 seconds)
    if [[ "$TTL" -lt 21600 ]]; then
        echo "Renewing Vault token (TTL: ${TTL}s)"
        NEW_TOKEN=$(vault token renew -format=json | jq -r '.auth.client_token')
        
        # Update environment file
        sed -i "s/VAULT_TOKEN=.*/VAULT_TOKEN=$NEW_TOKEN/" "$ENV_FILE"
        
        # Restart Traefik if running in Docker
        if docker ps | grep -q traefik; then
            echo "Restarting Traefik container"
            docker restart traefik
        fi
        
        echo "Token renewed successfully"
    else
        echo "Token still valid (TTL: ${TTL}s)"
    fi
else
    echo "Error: Cannot access Vault or token invalid"
    exit 1
fi
EOF
    
    chmod +x "$renewal_script"
    log_success "Token renewal script created: $renewal_script"
    
    # Suggest cron job
    log_info "Add this cron job for automatic token renewal:"
    echo "0 */4 * * * $renewal_script >> /var/log/traefik-vault-renewal.log 2>&1"
}

# Validate integration
validate_integration() {
    log_info "Validating Traefik-Vault integration..."
    
    local errors=0
    
    # Check if service token works
    local vault_token
    vault_token=$(vault kv get -field=service_token "secret/traefik/environments/$ENVIRONMENT/auth" 2>/dev/null || echo "")
    
    if [[ -n "$vault_token" ]]; then
        export VAULT_TOKEN="$vault_token"
        
        if vault kv get "secret/traefik/dashboard/credentials" >/dev/null 2>&1; then
            log_success "Service token can access Traefik secrets"
        else
            log_error "Service token cannot access Traefik secrets"
            ((errors++))
        fi
        
        unset VAULT_TOKEN
    else
        log_error "Service token not found"
        ((errors++))
    fi
    
    # Check configuration files
    local config_files=(
        "$TRAEFIK_CONFIG_DIR/vault-plugin.yml"
        "$TRAEFIK_CONFIG_DIR/dynamic/services.yml"
        "$TRAEFIK_CONFIG_DIR/../.env.$ENVIRONMENT"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            log_success "Configuration file exists: $config_file"
        else
            log_error "Configuration file missing: $config_file"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Integration validation passed!"
        return 0
    else
        log_error "$errors validation errors found"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting Traefik-Vault integration for $ENVIRONMENT environment..."
    
    check_prerequisites || exit 1
    setup_traefik_secrets
    generate_service_token
    create_vault_plugin_config
    update_traefik_dynamic_config
    create_traefik_env_file
    setup_token_renewal
    validate_integration
    
    log_success "Traefik-Vault integration completed successfully!"
    log_info "Next steps:"
    echo "  1. Review the generated configuration files"
    echo "  2. Restart Traefik with the new configuration"
    echo "  3. Test the integration by accessing Vault-protected routes"
    echo "  4. Set up the cron job for automatic token renewal"
    echo "  5. Monitor logs for any integration issues"
}

# Execute main function
main "$@"