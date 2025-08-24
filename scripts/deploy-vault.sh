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
ENVIRONMENT=""
ACTION="install"
VAULT_VERSION="1.17.3"

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
        *)
            echo "Unknown option: $1"
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

# Backup Vault
backup_vault() {
    log_step "Creating Vault backup..."
    
    BACKUP_DIR="/backups/vault/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if systemctl is-active vault >/dev/null 2>&1; then
        export VAULT_ADDR=http://localhost:8200
        
        # Try to create Raft snapshot
        if [[ -f /root/.vault/root-token ]]; then
            export VAULT_TOKEN=$(cat /root/.vault/root-token)
            vault operator raft snapshot save "$BACKUP_DIR/vault.snap" 2>/dev/null || true
        fi
        
        # Backup configuration
        tar -czf "$BACKUP_DIR/vault-config.tar.gz" /etc/vault.d/ 2>/dev/null || true
        
        # Backup policies
        vault policy list -format=json > "$BACKUP_DIR/policies.json" 2>/dev/null || true
    fi
    
    log_info "Backup created: $BACKUP_DIR"
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
    
    # Create Vault configuration
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
  prometheus_retention_time = "0s"
  disable_hostname = true
}
EOF
    
    # Replace SERVER_IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/SERVER_IP/${SERVER_IP}/g" /etc/vault.d/vault.hcl
    
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
    
    log_info "Vault $VAULT_VERSION installed successfully"
}

# Configure Vault policies and auth methods
configure_vault() {
    log_step "Configuring Vault..."
    
    export VAULT_ADDR=http://localhost:8200
    
    # Load root token if available
    if [[ -f /root/.vault/root-token ]]; then
        export VAULT_TOKEN=$(cat /root/.vault/root-token)
    else
        log_error "Root token not found. Please provide token."
        return 1
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

# Main execution
case "$ACTION" in
    check)
        STATE=$(check_vault)
        log_info "Vault state: $STATE"
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
    restart)
        systemctl restart vault
        log_info "Vault restarted"
        ;;
    *)
        log_error "Unknown action: $ACTION"
        exit 1
        ;;
esac

# Final health check
log_step "Health check..."
if curl -f -s http://localhost:8200/v1/sys/health | jq '.'; then
    log_info "✅ Vault is healthy"
else
    log_error "❌ Vault health check failed"
    exit 1
fi