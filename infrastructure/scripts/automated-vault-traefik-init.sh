#!/bin/bash
set -euo pipefail

# Automated Vault-Traefik Integration Script
# This script provides complete automation for Vault and Traefik integration
# No manual steps required - everything is automated

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-/opt/vault/data}"
LOG_FILE="${LOG_FILE:-/var/log/vault-traefik-init.log}"
CONFIG_DIR="/opt/traefik/config"
SECRETS_DIR="/opt/traefik/secrets"

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
trap 'error "Script failed at line $LINENO"' ERR

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local check_command=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    info "Waiting for ${service_name} to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if eval "$check_command" >/dev/null 2>&1; then
            success "${service_name} is ready!"
            return 0
        fi
        
        info "Attempt ${attempt}/${max_attempts} - ${service_name} not ready yet, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    error "${service_name} failed to become ready after ${max_attempts} attempts"
    return 1
}

# Function to check if Vault is sealed
is_vault_sealed() {
    vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || echo "true"
}

# Function to initialize Vault if needed
init_vault_if_needed() {
    info "Checking Vault initialization status..."
    
    # Check if Vault is initialized
    if vault status -format=json 2>/dev/null | jq -e '.initialized == false' >/dev/null; then
        info "Vault not initialized, initializing now..."
        
        # Initialize Vault
        local init_output
        init_output=$(vault operator init -key-shares=5 -key-threshold=3 -format=json)
        
        # Store unseal keys and root token securely
        local unseal_keys_b64
        local root_token
        unseal_keys_b64=$(echo "$init_output" | jq -r '.unseal_keys_b64[]')
        root_token=$(echo "$init_output" | jq -r '.root_token')
        
        # Create secure storage directory
        mkdir -p "${VAULT_DATA_DIR}/init"
        chmod 700 "${VAULT_DATA_DIR}/init"
        
        # Save keys and token
        echo "$init_output" > "${VAULT_DATA_DIR}/init/vault-init.json"
        echo "$root_token" > "${VAULT_DATA_DIR}/init/root-token"
        chmod 600 "${VAULT_DATA_DIR}/init/"*
        
        success "Vault initialized successfully"
        
        # Unseal Vault
        local key_count=0
        while IFS= read -r key; do
            vault operator unseal "$key" >/dev/null
            key_count=$((key_count + 1))
            if [ $key_count -eq 3 ]; then
                break
            fi
        done <<< "$unseal_keys_b64"
        
        # Set root token
        export VAULT_TOKEN="$root_token"
        
        success "Vault unsealed successfully"
    else
        info "Vault already initialized"
        
        # Check if sealed and unseal if needed
        if [ "$(is_vault_sealed)" = "true" ]; then
            info "Vault is sealed, unsealing..."
            
            if [ -f "${VAULT_DATA_DIR}/init/vault-init.json" ]; then
                local unseal_keys_b64
                unseal_keys_b64=$(jq -r '.unseal_keys_b64[]' "${VAULT_DATA_DIR}/init/vault-init.json")
                
                local key_count=0
                while IFS= read -r key; do
                    vault operator unseal "$key" >/dev/null
                    key_count=$((key_count + 1))
                    if [ $key_count -eq 3 ]; then
                        break
                    fi
                done <<< "$unseal_keys_b64"
                
                success "Vault unsealed successfully"
            else
                error "Vault is sealed but no unseal keys found"
                return 1
            fi
        fi
        
        # Set root token if available
        if [ -f "${VAULT_DATA_DIR}/init/root-token" ]; then
            export VAULT_TOKEN=$(cat "${VAULT_DATA_DIR}/init/root-token")
        fi
    fi
}

# Function to enable KV secrets engine
enable_kv_engine() {
    info "Enabling KV secrets engine..."
    
    if vault secrets list | grep -q "^secret/"; then
        info "KV secrets engine already enabled"
    else
        vault secrets enable -path=secret -version=2 kv
        success "KV secrets engine enabled"
    fi
}

# Function to create Traefik policy
create_traefik_policy() {
    info "Creating Traefik Vault policy..."
    
    cat > /tmp/traefik-policy.hcl <<EOF
# Traefik Service Policy
# Allows Traefik to access dashboard credentials and certificates

# Dashboard credentials access
path "secret/data/traefik/dashboard/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/dashboard/*" {
  capabilities = ["read", "list"]
}

# Certificate management access
path "secret/data/traefik/certificates/*" {
  capabilities = ["read", "create", "update"]
}

path "secret/metadata/traefik/certificates/*" {
  capabilities = ["read", "list"]
}

# SSL/TLS certificate storage
path "secret/data/traefik/tls/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/tls/*" {
  capabilities = ["read", "list"]
}

# Traefik configuration secrets
path "secret/data/traefik/config/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/config/*" {
  capabilities = ["read", "list"]
}

# API keys and middleware secrets
path "secret/data/traefik/auth/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/auth/*" {
  capabilities = ["read", "list"]
}

# Health check endpoints
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token renewal for long-running services
path "sys/health" {
  capabilities = ["read"]
}
EOF

    vault policy write traefik-policy /tmp/traefik-policy.hcl
    rm /tmp/traefik-policy.hcl
    success "Traefik policy created successfully"
}

# Function to generate and store Traefik credentials
setup_traefik_credentials() {
    info "Setting up Traefik dashboard credentials..."
    
    # Generate secure credentials
    local dashboard_user="admin"
    local dashboard_pass
    dashboard_pass=$(openssl rand -base64 32)
    
    # Generate bcrypt hash for Traefik
    local dashboard_hash
    dashboard_hash=$(htpasswd -nbB "$dashboard_user" "$dashboard_pass" 2>/dev/null | sed -e 's/\$/\$\$/g')
    
    # Store in Vault
    vault kv put secret/traefik/dashboard \
        username="$dashboard_user" \
        password="$dashboard_pass" \
        auth="$dashboard_hash" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    success "Dashboard credentials stored in Vault"
    info "Dashboard Username: $dashboard_user"
    info "Dashboard Password: $dashboard_pass"
}

# Function to create Traefik service token
create_traefik_token() {
    info "Creating Vault token for Traefik service..."
    
    local traefik_token
    traefik_token=$(vault token create \
        -policy=traefik-policy \
        -period=768h \
        -renewable=true \
        -display-name="traefik-service" \
        -format=json | jq -r '.auth.client_token')
    
    # Store token in Vault for reference
    vault kv put secret/traefik/vault \
        token="$traefik_token" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        policy="traefik-policy"
    
    # Also store in file for initial setup
    mkdir -p "$SECRETS_DIR"
    echo "$traefik_token" > "$SECRETS_DIR/vault-token"
    chmod 600 "$SECRETS_DIR/vault-token"
    
    success "Traefik service token created and stored"
    return 0
}

# Function to setup certificate storage
setup_certificate_storage() {
    info "Setting up certificate storage in Vault..."
    
    # Create certificate storage configuration
    vault kv put secret/traefik/certificates \
        storage_type="vault" \
        acme_email="admin@cloudya.net" \
        domain="*.cloudya.net" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Create TLS configuration
    vault kv put secret/traefik/tls \
        cert_resolver="letsencrypt" \
        key_type="EC256" \
        ca_server="https://acme-v02.api.letsencrypt.org/directory" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    success "Certificate storage configured in Vault"
}

