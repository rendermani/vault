#!/bin/bash

set -e

# Vault-specific deployment script
# This script handles ONLY Vault installation and configuration

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT="production"
ACTION="install"
VAULT_VERSION="1.17.3"
CONFIG_SOURCE="/tmp/vault.hcl"
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --action)
            ACTION="$2"
            shift 2
            ;;
        --version)
            VAULT_VERSION="$2"
            shift 2
            ;;
        --config)
            CONFIG_SOURCE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --environment ENV    Environment (production, staging)"
            echo "  --action ACTION      Action (install, check, backup, configure, restart)"
            echo "  --version VERSION    Vault version to install"
            echo "  --config FILE        Configuration file source"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1. Use --help for usage information."
            exit 1
            ;;
    esac
done

log_info() { echo -e "${GREEN}[VAULT]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check Vault status
check_vault() {
    if systemctl list-units --all | grep -q vault.service; then
        if systemctl is-active vault >/dev/null 2>&1; then
            CURRENT_VERSION=$(vault version 2>/dev/null | grep -oP 'Vault v\K[0-9.]+' || echo "unknown")
            echo "exists:running:${CURRENT_VERSION}"
        else
            echo "exists:stopped:unknown"
        fi
    else
        echo "not-exists:none:none"
    fi
}

# Enhanced health check
health_check() {
    log_step "Performing comprehensive health check..."
    
    export VAULT_ADDR=http://localhost:8200
    
    # Check if Vault is installed
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault binary not found"
        return 1
    fi
    
    log_info "Vault version: $(vault version | head -1)"
    
    # Check systemd service
    if systemctl is-active vault >/dev/null 2>&1; then
        log_info "✅ Vault service is active"
    else
        log_error "❌ Vault service is not active"
        return 1
    fi
    
    # Check Vault health endpoint
    if curl -f -s --max-time 10 http://localhost:8200/v1/sys/health >/dev/null; then
        HEALTH_JSON=$(curl -s http://localhost:8200/v1/sys/health)
        INITIALIZED=$(echo "$HEALTH_JSON" | jq -r '.initialized')
        SEALED=$(echo "$HEALTH_JSON" | jq -r '.sealed')
        
        log_info "✅ Vault API responding"
        log_info "Initialized: $INITIALIZED"
        log_info "Sealed: $SEALED"
    else
        log_error "❌ Vault health endpoint not responding"
        return 1
    fi
    
    # Check disk space
    DISK_USAGE=$(df /var/lib/vault 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || df / | tail -1 | awk '{print $5}' | sed 's/%//')
    log_info "Disk usage: ${DISK_USAGE}%"
    
    if [ "$DISK_USAGE" -gt 90 ]; then
        log_warn "⚠️ High disk usage: ${DISK_USAGE}%"
    fi
    
    log_info "✅ Health check completed"
    return 0
}

# Backup Vault
backup_vault() {
    log_step "Creating Vault backup..."
    
    BACKUP_DIR="/backups/vault/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Create backup metadata
    cat > "$BACKUP_DIR/metadata.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "vault_version": "$(vault version 2>/dev/null | grep -oP 'Vault v\K[0-9.]+' || echo 'unknown')",
  "backup_type": "automated",
  "hostname": "$(hostname)"
}
EOF
    
    if systemctl is-active vault >/dev/null 2>&1; then
        export VAULT_ADDR=http://localhost:8200
        
        # Backup Vault data directory
        if [ -d "/var/lib/vault" ]; then
            log_info "Backing up Vault data directory..."
            tar -czf "$BACKUP_DIR/vault-data.tar.gz" -C /var/lib vault/ 2>/dev/null || {
                log_warn "Failed to backup data directory (may be in use)"
            }
        fi
        
        # Try to create Raft snapshot if unsealed
        if [[ -f /root/.vault/root-token ]] && ! vault status 2>&1 | grep -q "Sealed.*true"; then
            export VAULT_TOKEN=$(cat /root/.vault/root-token)
            vault operator raft snapshot save "$BACKUP_DIR/vault.snap" 2>/dev/null && {
                log_info "✅ Raft snapshot created"
            } || {
                log_warn "Failed to create Raft snapshot (vault may be sealed)"
            }
            
            # Backup policies
            vault policy list -format=json > "$BACKUP_DIR/policies.json" 2>/dev/null || true
            
            # Backup auth methods
            vault auth list -format=json > "$BACKUP_DIR/auth-methods.json" 2>/dev/null || true
            
            # Backup secrets engines
            vault secrets list -format=json > "$BACKUP_DIR/secrets-engines.json" 2>/dev/null || true
        fi
        
        # Backup configuration
        tar -czf "$BACKUP_DIR/vault-config.tar.gz" /etc/vault.d/ 2>/dev/null || true
        
        # Backup systemd service
        cp /etc/systemd/system/vault.service "$BACKUP_DIR/vault.service" 2>/dev/null || true
        
        # Backup credentials (if they exist)
        if [ -d "/root/.vault" ]; then
            tar -czf "$BACKUP_DIR/vault-credentials.tar.gz" -C /root .vault/ 2>/dev/null && {
                chmod 600 "$BACKUP_DIR/vault-credentials.tar.gz"
            } || true
        fi
    else
        log_warn "Vault service not running - creating configuration backup only"
        tar -czf "$BACKUP_DIR/vault-config.tar.gz" /etc/vault.d/ 2>/dev/null || true
    fi
    
    # Set appropriate permissions
    chmod -R 600 "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    
    log_info "Backup created: $BACKUP_DIR"
    
    # Clean up old backups
    find /backups/vault -type d -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
    log_info "Old backups cleaned up (retention: $BACKUP_RETENTION_DAYS days)"
}

# Restore Vault from backup
restore_vault() {
    local BACKUP_PATH="$1"
    
    if [ ! -d "$BACKUP_PATH" ]; then
        log_error "Backup directory not found: $BACKUP_PATH"
        return 1
    fi
    
    log_step "Restoring Vault from backup: $BACKUP_PATH"
    
    # Stop Vault service
    systemctl stop vault 2>/dev/null || true
    
    # Restore configuration
    if [ -f "$BACKUP_PATH/vault-config.tar.gz" ]; then
        log_info "Restoring configuration..."
        tar -xzf "$BACKUP_PATH/vault-config.tar.gz" -C /
    fi
    
    # Restore systemd service
    if [ -f "$BACKUP_PATH/vault.service" ]; then
        cp "$BACKUP_PATH/vault.service" /etc/systemd/system/
        systemctl daemon-reload
    fi
    
    # Restore credentials
    if [ -f "$BACKUP_PATH/vault-credentials.tar.gz" ]; then
        log_info "Restoring credentials..."
        tar -xzf "$BACKUP_PATH/vault-credentials.tar.gz" -C /root/
        chmod -R 600 /root/.vault/
    fi
    
    # Start Vault
    systemctl start vault
    sleep 10
    
    log_info "✅ Restore completed"
}

# Install Vault
install_vault() {
    local VAULT_STATE=$(check_vault)
    IFS=':' read -r EXISTS STATUS VERSION <<< "$VAULT_STATE"
    
    if [[ "$EXISTS" == "exists" && "$VERSION" == "$VAULT_VERSION" ]]; then
        log_info "Vault $VAULT_VERSION already installed"
        return 0
    fi
    
    if [[ "$EXISTS" == "exists" ]]; then
        log_step "Upgrading Vault from $VERSION to $VAULT_VERSION..."
        backup_vault
        systemctl stop vault
    else
        log_step "Installing Vault $VAULT_VERSION..."
    fi
    
    # Download and install
    cd /tmp
    wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
    unzip -o "vault_${VAULT_VERSION}_linux_amd64.zip"
    mv vault /usr/local/bin/
    chmod +x /usr/local/bin/vault
    rm "vault_${VAULT_VERSION}_linux_amd64.zip"
    
    # Create user and directories
    if ! id -u vault >/dev/null 2>&1; then
        useradd --system --home /var/lib/vault --shell /bin/false vault
    fi
    mkdir -p /var/lib/vault /etc/vault.d /root/.vault
    chown -R vault:vault /var/lib/vault /etc/vault.d
    chmod 700 /root/.vault
    
    # Use configuration from source if available
    if [ -f "$CONFIG_SOURCE" ]; then
        log_info "Using configuration from: $CONFIG_SOURCE"
        cp "$CONFIG_SOURCE" /etc/vault.d/vault.hcl
    else
        log_info "Using default configuration"
        # Create default Vault configuration
        cat > /etc/vault.d/vault.hcl << 'EOF'
ui = true
disable_mlock = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}

storage "raft" {
  path    = "/var/lib/vault"
  node_id = "vault-1"
}

# API advertisement addresses
api_addr = "http://SERVER_IP:8200"
cluster_addr = "https://SERVER_IP:8201"

# Telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = false
}

log_level = "info"
EOF
    fi
    
    # Replace SERVER_IP with actual IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/SERVER_IP/${SERVER_IP}/g" /etc/vault.d/vault.hcl
    
    # Set proper permissions
    chown vault:vault /etc/vault.d/vault.hcl
    chmod 640 /etc/vault.d/vault.hcl
    
    # Create systemd service
    cat > /etc/systemd/system/vault.service << 'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
EnvironmentFile=-/etc/vault.d/vault.env
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF
    
    # Start Vault
    systemctl daemon-reload
    systemctl enable vault
    systemctl start vault
    
    # Wait for startup
    sleep 10
    
    # Initialize if needed
    export VAULT_ADDR=http://localhost:8200
    if vault status 2>&1 | grep -q "Initialized.*false"; then
        log_step "Initializing Vault..."
        
        vault operator init \
            -key-shares=5 \
            -key-threshold=3 \
            -format=json > /root/.vault/init-${ENVIRONMENT}.json
        
        # Extract keys
        UNSEAL_KEYS=$(jq -r '.unseal_keys_b64[]' /root/.vault/init-${ENVIRONMENT}.json)
        ROOT_TOKEN=$(jq -r '.root_token' /root/.vault/init-${ENVIRONMENT}.json)
        
        # Save root token separately
        echo "$ROOT_TOKEN" > /root/.vault/root-token
        chmod 600 /root/.vault/root-token
        
        # Unseal with first 3 keys
        echo "$UNSEAL_KEYS" | head -3 | while read key; do
            vault operator unseal "$key"
        done
        
        log_info "✅ Vault initialized and unsealed"
        log_info "📁 Credentials saved to /root/.vault/init-${ENVIRONMENT}.json"
    fi
    
    log_info "✅ Vault $VAULT_VERSION installed successfully"
    
    # Validate installation
    if ! health_check; then
        log_error "Installation validation failed"
        return 1
    fi
}

