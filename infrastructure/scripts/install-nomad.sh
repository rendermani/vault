#!/bin/bash
# Idempotent script to install and configure Nomad as systemd service
# Can be run multiple times safely
set -euo pipefail

# Configuration variables - can be overridden by environment
NOMAD_VERSION="${NOMAD_VERSION:-1.7.2}"
NOMAD_USER="${NOMAD_USER:-nomad}"
NOMAD_GROUP="${NOMAD_GROUP:-nomad}"
NOMAD_HOME="${NOMAD_HOME:-/opt/nomad}"
NOMAD_DATA_DIR="${NOMAD_DATA_DIR:-/opt/nomad/data}"
NOMAD_CONFIG_DIR="${NOMAD_CONFIG_DIR:-/etc/nomad}"
NOMAD_LOG_DIR="${NOMAD_LOG_DIR:-/var/log/nomad}"
NOMAD_PLUGIN_DIR="${NOMAD_PLUGIN_DIR:-/opt/nomad/plugins}"
NOMAD_BINARY_PATH="${NOMAD_BINARY_PATH:-/usr/local/bin/nomad}"
NOMAD_DATACENTER="${NOMAD_DATACENTER:-dc1}"
NOMAD_REGION="${NOMAD_REGION:-global}"
NOMAD_NODE_ROLE="${NOMAD_NODE_ROLE:-both}"
NOMAD_BOOTSTRAP_EXPECT="${NOMAD_BOOTSTRAP_EXPECT:-1}"
NOMAD_ENCRYPT_KEY="${NOMAD_ENCRYPT_KEY:-}"
NOMAD_BIND_ADDR="${NOMAD_BIND_ADDR:-0.0.0.0}"
NOMAD_ADVERTISE_ADDR="${NOMAD_ADVERTISE_ADDR:-}"
NOMAD_UI="${NOMAD_UI:-true}"
CONSUL_ENABLED="${CONSUL_ENABLED:-true}"
CONSUL_ADDRESS="${CONSUL_ADDRESS:-127.0.0.1:8500}"
# CRITICAL: Vault integration is disabled by default during bootstrap to prevent circular dependency
# Set NOMAD_VAULT_BOOTSTRAP_PHASE=true to ensure Vault stays disabled during initial deployment
VAULT_ENABLED="${VAULT_ENABLED:-false}"
VAULT_ADDRESS="${VAULT_ADDRESS:-https://127.0.0.1:8200}"
NOMAD_VAULT_BOOTSTRAP_PHASE="${NOMAD_VAULT_BOOTSTRAP_PHASE:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/nomad-install.log
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/nomad-install.log
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/nomad-install.log
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/nomad-install.log
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
        apt-get install -y wget unzip curl systemd docker.io
        systemctl enable docker
        systemctl start docker
        usermod -aG docker "$NOMAD_USER" 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        yum update -y
        yum install -y wget unzip curl systemd docker
        systemctl enable docker
        systemctl start docker
        usermod -aG docker "$NOMAD_USER" 2>/dev/null || true
    elif command -v dnf &> /dev/null; then
        dnf update -y
        dnf install -y wget unzip curl systemd docker
        systemctl enable docker
        systemctl start docker
        usermod -aG docker "$NOMAD_USER" 2>/dev/null || true
    else
        log_error "Unsupported package manager. Please install wget, unzip, curl, docker manually."
        exit 1
    fi
    
    log_success "Dependencies installed"
}

# Create nomad user and group
create_user() {
    log_info "Creating nomad user and group..."
    
    if ! getent group "$NOMAD_GROUP" &> /dev/null; then
        groupadd --system "$NOMAD_GROUP"
        log_success "Created group: $NOMAD_GROUP"
    else
        log_info "Group $NOMAD_GROUP already exists"
    fi
    
    if ! getent passwd "$NOMAD_USER" &> /dev/null; then
        useradd --system --gid "$NOMAD_GROUP" --home "$NOMAD_HOME" \
            --shell /bin/bash --comment "Nomad service user" "$NOMAD_USER"
        log_success "Created user: $NOMAD_USER"
    else
        log_info "User $NOMAD_USER already exists"
    fi
    
    # Add nomad user to docker group for container operations
    if getent group docker &> /dev/null; then
        usermod -aG docker "$NOMAD_USER" 2>/dev/null || true
        log_info "Added $NOMAD_USER to docker group"
    fi
}