# Function to create Vault agent configuration
create_vault_agent_config() {
    info "Creating Vault agent configuration for Traefik..."
    
    mkdir -p "$CONFIG_DIR/vault"
    
    cat > "$CONFIG_DIR/vault/agent.hcl" <<EOF
pid_file = "/var/run/vault-agent.pid"
vault {
  address = "$VAULT_ADDR"
}

auto_auth {
  method "token_file" {
    config = {
      token_file_path = "$SECRETS_DIR/vault-token"
    }
  }

  sink "file" {
    config = {
      path = "$SECRETS_DIR/vault-agent-token"
      mode = 0600
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

template {
  source      = "$CONFIG_DIR/vault/dashboard-auth.tpl"
  destination = "$CONFIG_DIR/dashboard-auth"
  perms       = 0600
  command     = "/usr/bin/systemctl reload traefik || true"
}

template {
  source      = "$CONFIG_DIR/vault/traefik-env.tpl"
  destination = "$CONFIG_DIR/traefik.env"
  perms       = 0600
  command     = "/usr/bin/systemctl restart traefik || true"
}
EOF

    # Create template files
    cat > "$CONFIG_DIR/vault/dashboard-auth.tpl" <<'EOF'
{{- with secret "secret/data/traefik/dashboard" }}
{{ .Data.data.auth }}
{{- end }}
EOF

    cat > "$CONFIG_DIR/vault/traefik-env.tpl" <<'EOF'
{{- with secret "secret/data/traefik/dashboard" }}
DASHBOARD_USER={{ .Data.data.username }}
DASHBOARD_PASS={{ .Data.data.password }}
DASHBOARD_AUTH={{ .Data.data.auth }}
{{- end }}
{{- with secret "secret/data/traefik/vault" }}
VAULT_TOKEN={{ .Data.data.token }}
{{- end }}
EOF

    chmod 640 "$CONFIG_DIR/vault/"*.hcl
    chmod 640 "$CONFIG_DIR/vault/"*.tpl
    
    success "Vault agent configuration created"
}

# Function to create systemd service for Vault agent
create_vault_agent_service() {
    info "Creating Vault agent systemd service..."
    
    cat > /etc/systemd/system/vault-agent.service <<EOF
[Unit]
Description=Vault Agent for Traefik
Documentation=https://www.vaultproject.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONFIG_DIR/vault/agent.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault agent -config=$CONFIG_DIR/vault/agent.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vault-agent
    
    success "Vault agent service created and enabled"
}

# Function to setup health monitoring
setup_health_monitoring() {
    info "Setting up health monitoring for Vault-Traefik integration..."
    
    cat > /usr/local/bin/vault-traefik-health-check <<'EOF'
#!/bin/bash

# Health check script for Vault-Traefik integration
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
LOG_FILE="/var/log/vault-traefik-health.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check Vault status
if ! vault status >/dev/null 2>&1; then
    log "ERROR: Vault is not accessible"
    exit 1
fi

# Check if Vault is sealed
if vault status -format=json | jq -e '.sealed == true' >/dev/null; then
    log "ERROR: Vault is sealed"
    exit 1
fi

# Check Vault agent
if ! systemctl is-active vault-agent >/dev/null 2>&1; then
    log "ERROR: Vault agent is not running"
    exit 1
fi

# Check if Traefik credentials are accessible
if [ -f "$SECRETS_DIR/vault-token" ]; then
    export VAULT_TOKEN=$(cat "$SECRETS_DIR/vault-token")
    if ! vault kv get secret/traefik/dashboard >/dev/null 2>&1; then
        log "ERROR: Cannot access Traefik credentials in Vault"
        exit 1
    fi
else
    log "ERROR: Vault token file not found"
    exit 1
fi

log "SUCCESS: All health checks passed"
exit 0
EOF

    chmod +x /usr/local/bin/vault-traefik-health-check
    
    # Create systemd timer for health checks
    cat > /etc/systemd/system/vault-traefik-health.service <<EOF
[Unit]
Description=Vault-Traefik Integration Health Check
After=vault.service vault-agent.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vault-traefik-health-check
User=vault
Group=vault
EOF

    cat > /etc/systemd/system/vault-traefik-health.timer <<EOF
[Unit]
Description=Run Vault-Traefik Health Check every 5 minutes
Requires=vault-traefik-health.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable vault-traefik-health.timer
    systemctl start vault-traefik-health.timer
    
    success "Health monitoring configured and started"
}

# Function to create credential rotation script
setup_credential_rotation() {
    info "Setting up automated credential rotation..."
    
    cat > /usr/local/bin/rotate-traefik-credentials <<'EOF'
#!/bin/bash
set -euo pipefail

# Traefik credential rotation script
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
LOG_FILE="/var/log/traefik-credential-rotation.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Set Vault token
if [ -f "/opt/traefik/secrets/vault-token" ]; then
    export VAULT_TOKEN=$(cat "/opt/traefik/secrets/vault-token")
else
    log "ERROR: Vault token not found"
    exit 1
fi

log "Starting credential rotation..."

# Generate new dashboard password
new_password=$(openssl rand -base64 32)
new_hash=$(htpasswd -nbB "admin" "$new_password" 2>/dev/null | sed -e 's/\$/\$\$/g')

# Update credentials in Vault
vault kv put secret/traefik/dashboard \
    username="admin" \
    password="$new_password" \
    auth="$new_hash" \
    rotated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    rotation_count="$(vault kv get -field=rotation_count secret/traefik/dashboard 2>/dev/null | awk '{print $1+1}' || echo '1')"

log "Dashboard credentials rotated successfully"

# Renew Traefik service token
vault token renew >/dev/null 2>&1 || {
    log "WARNING: Failed to renew service token"
}

# Signal Vault agent to refresh templates
if systemctl is-active vault-agent >/dev/null 2>&1; then
    systemctl reload vault-agent
    log "Vault agent reloaded"
fi

# Signal Traefik to reload configuration
if systemctl is-active traefik >/dev/null 2>&1; then
    systemctl reload traefik
    log "Traefik configuration reloaded"
fi

log "Credential rotation completed successfully"
EOF

    chmod +x /usr/local/bin/rotate-traefik-credentials
    
    # Create systemd timer for credential rotation (weekly)
    cat > /etc/systemd/system/traefik-credential-rotation.service <<EOF
[Unit]
Description=Rotate Traefik Credentials
After=vault.service vault-agent.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rotate-traefik-credentials
User=vault
Group=vault
EOF

    cat > /etc/systemd/system/traefik-credential-rotation.timer <<EOF
[Unit]
Description=Rotate Traefik credentials weekly
Requires=traefik-credential-rotation.service

[Timer]
OnCalendar=Sun 02:00
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable traefik-credential-rotation.timer
    systemctl start traefik-credential-rotation.timer
    
    success "Credential rotation configured and scheduled"
}

# Function to test the integration
test_integration() {
    info "Testing Vault-Traefik integration..."
    
    # Test 1: Vault accessibility
    if ! vault status >/dev/null 2>&1; then
        error "Test failed: Vault is not accessible"
        return 1
    fi
    success "✓ Vault is accessible"
    
    # Test 2: Credentials retrieval
    local test_token
    if [ -f "$SECRETS_DIR/vault-token" ]; then
        test_token=$(cat "$SECRETS_DIR/vault-token")
        if VAULT_TOKEN="$test_token" vault kv get secret/traefik/dashboard >/dev/null 2>&1; then
            success "✓ Traefik credentials accessible"
        else
            error "Test failed: Cannot access Traefik credentials"
            return 1
        fi
    else
        error "Test failed: Vault token file not found"
        return 1
    fi
    
    # Test 3: Vault agent status
    if systemctl is-active vault-agent >/dev/null 2>&1; then
        success "✓ Vault agent is running"
    else
        warn "Vault agent is not running (will be started with Traefik)"
    fi
    
    # Test 4: Health check script
    if /usr/local/bin/vault-traefik-health-check; then
        success "✓ Health check passed"
    else
        error "Test failed: Health check failed"
        return 1
    fi
    
    success "All integration tests passed!"
    return 0
}

# Main execution function
main() {
    info "Starting automated Vault-Traefik integration setup..."
    info "Log file: $LOG_FILE"
    
    # Create necessary directories
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$CONFIG_DIR" "$SECRETS_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$SECRETS_DIR"
    
    # Ensure vault user exists
    if ! getent passwd vault >/dev/null; then
        useradd --system --home /etc/vault.d --shell /bin/false vault
        info "Created vault system user"
    fi
    
    # Set ownership
    chown -R vault:vault "$CONFIG_DIR" "$SECRETS_DIR"
    
    # Wait for Vault to be ready
    wait_for_service "Vault" "vault status"
    
    # Initialize Vault if needed
    init_vault_if_needed
    
    # Enable KV engine
    enable_kv_engine
    
    # Create Traefik policy
    create_traefik_policy
    
    # Setup Traefik credentials
    setup_traefik_credentials
    
    # Create Traefik service token
    create_traefik_token
    
    # Setup certificate storage
    setup_certificate_storage
    
    # Create Vault agent configuration
    create_vault_agent_config
    
    # Create Vault agent systemd service
    create_vault_agent_service
    
    # Setup health monitoring
    setup_health_monitoring
    
    # Setup credential rotation
    setup_credential_rotation
    
    # Test the integration
    test_integration
    
    success "🎉 Vault-Traefik integration setup completed successfully!"
    
    info "Summary of what was configured:"
    info "  • Vault initialized and unsealed (if needed)"
    info "  • KV secrets engine enabled"
    info "  • Traefik policy created"
    info "  • Dashboard credentials generated and stored"
    info "  • Service token created"
    info "  • Certificate storage configured"
    info "  • Vault agent configured and enabled"
    info "  • Health monitoring setup"
    info "  • Automatic credential rotation scheduled"
    
    info "Next steps:"
    info "  1. Start Vault agent: systemctl start vault-agent"
    info "  2. Deploy Traefik with Vault integration"
    info "  3. Monitor logs: tail -f $LOG_FILE"
    info "  4. Check health: /usr/local/bin/vault-traefik-health-check"
    
    info "Credentials are stored in Vault at:"
    info "  • Dashboard: secret/traefik/dashboard"
    info "  • Certificates: secret/traefik/certificates"
    info "  • Service token: secret/traefik/vault"
    
    return 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi