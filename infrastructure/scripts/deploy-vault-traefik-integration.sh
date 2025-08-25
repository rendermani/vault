#!/bin/bash
set -euo pipefail

# Complete Deployment Script for Vault-Traefik Integration
# This script handles the complete deployment workflow with zero manual steps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
LOG_FILE="/var/log/vault-traefik-deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
trap 'error "Deployment failed at line $LINENO"' ERR

# Function to check service health
check_service_health() {
    local service_name=$1
    local check_command=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    info "Checking ${service_name} health..."
    
    while [ $attempt -le $max_attempts ]; do
        if eval "$check_command" >/dev/null 2>&1; then
            success "${service_name} is healthy"
            return 0
        fi
        
        info "Attempt ${attempt}/${max_attempts} - ${service_name} not healthy, waiting..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    error "${service_name} failed health check after ${max_attempts} attempts"
    return 1
}

# Function to setup host volumes
setup_host_volumes() {
    info "Setting up Nomad host volumes..."
    
    # Create volume directories
    local volumes=(
        "traefik-certs"
        "traefik-config"
        "traefik-secrets"
    )
    
    for volume in "${volumes[@]}"; do
        local volume_path="/opt/nomad/volumes/${volume}"
        
        if [ ! -d "$volume_path" ]; then
            mkdir -p "$volume_path"
            success "Created volume directory: $volume_path"
        else
            info "Volume directory already exists: $volume_path"
        fi
        
        # Set appropriate permissions
        case $volume in
            "traefik-secrets")
                chmod 700 "$volume_path"
                ;;
            "traefik-certs")
                chmod 700 "$volume_path"
                ;;
            *)
                chmod 755 "$volume_path"
                ;;
        esac
        
        # Set ownership to nomad user if exists
        if getent passwd nomad >/dev/null 2>&1; then
            chown nomad:nomad "$volume_path"
        fi
    done
    
    # Update Nomad client configuration to include host volumes
    local nomad_config_file="/etc/nomad.d/nomad.hcl"
    
    if [ -f "$nomad_config_file" ]; then
        info "Adding host volumes to Nomad configuration..."
        
        # Backup original config
        cp "$nomad_config_file" "${nomad_config_file}.backup-$(date +%Y%m%d-%H%M%S)"
        
        # Check if host_volume block already exists
        if ! grep -q "host_volume" "$nomad_config_file"; then
            cat >> "$nomad_config_file" <<EOF

# Host volumes for Traefik
client {
  host_volume "traefik-certs" {
    path      = "/opt/nomad/volumes/traefik-certs"
    read_only = false
  }
  
  host_volume "traefik-config" {
    path      = "/opt/nomad/volumes/traefik-config"
    read_only = false
  }
  
  host_volume "traefik-secrets" {
    path      = "/opt/nomad/volumes/traefik-secrets"
    read_only = false
  }
}
EOF
            success "Host volumes added to Nomad configuration"
            
            # Restart Nomad to apply configuration
            if systemctl is-active nomad >/dev/null 2>&1; then
                systemctl restart nomad
                info "Nomad restarted to apply volume configuration"
                
                # Wait for Nomad to be ready
                check_service_health "Nomad" "nomad status"
            fi
        else
            info "Host volumes already configured in Nomad"
        fi
    else
        warn "Nomad configuration file not found at $nomad_config_file"
    fi
}

