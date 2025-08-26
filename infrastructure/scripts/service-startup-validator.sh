#!/bin/bash
# Service Startup Validator
# Ensures proper service startup sequence and fixes common issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

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
    echo -e "${BLUE}[VALIDATOR]${NC} $1"
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

# Pre-startup system validation
validate_system() {
    log_info "Validating system prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check Docker is available and running
    if ! systemctl is-active --quiet docker; then
        log_warning "Docker is not running, attempting to start..."
        systemctl start docker
        systemctl enable docker
        sleep 5
    fi
    
    # Verify Docker is working
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not properly configured"
        exit 1
    fi
    
    log_success "System prerequisites validated"
}

# Create all required directories with proper permissions
create_directories() {
    log_info "Creating and fixing directory structure..."
    
    # Create system users if they don't exist
    for user in consul nomad vault; do
        if ! id "$user" >/dev/null 2>&1; then
            useradd --system --home "/opt/$user" --shell /bin/false "$user"
            log_info "Created user: $user"
        fi
    done
    
    # Create base directories
    for service in consul nomad vault; do
        mkdir -p "/opt/$service"/{data,config,logs}
        mkdir -p "/var/log/$service"
        
        # Set ownership
        chown -R "$service:$service" "/opt/$service"
        chown -R "$service:$service" "/var/log/$service"
        
        # Set permissions
        chmod 755 "/opt/$service"
        chmod 700 "/opt/$service/data"
        chmod 755 "/opt/$service/config"
        chmod 755 "/opt/$service/logs"
        chmod 755 "/var/log/$service"
    done
    
    # Create Nomad volumes directory
    mkdir -p /opt/nomad/volumes/{vault-{develop,staging,production}-{data,config,logs},traefik-{certs,config}}
    mkdir -p /opt/nomad/volumes/traefik-config/dynamic
    
    # Set Nomad volume permissions
    for env in develop staging production; do
        chmod 700 "/opt/nomad/volumes/vault-${env}-data"
        chmod 755 "/opt/nomad/volumes/vault-${env}-config"
        chmod 755 "/opt/nomad/volumes/vault-${env}-logs"
    done
    
    chmod 700 /opt/nomad/volumes/traefik-certs
    chmod 755 /opt/nomad/volumes/traefik-config
    chown -R nomad:nomad /opt/nomad/volumes
    
    # Ensure nomad user has Docker access
    usermod -aG docker nomad || log_warning "Could not add nomad to docker group"
    
    log_success "Directory structure created and permissions set"
}

