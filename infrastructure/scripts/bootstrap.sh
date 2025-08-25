#!/bin/bash

# Enterprise Infrastructure Bootstrap Script
# Coordinates deployment of Vault -> Nomad -> Traefik in proper dependency order

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-develop}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Health check function
check_service_health() {
    local service=$1
    local health_endpoint=$2
    local max_retries=${3:-30}
    local retry_interval=${4:-10}
    
    log_info "Checking health of $service..."
    
    for ((i=1; i<=max_retries; i++)); do
        if curl -sf "$health_endpoint" > /dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
        fi
        
        log_warn "$service not ready, attempt $i/$max_retries"
        sleep $retry_interval
    done
    
    log_error "$service failed health check after $max_retries attempts"
    return 1
}

# Bootstrap Vault first (foundation layer)
bootstrap_vault() {
    log_info "Bootstrapping Vault for environment: $ENVIRONMENT"
    
    cd "$INFRA_DIR/repositories/vault"
    
    # Environment-specific configuration
    case $ENVIRONMENT in
        develop)
            export VAULT_DEV_MODE=true
            export VAULT_REPLICAS=1
            ;;
        staging)
            export VAULT_REPLICAS=3
            export VAULT_HA_ENABLED=true
            ;;
        production)
            export VAULT_REPLICAS=5
            export VAULT_HA_ENABLED=true
            export VAULT_PERFORMANCE_STANDBY=true
            ;;
    esac
    
    # Deploy Vault
    log_info "Deploying Vault cluster..."
    if [[ -f "deploy-$ENVIRONMENT.sh" ]]; then
        ./deploy-$ENVIRONMENT.sh
    else
        log_warn "No environment-specific deploy script found, using default"
        make deploy ENVIRONMENT=$ENVIRONMENT
    fi
    
    # Health check
    check_service_health "Vault" "http://localhost:8200/v1/sys/health"
    
    # Initialize if needed
    if [[ ! -f "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json" ]]; then
        log_info "Initializing Vault..."
        vault operator init -format=json > "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json"
        log_success "Vault initialized, keys saved"
    fi
    
    # Unseal Vault
    log_info "Unsealing Vault..."
    UNSEAL_KEYS=$(jq -r '.unseal_keys_b64[]' "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json")
    for key in $(echo $UNSEAL_KEYS | head -3); do
        vault operator unseal "$key"
    done
    
    # Setup initial policies and secrets
    log_info "Setting up initial Vault configuration..."
    ROOT_TOKEN=$(jq -r '.root_token' "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json")
    export VAULT_TOKEN=$ROOT_TOKEN
    
    # Enable secret engines
    vault secrets enable -path=secret kv-v2
    vault secrets enable -path=nomad-secrets kv-v2
    vault secrets enable -path=traefik-secrets kv-v2
    
    # Create policies
    vault policy write nomad-policy - <<EOF
path "nomad-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/*" {
  capabilities = ["read", "list"]
}
EOF
    
    vault policy write traefik-policy - <<EOF
path "traefik-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/*" {
  capabilities = ["read", "list"]
}
EOF
    
    log_success "Vault bootstrap completed"
}

# Bootstrap Nomad second (orchestration layer)
bootstrap_nomad() {
    log_info "Bootstrapping Nomad for environment: $ENVIRONMENT"
    
    # Ensure Vault is available
    if ! vault status > /dev/null 2>&1; then
        log_error "Vault is not available, cannot bootstrap Nomad"
        return 1
    fi
    
    cd "$INFRA_DIR/repositories/nomad"
    
    # Environment-specific configuration
    case $ENVIRONMENT in
        develop)
            export NOMAD_DEV_MODE=true
            export NOMAD_REPLICAS=1
            ;;
        staging)
            export NOMAD_REPLICAS=3
            export NOMAD_BOOTSTRAP_EXPECT=3
            ;;
        production)
            export NOMAD_REPLICAS=5
            export NOMAD_BOOTSTRAP_EXPECT=5
            ;;
    esac
    
    # Setup Vault integration
    log_info "Configuring Nomad-Vault integration..."
    
    # Create Nomad token in Vault
    NOMAD_TOKEN=$(vault write -field=token auth/token/create policies=nomad-policy)
    export VAULT_TOKEN=$NOMAD_TOKEN
    
    # Deploy Nomad
    log_info "Deploying Nomad cluster..."
    if [[ -f "deploy-$ENVIRONMENT.sh" ]]; then
        ./deploy-$ENVIRONMENT.sh
    else
        log_warn "No environment-specific deploy script found, using default"
        make deploy ENVIRONMENT=$ENVIRONMENT
    fi
    
    # Health check
    check_service_health "Nomad" "http://localhost:4646/v1/status/leader"
    
    # Bootstrap ACLs if needed
    if [[ ! -f "$INFRA_DIR/secrets/nomad-bootstrap-$ENVIRONMENT.json" ]]; then
        log_info "Bootstrapping Nomad ACLs..."
        nomad acl bootstrap -json > "$INFRA_DIR/secrets/nomad-bootstrap-$ENVIRONMENT.json"
        log_success "Nomad ACLs bootstrapped"
    fi
    
    log_success "Nomad bootstrap completed"
}

