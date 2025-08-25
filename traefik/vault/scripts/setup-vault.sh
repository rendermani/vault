#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(dirname "$SCRIPT_DIR")"
POLICIES_DIR="$VAULT_DIR/policies"

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v vault &> /dev/null; then
        error "Vault CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq is not installed or not in PATH"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Wait for Vault to be available
wait_for_vault() {
    log "Waiting for Vault to be available at $VAULT_ADDR..."
    
    timeout=300
    while ! vault status >/dev/null 2>&1; do
        if [ $timeout -le 0 ]; then
            error "Timeout waiting for Vault to be available"
            exit 1
        fi
        echo -n "."
        sleep 5
        timeout=$((timeout-5))
    done
    
    echo ""
    success "Vault is available"
}

# Initialize Vault if not already initialized
initialize_vault() {
    log "Checking Vault initialization status..."
    
    if vault status | grep -q "Initialized.*true"; then
        success "Vault is already initialized"
        return 0
    fi
    
    warn "Vault is not initialized. Initializing now..."
    
    # Create secure directory for keys
    KEYS_DIR="/vault/data/keys"
    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"
    
    # Initialize Vault
    vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > "$KEYS_DIR/vault-init.json"
    
    chmod 600 "$KEYS_DIR/vault-init.json"
    
    success "Vault initialized successfully!"
    warn "IMPORTANT: Unseal keys and root token are stored in $KEYS_DIR/vault-init.json"
    warn "Please secure these keys immediately and distribute them to key holders!"
    
    return 1  # Return 1 to indicate we just initialized
}

# Unseal Vault
unseal_vault() {
    log "Checking Vault seal status..."
    
    if vault status | grep -q "Sealed.*false"; then
        success "Vault is already unsealed"
        return 0
    fi
    
    warn "Vault is sealed. Attempting to unseal..."
    
    KEYS_FILE="/vault/data/keys/vault-init.json"
    if [ ! -f "$KEYS_FILE" ]; then
        error "Cannot find initialization keys at $KEYS_FILE"
        error "Please unseal Vault manually using: vault operator unseal <key>"
        exit 1
    fi
    
    # Auto-unseal using first 3 keys (development only)
    warn "Auto-unsealing Vault (development only - do not use in production)"
    
    for i in {0..2}; do
        UNSEAL_KEY=$(jq -r ".unseal_keys_b64[$i]" "$KEYS_FILE")
        vault operator unseal "$UNSEAL_KEY" >/dev/null
        log "Applied unseal key $((i+1))/3"
    done
    
    success "Vault unsealed successfully"
}

# Login with root token
login_vault() {
    log "Logging in to Vault..."
    
    KEYS_FILE="/vault/data/keys/vault-init.json"
    if [ ! -f "$KEYS_FILE" ]; then
        error "Cannot find initialization keys at $KEYS_FILE"
        error "Please set VAULT_TOKEN environment variable with a valid token"
        exit 1
    fi
    
    ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
    export VAULT_TOKEN="$ROOT_TOKEN"
    
    # Verify login
    if ! vault auth -method=token "$ROOT_TOKEN" >/dev/null 2>&1; then
        error "Failed to authenticate with root token"
        exit 1
    fi
    
    success "Successfully authenticated with Vault"
}

# Enable secret engines
enable_secret_engines() {
    log "Enabling secret engines..."
    
    # Key-Value secrets engine
    if ! vault secrets list | grep -q "secret/"; then
        vault secrets enable -path=secret kv-v2
        success "Enabled KV v2 secrets engine at secret/"
    else
        log "KV v2 secrets engine already enabled at secret/"
    fi
    
    # PKI secrets engine for certificates
    if ! vault secrets list | grep -q "pki/"; then
        vault secrets enable -path=pki pki
        vault secrets tune -max-lease-ttl=8760h pki  # 1 year
        success "Enabled PKI secrets engine at pki/"
    else
        log "PKI secrets engine already enabled at pki/"
    fi
    
    # Transit secrets engine for encryption
    if ! vault secrets list | grep -q "transit/"; then
        vault secrets enable -path=transit transit
        success "Enabled Transit secrets engine at transit/"
    else
        log "Transit secrets engine already enabled at transit/"
    fi
    
    # Database secrets engine
    if ! vault secrets list | grep -q "database/"; then
        vault secrets enable -path=database database
        success "Enabled Database secrets engine at database/"
    else
        log "Database secrets engine already enabled at database/"
    fi
}

# Configure PKI
configure_pki() {
    log "Configuring PKI..."
    
    # Generate root CA
    vault write pki/root/generate/internal \
        common_name="Cloudya Internal CA" \
        issuer_name="root-2024" \
        ttl=8760h
    
    # Configure CA and CRL URLs
    vault write pki/config/urls \
        issuing_certificates="https://vault.cloudya.net/v1/pki/ca" \
        crl_distribution_points="https://vault.cloudya.net/v1/pki/crl"
    
    # Create a role for server certificates
    vault write pki/roles/server-cert \
        issuer_ref="root-2024" \
        allowed_domains="cloudya.net,localhost" \
        allow_subdomains=true \
        allow_localhost=true \
        allow_ip_sans=true \
        max_ttl=8760h \
        ttl=720h
        
    # Create a role specifically for Traefik
    vault write pki/roles/traefik-cert \
        issuer_ref="root-2024" \
        allowed_domains="cloudya.net" \
        allow_subdomains=true \
        allow_wildcard_certificates=true \
        max_ttl=8760h \
        ttl=2160h  # 90 days
    
    success "PKI configuration completed"
}

# Configure Transit encryption
configure_transit() {
    log "Configuring Transit encryption..."
    
    # Create encryption key for application data
    vault write -f transit/keys/app-key
    
    success "Transit encryption configured"
}