# Fix network configuration issues
fix_network_config() {
    log_info "Fixing network configuration..."
    
    # Ensure required ports are not blocked
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 8500/tcp  # Consul HTTP
        ufw allow 8600/udp  # Consul DNS
        ufw allow 4646/tcp  # Nomad HTTP
        ufw allow 4647/tcp  # Nomad RPC
        ufw allow 4648/tcp  # Nomad Serf
        ufw allow 8200/tcp  # Vault (for UI access via Traefik)
        ufw allow 8080/tcp  # Traefik Dashboard
        log_info "UFW firewall rules updated"
    fi
    
    # Check for conflicting processes on required ports
    local conflicting_ports=()
    for port in 8500 4646 4647 4648; do
        if lsof -i ":$port" >/dev/null 2>&1; then
            local process=$(lsof -i ":$port" | tail -n1 | awk '{print $1}')
            if [[ "$process" != "consul" && "$process" != "nomad" ]]; then
                conflicting_ports+=("$port:$process")
            fi
        fi
    done
    
    if [[ ${#conflicting_ports[@]} -gt 0 ]]; then
        log_error "Conflicting processes found on required ports:"
        for conflict in "${conflicting_ports[@]}"; do
            log_error "  Port ${conflict%:*} used by ${conflict#*:}"
        done
        log_error "Please stop conflicting services before starting HashiCorp stack"
        exit 1
    fi
    
    log_success "Network configuration validated"
}

# Validate configuration files exist and are syntactically correct
validate_configurations() {
    log_info "Validating configuration files..."
    
    # Check Consul config
    if [[ ! -f /opt/consul/config/consul.hcl ]]; then
        log_error "Consul configuration not found: /opt/consul/config/consul.hcl"
        exit 1
    fi
    
    # Validate Consul config syntax (basic check)
    if ! grep -q "datacenter" /opt/consul/config/consul.hcl; then
        log_error "Consul configuration appears invalid - missing datacenter"
        exit 1
    fi
    
    # Check Nomad config
    if [[ ! -f /opt/nomad/config/nomad.hcl ]]; then
        log_error "Nomad configuration not found: /opt/nomad/config/nomad.hcl"
        exit 1
    fi
    
    # Validate Nomad config syntax (basic check)
    if ! grep -q "datacenter" /opt/nomad/config/nomad.hcl; then
        log_error "Nomad configuration appears invalid - missing datacenter"
        exit 1
    fi
    
    # Fix config permissions
    chown consul:consul /opt/consul/config/consul.hcl
    chmod 640 /opt/consul/config/consul.hcl
    
    chown nomad:nomad /opt/nomad/config/nomad.hcl
    chmod 640 /opt/nomad/config/nomad.hcl
    
    log_success "Configuration files validated"
}

# Check systemd service files and fix common issues
validate_systemd_services() {
    log_info "Validating systemd service files..."
    
    # Check service files exist
    if [[ ! -f /etc/systemd/system/consul.service ]]; then
        log_error "Consul systemd service not found: /etc/systemd/system/consul.service"
        exit 1
    fi
    
    if [[ ! -f /etc/systemd/system/nomad.service ]]; then
        log_error "Nomad systemd service not found: /etc/systemd/system/nomad.service"
        exit 1
    fi
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    log_success "Systemd services validated"
}

# Perform startup sequence validation
startup_sequence_test() {
    log_info "Testing startup sequence..."
    
    # Stop all services first
    systemctl stop nomad 2>/dev/null || true
    systemctl stop consul 2>/dev/null || true
    
    # Wait for services to stop
    sleep 5
    
    # Test Consul startup
    log_info "Testing Consul startup..."
    systemctl start consul
    
    local consul_ready=false
    for attempt in {1..20}; do
        if curl -s --connect-timeout 2 http://localhost:8500/v1/status/leader >/dev/null 2>&1; then
            consul_ready=true
            break
        fi
        sleep 3
    done
    
    if [[ "$consul_ready" != "true" ]]; then
        log_error "Consul failed to start properly during validation"
        systemctl status consul --no-pager
        exit 1
    fi
    
    log_success "Consul startup validated"
    
    # Test Nomad startup
    log_info "Testing Nomad startup..."
    systemctl start nomad
    
    local nomad_ready=false
    for attempt in {1..30}; do
        if curl -s --connect-timeout 2 http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
            nomad_ready=true
            break
        fi
        sleep 4
    done
    
    if [[ "$nomad_ready" != "true" ]]; then
        log_error "Nomad failed to start properly during validation"
        systemctl status nomad --no-pager
        exit 1
    fi
    
    log_success "Nomad startup validated"
    log_success "Startup sequence validation completed successfully"
}

# Clean up any problematic state
cleanup_stale_state() {
    log_info "Cleaning up stale state..."
    
    # Remove any stale lock files
    rm -f /opt/consul/data/.consul.lock 2>/dev/null || true
    rm -f /opt/nomad/data/server/raft/raft.db.lock 2>/dev/null || true
    
    # Clear any temporary files
    rm -f /tmp/consul-* 2>/dev/null || true
    rm -f /tmp/nomad-* 2>/dev/null || true
    
    log_success "Stale state cleaned up"
}

# Usage function
usage() {
    cat <<EOF
Service Startup Validator
Validates and fixes common service startup issues

Usage: $0 [OPTIONS]

Options:
  --test-only       Only run validation tests, don't start services
  --fix-perms       Fix directory permissions and ownership
  --verbose         Enable verbose debug output
  -h, --help        Show this help message

Examples:
  $0                    # Full validation and startup test
  $0 --test-only        # Validation only
  $0 --fix-perms        # Fix permissions and validate
  $0 --verbose          # Verbose output
EOF
}

# Main execution
main() {
    local test_only=false
    local fix_perms=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test-only)
                test_only=true
                shift
                ;;
            --fix-perms)
                fix_perms=true
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
    
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}SERVICE STARTUP VALIDATOR${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
    
    # Run validation steps
    validate_system
    
    if [[ "$fix_perms" == "true" ]] || [[ "$test_only" == "false" ]]; then
        create_directories
    fi
    
    cleanup_stale_state
    fix_network_config
    validate_configurations
    validate_systemd_services
    
    if [[ "$test_only" == "false" ]]; then
        startup_sequence_test
    else
        log_info "Test-only mode: skipping startup sequence test"
    fi
    
    echo -e "${WHITE}================================================================================================${NC}"
    log_success "Service startup validation completed successfully!"
    echo -e "${WHITE}================================================================================================${NC}"
    
    if [[ "$test_only" == "false" ]]; then
        log_info "Services are now running and validated"
        log_info "Consul: http://localhost:8500"
        log_info "Nomad: http://localhost:4646"
        log_info "Use './manage-services.sh status' to check service status"
    fi
}

# Execute main function
main "$@"