# Download and install Nomad binary
install_nomad_binary() {
    log_info "Installing Nomad binary version $NOMAD_VERSION..."
    
    # Check if Nomad is already installed and at correct version
    if [[ -f "$NOMAD_BINARY_PATH" ]]; then
        local installed_version
        installed_version=$("$NOMAD_BINARY_PATH" version | head -n1 | cut -d' ' -f2 | sed 's/v//')
        if [[ "$installed_version" == "$NOMAD_VERSION" ]]; then
            log_info "Nomad $NOMAD_VERSION already installed"
            return 0
        else
            log_info "Upgrading Nomad from $installed_version to $NOMAD_VERSION"
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
    local zip_file="nomad_${NOMAD_VERSION}_${os}_${arch}.zip"
    local download_url="https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/${zip_file}"
    
    log_info "Downloading from: $download_url"
    
    if ! wget -q "$download_url" -O "$temp_dir/$zip_file"; then
        log_error "Failed to download Nomad"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    cd "$temp_dir"
    unzip -q "$zip_file"
    
    # Stop service if running before replacing binary
    if systemctl is-active --quiet nomad; then
        log_info "Stopping Nomad service for binary update"
        systemctl stop nomad
    fi
    
    chmod +x nomad
    mv nomad "$NOMAD_BINARY_PATH"
    chown root:root "$NOMAD_BINARY_PATH"
    
    rm -rf "$temp_dir"
    
    log_success "Nomad binary installed at $NOMAD_BINARY_PATH"
}

# Create directories
create_directories() {
    log_info "Creating Nomad directories..."
    
    local directories=(
        "$NOMAD_HOME"
        "$NOMAD_DATA_DIR"
        "$NOMAD_CONFIG_DIR"
        "$NOMAD_LOG_DIR"
        "$NOMAD_PLUGIN_DIR"
        "/etc/nomad.d"
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
    chown -R "$NOMAD_USER:$NOMAD_GROUP" "$NOMAD_HOME" "$NOMAD_DATA_DIR" "$NOMAD_LOG_DIR" "$NOMAD_PLUGIN_DIR"
    chown -R "$NOMAD_USER:$NOMAD_GROUP" "$NOMAD_CONFIG_DIR" "/etc/nomad.d"
    
    # Set permissions
    chmod 755 "$NOMAD_HOME" "$NOMAD_DATA_DIR" "$NOMAD_CONFIG_DIR" "$NOMAD_PLUGIN_DIR" "/etc/nomad.d"
    chmod 750 "$NOMAD_LOG_DIR"
    
    log_success "Directory permissions set"
}

# Generate encryption key if not provided
generate_encrypt_key() {
    if [[ -z "$NOMAD_ENCRYPT_KEY" ]]; then
        log_info "Generating Nomad encryption key..."
        NOMAD_ENCRYPT_KEY=$("$NOMAD_BINARY_PATH" operator gossip keyring generate)
        log_success "Generated encryption key"
        log_warning "Save this encryption key for other nodes: $NOMAD_ENCRYPT_KEY"
    fi
}

# Create Nomad configuration
create_configuration() {
    log_info "Creating Nomad configuration..."
    
    local config_file="$NOMAD_CONFIG_DIR/nomad.hcl"
    local is_server="false"
    local is_client="false"
    
    case "$NOMAD_NODE_ROLE" in
        "server") is_server="true" ;;
        "client") is_client="true" ;;
        "both") 
            is_server="true"
            is_client="true"
            ;;
        *)
            log_error "Invalid NOMAD_NODE_ROLE: $NOMAD_NODE_ROLE. Must be 'server', 'client', or 'both'"
            exit 1
            ;;
    esac
    
    # Backup existing config
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing configuration"
    fi
    
    # Auto-detect advertise address if not provided
    if [[ -z "$NOMAD_ADVERTISE_ADDR" ]]; then
        NOMAD_ADVERTISE_ADDR=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
        log_info "Auto-detected advertise address: $NOMAD_ADVERTISE_ADDR"
    fi
    
    cat > "$config_file" <<EOF