# Create policies
create_policies() {
    log "Creating Vault policies..."
    
    for policy_file in "$POLICIES_DIR"/*.hcl; do
        if [ -f "$policy_file" ]; then
            policy_name=$(basename "$policy_file" .hcl)
            vault policy write "$policy_name" "$policy_file"
            success "Created policy: $policy_name"
        fi
    done
}

# Enable authentication methods
enable_auth_methods() {
    log "Enabling authentication methods..."
    
    # AppRole for applications and CI/CD
    if ! vault auth list | grep -q "approle/"; then
        vault auth enable approle
        success "Enabled AppRole auth method"
    else
        log "AppRole auth method already enabled"
    fi
    
    # GitHub auth for developers (optional)
    # Uncomment if you want GitHub authentication
    # if ! vault auth list | grep -q "github/"; then
    #     vault auth enable github
    #     vault write auth/github/config organization=your-org
    #     success "Enabled GitHub auth method"
    # else
    #     log "GitHub auth method already enabled"
    # fi
}

# Create AppRole for CI/CD
create_cicd_approle() {
    log "Creating CI/CD AppRole..."
    
    # Create AppRole for CI/CD
    vault write auth/approle/role/cicd \
        token_policies="cicd-policy" \
        token_ttl=1h \
        token_max_ttl=4h \
        secret_id_ttl=10m
    
    # Get role ID
    ROLE_ID=$(vault read -field=role_id auth/approle/role/cicd/role-id)
    
    # Generate secret ID
    SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/cicd/secret-id)
    
    # Store credentials securely
    CREDENTIALS_DIR="/vault/data/credentials"
    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"
    
    cat > "$CREDENTIALS_DIR/cicd-approle.json" <<EOF
{
    "role_id": "$ROLE_ID",
    "secret_id": "$SECRET_ID",
    "auth_path": "auth/approle/login"
}
EOF
    
    chmod 600 "$CREDENTIALS_DIR/cicd-approle.json"
    
    success "CI/CD AppRole created"
    warn "Role ID and Secret ID stored in $CREDENTIALS_DIR/cicd-approle.json"
    warn "Secret ID will expire in 10 minutes - update CI/CD configuration immediately"
}

# Create AppRole for Traefik
create_traefik_approle() {
    log "Creating Traefik AppRole..."
    
    # Create AppRole for Traefik
    vault write auth/approle/role/traefik \
        token_policies="traefik-policy" \
        token_ttl=24h \
        token_max_ttl=72h \
        secret_id_ttl=0  # Never expires
    
    # Get role ID
    ROLE_ID=$(vault read -field=role_id auth/approle/role/traefik/role-id)
    
    # Generate secret ID
    SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/traefik/secret-id)
    
    # Store credentials securely
    CREDENTIALS_DIR="/vault/data/credentials"
    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"
    
    cat > "$CREDENTIALS_DIR/traefik-approle.json" <<EOF
{
    "role_id": "$ROLE_ID",
    "secret_id": "$SECRET_ID",
    "auth_path": "auth/approle/login"
}
EOF
    
    chmod 600 "$CREDENTIALS_DIR/traefik-approle.json"
    
    success "Traefik AppRole created"
}

# Store initial secrets
store_initial_secrets() {
    log "Storing initial secrets..."
    
    # Traefik dashboard credentials
    DASHBOARD_PASSWORD=$(openssl rand -base64 32)
    vault kv put secret/traefik/dashboard \
        username="admin" \
        password="$DASHBOARD_PASSWORD"
    
    # Store password in credentials file for reference
    CREDENTIALS_DIR="/vault/data/credentials"
    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"
    
    cat > "$CREDENTIALS_DIR/traefik-dashboard.txt" <<EOF
Traefik Dashboard Credentials:
Username: admin
Password: $DASHBOARD_PASSWORD
EOF
    
    chmod 600 "$CREDENTIALS_DIR/traefik-dashboard.txt"
    
    # CI/CD secrets
    vault kv put secret/cicd/deploy \
        ssh_key="replace-with-actual-ssh-key" \
        docker_password="replace-with-actual-password"
    
    success "Initial secrets stored"
    warn "Traefik dashboard password stored in $CREDENTIALS_DIR/traefik-dashboard.txt"
}

# Create backup script
create_backup_script() {
    log "Creating backup script..."
    
    cat > "$SCRIPT_DIR/backup-vault.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# Vault backup script
BACKUP_DIR="/vault/backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="$BACKUP_DIR/vault-backup-$DATE.json"

mkdir -p "$BACKUP_DIR"

# Create backup
vault operator raft snapshot save "$BACKUP_FILE.snap" 2>/dev/null || {
    echo "Raft snapshot not available, creating manual backup..."
    # For file backend, we backup the entire data directory
    tar -czf "$BACKUP_FILE.tar.gz" -C /vault/data .
}

echo "Backup created: $BACKUP_FILE"

# Keep only last 7 backups
find "$BACKUP_DIR" -name "vault-backup-*.json*" -mtime +7 -delete 2>/dev/null || true
EOF
    
    chmod +x "$SCRIPT_DIR/backup-vault.sh"
    
    success "Backup script created at $SCRIPT_DIR/backup-vault.sh"
}

# Display summary
display_summary() {
    echo ""
    success "=== Vault Setup Complete ==="
    echo ""
    echo "Vault Address: $VAULT_ADDR"
    echo "UI Available: https://vault.cloudya.net (via Traefik)"
    echo ""
    echo "Important files:"
    echo "  - Unseal keys: /vault/data/keys/vault-init.json"
    echo "  - CI/CD AppRole: /vault/data/credentials/cicd-approle.json"
    echo "  - Traefik AppRole: /vault/data/credentials/traefik-approle.json" 
    echo "  - Dashboard creds: /vault/data/credentials/traefik-dashboard.txt"
    echo ""
    echo "Policies created:"
    echo "  - admin-policy (full access)"
    echo "  - cicd-policy (CI/CD access)"
    echo "  - traefik-policy (Traefik access)"
    echo ""
    echo "Secret engines enabled:"
    echo "  - secret/ (KV v2)"
    echo "  - pki/ (PKI)"
    echo "  - transit/ (Encryption)"
    echo "  - database/ (Dynamic secrets)"
    echo ""
    warn "SECURITY REMINDERS:"
    warn "1. Secure the unseal keys immediately"
    warn "2. Distribute keys to multiple key holders"
    warn "3. Update CI/CD with new AppRole credentials"
    warn "4. Configure regular backups"
    warn "5. Enable audit logging in production"
}

# Main execution
main() {
    log "Starting Vault setup..."
    
    check_prerequisites
    wait_for_vault
    
    # Initialize and unseal
    if initialize_vault; then
        # Already initialized, just unseal
        unseal_vault
        login_vault
    else
        # Just initialized, unseal and login
        unseal_vault
        login_vault
        
        # First-time setup
        enable_secret_engines
        configure_pki
        configure_transit
        create_policies
        enable_auth_methods
        create_cicd_approle
        create_traefik_approle
        store_initial_secrets
    fi
    
    create_backup_script
    display_summary
    
    success "Vault setup completed successfully!"
}

# Run main function
main "$@"