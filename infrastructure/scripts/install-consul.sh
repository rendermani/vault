#!/bin/bash
# Idempotent script to install and configure Consul as systemd service
# Can be run multiple times safely
set -euo pipefail

# Configuration variables - can be overridden by environment
CONSUL_VERSION="${CONSUL_VERSION:-1.17.0}"
CONSUL_USER="${CONSUL_USER:-consul}"
CONSUL_GROUP="${CONSUL_GROUP:-consul}"
CONSUL_HOME="${CONSUL_HOME:-/opt/consul}"
CONSUL_DATA_DIR="${CONSUL_DATA_DIR:-/opt/consul/data}"
CONSUL_CONFIG_DIR="${CONSUL_CONFIG_DIR:-/etc/consul}"
CONSUL_LOG_DIR="${CONSUL_LOG_DIR:-/var/log/consul}"
CONSUL_BINARY_PATH="${CONSUL_BINARY_PATH:-/usr/local/bin/consul}"
CONSUL_DATACENTER="${CONSUL_DATACENTER:-dc1}"
CONSUL_NODE_ROLE="${CONSUL_NODE_ROLE:-server}"
CONSUL_BOOTSTRAP_EXPECT="${CONSUL_BOOTSTRAP_EXPECT:-1}"
CONSUL_ENCRYPT_KEY="${CONSUL_ENCRYPT_KEY:-}"
CONSUL_BIND_ADDR="${CONSUL_BIND_ADDR:-0.0.0.0}"
CONSUL_CLIENT_ADDR="${CONSUL_CLIENT_ADDR:-0.0.0.0}"
CONSUL_UI="${CONSUL_UI:-true}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/consul-install.log
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/consul-install.log
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/consul-install.log
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/consul-install.log
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y wget unzip curl systemd
    elif command -v yum &> /dev/null; then
        yum update -y
        yum install -y wget unzip curl systemd
    elif command -v dnf &> /dev/null; then
        dnf update -y
        dnf install -y wget unzip curl systemd
    else
        log_error "Unsupported package manager. Please install wget, unzip, curl manually."
        exit 1
    fi
    
    log_success "Dependencies installed"
}

# Create consul user and group
create_user() {
    log_info "Creating consul user and group..."
    
    if ! getent group "$CONSUL_GROUP" &> /dev/null; then
        groupadd --system "$CONSUL_GROUP"
        log_success "Created group: $CONSUL_GROUP"
    else
        log_info "Group $CONSUL_GROUP already exists"
    fi
    
    if ! getent passwd "$CONSUL_USER" &> /dev/null; then
        useradd --system --gid "$CONSUL_GROUP" --home "$CONSUL_HOME" \
            --shell /bin/false --comment "Consul service user" "$CONSUL_USER"
        log_success "Created user: $CONSUL_USER"
    else
        log_info "User $CONSUL_USER already exists"
    fi
}

# Download and install Consul binary
install_consul_binary() {
    log_info "Installing Consul binary version $CONSUL_VERSION..."
    
    # Check if Consul is already installed and at correct version
    if [[ -f "$CONSUL_BINARY_PATH" ]]; then
        local installed_version
        installed_version=$("$CONSUL_BINARY_PATH" version | head -n1 | cut -d' ' -f2 | sed 's/v//')
        if [[ "$installed_version" == "$CONSUL_VERSION" ]]; then
            log_info "Consul $CONSUL_VERSION already installed"
            return 0
        else
            log_info "Upgrading Consul from $installed_version to $CONSUL_VERSION"
        fi
    fi
    
    # Determine architecture
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) 
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    
    local os
    case $(uname -s) in
        Linux) os="linux" ;;
        Darwin) os="darwin" ;;
        *) 
            log_error "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
    
    # Download and install
    local temp_dir
    temp_dir=$(mktemp -d)
    local zip_file="consul_${CONSUL_VERSION}_${os}_${arch}.zip"
    local download_url="https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${zip_file}"
    
    log_info "Downloading from: $download_url"
    
    if ! wget -q "$download_url" -O "$temp_dir/$zip_file"; then
        log_error "Failed to download Consul"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    cd "$temp_dir"
    unzip -q "$zip_file"
    
    # Stop service if running before replacing binary
    if systemctl is-active --quiet consul; then
        log_info "Stopping Consul service for binary update"
        systemctl stop consul
    fi
    
    chmod +x consul
    mv consul "$CONSUL_BINARY_PATH"
    chown root:root "$CONSUL_BINARY_PATH"
    
    rm -rf "$temp_dir"
    
    log_success "Consul binary installed at $CONSUL_BINARY_PATH"
}

# Create directories
create_directories() {
    log_info "Creating Consul directories..."
    
    local directories=(
        "$CONSUL_HOME"
        "$CONSUL_DATA_DIR"
        "$CONSUL_CONFIG_DIR"
        "$CONSUL_LOG_DIR"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        else
            log_info "Directory already exists: $dir"
        fi
    done
    
    # Set ownership
    chown -R "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_HOME" "$CONSUL_DATA_DIR" "$CONSUL_LOG_DIR"
    chown -R "$CONSUL_USER:$CONSUL_GROUP" "$CONSUL_CONFIG_DIR"
    
    # Set permissions
    chmod 755 "$CONSUL_HOME" "$CONSUL_DATA_DIR" "$CONSUL_CONFIG_DIR"
    chmod 750 "$CONSUL_LOG_DIR"
    
    log_success "Directory permissions set"
}

# Generate encryption key if not provided
generate_encrypt_key() {
    if [[ -z "$CONSUL_ENCRYPT_KEY" ]]; then
        log_info "Generating Consul encryption key..."
        CONSUL_ENCRYPT_KEY=$("$CONSUL_BINARY_PATH" keygen)
        log_success "Generated encryption key"
        log_warning "Save this encryption key for other nodes: $CONSUL_ENCRYPT_KEY"
    fi
}

# Create Consul configuration
create_configuration() {
    log_info "Creating Consul configuration..."
    
    local config_file="$CONSUL_CONFIG_DIR/consul.hcl"
    local is_server="false"
    
    if [[ "$CONSUL_NODE_ROLE" == "server" ]]; then
        is_server="true"
    fi
    
    # Backup existing config
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing configuration"
    fi
    
    cat > "$config_file" <<EOF
# Consul Configuration
datacenter = "$CONSUL_DATACENTER"
data_dir = "$CONSUL_DATA_DIR"
log_level = "INFO"
log_file = "$CONSUL_LOG_DIR/consul.log"
log_rotate_duration = "24h"
log_rotate_max_files = 7
server = $is_server
ui_config {
  enabled = $CONSUL_UI
}

bind_addr = "$CONSUL_BIND_ADDR"
client_addr = "$CONSUL_CLIENT_ADDR"

connect {
  enabled = true
}

ports {
  grpc = 8502
}

encrypt = "$CONSUL_ENCRYPT_KEY"

EOF

    # Add server-specific configuration
    if [[ "$CONSUL_NODE_ROLE" == "server" ]]; then
        cat >> "$config_file" <<EOF

bootstrap_expect = $CONSUL_BOOTSTRAP_EXPECT

EOF
    fi
    
    chown "$CONSUL_USER:$CONSUL_GROUP" "$config_file"
    chmod 640 "$config_file"
    
    log_success "Configuration created at $config_file"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    local service_file="/etc/systemd/system/consul.service"
    
    # Backup existing service file
    if [[ -f "$service_file" ]]; then
        cp "$service_file" "$service_file.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing service file"
    fi
    
    cat > "$service_file" <<EOF
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONSUL_CONFIG_DIR/consul.hcl

[Service]
Type=notify
User=$CONSUL_USER
Group=$CONSUL_GROUP
ExecStart=$CONSUL_BINARY_PATH agent -config-dir=$CONSUL_CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Security settings
PrivateTmp=yes
PrivateDevices=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=$CONSUL_DATA_DIR $CONSUL_LOG_DIR
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable consul
    
    log_success "Systemd service created and enabled"
}

# Start and verify service
start_and_verify_service() {
    log_info "Starting Consul service..."
    
    if systemctl is-active --quiet consul; then
        log_info "Consul is already running, restarting..."
        systemctl restart consul
    else
        systemctl start consul
    fi
    
    # Wait for service to start
    sleep 5
    
    # Verify service is running
    if systemctl is-active --quiet consul; then
        log_success "Consul service started successfully"
    else
        log_error "Consul service failed to start"
        systemctl status consul
        exit 1
    fi
    
    # Wait for Consul to be ready
    local timeout=60
    local count=0
    
    log_info "Waiting for Consul to be ready..."
    
    while [[ $count -lt $timeout ]]; do
        if "$CONSUL_BINARY_PATH" members &> /dev/null; then
            log_success "Consul is ready and responding"
            break
        fi
        
        sleep 1
        ((count++))
    done
    
    if [[ $count -ge $timeout ]]; then
        log_error "Consul did not become ready within $timeout seconds"
        exit 1
    fi
    
    # Show cluster members
    log_info "Consul cluster members:"
    "$CONSUL_BINARY_PATH" members
}

# Create logrotate configuration
create_logrotate_config() {
    log_info "Creating logrotate configuration..."
    
    local logrotate_file="/etc/logrotate.d/consul"
    
    cat > "$logrotate_file" <<EOF
$CONSUL_LOG_DIR/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 $CONSUL_USER $CONSUL_GROUP
    postrotate
        systemctl reload consul > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Logrotate configuration created"
}

# Save installation information
save_installation_info() {
    log_info "Saving installation information..."
    
    local info_file="$CONSUL_CONFIG_DIR/installation-info.txt"
    
    cat > "$info_file" <<EOF
Consul Installation Information
==============================
Installation Date: $(date)
Version: $CONSUL_VERSION
User: $CONSUL_USER
Group: $CONSUL_GROUP
Home: $CONSUL_HOME
Data Directory: $CONSUL_DATA_DIR
Config Directory: $CONSUL_CONFIG_DIR
Log Directory: $CONSUL_LOG_DIR
Binary Path: $CONSUL_BINARY_PATH
Datacenter: $CONSUL_DATACENTER
Node Role: $CONSUL_NODE_ROLE
Encryption Key: [REDACTED]

Useful Commands:
===============
sudo systemctl status consul
sudo systemctl restart consul
sudo journalctl -u consul -f
consul members
consul info
consul monitor
EOF
    
    chown "$CONSUL_USER:$CONSUL_GROUP" "$info_file"
    chmod 640 "$info_file"
    
    log_success "Installation information saved to $info_file"
}

# Main installation function
main() {
    log_info "Starting Consul installation script"
    log_info "Version: $CONSUL_VERSION"
    log_info "Node Role: $CONSUL_NODE_ROLE"
    
    check_root
    install_dependencies
    create_user
    install_consul_binary
    create_directories
    generate_encrypt_key
    create_configuration
    create_systemd_service
    create_logrotate_config
    start_and_verify_service
    save_installation_info
    
    log_success "Consul installation completed successfully!"
    log_info "Consul is running and ready to use"
    log_info "Configuration file: $CONSUL_CONFIG_DIR/consul.hcl"
    log_info "Log file: $CONSUL_LOG_DIR/consul.log"
    
    if [[ "$CONSUL_NODE_ROLE" == "server" && -n "$CONSUL_ENCRYPT_KEY" ]]; then
        log_warning "IMPORTANT: Save this encryption key for joining other nodes:"
        log_warning "CONSUL_ENCRYPT_KEY=$CONSUL_ENCRYPT_KEY"
    fi
    
    log_info "Use 'consul members' to check cluster status"
    log_info "Use 'systemctl status consul' to check service status"
}

# Run main function
main "$@"