#!/bin/bash
# Common functions and utilities for deployment scripts
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

# Configuration defaults - can be overridden by environment or sourcing scripts
DEFAULT_CONSUL_VERSION="1.17.0"
DEFAULT_NOMAD_VERSION="1.7.2"
DEFAULT_VAULT_VERSION="1.17.6"
DEFAULT_TRAEFIK_VERSION="v3.2.3"

DEFAULT_DATACENTER="dc1"
DEFAULT_REGION="global"
DEFAULT_DOMAIN="cloudya.net"
DEFAULT_NAMESPACE="default"

# Paths
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
LOGS_DIR="${LOGS_DIR:-${PROJECT_ROOT}/logs}"
TEMP_DIR="${TEMP_DIR:-${PROJECT_ROOT}/tmp}"

# Color codes for output
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
fi

# Logging functions with consistent format
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/deployment.log" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/deployment.log" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/deployment.log" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/deployment.log" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/deployment.log" 2>/dev/null || echo -e "${CYAN}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Utility functions

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        return 1
    fi
}

# Check if command is available
check_command() {
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Wait for service to be ready with timeout
wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local timeout="${3:-120}"
    local interval="${4:-5}"
    local elapsed=0
    
    log_info "Waiting for $service_name to be ready..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$check_command" &> /dev/null; then
            log_success "$service_name is ready"
            return 0
        fi
        
        log_debug "$service_name not ready, waiting... (${elapsed}s/${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "$service_name did not become ready within $timeout seconds"
    return 1
}

# Create directories with proper permissions
create_directory() {
    local dir="$1"
    local owner="${2:-root:root}"
    local perms="${3:-755}"
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
    
    chown "$owner" "$dir"
    chmod "$perms" "$dir"
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_suffix="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.${backup_suffix}"
        log_info "Backed up $file to ${file}.backup.${backup_suffix}"
        return 0
    else
        log_debug "File $file does not exist, skipping backup"
        return 1
    fi
}

# Generate secure random password
generate_password() {
    local length="${1:-16}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Validate email address
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get system architecture
get_architecture() {
    case $(uname -m) in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "arm" ;;
        *) echo "unknown" ;;
    esac
}

# Get operating system
get_os() {
    case $(uname -s) in
        Linux) echo "linux" ;;
        Darwin) echo "darwin" ;;
        *) echo "unknown" ;;
    esac
}

# Download file with retry and verification
download_file() {
    local url="$1"
    local destination="$2"
    local max_retries="${3:-3}"
    local retry_delay="${4:-5}"
    local expected_sha256="${5:-}"
    
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Downloading $url (attempt $((retry_count + 1))/$max_retries)"
        
        if wget -q -O "$destination" "$url"; then
            # Verify checksum if provided
            if [[ -n "$expected_sha256" ]]; then
                local actual_sha256
                actual_sha256=$(sha256sum "$destination" | cut -d' ' -f1)
                
                if [[ "$actual_sha256" == "$expected_sha256" ]]; then
                    log_success "Downloaded and verified: $destination"
                    return 0
                else
                    log_warning "Checksum mismatch for $destination (expected: $expected_sha256, got: $actual_sha256)"
                    rm -f "$destination"
                fi
            else
                log_success "Downloaded: $destination"
                return 0
            fi
        else
            log_warning "Download failed for $url"
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $max_retries ]]; then
            log_info "Retrying in $retry_delay seconds..."
            sleep $retry_delay
        fi
    done
    
    log_error "Failed to download $url after $max_retries attempts"
    return 1
}

# Install system dependencies
install_system_dependencies() {
    log_info "Installing system dependencies..."
    
    local packages=("wget" "unzip" "curl" "systemd" "jq")
    
    if check_command "apt-get"; then
        apt-get update
        apt-get install -y "${packages[@]}"
    elif check_command "yum"; then
        yum update -y
        yum install -y "${packages[@]}"
    elif check_command "dnf"; then
        dnf update -y
        dnf install -y "${packages[@]}"
    else
        log_error "Unsupported package manager. Please install packages manually: ${packages[*]}"
        return 1
    fi
    
    log_success "System dependencies installed"
}

# Setup logging directory
setup_logging() {
    create_directory "$LOGS_DIR" "root:root" "755"
    create_directory "$TEMP_DIR" "root:root" "755"
}