# Configure Vault policies and auth methods
configure_vault() {
    log_step "Configuring Vault..."
    
    export VAULT_ADDR=http://localhost:8200
    
    # Load root token if available
    if [[ -f /root/.vault/root-token ]]; then
        export VAULT_TOKEN=$(cat /root/.vault/root-token)
    elif [[ -f /opt/vault/init.json ]]; then
        export VAULT_TOKEN=$(jq -r '.root_token' /opt/vault/init.json 2>/dev/null)
    else
        log_warning "Root token not found. Vault may need initialization."
        log_info "Skipping configuration that requires authentication."
        log_info "Run 'vault operator init' or use --action init after deployment."
        # Don't fail installation, just skip auth-required configuration
        return 0
    fi
    
    # Check if Nomad is available for integration
    if curl -f -s --max-time 5 http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
        log_info "Nomad detected - configuring integration..."
        
        # Create Nomad policy
        vault policy write nomad-server - <<EOF
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/lookup" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
        
        # Create token role for Nomad
        vault write auth/token/roles/nomad-cluster \
            name=nomad-cluster \
            orphan=true \
            period=259200 \
            renewable=true \
            explicit_max_ttl=0 \
            allowed_policies=nomad-server
        
        # Create a token for Nomad
        NOMAD_TOKEN=$(vault write -field=token auth/token/create/nomad-cluster policies="nomad-server")
        echo "$NOMAD_TOKEN" > /root/.vault/nomad-token
        chmod 600 /root/.vault/nomad-token
        
        log_info "✅ Nomad integration configured"
    else
        log_info "ℹ️ Nomad not found - skipping integration"
    fi
    
    # Enable KV secrets engine
    vault secrets enable -path=kv kv-v2 2>/dev/null || true
    
    # Enable userpass auth
    vault auth enable userpass 2>/dev/null || true
    
    log_info "✅ Vault configuration complete"
}

# Validate environment
if [ -z "$ENVIRONMENT" ]; then
    log_error "Environment not specified. Use --environment production|staging"
    exit 1
fi

log_info "Starting Vault deployment script"
log_info "Environment: $ENVIRONMENT"
log_info "Action: $ACTION"
log_info "Version: $VAULT_VERSION"

# Main execution
case "$ACTION" in
    check)
        STATE=$(check_vault)
        log_info "Vault state: $STATE"
        health_check
        ;;
    install)
        install_vault
        configure_vault
        ;;
    upgrade)
        install_vault
        ;;
    configure)
        configure_vault
        ;;
    backup)
        backup_vault
        ;;
    restore)
        if [ -z "$2" ]; then
            log_error "Restore requires backup path: --action restore <backup_path>"
            exit 1
        fi
        restore_vault "$2"
        ;;
    restart)
        systemctl restart vault
        sleep 10
        health_check
        log_info "Vault restarted"
        ;;
    health)
        health_check
        ;;
    *)
        log_error "Unknown action: $ACTION"
        log_error "Valid actions: check, install, upgrade, configure, backup, restore, restart, health"
        exit 1
        ;;
esac

# Final health check for install/upgrade actions
if [[ "$ACTION" =~ ^(install|upgrade|configure)$ ]]; then
    log_step "Final health check..."
    if health_check; then
        log_info "✅ Deployment completed successfully"
    else
        log_error "❌ Health check failed after $ACTION"
        exit 1
    fi
fi

log_info "✅ Script execution completed successfully"