# Bootstrap Traefik last (gateway layer)
bootstrap_traefik() {
    log_info "Bootstrapping Traefik for environment: $ENVIRONMENT"
    
    # Ensure dependencies are available
    if ! vault status > /dev/null 2>&1; then
        log_error "Vault is not available, cannot bootstrap Traefik"
        return 1
    fi
    
    if ! nomad status > /dev/null 2>&1; then
        log_error "Nomad is not available, cannot bootstrap Traefik"
        return 1
    fi
    
    cd "$INFRA_DIR/repositories/traefik"
    
    # Setup secrets in Vault
    log_info "Setting up Traefik secrets in Vault..."
    
    # Generate dashboard credentials
    TRAEFIK_USER="admin"
    TRAEFIK_PASSWORD=$(openssl rand -base64 32)
    TRAEFIK_HASH=$(htpasswd -nbB "$TRAEFIK_USER" "$TRAEFIK_PASSWORD" | cut -d: -f2)
    
    # Store in Vault
    vault kv put traefik-secrets/dashboard \
        username="$TRAEFIK_USER" \
        password="$TRAEFIK_PASSWORD" \
        hash="$TRAEFIK_HASH"
    
    # Generate API key
    TRAEFIK_API_KEY=$(openssl rand -hex 32)
    vault kv put traefik-secrets/api \
        key="$TRAEFIK_API_KEY"
    
    # Setup certificates (if not development)
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        log_info "Setting up TLS certificates..."
        # Certificate generation/management logic here
    fi
    
    # Environment-specific configuration
    case $ENVIRONMENT in
        develop)
            export TRAEFIK_LOG_LEVEL=DEBUG
            export TRAEFIK_API_INSECURE=true
            export TRAEFIK_DASHBOARD=true
            ;;
        staging)
            export TRAEFIK_LOG_LEVEL=INFO
            export TRAEFIK_API_INSECURE=false
            export TRAEFIK_DASHBOARD=true
            ;;
        production)
            export TRAEFIK_LOG_LEVEL=WARN
            export TRAEFIK_API_INSECURE=false
            export TRAEFIK_DASHBOARD=false
            ;;
    esac
    
    # Deploy Traefik via Nomad
    log_info "Deploying Traefik via Nomad..."
    nomad job run traefik-$ENVIRONMENT.nomad
    
    # Health check
    check_service_health "Traefik" "http://localhost:8080/ping"
    
    log_success "Traefik bootstrap completed"
    
    # Output credentials for development/staging
    if [[ "$ENVIRONMENT" != "production" ]]; then
        log_info "Traefik Dashboard Credentials:"
        echo "URL: http://localhost:8080/dashboard/"
        echo "Username: $TRAEFIK_USER"
        echo "Password: $TRAEFIK_PASSWORD"
    fi
}

# Main bootstrap function
main() {
    log_info "Starting enterprise infrastructure bootstrap for environment: $ENVIRONMENT"
    
    # Create necessary directories
    mkdir -p "$INFRA_DIR/secrets"
    mkdir -p "$INFRA_DIR/logs"
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be develop, staging, or production"
        exit 1
    fi
    
    # Bootstrap in dependency order
    bootstrap_vault
    bootstrap_nomad
    bootstrap_traefik
    
    log_success "Enterprise infrastructure bootstrap completed successfully!"
    log_info "Services are now available:"
    log_info "  - Vault: http://localhost:8200"
    log_info "  - Nomad: http://localhost:4646"
    log_info "  - Traefik: http://localhost:8080"
}

# Run main function
main "$@"