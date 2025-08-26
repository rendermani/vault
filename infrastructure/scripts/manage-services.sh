#!/bin/bash

# Service Management Script for HashiCorp Infrastructure
# Handles idempotent installation, configuration, and management of Consul, Nomad, and Vault

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Version configuration
CONSUL_VERSION="1.17.0"
NOMAD_VERSION="1.7.2"
VAULT_VERSION="1.15.4"

# Service configuration
CONSUL_USER="consul"
NOMAD_USER="nomad"
VAULT_USER="vault"

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
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create system users
create_system_users() {
    log_info "Creating system users..."
    
    # Create consul user
    if ! id "$CONSUL_USER" &>/dev/null; then
        useradd --system --home /opt/consul --shell /bin/false "$CONSUL_USER"
        log_success "Created user: $CONSUL_USER"
    else
        log_debug "User $CONSUL_USER already exists"
    fi
    
    # Create nomad user
    if ! id "$NOMAD_USER" &>/dev/null; then
        useradd --system --home /opt/nomad --shell /bin/false "$NOMAD_USER"
        log_success "Created user: $NOMAD_USER"
    else
        log_debug "User $NOMAD_USER already exists"
    fi
    
    # Create vault user
    if ! id "$VAULT_USER" &>/dev/null; then
        useradd --system --home /opt/vault --shell /bin/false "$VAULT_USER"
        log_success "Created user: $VAULT_USER"
    else
        log_debug "User $VAULT_USER already exists"
    fi
}

# Install HashiCorp tools
install_hashicorp_tools() {
    log_info "Installing HashiCorp tools..."
    
    cd /tmp
    
    # Install Consul
    if [[ ! -f /usr/local/bin/consul ]] || [[ "$(consul version | head -1 | grep -o 'v[0-9.]*')" != "v$CONSUL_VERSION" ]]; then
        log_info "Installing Consul $CONSUL_VERSION..."
        curl -fsSL "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip" -o consul.zip
        unzip -q consul.zip
        mv consul /usr/local/bin/
        chmod +x /usr/local/bin/consul
        rm consul.zip
        log_success "Consul $CONSUL_VERSION installed"
    else
        log_debug "Consul $CONSUL_VERSION already installed"
    fi
    
    # Install Nomad
    if [[ ! -f /usr/local/bin/nomad ]] || [[ "$(nomad version | head -1 | grep -o 'v[0-9.]*')" != "v$NOMAD_VERSION" ]]; then
        log_info "Installing Nomad $NOMAD_VERSION..."
        curl -fsSL "https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip" -o nomad.zip
        unzip -q nomad.zip
        mv nomad /usr/local/bin/
        chmod +x /usr/local/bin/nomad
        rm nomad.zip
        log_success "Nomad $NOMAD_VERSION installed"
    else
        log_debug "Nomad $NOMAD_VERSION already installed"
    fi
    
    # Install Vault CLI
    if [[ ! -f /usr/local/bin/vault ]] || [[ "$(vault version | head -1 | grep -o 'v[0-9.]*')" != "v$VAULT_VERSION" ]]; then
        log_info "Installing Vault CLI $VAULT_VERSION..."
        curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o vault.zip
        unzip -q vault.zip
        mv vault /usr/local/bin/
        chmod +x /usr/local/bin/vault
        rm vault.zip
        log_success "Vault CLI $VAULT_VERSION installed"
    else
        log_debug "Vault CLI $VAULT_VERSION already installed"
    fi
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    # Consul directories
    mkdir -p /opt/consul/{data,config,logs}
    chown -R "$CONSUL_USER:$CONSUL_USER" /opt/consul
    chmod 755 /opt/consul
    chmod 700 /opt/consul/data
    
    # Nomad directories
    mkdir -p /opt/nomad/{data,config,logs,volumes}
    chown -R "$NOMAD_USER:$NOMAD_USER" /opt/nomad
    chmod 755 /opt/nomad
    chmod 700 /opt/nomad/data
    
    # Vault directories (for CLI only, actual Vault runs in Nomad)
    mkdir -p /opt/vault/{config,logs}
    chown -R "$VAULT_USER:$VAULT_USER" /opt/vault
    chmod 755 /opt/vault
    
    # Create Nomad volume directories
    mkdir -p /opt/nomad/volumes/{vault-{develop,staging,production}-{data,config,logs},traefik-{certs,config}}
    
    # Set proper permissions for volumes
    for env in develop staging production; do
        chmod 700 "/opt/nomad/volumes/vault-${env}-data"
        chmod 755 "/opt/nomad/volumes/vault-${env}-config"
        chmod 755 "/opt/nomad/volumes/vault-${env}-logs"
    done
    
    chmod 700 /opt/nomad/volumes/traefik-certs
    chmod 755 /opt/nomad/volumes/traefik-config
    mkdir -p /opt/nomad/volumes/traefik-config/dynamic
    
    # Ensure nomad user owns volumes
    chown -R "$NOMAD_USER:$NOMAD_USER" /opt/nomad/volumes
    
    log_success "Directory structure created"
}

# Install configurations
install_configurations() {
    log_info "Installing service configurations..."
    
    # Source config templates for dynamic generation
    if [[ -f "$SCRIPT_DIR/config-templates.sh" ]]; then
        source "$SCRIPT_DIR/config-templates.sh"
        log_debug "Loaded configuration templates"
    else
        log_error "config-templates.sh not found: $SCRIPT_DIR/config-templates.sh"
        exit 1
    fi
    
    # Generate and install Consul configuration
    mkdir -p /opt/consul/config
    log_info "Generating Consul configuration..."
    # Generate proper Consul encryption key (16 bytes base64 encoded)
    local consul_encrypt_key
    consul_encrypt_key=$(openssl rand -base64 16 | tr -d '\n')
    
    generate_consul_config "develop" "dc1" "/opt/consul/data" "/opt/consul/config" "/var/log/consul" "server" "$consul_encrypt_key" > /opt/consul/config/consul.hcl
    chown "$CONSUL_USER:$CONSUL_USER" /opt/consul/config/consul.hcl
    chmod 640 /opt/consul/config/consul.hcl
    log_success "Consul configuration generated and installed"
    
    # Generate and install Nomad configuration with bootstrap phase awareness
    mkdir -p /opt/nomad/config
    mkdir -p /etc/nomad
    log_info "Generating Nomad configuration..."
    
    # Respect bootstrap phase environment variables
    local vault_enabled="${VAULT_ENABLED:-false}"
    local bootstrap_phase="${BOOTSTRAP_PHASE:-false}"
    local nomad_vault_bootstrap_phase="${NOMAD_VAULT_BOOTSTRAP_PHASE:-false}"
    
    log_debug "Bootstrap configuration: VAULT_ENABLED=$vault_enabled, BOOTSTRAP_PHASE=$bootstrap_phase, NOMAD_VAULT_BOOTSTRAP_PHASE=$nomad_vault_bootstrap_phase"
    
    # Force Vault to be disabled during bootstrap phase
    if [[ "$bootstrap_phase" == "true" || "$nomad_vault_bootstrap_phase" == "true" ]]; then
        log_warning "Bootstrap phase detected - forcing Vault integration to be disabled"
        vault_enabled="false"
        nomad_vault_bootstrap_phase="true"
    fi
    
    # Generate Nomad config with proper bootstrap phase handling
    # Generate proper Nomad encryption key (16 bytes base64 encoded)
    local nomad_encrypt_key
    nomad_encrypt_key=$(openssl rand -base64 16 | tr -d '\n')
    
    generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
        "both" "$nomad_encrypt_key" "0.0.0.0" "" "1" "true" "127.0.0.1:8500" \
        "$vault_enabled" "http://localhost:8200" "$nomad_vault_bootstrap_phase" > /opt/nomad/config/nomad.hcl
    
    # Also create the expected /etc/nomad/nomad.hcl file
    cp /opt/nomad/config/nomad.hcl /etc/nomad/nomad.hcl
    
    chown "$NOMAD_USER:$NOMAD_USER" /opt/nomad/config/nomad.hcl
    chown "$NOMAD_USER:$NOMAD_USER" /etc/nomad/nomad.hcl
    chmod 640 /opt/nomad/config/nomad.hcl
    chmod 640 /etc/nomad/nomad.hcl
    log_success "Nomad configuration generated and installed to both locations"
    
    if [[ "$bootstrap_phase" == "true" ]]; then
        log_warning "Bootstrap phase active: Vault integration disabled in Nomad configuration"
    fi
}

# Install systemd service files
install_systemd_services() {
    log_info "Installing systemd service files..."
    
    # Install Consul service
    if [[ -f "$INFRA_DIR/config/consul.service" ]]; then
        cp "$INFRA_DIR/config/consul.service" /etc/systemd/system/
        log_success "Consul systemd service installed"
    else
        log_error "Consul service file not found: $INFRA_DIR/config/consul.service"
        exit 1
    fi
    
    # Install Nomad service
    if [[ -f "$INFRA_DIR/config/nomad.service" ]]; then
        cp "$INFRA_DIR/config/nomad.service" /etc/systemd/system/
        log_success "Nomad systemd service installed"
    else
        log_error "Nomad service file not found: $INFRA_DIR/config/nomad.service"
        exit 1
    fi
    
    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd daemon reloaded"
}

# Start services
start_services() {
    local start_consul="${1:-true}"
    local start_nomad="${2:-true}"
    
    log_info "Starting services..."
    
    # Start and enable Consul
    if [[ "$start_consul" == "true" ]]; then
        log_info "Starting Consul service..."
        
        # Validate Consul configuration before starting
        if [[ ! -f "/opt/consul/config/consul.hcl" ]]; then
            log_error "Consul configuration file not found: /opt/consul/config/consul.hcl"
            log_error "Configuration must be generated before starting Consul"
            exit 1
        fi
        
        # Validate configuration syntax
        if ! consul validate /opt/consul/config/consul.hcl; then
            log_error "Consul configuration validation failed"
            log_error "Please check the configuration file"
            exit 1
        fi
        
        systemctl enable consul
        
        # Ensure consul user can access required directories
        mkdir -p /var/log/consul
        chown -R consul:consul /var/log/consul
        chown -R consul:consul /opt/consul
        
        if systemctl is-active --quiet consul; then
            log_info "Consul is already running, restarting..."
            systemctl restart consul
        else
            systemctl start consul
        fi
        
        # Wait for Consul to be ready with extended timeout
        log_info "Waiting for Consul to be ready..."
        local consul_ready=false
        for attempt in {1..30}; do
            if systemctl is-active --quiet consul; then
                log_debug "Consul systemd service is active (attempt $attempt)"
                # Check if API is responding
                if curl -s --connect-timeout 2 http://localhost:8500/v1/status/leader >/dev/null 2>&1; then
                    log_success "Consul is ready and responding"
                    consul_ready=true
                    break
                else
                    log_debug "Consul service active but API not responding yet (attempt $attempt)"
                fi
            else
                log_debug "Consul systemd service not active yet (attempt $attempt)"
            fi
            sleep 3
        done
        
        if [[ "$consul_ready" != "true" ]]; then
            log_error "Consul did not become ready within timeout"
            log_error "Consul service status:"
            systemctl status consul --no-pager || true
            log_error "Consul logs:"
            journalctl -u consul --no-pager --lines=20 || true
            exit 1
        fi
    fi
    
    # Start and enable Nomad
    if [[ "$start_nomad" == "true" ]]; then
        log_info "Starting Nomad service..."
        
        # Validate Nomad configuration before starting
        if [[ ! -f "/opt/nomad/config/nomad.hcl" ]]; then
            log_error "Nomad configuration file not found: /opt/nomad/config/nomad.hcl"
            log_error "Configuration must be generated before starting Nomad"
            exit 1
        fi
        
        # Validate configuration syntax
        if ! nomad config validate /opt/nomad/config/nomad.hcl; then
            log_error "Nomad configuration validation failed"
            log_error "Please check the configuration file"
            exit 1
        fi
        
        systemctl enable nomad
        
        # Ensure nomad user has Docker access and directory permissions
        mkdir -p /var/log/nomad
        chown -R nomad:nomad /var/log/nomad
        chown -R nomad:nomad /opt/nomad
        usermod -aG docker nomad 2>/dev/null || log_warning "Could not add nomad user to docker group"
        
        if systemctl is-active --quiet nomad; then
            log_info "Nomad is already running, restarting..."
            systemctl restart nomad
        else
            systemctl start nomad
        fi
        
        # Wait for Nomad to be ready with extended timeout
        log_info "Waiting for Nomad to be ready..."
        local nomad_ready=false
        for attempt in {1..45}; do
            if systemctl is-active --quiet nomad; then
                log_debug "Nomad systemd service is active (attempt $attempt)"
                # Check if API is responding
                if curl -s --connect-timeout 2 http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
                    log_success "Nomad is ready and responding"
                    nomad_ready=true
                    break
                else
                    log_debug "Nomad service active but API not responding yet (attempt $attempt)"
                    # Check if the port is bound
                    if netstat -tlnp 2>/dev/null | grep -q ":4646.*LISTEN"; then
                        log_debug "Nomad port 4646 is listening, waiting for API readiness"
                    else
                        log_debug "Nomad port 4646 not yet listening"
                    fi
                fi
            else
                log_debug "Nomad systemd service not active yet (attempt $attempt)"
                # Check for service failures
                if systemctl is-failed --quiet nomad; then
                    log_error "Nomad service has failed"
                    systemctl status nomad --no-pager || true
                    journalctl -u nomad --no-pager --lines=20 || true
                    exit 1
                fi
            fi
            sleep 4
        done
        
        if [[ "$nomad_ready" != "true" ]]; then
            log_error "Nomad did not become ready within timeout"
            log_error "Nomad service status:"
            systemctl status nomad --no-pager || true
            log_error "Nomad logs:"
            journalctl -u nomad --no-pager --lines=20 || true
            log_error "Network status:"
            netstat -tlnp | grep -E ":(4646|4647|4648)" || echo "No Nomad ports listening"
            log_error "Configuration validation:"
            nomad config validate /opt/nomad/config/nomad.hcl || true
            exit 1
        fi
    fi
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    
    # Stop Nomad first (depends on Consul)
    if systemctl is-active --quiet nomad; then
        systemctl stop nomad
        log_success "Nomad stopped"
    else
        log_debug "Nomad is not running"
    fi
    
    # Stop Consul
    if systemctl is-active --quiet consul; then
        systemctl stop consul
        log_success "Consul stopped"
    else
        log_debug "Consul is not running"
    fi
}

# Get service status
status_services() {
    echo -e "${WHITE}=== Service Status ===${NC}"
    
    echo -e "\n${CYAN}Consul:${NC}"
    systemctl status consul --no-pager --lines=0 2>/dev/null || echo "  Not installed or not running"
    
    echo -e "\n${CYAN}Nomad:${NC}"
    systemctl status nomad --no-pager --lines=0 2>/dev/null || echo "  Not installed or not running"
    
    echo -e "\n${CYAN}Service Health:${NC}"
    if curl -s http://localhost:8500/v1/status/leader >/dev/null 2>&1; then
        echo -e "  Consul: ${GREEN}Healthy${NC}"
    else
        echo -e "  Consul: ${RED}Unhealthy${NC}"
    fi
    
    if curl -s http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
        echo -e "  Nomad: ${GREEN}Healthy${NC}"
    else
        echo -e "  Nomad: ${RED}Unhealthy${NC}"
    fi
    
    echo -e "\n${CYAN}Active Nomad Jobs:${NC}"
    if command -v nomad >/dev/null 2>&1 && curl -s http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
        NOMAD_ADDR=http://localhost:4646 nomad job status 2>/dev/null | head -n 20 || echo "  No jobs running or Nomad not accessible"
    else
        echo "  Nomad not available"
    fi
}

# Health check
health_check() {
    log_info "Performing health check..."
    
    local health_ok=true
    
    # Check Consul
    if ! curl -s http://localhost:8500/v1/status/leader >/dev/null 2>&1; then
        log_error "Consul health check failed"
        health_ok=false
    else
        log_success "Consul health check passed"
    fi
    
    # Check Nomad
    if ! curl -s http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
        log_error "Nomad health check failed"
        health_ok=false
    else
        log_success "Nomad health check passed"
    fi
    
    # Check if Nomad can communicate with Consul
    if command -v nomad >/dev/null 2>&1 && curl -s http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
        if NOMAD_ADDR=http://localhost:4646 nomad server members >/dev/null 2>&1; then
            log_success "Nomad-Consul integration working"
        else
            log_warning "Nomad-Consul integration may have issues"
        fi
    fi
    
    if [[ "$health_ok" == "true" ]]; then
        log_success "All health checks passed"
    else
        log_error "Some health checks failed"
        exit 1
    fi
}

# Usage function
usage() {
    cat <<EOF
HashiCorp Infrastructure Service Management Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  install     Install and configure all services
  start       Start all services
  stop        Stop all services
  restart     Restart all services
  status      Show service status
  health      Perform health check
  logs        Show service logs

Options:
  --consul-only     Only operate on Consul
  --nomad-only      Only operate on Nomad
  --verbose         Enable verbose output

Examples:
  $0 install
  $0 start
  $0 status
  $0 restart --nomad-only
  $0 health --verbose
EOF
}

# Main execution
main() {
    local command="${1:-}"
    local consul_only=false
    local nomad_only=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|start|stop|restart|status|health|logs)
                command="$1"
                shift
                ;;
            --consul-only)
                consul_only=true
                shift
                ;;
            --nomad-only)
                nomad_only=true
                shift
                ;;
            --verbose)
                export VERBOSE=true
                shift
                ;;
            --help|-h)
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
    
    # Determine service flags
    local start_consul=true
    local start_nomad=true
    
    if [[ "$consul_only" == "true" ]]; then
        start_nomad=false
    elif [[ "$nomad_only" == "true" ]]; then
        start_consul=false
    fi
    
    case "$command" in
        install)
            check_root
            create_system_users
            install_hashicorp_tools
            create_directories
            install_configurations
            install_systemd_services
            start_services "$start_consul" "$start_nomad"
            health_check
            log_success "Installation completed successfully"
            ;;
        start)
            check_root
            start_services "$start_consul" "$start_nomad"
            ;;
        stop)
            check_root
            stop_services
            ;;
        restart)
            check_root
            stop_services
            start_services "$start_consul" "$start_nomad"
            ;;
        status)
            status_services
            ;;
        health)
            health_check
            ;;
        logs)
            echo -e "${WHITE}=== Consul Logs ===${NC}"
            journalctl -u consul --no-pager --lines=20
            echo -e "\n${WHITE}=== Nomad Logs ===${NC}"
            journalctl -u nomad --no-pager --lines=20
            ;;
        "")
            log_error "No command specified"
            usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"