# Cleanup temporary files
cleanup_temp_files() {
    local pattern="${1:-deployment-*}"
    
    if [[ -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary files: $TEMP_DIR/$pattern"
        rm -f "$TEMP_DIR/$pattern"
    fi
}

# Check service status
check_service_status() {
    local service_name="$1"
    
    if systemctl is-active --quiet "$service_name"; then
        echo "running"
    elif systemctl is-enabled --quiet "$service_name"; then
        echo "enabled"
    elif systemctl list-unit-files "$service_name.service" &>/dev/null; then
        echo "installed"
    else
        echo "not_found"
    fi
}

# Start and enable service
start_and_enable_service() {
    local service_name="$1"
    local wait_time="${2:-10}"
    
    log_info "Starting and enabling $service_name..."
    
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl start "$service_name"
    
    # Wait a bit for service to start
    sleep "$wait_time"
    
    if systemctl is-active --quiet "$service_name"; then
        log_success "$service_name started successfully"
        return 0
    else
        log_error "$service_name failed to start"
        systemctl status "$service_name" || true
        return 1
    fi
}

# Generate systemd service file
generate_systemd_service() {
    local service_name="$1"
    local description="$2"
    local exec_start="$3"
    local user="${4:-root}"
    local group="${5:-root}"
    local additional_config="${6:-}"
    
    local service_file="/etc/systemd/system/${service_name}.service"
    
    # Backup existing service file
    backup_file "$service_file"
    
    cat > "$service_file" <<EOF
[Unit]
Description=$description
Documentation=https://www.hashicorp.com/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/$service_name/$service_name.hcl

[Service]
Type=notify
User=$user
Group=$group
ExecStart=$exec_start
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

$additional_config

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "Generated systemd service: $service_file"
}

# Environment-specific configuration
get_environment_config() {
    local environment="$1"
    local component="${2:-general}"
    
    case "$environment" in
        develop|development)
            case "$component" in
                vault)
                    echo "tls_disable=true log_level=DEBUG"
                    ;;
                traefik)
                    echo "log_level=DEBUG api_insecure=true"
                    ;;
                *)
                    echo "log_level=DEBUG"
                    ;;
            esac
            ;;
        staging)
            case "$component" in
                vault)
                    echo "tls_disable=false log_level=INFO"
                    ;;
                traefik)
                    echo "log_level=INFO certificatesResolvers.letsencrypt.acme.caServer=https://acme-staging-v02.api.letsencrypt.org/directory"
                    ;;
                *)
                    echo "log_level=INFO"
                    ;;
            esac
            ;;
        production)
            case "$component" in
                vault)
                    echo "tls_disable=false log_level=WARN"
                    ;;
                traefik)
                    echo "log_level=WARN certificatesResolvers.letsencrypt.acme.caServer=https://acme-v02.api.letsencrypt.org/directory"
                    ;;
                *)
                    echo "log_level=WARN"
                    ;;
            esac
            ;;
        *)
            log_warning "Unknown environment: $environment, using production settings"
            get_environment_config "production" "$component"
            ;;
    esac
}

# Check if port is available
check_port_available() {
    local port="$1"
    local host="${2:-localhost}"
    
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Get available port starting from given port
get_available_port() {
    local start_port="$1"
    local max_attempts="${2:-100}"
    
    for ((port=start_port; port<start_port+max_attempts; port++)); do
        if check_port_available "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    log_error "No available port found starting from $start_port"
    return 1
}

# Validate environment name
validate_environment() {
    local environment="$1"
    
    case "$environment" in
        develop|development|staging|production)
            return 0
            ;;
        *)
            log_error "Invalid environment: $environment"
            log_error "Valid environments: develop, staging, production"
            return 1
            ;;
    esac
}

# Auto-detect environment based on hostname or other factors
auto_detect_environment() {
    local hostname
    hostname=$(hostname)
    
    if [[ "$hostname" == *"prod"* || "$hostname" == *"production"* ]]; then
        echo "production"
    elif [[ "$hostname" == *"stage"* || "$hostname" == *"staging"* ]]; then
        echo "staging"
    elif [[ "$hostname" == *"dev"* || "$hostname" == *"develop"* ]]; then
        echo "develop"
    else
        # Default to develop if unsure
        echo "develop"
    fi
}

# Check if running in CI/CD environment
is_ci_environment() {
    if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${JENKINS_URL:-}" ]]; then
        return 0
    else
        return 1
    fi
}

# Prompt for user confirmation (skip in CI)
confirm_action() {
    local message="$1"
    local auto_approve="${2:-false}"
    
    if [[ "$auto_approve" == "true" ]] || is_ci_environment; then
        log_info "Auto-approving: $message"
        return 0
    fi
    
    echo ""
    log_warning "$message"
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "Operation cancelled by user"
        return 1
    fi
}

# Initialize common environment
init_common_environment() {
    setup_logging
    
    # Set default environment if not provided
    ENVIRONMENT="${ENVIRONMENT:-$(auto_detect_environment)}"
    
    log_debug "Common environment initialized"
    log_debug "  Project root: $PROJECT_ROOT"
    log_debug "  Logs directory: $LOGS_DIR"
    log_debug "  Temp directory: $TEMP_DIR"
    log_debug "  Environment: $ENVIRONMENT"
}

# Cleanup function for script exit
cleanup_on_exit() {
    log_debug "Performing cleanup on exit"
    cleanup_temp_files
}

# Set up exit trap
setup_exit_trap() {
    trap cleanup_on_exit EXIT
}

# Load configuration from file
load_config() {
    local config_file="$1"
    
    if [[ -f "$config_file" ]]; then
        log_info "Loading configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_debug "Configuration file not found: $config_file"
    fi
}

# Save configuration to file
save_config() {
    local config_file="$1"
    shift
    local vars=("$@")
    
    log_info "Saving configuration to: $config_file"
    
    cat > "$config_file" <<EOF
# Generated configuration file
# $(date)

EOF
    
    for var in "${vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            echo "$var=\"${!var}\"" >> "$config_file"
        fi
    done
}

# Export common functions and variables
export -f log_info log_success log_warning log_error log_debug
export -f check_root check_command wait_for_service create_directory backup_file
export -f generate_password validate_ip validate_email get_architecture get_os
export -f download_file install_system_dependencies setup_logging cleanup_temp_files
export -f check_service_status start_and_enable_service generate_systemd_service
export -f get_environment_config check_port_available get_available_port
export -f validate_environment auto_detect_environment is_ci_environment confirm_action
export -f init_common_environment cleanup_on_exit setup_exit_trap load_config save_config

# Initialize if sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "Common functions loaded"
    init_common_environment
fi