# Nomad Configuration
datacenter = "$NOMAD_DATACENTER"
region = "$NOMAD_REGION"
data_dir = "$NOMAD_DATA_DIR"
plugin_dir = "$NOMAD_PLUGIN_DIR"
log_level = "INFO"
log_file = "$NOMAD_LOG_DIR/nomad.log"
log_rotate_duration = "24h"
log_rotate_max_files = 7
enable_debug = false

bind_addr = "$NOMAD_BIND_ADDR"
advertise {
  http = "$NOMAD_ADVERTISE_ADDR"
  rpc = "$NOMAD_ADVERTISE_ADDR"
  serf = "$NOMAD_ADVERTISE_ADDR"
}

ports {
  http = 4646
  rpc = 4647
  serf = 4648
}

EOF

    # Add server configuration
    if [[ "$is_server" == "true" ]]; then
        cat >> "$config_file" <<EOF
server {
  enabled = true
  bootstrap_expect = $NOMAD_BOOTSTRAP_EXPECT
  encrypt = "$NOMAD_ENCRYPT_KEY"
}

EOF
    fi

    # Add client configuration
    if [[ "$is_client" == "true" ]]; then
        cat >> "$config_file" <<EOF
client {
  enabled = true
  
  # Host volumes for bind mounts
  host_volume "docker-sock" {
    path = "/var/run/docker.sock"
    read_only = false
  }
  
  host_volume "host-tmp" {
    path = "/tmp"
    read_only = false
  }
  
  # Resource limits
  reserved {
    cpu = 100
    memory = 256
    disk = 1000
  }
  
  # Node metadata
  meta {
    node_type = "worker"
    environment = "production"
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    allow_caps = ["CHOWN", "DAC_OVERRIDE", "FSETID", "FOWNER", "MKNOD", "NET_RAW", "SETGID", "SETUID", "SETFCAP", "SETPCAP", "NET_BIND_SERVICE", "SYS_CHROOT", "KILL", "AUDIT_WRITE"]
    volumes {
      enabled = true
    }
  }
}

EOF
    fi

    # Add UI configuration
    if [[ "$NOMAD_UI" == "true" ]]; then
        cat >> "$config_file" <<EOF
ui {
  enabled = $NOMAD_UI
}

EOF
    fi

    # Add Consul integration if enabled
    if [[ "$CONSUL_ENABLED" == "true" ]]; then
        cat >> "$config_file" <<EOF
consul {
  address = "$CONSUL_ADDRESS"
  auto_advertise = true
  server_auto_join = true
  client_auto_join = true
  
  # Service registration
  server_service_name = "nomad-server"
  client_service_name = "nomad-client"
  
  # Tags for service discovery
  tags = ["nomad", "$NOMAD_NODE_ROLE", "$NOMAD_DATACENTER"]
}

EOF
    fi

    # Add Vault integration if enabled (but respect bootstrap phase)
    # During bootstrap phase, Vault integration is always disabled to prevent circular dependency
    if [[ "$VAULT_ENABLED" == "true" && "$NOMAD_VAULT_BOOTSTRAP_PHASE" != "true" ]]; then
        cat >> "$config_file" <<EOF
vault {
  enabled = true
  address = "$VAULT_ADDRESS"
  
  # Vault integration settings
  create_from_role = "nomad-cluster"
  task_token_ttl = "1h"
  ca_path = "/opt/vault/tls/ca.crt"
  cert_path = "/opt/vault/tls/tls.crt"
  key_path = "/opt/vault/tls/tls.key"
  tls_server_name = "vault.service.consul"
}

EOF
    elif [[ "$NOMAD_VAULT_BOOTSTRAP_PHASE" == "true" ]]; then
        cat >> "$config_file" <<EOF
# Vault integration disabled during bootstrap phase
# This prevents circular dependency: Nomad needs Vault, but Vault runs on Nomad
# After Vault deployment, run reconfigure_nomad_with_vault() to enable Vault integration
# vault {
#   enabled = false
#   # Will be enabled after Vault deployment
# }

EOF
        log_info "Vault integration disabled during bootstrap phase to prevent circular dependency"
    fi

    # Add telemetry configuration
    cat >> "$config_file" <<EOF
telemetry {
  collection_interval = "10s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

# TLS configuration (disabled by default for development)
# Uncomment and configure for production
# tls {
#   http = true
#   rpc = true
#   ca_file = "/etc/nomad/tls/ca.crt"
#   cert_file = "/etc/nomad/tls/nomad.crt"
#   key_file = "/etc/nomad/tls/nomad.key"
#   verify_server_hostname = true
#   verify_https_client = true
# }

# Access Control Lists (disabled by default)
# Uncomment for production with proper ACL tokens
# acl {
#   enabled = true
#   token_ttl = "30s"
#   policy_ttl = "60s"
# }

EOF
    
    chown "$NOMAD_USER:$NOMAD_GROUP" "$config_file"
    chmod 640 "$config_file"
    
    log_success "Configuration created at $config_file"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    local service_file="/etc/systemd/system/nomad.service"
    
    # Backup existing service file
    if [[ -f "$service_file" ]]; then
        cp "$service_file" "$service_file.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing service file"
    fi
    
    cat > "$service_file" <<EOF
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$NOMAD_CONFIG_DIR/nomad.hcl

[Service]
Type=notify
User=$NOMAD_USER
Group=$NOMAD_GROUP
ExecStart=$NOMAD_BINARY_PATH agent -config=$NOMAD_CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity

# Security settings
PrivateTmp=no
PrivateDevices=no
ProtectHome=no
ProtectSystem=no
NoNewPrivileges=no

# Required for Docker integration
SupplementaryGroups=docker

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable nomad
    
    log_success "Systemd service created and enabled"
}

# Install CNI plugins for networking
install_cni_plugins() {
    log_info "Installing CNI plugins..."
    
    local cni_version="v1.3.0"
    local cni_dir="/opt/cni/bin"
    
    if [[ -d "$cni_dir" ]] && [[ -f "$cni_dir/bridge" ]]; then
        log_info "CNI plugins already installed"
        return 0
    fi
    
    mkdir -p "$cni_dir"
    
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) 
            log_warning "Unsupported architecture for CNI plugins: $(uname -m)"
            return 0
            ;;
    esac
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local cni_file="cni-plugins-linux-${arch}-${cni_version}.tgz"
    local download_url="https://github.com/containernetworking/plugins/releases/download/${cni_version}/${cni_file}"
    
    if wget -q "$download_url" -O "$temp_dir/$cni_file"; then
        tar -C "$cni_dir" -xzf "$temp_dir/$cni_file"
        log_success "CNI plugins installed at $cni_dir"
    else
        log_warning "Failed to download CNI plugins, continuing without them"
    fi
    
    rm -rf "$temp_dir"
}

# Start and verify service
start_and_verify_service() {
    log_info "Starting Nomad service..."
    
    if systemctl is-active --quiet nomad; then
        log_info "Nomad is already running, restarting..."
        systemctl restart nomad
    else
        systemctl start nomad
    fi
    
    # Wait for service to start
    sleep 10
    
    # Verify service is running
    if systemctl is-active --quiet nomad; then
        log_success "Nomad service started successfully"
    else
        log_error "Nomad service failed to start"
        systemctl status nomad
        journalctl -u nomad -n 50
        exit 1
    fi
    
    # Wait for Nomad to be ready
    local timeout=120
    local count=0
    
    log_info "Waiting for Nomad to be ready..."
    
    while [[ $count -lt $timeout ]]; do
        if "$NOMAD_BINARY_PATH" node status &> /dev/null; then
            log_success "Nomad is ready and responding"
            break
        fi
        
        sleep 2
        ((count += 2))
    done
    
    if [[ $count -ge $timeout ]]; then
        log_error "Nomad did not become ready within $timeout seconds"
        exit 1
    fi
    
    # Show node status
    log_info "Nomad node status:"
    "$NOMAD_BINARY_PATH" node status
    
    # Show server members if this is a server
    if [[ "$NOMAD_NODE_ROLE" == "server" || "$NOMAD_NODE_ROLE" == "both" ]]; then
        log_info "Nomad server members:"
        "$NOMAD_BINARY_PATH" server members || log_warning "Could not retrieve server members (may be expected in single-node setup)"
    fi
}