# Function to deploy template files
deploy_template_files() {
    info "Deploying Vault template files..."
    
    local template_dir="/opt/nomad/volumes/traefik-config/templates"
    mkdir -p "$template_dir"
    
    # Copy template files from infrastructure repo
    local source_template_dir="$INFRA_ROOT/traefik/config/templates"
    
    if [ -d "$source_template_dir" ]; then
        cp "$source_template_dir"/*.tpl "$template_dir/" 2>/dev/null || {
            warn "Some template files might not exist, creating minimal templates"
        }
        
        # Ensure key template files exist
        if [ ! -f "$template_dir/dashboard-auth.tpl" ]; then
            cat > "$template_dir/dashboard-auth.tpl" <<'EOF'
{{- with secret "secret/data/traefik/dashboard" -}}
{{ .Data.data.auth }}
{{- end }}
EOF
            success "Created dashboard-auth.tpl template"
        fi
        
        if [ ! -f "$template_dir/traefik-env.tpl" ]; then
            cat > "$template_dir/traefik-env.tpl" <<'EOF'
{{- with secret "secret/data/traefik/dashboard" -}}
DASHBOARD_USER={{ .Data.data.username }}
DASHBOARD_PASS={{ .Data.data.password }}
DASHBOARD_AUTH={{ .Data.data.auth }}
{{- end }}

{{- with secret "secret/data/traefik/vault" -}}
VAULT_TOKEN={{ .Data.data.token }}
{{- end }}

{{- with secret "secret/data/traefik/cloudflare" -}}
CF_API_EMAIL={{ .Data.data.email }}
CF_API_KEY={{ .Data.data.api_key }}
{{- end }}
EOF
            success "Created traefik-env.tpl template"
        fi
        
        # Set permissions
        chmod 644 "$template_dir"/*.tpl
        
        success "Template files deployed"
    else
        warn "Source template directory not found: $source_template_dir"
    fi
}

# Function to run Vault initialization
run_vault_initialization() {
    info "Running Vault initialization for Traefik integration..."
    
    local init_script="$SCRIPT_DIR/automated-vault-traefik-init.sh"
    
    if [ -f "$init_script" ]; then
        # Make script executable
        chmod +x "$init_script"
        
        # Run initialization
        VAULT_ADDR="$VAULT_ADDR" "$init_script"
        success "Vault initialization completed"
    else
        error "Vault initialization script not found: $init_script"
        return 1
    fi
}

# Function to deploy Traefik job
deploy_traefik_job() {
    info "Deploying Traefik with Vault integration to Nomad..."
    
    local job_file="$INFRA_ROOT/traefik/traefik-vault-integration.nomad"
    
    if [ ! -f "$job_file" ]; then
        error "Traefik job file not found: $job_file"
        return 1
    fi
    
    # Check if job is already running
    if nomad job status traefik-vault >/dev/null 2>&1; then
        info "Traefik job already exists, updating..."
        nomad job run "$job_file"
    else
        info "Deploying new Traefik job..."
        nomad job run "$job_file"
    fi
    
    # Wait for deployment to complete
    info "Waiting for Traefik deployment to complete..."
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status
        status=$(nomad job status -short traefik-vault | grep "Status" | awk '{print $3}' || echo "unknown")
        
        if [ "$status" = "running" ]; then
            # Check allocation health
            local alloc_id
            alloc_id=$(nomad job status traefik-vault | grep "running" | head -1 | awk '{print $1}' || echo "")
            
            if [ ! -z "$alloc_id" ]; then
                local alloc_status
                alloc_status=$(nomad alloc status "$alloc_id" | grep "Task.*State" | grep traefik | awk '{print $3}' || echo "unknown")
                
                if [ "$alloc_status" = "running" ]; then
                    success "Traefik deployment completed successfully"
                    break
                fi
            fi
        fi
        
        info "Attempt ${attempt}/${max_attempts} - Deployment status: $status, waiting..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Traefik deployment did not complete within expected time"
        
        # Show debugging information
        warn "Showing job status for debugging:"
        nomad job status traefik-vault || true
        
        return 1
    fi
}

# Function to verify integration
verify_integration() {
    info "Verifying Vault-Traefik integration..."
    
    # Test 1: Check Traefik service health
    if ! check_service_health "Traefik HTTP" "curl -f http://localhost/ping" 10; then
        error "Traefik HTTP endpoint not responding"
        return 1
    fi
    
    # Test 2: Check Traefik HTTPS (if certificates are ready)
    info "Checking HTTPS endpoint (may take time for certificates)"
    if curl -f -k https://localhost/ping >/dev/null 2>&1; then
        success "Traefik HTTPS endpoint responding"
    else
        warn "HTTPS endpoint not yet available (certificates may still be provisioning)"
    fi
    
    # Test 3: Check Vault Agent health
    if curl -f http://localhost:8100/agent/v1/cache-status >/dev/null 2>&1; then
        success "Vault Agent is healthy"
    else
        warn "Vault Agent health check failed"
    fi
    
    # Test 4: Verify dashboard authentication
    info "Checking dashboard authentication setup..."
    local auth_file="/opt/nomad/volumes/traefik-config/dashboard-auth"
    
    if [ -f "$auth_file" ] && [ -s "$auth_file" ]; then
        success "Dashboard authentication file is present and non-empty"
    else
        warn "Dashboard authentication file not found or empty"
    fi
    
    # Test 5: Check certificate storage
    local acme_file="/opt/nomad/volumes/traefik-certs/acme.json"
    
    if [ -f "$acme_file" ]; then
        success "ACME certificate storage is configured"
    else
        warn "ACME certificate storage file not found"
    fi
    
    success "Integration verification completed"
}

# Function to show deployment summary
show_deployment_summary() {
    info "🎉 Vault-Traefik Integration Deployment Summary"
    info "================================================"
    
    info "Services Status:"
    
    # Vault status
    if vault status >/dev/null 2>&1; then
        success "  ✓ Vault: Running and accessible"
    else
        error "  ✗ Vault: Not accessible"
    fi
    
    # Nomad status
    if nomad status >/dev/null 2>&1; then
        success "  ✓ Nomad: Running and accessible"
    else
        error "  ✗ Nomad: Not accessible"
    fi
    
    # Traefik job status
    if nomad job status traefik-vault >/dev/null 2>&1; then
        local job_status
        job_status=$(nomad job status -short traefik-vault | grep "Status" | awk '{print $3}' || echo "unknown")
        if [ "$job_status" = "running" ]; then
            success "  ✓ Traefik Job: Running"
        else
            warn "  ⚠ Traefik Job: $job_status"
        fi
    else
        error "  ✗ Traefik Job: Not found"
    fi
    
    # Service endpoints
    info "
Service Endpoints:"
    info "  • Traefik Dashboard: https://traefik.cloudya.net"
    info "  • Vault UI: https://vault.cloudya.net"
    info "  • Nomad UI: https://nomad.cloudya.net"
    info "  • Metrics: https://metrics.cloudya.net"
    
    # Credentials location
    info "
Credentials:"
    info "  • Dashboard credentials stored in: secret/traefik/dashboard"
    info "  • Service token stored in: secret/traefik/vault"
    info "  • Certificate config stored in: secret/traefik/certificates"
    
    # Log files
    info "
Log Files:"
    info "  • Deployment: $LOG_FILE"
    info "  • Vault Agent: /var/log/vault-agent-traefik.log"
    info "  • Health Monitoring: /var/log/vault-traefik-health.log"
    
    # Next steps
    info "
Next Steps:"
    info "  1. Monitor deployment: nomad job status traefik-vault"
    info "  2. Check logs: tail -f $LOG_FILE"
    info "  3. Access dashboard with credentials from Vault"
    info "  4. Verify SSL certificates are working"
    info "  5. Set up monitoring and alerting"
}

# Main deployment function
main() {
    info "Starting complete Vault-Traefik integration deployment..."
    info "Log file: $LOG_FILE"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Pre-flight checks
    info "Running pre-flight checks..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("vault" "nomad" "curl" "jq" "htpasswd")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check service accessibility
    check_service_health "Vault" "vault status"
    check_service_health "Nomad" "nomad status"
    
    # Step 1: Setup host volumes
    setup_host_volumes
    
    # Step 2: Deploy template files
    deploy_template_files
    
    # Step 3: Run Vault initialization
    run_vault_initialization
    
    # Step 4: Deploy Traefik job
    deploy_traefik_job
    
    # Step 5: Verify integration
    verify_integration
    
    # Step 6: Show summary
    show_deployment_summary
    
    success "🎉 Vault-Traefik integration deployment completed successfully!"
    
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi