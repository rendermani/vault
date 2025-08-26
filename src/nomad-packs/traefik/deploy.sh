#!/usr/bin/env bash
# Traefik Nomad Pack Deployment Script - Phase 6 Production Ready
# Deploy Traefik with Vault integration and SSL certificates

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_NAME="traefik"
ENVIRONMENT="${ENVIRONMENT:-production}"
DRY_RUN="${DRY_RUN:-false}"

# Color coding for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Verify prerequisites
verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    # Check if nomad-pack is installed
    if ! command -v nomad-pack &> /dev/null; then
        log_error "nomad-pack CLI not found. Install from: https://github.com/hashicorp/nomad-pack"
        exit 1
    fi
    
    # Check if Nomad CLI is available
    if ! command -v nomad &> /dev/null; then
        log_error "nomad CLI not found"
        exit 1
    fi
    
    # Verify Nomad connection
    if ! nomad status &> /dev/null; then
        log_error "Cannot connect to Nomad cluster"
        exit 1
    fi
    
    # Check if Vault CLI is available
    if ! command -v vault &> /dev/null; then
        log_error "vault CLI not found"
        exit 1
    fi
    
    # Verify Vault connection
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault"
        exit 1
    fi
    
    log_success "All prerequisites verified"
}

# Create required Vault secrets
setup_vault_secrets() {
    log_info "Setting up Vault secrets..."
    
    # Create KV v2 secrets engine if it doesn't exist
    if ! vault secrets list | grep -q "kv/"; then
        log_info "Creating KV v2 secrets engine..."
        vault secrets enable -path=kv kv-v2
    fi
    
    # Check if required secrets exist
    local secrets_missing=false
    
    if ! vault kv get kv/cloudflare &> /dev/null; then
        log_warn "Cloudflare credentials not found at kv/cloudflare"
        secrets_missing=true
    fi
    
    if ! vault kv get kv/traefik/dashboard &> /dev/null; then
        log_warn "Dashboard credentials not found at kv/traefik/dashboard"
        secrets_missing=true
    fi
    
    if [[ "$secrets_missing" == "true" ]]; then
        log_warn "Some secrets are missing. Please create them manually or use the setup script:"
        echo "  vault kv put kv/cloudflare api_key=your_api_key email=your_email"
        echo "  vault kv put kv/traefik/dashboard basic_auth='admin:\$2y\$10\$...'"
        read -p "Continue anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Vault secrets verification completed"
}

# Setup Vault policies
setup_vault_policies() {
    log_info "Setting up Vault policies..."
    
    # Create Traefik policy from template
    local policy_file="${SCRIPT_DIR}/templates/vault-policy.hcl.tpl"
    if [[ -f "$policy_file" ]]; then
        # Process template to remove template syntax for policy creation
        sed 's/\[\[.*\]\]//g' "$policy_file" | vault policy write traefik-policy -
        log_success "Traefik policy created"
    else
        log_warn "Policy template not found at $policy_file"
    fi
    
    # Verify JWT auth method exists
    if ! vault auth list | grep -q "jwt/"; then
        log_warn "JWT auth method not enabled. Please enable it first:"
        echo "  vault auth enable jwt"
        exit 1
    fi
    
    # Create JWT role for Traefik
    vault write auth/jwt/role/traefik \
        bound_audiences="nomad" \
        bound_claims='{"nomad_job_name":"traefik","nomad_task":"traefik"}' \
        user_claim="nomad_job_id" \
        role_type="jwt" \
        policies="traefik-policy" \
        ttl=1h \
        max_ttl=24h
    
    log_success "JWT role created for Traefik"
}

# Setup host volumes for ACME storage
setup_host_volumes() {
    log_info "Setting up host volumes..."
    
    # This should be done on all Nomad clients
    log_warn "Ensure the following host volume is configured on all Nomad clients:"
    echo "  client {"
    echo "    host_volume \"traefik-acme\" {"
    echo "      path      = \"/opt/nomad/volumes/traefik-acme\""
    echo "      read_only = false"
    echo "    }"
    echo "  }"
    
    read -p "Press Enter when host volumes are configured..."
}

# Validate pack configuration
validate_pack() {
    log_info "Validating pack configuration..."
    
    cd "$SCRIPT_DIR"
    
    # Check if pack renders correctly
    if nomad-pack render . --name "$PACK_NAME" > /tmp/traefik-rendered.nomad; then
        log_success "Pack renders successfully"
        
        # Validate with Nomad
        if nomad job validate /tmp/traefik-rendered.nomad; then
            log_success "Nomad job validation passed"
        else
            log_error "Nomad job validation failed"
            exit 1
        fi
    else
        log_error "Pack rendering failed"
        exit 1
    fi
    
    # Clean up
    rm -f /tmp/traefik-rendered.nomad
}

# Deploy the pack
deploy_pack() {
    log_info "Deploying Traefik pack..."
    
    cd "$SCRIPT_DIR"
    
    local deploy_cmd="nomad-pack run . --name $PACK_NAME"
    
    # Add environment-specific variables
    case "$ENVIRONMENT" in
        "development")
            deploy_cmd+=" --var acme_ca_server=https://acme-staging-v02.api.letsencrypt.org/directory"
            deploy_cmd+=" --var debug_enabled=true"
            deploy_cmd+=" --var log_level=DEBUG"
            ;;
        "staging")
            deploy_cmd+=" --var acme_ca_server=https://acme-staging-v02.api.letsencrypt.org/directory"
            deploy_cmd+=" --var count=2"
            ;;
        "production")
            deploy_cmd+=" --var environment=production"
            deploy_cmd+=" --var count=3"
            ;;
        *)
            log_error "Unknown environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - would execute: $deploy_cmd"
        return 0
    fi
    
    # Execute deployment
    if eval "$deploy_cmd"; then
        log_success "Traefik pack deployed successfully"
    else
        log_error "Pack deployment failed"
        exit 1
    fi
}

# Monitor deployment
monitor_deployment() {
    log_info "Monitoring deployment status..."
    
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [[ $elapsed -lt $timeout ]]; do
        if nomad job status traefik &> /dev/null; then
            local status=$(nomad job status traefik | grep "Status" | awk '{print $3}')
            case "$status" in
                "running")
                    log_success "Traefik is running successfully"
                    break
                    ;;
                "pending")
                    log_info "Deployment still pending... (${elapsed}s elapsed)"
                    ;;
                "dead"|"failed")
                    log_error "Deployment failed with status: $status"
                    nomad job status traefik
                    exit 1
                    ;;
            esac
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Deployment timeout after ${timeout}s"
        exit 1
    fi
}

# Verify services
verify_services() {
    log_info "Verifying services..."
    
    # Check if services are registered in Consul
    local services=("traefik" "traefik-metrics")
    
    for service in "${services[@]}"; do
        if nomad service list | grep -q "$service"; then
            log_success "Service $service is registered"
        else
            log_warn "Service $service not found"
        fi
    done
    
    # Test HTTP endpoints if accessible
    if command -v curl &> /dev/null; then
        log_info "Testing HTTP endpoints..."
        
        # Test Traefik ping endpoint
        if curl -f -s http://localhost:8080/ping > /dev/null; then
            log_success "Traefik ping endpoint accessible"
        else
            log_warn "Traefik ping endpoint not accessible"
        fi
        
        # Test metrics endpoint
        if curl -f -s http://localhost:8082/metrics > /dev/null; then
            log_success "Metrics endpoint accessible"
        else
            log_warn "Metrics endpoint not accessible"
        fi
    fi
}

# Show deployment summary
show_summary() {
    log_info "Deployment Summary:"
    echo "  Pack Name: $PACK_NAME"
    echo "  Environment: $ENVIRONMENT"
    echo "  Nomad Job: traefik"
    echo ""
    echo "Access URLs:"
    echo "  Dashboard: https://traefik.cloudya.net"
    echo "  Vault: https://vault.cloudya.net"
    echo "  Consul: https://consul.cloudya.net"
    echo "  Nomad: https://nomad.cloudya.net"
    echo ""
    echo "Monitoring:"
    echo "  Metrics: http://localhost:8082/metrics"
    echo "  Health: http://localhost:8080/ping"
    echo ""
    echo "Management Commands:"
    echo "  Status: nomad job status traefik"
    echo "  Logs: nomad alloc logs -job traefik"
    echo "  Stop: nomad job stop traefik"
    echo "  Update: nomad-pack run . --name $PACK_NAME"
}

# Main execution
main() {
    log_info "Starting Traefik deployment for environment: $ENVIRONMENT"
    
    verify_prerequisites
    setup_vault_secrets
    setup_vault_policies
    setup_host_volumes
    validate_pack
    deploy_pack
    
    if [[ "$DRY_RUN" != "true" ]]; then
        monitor_deployment
        verify_services
        show_summary
    fi
    
    log_success "Traefik deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h          Show this help"
        echo "  --dry-run          Validate only, don't deploy"
        echo ""
        echo "Environment variables:"
        echo "  ENVIRONMENT        deployment environment (development|staging|production)"
        echo "  DRY_RUN           set to 'true' for dry-run mode"
        exit 0
        ;;
    "--dry-run")
        DRY_RUN="true"
        ;;
esac

# Execute main function
main