# Create logrotate configuration
create_logrotate_config() {
    log_info "Creating logrotate configuration..."
    
    local logrotate_file="/etc/logrotate.d/nomad"
    
    cat > "$logrotate_file" <<EOF
$NOMAD_LOG_DIR/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 $NOMAD_USER $NOMAD_GROUP
    postrotate
        systemctl reload nomad > /dev/null 2>&1 || true
    endscript
}
EOF
    
    log_success "Logrotate configuration created"
}

# Save installation information
save_installation_info() {
    log_info "Saving installation information..."
    
    local info_file="$NOMAD_CONFIG_DIR/installation-info.txt"
    
    cat > "$info_file" <<EOF
Nomad Installation Information
=============================
Installation Date: $(date)
Version: $NOMAD_VERSION
User: $NOMAD_USER
Group: $NOMAD_GROUP
Home: $NOMAD_HOME
Data Directory: $NOMAD_DATA_DIR
Config Directory: $NOMAD_CONFIG_DIR
Log Directory: $NOMAD_LOG_DIR
Plugin Directory: $NOMAD_PLUGIN_DIR
Binary Path: $NOMAD_BINARY_PATH
Datacenter: $NOMAD_DATACENTER
Region: $NOMAD_REGION
Node Role: $NOMAD_NODE_ROLE
Encryption Key: [REDACTED]

Integration:
===========
Consul Enabled: $CONSUL_ENABLED
Consul Address: $CONSUL_ADDRESS
Vault Enabled: $VAULT_ENABLED
Vault Address: $VAULT_ADDRESS

Useful Commands:
===============
sudo systemctl status nomad
sudo systemctl restart nomad
sudo journalctl -u nomad -f
nomad node status
nomad server members
nomad job status
nomad ui (opens web UI)
EOF
    
    chown "$NOMAD_USER:$NOMAD_GROUP" "$info_file"
    chmod 640 "$info_file"
    
    log_success "Installation information saved to $info_file"
}

# Main installation function
main() {
    log_info "Starting Nomad installation script"
    log_info "Version: $NOMAD_VERSION"
    log_info "Node Role: $NOMAD_NODE_ROLE"
    log_info "Datacenter: $NOMAD_DATACENTER"
    log_info "Region: $NOMAD_REGION"
    
    check_root
    install_dependencies
    create_user
    install_nomad_binary
    create_directories
    generate_encrypt_key
    create_configuration
    create_systemd_service
    install_cni_plugins
    create_logrotate_config
    start_and_verify_service
    save_installation_info
    
    log_success "Nomad installation completed successfully!"
    log_info "Nomad is running and ready to use"
    log_info "Configuration file: $NOMAD_CONFIG_DIR/nomad.hcl"
    log_info "Log file: $NOMAD_LOG_DIR/nomad.log"
    log_info "Web UI: http://$(hostname -I | awk '{print $1}'):4646"
    
    if [[ "$NOMAD_NODE_ROLE" == "server" || "$NOMAD_NODE_ROLE" == "both" ]]; then
        log_warning "IMPORTANT: Save this encryption key for joining other nodes:"
        log_warning "NOMAD_ENCRYPT_KEY=$NOMAD_ENCRYPT_KEY"
    fi
    
    if [[ "$NOMAD_VAULT_BOOTSTRAP_PHASE" == "true" ]]; then
        log_warning "BOOTSTRAP PHASE DEPLOYMENT:"
        log_warning "Vault integration is DISABLED to prevent circular dependency"
        log_warning "After deploying Vault, run: reconfigure_nomad_with_vault() to enable Vault"
    fi
    
    log_info "Use 'nomad node status' to check cluster status"
    log_info "Use 'systemctl status nomad' to check service status"
    log_info "Use 'nomad ui' to access the web interface"
}

# Run main function
main "$@"