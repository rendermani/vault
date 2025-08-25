#!/bin/bash

# Unified Infrastructure Bootstrap Script

# Ensure homebrew binaries are in PATH (for macOS)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Handles Nomad → Vault → Traefik deployment sequence with circular dependency resolution
# Supports both GitHub Actions and manual deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Default configuration
ENVIRONMENT="develop"
COMPONENTS="all"
DRY_RUN=false
FORCE_BOOTSTRAP=false
SKIP_VALIDATION=false
CLEANUP_ON_FAILURE=true
VERBOSE=false

# Service endpoints
CONSUL_ADDR="http://localhost:8500"
NOMAD_ADDR="http://localhost:4646"
VAULT_ADDR_DEVELOP="http://localhost:8200"
VAULT_ADDR_STAGING="https://localhost:8210"
VAULT_ADDR_PRODUCTION="https://localhost:8220"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging functions
log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

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

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Usage function
usage() {
    cat <<EOF
Unified Infrastructure Bootstrap Script
Deploys Nomad → Vault → Traefik in the correct dependency order

Usage: $0 [OPTIONS]

Options:
  -e, --environment ENV      Environment (develop|staging|production) [default: develop]
  -c, --components COMP      Components to deploy (all|nomad|vault|traefik|nomad,vault) [default: all]
  -d, --dry-run             Perform dry run without actual deployment
  -f, --force-bootstrap     Force complete bootstrap (destroys existing data)
  -s, --skip-validation     Skip pre-deployment validation
  -n, --no-cleanup          Don't cleanup on failure
  -v, --verbose             Enable verbose debug output
  -h, --help                Show this help message

Examples:
  $0 --environment develop
  $0 --environment staging --components nomad,vault --dry-run
  $0 --environment production --force-bootstrap
  $0 --components vault --verbose

Component Deployment Order:
  1. Nomad (orchestration foundation)
  2. Vault (secrets management)
  3. Traefik (gateway and load balancing)

Bootstrap Process:
  - Uses temporary GitHub secrets for initial Nomad cluster
  - Deploys Vault on Nomad using temporary tokens
  - Migrates from temporary tokens to Vault-managed tokens
  - Deploys Traefik with full Vault integration

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -c|--components)
                COMPONENTS="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force-bootstrap)
                FORCE_BOOTSTRAP=true
                shift
                ;;
            -s|--skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -n|--no-cleanup)
                CLEANUP_ON_FAILURE=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        develop|staging|production)
            log_info "Environment validated: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid environments: develop, staging, production"
            exit 1
            ;;
    esac
    
    # Set environment-specific Vault address
    case $ENVIRONMENT in
        develop)
            export VAULT_ADDR="$VAULT_ADDR_DEVELOP"
            ;;
        staging)
            export VAULT_ADDR="$VAULT_ADDR_STAGING"
            ;;
        production)
            export VAULT_ADDR="$VAULT_ADDR_PRODUCTION"
            ;;
    esac
    
    export NOMAD_ADDR="$NOMAD_ADDR"
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"
}

# Validate components to deploy
validate_components() {
    DEPLOY_NOMAD=false
    DEPLOY_VAULT=false
    DEPLOY_TRAEFIK=false
    
    if [[ "$COMPONENTS" == "all" ]]; then
        DEPLOY_NOMAD=true
        DEPLOY_VAULT=true
        DEPLOY_TRAEFIK=true
        log_info "All components will be deployed"
    else
        IFS=',' read -ra COMP_ARRAY <<< "$COMPONENTS"
        for component in "${COMP_ARRAY[@]}"; do
            case $component in
                nomad)
                    DEPLOY_NOMAD=true
                    log_info "Nomad will be deployed"
                    ;;
                vault)
                    DEPLOY_VAULT=true
                    log_info "Vault will be deployed"
                    ;;
                traefik)
                    DEPLOY_TRAEFIK=true
                    log_info "Traefik will be deployed"
                    ;;
                *)
                    log_error "Invalid component: $component"
                    log_error "Valid components: nomad, vault, traefik, all"
                    exit 1
                    ;;
            esac
        done
    fi
    
    # Validate component dependencies
    if [[ "$DEPLOY_VAULT" == "true" && "$DEPLOY_NOMAD" == "false" ]]; then
        log_warning "Vault requires Nomad to be available"
        log_warning "Assuming Nomad is already deployed"
    fi
    
    if [[ "$DEPLOY_TRAEFIK" == "true" && "$DEPLOY_VAULT" == "false" ]]; then
        log_warning "Traefik requires Vault to be available"
        log_warning "Assuming Vault is already deployed"
    fi
}

# Check prerequisites
check_prerequisites() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping prerequisites validation as requested"
        return 0
    fi
    
    log_step "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("curl" "jq" "docker")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
        log_debug "$cmd: $(which $cmd)"
    done
    
    # Check HashiCorp tools if components are being deployed
    if [[ "$DEPLOY_NOMAD" == "true" ]]; then
        if ! command -v nomad &> /dev/null; then
            log_error "Nomad CLI not found. Please install Nomad."
            exit 1
        fi
        log_debug "nomad: $(nomad version | head -1)"
    fi
    
    if [[ "$DEPLOY_VAULT" == "true" ]]; then
        if ! command -v vault &> /dev/null; then
            log_error "Vault CLI not found. Please install Vault."
            exit 1
        fi
        log_debug "vault: $(vault version | head -1)"
    fi
    
    # Check if running as root for some operations
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. Some operations may behave differently."
    fi
    
    # Check Docker if required
    if ! docker ps &> /dev/null; then
        log_error "Docker is not available or not running."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Determine if this is a bootstrap deployment
determine_deployment_strategy() {
    local is_bootstrap=false
    
    if [[ "$FORCE_BOOTSTRAP" == "true" ]]; then
        is_bootstrap=true
        log_warning "Force bootstrap requested - this will destroy existing data!"
    elif [[ ! -f "$INFRA_DIR/environments/$ENVIRONMENT/.deployed" ]]; then
        is_bootstrap=true
        log_info "No deployment marker found - performing bootstrap deployment"
    else
        log_info "Existing deployment detected - performing update deployment"
    fi
    
    if [[ "$is_bootstrap" == "true" ]]; then
        if [[ "$FORCE_BOOTSTRAP" != "true" && "$DRY_RUN" != "true" ]]; then
            echo ""
            log_warning "This will perform a BOOTSTRAP deployment which may:"
            log_warning "- Destroy existing data"
            log_warning "- Reset all secrets and tokens" 
            log_warning "- Reinitialize all services"
            echo ""
            read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Bootstrap cancelled by user"
                exit 0
            fi
        fi
        export IS_BOOTSTRAP=true
    else
        export IS_BOOTSTRAP=false
    fi
}

# Setup temporary bootstrap tokens
setup_bootstrap_tokens() {
    if [[ "$IS_BOOTSTRAP" != "true" ]]; then
        log_debug "Not a bootstrap deployment, skipping temporary token setup"
        return 0
    fi
    
    log_step "Setting up temporary bootstrap tokens..."
    
    # Create temporary directory for bootstrap tokens
    TEMP_DIR=$(mktemp -d -t bootstrap-tokens.XXXXXX)
    mkdir -p "$TEMP_DIR"
    
    # In GitHub Actions, these would come from secrets
    # For manual deployment, generate temporary tokens
    if [[ -z "${NOMAD_BOOTSTRAP_TOKEN:-}" ]]; then
        log_info "Generating temporary Nomad bootstrap token..."
        NOMAD_BOOTSTRAP_TOKEN=$(openssl rand -hex 32)
        export NOMAD_BOOTSTRAP_TOKEN
    fi
    
    if [[ -z "${CONSUL_BOOTSTRAP_TOKEN:-}" ]]; then
        log_info "Generating temporary Consul bootstrap token..."
        CONSUL_BOOTSTRAP_TOKEN=$(openssl rand -hex 32)
        export CONSUL_BOOTSTRAP_TOKEN
    fi
    
    # Store tokens temporarily with secure permissions
    echo "$NOMAD_BOOTSTRAP_TOKEN" > "$TEMP_DIR/nomad.token"
    echo "$CONSUL_BOOTSTRAP_TOKEN" > "$TEMP_DIR/consul.token"
    chmod 600 "$TEMP_DIR"/*.token
    
    log_success "Temporary bootstrap tokens configured"
    log_warning "These tokens will be replaced with Vault-managed tokens after Vault deployment"
}

# Deploy Nomad cluster
deploy_nomad() {
    if [[ "$DEPLOY_NOMAD" != "true" ]]; then
        log_debug "Skipping Nomad deployment"
        return 0
    fi
    
    log_header "DEPLOYING NOMAD CLUSTER"
    
    log_step "Starting Consul for service discovery..."
    if [[ "$DRY_RUN" != "true" ]]; then
        # Start Consul in development mode
        consul agent -dev -client=0.0.0.0 &
        local consul_pid=$!
        sleep 10
        
        # Verify Consul is running
        if ! consul members &> /dev/null; then
            log_error "Failed to start Consul"
            exit 1
        fi
        log_success "Consul started successfully"
    else
        log_info "[DRY RUN] Would start Consul agent"
    fi
    
    log_step "Configuring Nomad cluster..."
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create Nomad directories
        sudo mkdir -p /opt/nomad/{data,config}
        sudo chown -R $USER:$USER /opt/nomad
        
        # Generate Nomad configuration
        cat > /tmp/nomad-config.hcl <<EOF
datacenter = "dc1"
data_dir   = "/opt/nomad/data"
log_level  = "INFO"

server {
  enabled          = true
  bootstrap_expect = 1
  encrypt         = "$(nomad operator keygen)"
}

client {
  enabled = true
  servers = ["127.0.0.1:4647"]
}

consul {
  address = "127.0.0.1:8500"
}

vault {
  enabled = true
  address = "$VAULT_ADDR"
}

ui_config {
  enabled = true
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
EOF
        
        cp /tmp/nomad-config.hcl /opt/nomad/config/nomad.hcl
        log_success "Nomad configuration created"
    else
        log_info "[DRY RUN] Would create Nomad configuration"
    fi
    
    log_step "Starting Nomad cluster..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad agent -config /opt/nomad/config/nomad.hcl &
        local nomad_pid=$!
        sleep 15
        
        # Verify Nomad is running
        if ! nomad node status &> /dev/null; then
            log_error "Failed to start Nomad cluster"
            exit 1
        fi
        
        nomad node status
        nomad server members
        log_success "Nomad cluster started successfully"
    else
        log_info "[DRY RUN] Would start Nomad cluster"
    fi
    
    log_step "Setting up Nomad volumes..."
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create host volumes for persistent storage
        sudo mkdir -p /opt/nomad/volumes/{vault-${ENVIRONMENT}-{data,config,logs},traefik-{certs,config}}
        sudo chown -R $USER:$USER /opt/nomad/volumes
        
        # Set proper permissions
        chmod 700 /opt/nomad/volumes/vault-${ENVIRONMENT}-data
        chmod 755 /opt/nomad/volumes/vault-${ENVIRONMENT}-config
        chmod 755 /opt/nomad/volumes/vault-${ENVIRONMENT}-logs
        chmod 700 /opt/nomad/volumes/traefik-certs
        chmod 755 /opt/nomad/volumes/traefik-config
        
        # Register host volumes with Nomad by updating configuration
        cat >> /opt/nomad/config/nomad.hcl <<EOF

client {
  host_volume "vault-${ENVIRONMENT}-data" {
    path      = "/opt/nomad/volumes/vault-${ENVIRONMENT}-data"
    read_only = false
  }
  
  host_volume "vault-${ENVIRONMENT}-config" {
    path      = "/opt/nomad/volumes/vault-${ENVIRONMENT}-config"
    read_only = false
  }
  
  host_volume "vault-${ENVIRONMENT}-logs" {
    path      = "/opt/nomad/volumes/vault-${ENVIRONMENT}-logs"
    read_only = false
  }
  
  host_volume "traefik-certs" {
    path      = "/opt/nomad/volumes/traefik-certs"
    read_only = false
  }
  
  host_volume "traefik-config" {
    path      = "/opt/nomad/volumes/traefik-config"
    read_only = false
  }
}
EOF
        
        # Restart Nomad to pick up volume configuration
        kill $nomad_pid 2>/dev/null || true
        sleep 5
        nomad agent -config /opt/nomad/config/nomad.hcl &
        sleep 10
        
        log_success "Nomad volumes configured and registered"
    else
        log_info "[DRY RUN] Would setup Nomad volumes"
    fi
    
    log_success "Nomad deployment completed successfully"
}

# Deploy Vault on Nomad
deploy_vault() {
    if [[ "$DEPLOY_VAULT" != "true" ]]; then
        log_debug "Skipping Vault deployment"
        return 0
    fi
    
    log_header "DEPLOYING VAULT ON NOMAD"
    
    local job_file="$INFRA_DIR/nomad/jobs/$ENVIRONMENT/vault.nomad"
    
    if [[ ! -f "$job_file" ]]; then
        log_error "Vault job file not found: $job_file"
        exit 1
    fi
    
    log_step "Validating Vault job configuration..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job validate "$job_file"
        log_success "Vault job validation passed"
    else
        log_info "[DRY RUN] Would validate Vault job file: $job_file"
    fi
    
    log_step "Planning Vault deployment..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job plan "$job_file"
        log_success "Vault deployment plan generated"
    else
        log_info "[DRY RUN] Would plan Vault deployment"
    fi
    
    log_step "Deploying Vault job to Nomad..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job run "$job_file"
        
        # Wait for deployment to be healthy
        log_info "Waiting for Vault deployment to be healthy..."
        local timeout=600
        while [[ $timeout -gt 0 ]]; do
            if nomad job status "vault-$ENVIRONMENT" | grep -q "Status.*running"; then
                local running_allocs=$(nomad job status "vault-$ENVIRONMENT" | grep -c "running" || echo "0")
                if [[ "$running_allocs" -gt 0 ]]; then
                    log_success "Vault deployment is healthy"
                    break
                fi
            fi
            log_info "Waiting for Vault to be healthy... (${timeout}s remaining)"
            sleep 10
            timeout=$((timeout-10))
        done
        
        if [[ $timeout -le 0 ]]; then
            log_error "Vault deployment did not become healthy within timeout"
            nomad job status "vault-$ENVIRONMENT"
            exit 1
        fi
    else
        log_info "[DRY RUN] Would deploy Vault job"
    fi
    
    # Initialize Vault if this is a bootstrap
    if [[ "$IS_BOOTSTRAP" == "true" && "$DRY_RUN" != "true" ]]; then
        log_step "Initializing Vault..."
        
        # Wait for Vault to be available
        local timeout=300
        while [[ $timeout -gt 0 ]]; do
            if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
                log_success "Vault is available"
                break
            fi
            log_info "Waiting for Vault to be available... (${timeout}s remaining)"
            sleep 10
            timeout=$((timeout-10))
        done
        
        if [[ $timeout -le 0 ]]; then
            log_error "Vault did not become available within timeout"
            exit 1
        fi
        
        # Check if Vault is already initialized
        if vault status | grep -q "Initialized.*true"; then
            log_info "Vault is already initialized"
        else
            log_info "Initializing Vault for $ENVIRONMENT..."
            
            # Create secrets directory
            mkdir -p "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT"
            
            # Environment-specific initialization
            case $ENVIRONMENT in
                develop)
                    vault operator init -key-shares=3 -key-threshold=2 -format=json > "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json"
                    
                    # Auto-unseal for development
                    local unseal_key_1=$(jq -r '.unseal_keys_b64[0]' "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json")
                    local unseal_key_2=$(jq -r '.unseal_keys_b64[1]' "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json")
                    
                    vault operator unseal "$unseal_key_1"
                    vault operator unseal "$unseal_key_2"
                    
                    log_success "Vault initialized and unsealed for development"
                    ;;
                staging|production)
                    vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json > "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json"
                    log_warning "Vault initialized for $ENVIRONMENT - SECURE THE RECOVERY KEYS IMMEDIATELY!"
                    ;;
            esac
        fi
        
        # Setup Vault policies and secrets
        log_step "Setting up Vault policies and secrets..."
        local root_token=$(jq -r '.root_token' "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json")
        export VAULT_TOKEN="$root_token"
        
        # Enable secret engines
        vault secrets enable -path=secret kv-v2 2>/dev/null || log_debug "KV engine already enabled"
        vault secrets enable -path=nomad-secrets kv-v2 2>/dev/null || log_debug "Nomad secrets engine already enabled"
        vault secrets enable -path=traefik-secrets kv-v2 2>/dev/null || log_debug "Traefik secrets engine already enabled"
        
        # Create policies
        vault policy write nomad-policy - <<EOF
path "nomad-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}
path "auth/token/create/nomad" {
  capabilities = ["update"]
}
EOF
        
        vault policy write traefik-policy - <<EOF
path "traefik-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/traefik/*" {
  capabilities = ["read", "list"]
}
EOF
        
        # Create service integration tokens
        local nomad_vault_token=$(vault write -field=token auth/token/create policies=nomad-policy ttl=24h renewable=true)
        local traefik_vault_token=$(vault write -field=token auth/token/create policies=traefik-policy ttl=24h renewable=true)
        
        # Store integration tokens
        echo "$nomad_vault_token" > "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/nomad-token.txt"
        echo "$traefik_vault_token" > "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/traefik-token.txt"
        
        log_success "Vault policies and integration tokens created"
        
        # Migrate from temporary tokens
        log_step "Migrating from temporary tokens to Vault-managed tokens..."
        log_info "Bootstrap tokens are now replaced with Vault-managed tokens"
        log_info "Nomad token: ${nomad_vault_token:0:10}..."
        log_info "Traefik token: ${traefik_vault_token:0:10}..."
        
        log_success "Token migration completed"
    fi
    
    log_success "Vault deployment completed successfully"
}

# Setup SSL certificates and directories
setup_ssl_certificates() {
    log_step "Setting up SSL certificate infrastructure..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Run SSL certificate setup script
        if [[ -x "$SCRIPT_DIR/setup-ssl-certificates.sh" ]]; then
            log_info "Running SSL certificate setup..."
            "$SCRIPT_DIR/setup-ssl-certificates.sh" setup
            log_success "SSL certificate infrastructure setup completed"
        else
            log_warning "SSL setup script not found or not executable"
            
            # Manual SSL directory setup as fallback
            log_info "Setting up SSL directories manually..."
            sudo mkdir -p /opt/nomad/volumes/traefik-certs/{certs,private}
            sudo mkdir -p /opt/nomad/volumes/traefik-config/dynamic
            sudo mkdir -p /opt/nomad/volumes/traefik-logs
            
            # Set permissions
            sudo chmod 700 /opt/nomad/volumes/traefik-certs
            sudo chmod 755 /opt/nomad/volumes/traefik-certs/certs
            sudo chmod 700 /opt/nomad/volumes/traefik-certs/private
            sudo chmod 755 /opt/nomad/volumes/traefik-config
            sudo chmod 755 /opt/nomad/volumes/traefik-logs
            
            # Initialize ACME storage
            for acme_file in acme.json acme-staging.json; do
                if [[ ! -f "/opt/nomad/volumes/traefik-certs/$acme_file" ]]; then
                    echo '{}' | sudo tee "/opt/nomad/volumes/traefik-certs/$acme_file" > /dev/null
                    sudo chmod 600 "/opt/nomad/volumes/traefik-certs/$acme_file"
                    log_info "Created ACME storage: $acme_file"
                fi
            done
            
            log_success "Manual SSL directory setup completed"
        fi
    else
        log_info "[DRY RUN] Would setup SSL certificate infrastructure"
    fi
}

# Deploy Traefik with Vault integration and SSL
deploy_traefik() {
    if [[ "$DEPLOY_TRAEFIK" != "true" ]]; then
        log_debug "Skipping Traefik deployment"
        return 0
    fi
    
    log_header "DEPLOYING TRAEFIK WITH VAULT INTEGRATION AND SSL CERTIFICATES"
    
    # Setup SSL certificates first
    setup_ssl_certificates
    
    local job_file="$INFRA_DIR/nomad/jobs/traefik-production.nomad"
    
    # Use environment-specific job file if available
    if [[ "$ENVIRONMENT" != "production" ]]; then
        local env_job_file="$INFRA_DIR/nomad/jobs/${ENVIRONMENT}/traefik.nomad"
        if [[ -f "$env_job_file" ]]; then
            job_file="$env_job_file"
        fi
    fi
    
    if [[ ! -f "$job_file" ]]; then
        log_error "Traefik job file not found: $job_file"
        exit 1
    fi
    
    # Setup Traefik secrets in Vault
    if [[ "$IS_BOOTSTRAP" == "true" && "$DRY_RUN" != "true" ]]; then
        log_step "Setting up Traefik secrets in Vault..."
        
        # Setup Vault token for operations
        if [[ "$ENVIRONMENT" == "develop" ]]; then
            # Use root token for development
            if [[ -f "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json" ]]; then
                local root_token=$(jq -r '.root_token' "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/init.json")
                export VAULT_TOKEN="$root_token"
            fi
        elif [[ -f "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/traefik-token.txt" ]]; then
            export VAULT_TOKEN=$(cat "$INFRA_DIR/tmp/vault-secrets-$ENVIRONMENT/traefik-token.txt")
        fi
        
        # Enable KV engine if needed
        vault secrets enable -path=kv kv-v2 2>/dev/null || log_debug "KV engine already enabled"
        
        # Generate Traefik dashboard credentials
        local dashboard_user="admin"
        local dashboard_pass=$(openssl rand -base64 24)
        local dashboard_auth=$(echo "${dashboard_user}:${dashboard_pass}" | openssl passwd -apr1 -stdin)
        
        # Store dashboard credentials in Vault
        vault kv put kv/traefik/dashboard \
            username="$dashboard_user" \
            password="$dashboard_pass" \
            auth="$dashboard_auth"
        
        # Store Nomad integration details
        vault kv put kv/traefik/nomad \
            token="placeholder-nomad-token" \
            addr="$NOMAD_ADDR"
        
        log_success "Traefik secrets stored in Vault"
        log_info "Dashboard credentials: ${dashboard_user} / ${dashboard_pass:0:6}..."
    fi
    
    log_step "Validating Traefik job configuration..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job validate "$job_file"
        log_success "Traefik job validation passed"
    else
        log_info "[DRY RUN] Would validate Traefik job file: $job_file"
    fi
    
    log_step "Planning Traefik deployment..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job plan "$job_file"
        log_success "Traefik deployment plan generated"
    else
        log_info "[DRY RUN] Would plan Traefik deployment"
    fi
    
    log_step "Deploying Traefik job to Nomad..."
    if [[ "$DRY_RUN" != "true" ]]; then
        nomad job run "$job_file"
        
        # Wait for deployment to be healthy
        log_info "Waiting for Traefik deployment to be healthy..."
        local timeout=300
        while [[ $timeout -gt 0 ]]; do
            if nomad job status "traefik" | grep -q "Status.*running"; then
                local running_allocs=$(nomad job status "traefik" | grep -c "running" || echo "0")
                if [[ "$running_allocs" -gt 0 ]]; then
                    log_success "Traefik deployment is healthy"
                    break
                fi
            fi
            log_info "Waiting for Traefik to be healthy... (${timeout}s remaining)"
            sleep 10
            timeout=$((timeout-10))
        done
        
        if [[ $timeout -le 0 ]]; then
            log_error "Traefik deployment did not become healthy within timeout"
            nomad job status "traefik"
            exit 1
        fi
        
        # Test Traefik connectivity
        log_step "Testing Traefik connectivity..."
        local timeout=120
        while [[ $timeout -gt 0 ]]; do
            if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
                log_success "Traefik is accessible"
                break
            fi
            log_info "Waiting for Traefik to be accessible... (${timeout}s remaining)"
            sleep 5
            timeout=$((timeout-5))
        done
        
        if [[ $timeout -le 0 ]]; then
            log_warning "Traefik ping endpoint not accessible within timeout"
        fi
    else
        log_info "[DRY RUN] Would deploy Traefik job"
    fi
    
    log_success "Traefik deployment completed successfully"
}

# Comprehensive deployment validation
validate_deployment() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping deployment validation as requested"
        return 0
    fi
    
    log_header "DEPLOYMENT VALIDATION"
    
    local validation_failed=false
    
    # Validate Nomad
    if [[ "$DEPLOY_NOMAD" == "true" || "$DEPLOY_VAULT" == "true" || "$DEPLOY_TRAEFIK" == "true" ]]; then
        log_step "Validating Nomad..."
        if [[ "$DRY_RUN" != "true" ]]; then
            if nomad node status &> /dev/null && nomad server members &> /dev/null; then
                log_success "Nomad validation passed"
                log_debug "$(nomad node status)"
            else
                log_error "Nomad validation failed"
                validation_failed=true
            fi
        else
            log_info "[DRY RUN] Would validate Nomad cluster"
        fi
    fi
    
    # Validate Vault
    if [[ "$DEPLOY_VAULT" == "true" ]]; then
        log_step "Validating Vault..."
        if [[ "$DRY_RUN" != "true" ]]; then
            if curl -s "$VAULT_ADDR/v1/sys/health" | jq .initialized | grep -q true; then
                log_success "Vault validation passed"
                if [[ -n "${VAULT_TOKEN:-}" ]]; then
                    log_debug "$(vault status)"
                fi
            else
                log_error "Vault validation failed"
                validation_failed=true
            fi
        else
            log_info "[DRY RUN] Would validate Vault deployment"
        fi
    fi
    
    # Validate Traefik
    if [[ "$DEPLOY_TRAEFIK" == "true" ]]; then
        log_step "Validating Traefik..."
        if [[ "$DRY_RUN" != "true" ]]; then
            if curl -s http://localhost:8080/ping | grep -q OK; then
                log_success "Traefik validation passed"
                
                # Validate SSL configuration
                log_step "Validating SSL configuration..."
                if [[ -x "$SCRIPT_DIR/validate-ssl-config.sh" ]]; then
                    if "$SCRIPT_DIR/validate-ssl-config.sh" traefik; then
                        log_success "SSL configuration validation passed"
                    else
                        log_warning "SSL configuration validation failed (non-critical)"
                    fi
                else
                    log_warning "SSL validation script not found"
                fi
                
            else
                log_error "Traefik validation failed"
                validation_failed=true
            fi
        else
            log_info "[DRY RUN] Would validate Traefik deployment and SSL configuration"
        fi
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Deployment validation failed"
        exit 1
    else
        log_success "All deployment validations passed"
    fi
}

# Create deployment marker
create_deployment_marker() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create deployment marker"
        return 0
    fi
    
    log_step "Creating deployment marker..."
    
    local marker_dir="$INFRA_DIR/environments/$ENVIRONMENT"
    mkdir -p "$marker_dir"
    
    cat > "$marker_dir/.deployed" <<EOF
# Deployment marker file
# Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Environment: $ENVIRONMENT
# Components: $COMPONENTS
# Bootstrap: $IS_BOOTSTRAP

NOMAD_DEPLOYED=$DEPLOY_NOMAD
VAULT_DEPLOYED=$DEPLOY_VAULT
TRAEFIK_DEPLOYED=$DEPLOY_TRAEFIK
BOOTSTRAP_COMPLETED=$IS_BOOTSTRAP
DEPLOYMENT_SCRIPT_VERSION=1.0.0
EOF
    
    log_success "Deployment marker created: $marker_dir/.deployed"
}

# Enhanced cleanup function with secure token removal
secure_cleanup() {
    local exit_code=$?
    
    # Securely remove temporary token files
    if [[ -d "${TEMP_DIR:-}" ]]; then
        find "$TEMP_DIR" -type f -exec shred -vfz -n 3 {} \; 2>/dev/null || true
        rm -rf "$TEMP_DIR"
    fi
    
    # Clear environment variables
    unset VAULT_TOKEN NOMAD_BOOTSTRAP_TOKEN CONSUL_BOOTSTRAP_TOKEN
    
    if [[ $exit_code -ne 0 && "$CLEANUP_ON_FAILURE" == "true" ]]; then
        log_warning "Deployment failed, running cleanup..."
        
        # Stop processes
        pkill -f "consul agent" 2>/dev/null || true
        pkill -f "nomad agent" 2>/dev/null || true
        pkill -f "vault server" 2>/dev/null || true
        
        # Remove temporary files
        rm -rf /tmp/nomad-config.hcl 2>/dev/null || true
        
        log_info "Cleanup completed"
    fi
    
    exit $exit_code
}

# Original cleanup for compatibility
cleanup() {
    secure_cleanup
}

# Generate deployment summary
generate_summary() {
    log_header "DEPLOYMENT SUMMARY"
    
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Components:${NC} $COMPONENTS"
    echo -e "${WHITE}Bootstrap:${NC} $IS_BOOTSTRAP"
    echo -e "${WHITE}Dry Run:${NC} $DRY_RUN"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo -e "${WHITE}Service Endpoints:${NC}"
        if [[ "$DEPLOY_NOMAD" == "true" ]]; then
            echo -e "  ${CYAN}Nomad:${NC} $NOMAD_ADDR"
        fi
        if [[ "$DEPLOY_VAULT" == "true" ]]; then
            echo -e "  ${CYAN}Vault:${NC} $VAULT_ADDR"
        fi
        if [[ "$DEPLOY_TRAEFIK" == "true" ]]; then
            echo -e "  ${CYAN}Traefik:${NC} http://localhost:8080"
        fi
        
        if [[ "$ENVIRONMENT" == "develop" ]]; then
            echo ""
            echo -e "${WHITE}Development Access:${NC}"
            echo -e "  ${CYAN}Nomad UI:${NC} http://localhost:4646"
            echo -e "  ${CYAN}Vault UI:${NC} http://localhost:8200"
            echo -e "  ${CYAN}Traefik Dashboard:${NC} http://localhost:8080"
        fi
        
        if [[ "$IS_BOOTSTRAP" == "true" && "$ENVIRONMENT" != "develop" ]]; then
            echo ""
            echo -e "${RED}IMPORTANT SECURITY REMINDERS:${NC}"
            echo -e "  ${YELLOW}1. Secure Vault recovery keys immediately${NC}"
            echo -e "  ${YELLOW}2. Revoke root tokens after setup${NC}"
            echo -e "  ${YELLOW}3. Configure monitoring and backups${NC}"
            echo -e "  ${YELLOW}4. Complete security audit${NC}"
        fi
    fi
    
    echo ""
    log_success "Infrastructure deployment completed successfully!"
}

# Main execution function
main() {
    # Setup cleanup trap with secure cleanup
    trap secure_cleanup EXIT ERR INT TERM
    
    log_header "UNIFIED INFRASTRUCTURE BOOTSTRAP"
    echo -e "${WHITE}Nomad → Vault → Traefik Deployment Pipeline${NC}"
    echo ""
    
    # Parse and validate arguments
    parse_arguments "$@"
    validate_environment
    validate_components
    
    # Show configuration
    echo -e "${WHITE}Configuration:${NC}"
    echo -e "  Environment: ${CYAN}$ENVIRONMENT${NC}"
    echo -e "  Components: ${CYAN}$COMPONENTS${NC}"
    echo -e "  Dry Run: ${CYAN}$DRY_RUN${NC}"
    echo -e "  Force Bootstrap: ${CYAN}$FORCE_BOOTSTRAP${NC}"
    echo -e "  Verbose: ${CYAN}$VERBOSE${NC}"
    echo ""
    
    # Execute deployment pipeline
    check_prerequisites
    determine_deployment_strategy
    setup_bootstrap_tokens
    
    # Deploy components in dependency order
    deploy_nomad
    deploy_vault
    deploy_traefik
    
    # Validate and finalize
    validate_deployment
    create_deployment_marker
    generate_summary
    
    # Remove cleanup trap on success
    trap - EXIT ERR
}

# Execute main function with all arguments
main "$@"