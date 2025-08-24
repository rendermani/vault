#!/bin/bash
# Initialize Vault and save keys securely with enhanced security

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(dirname "$SCRIPT_DIR")"
SECURITY_SCRIPTS_DIR="$VAULT_DIR/security"

# Check if security system is available
SECURE_MODE=false
if [[ -x "$SECURITY_SCRIPTS_DIR/secure-token-manager.sh" ]]; then
    SECURE_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Determine Vault address based on TLS configuration
if [[ -f "/etc/vault.d/tls/vault-cert.pem" ]]; then
    export VAULT_ADDR="https://127.0.0.1:8200"
    log_info "Using HTTPS (TLS configured)"
else
    export VAULT_ADDR="http://127.0.0.1:8200"
    log_warn "Using HTTP (TLS not configured - consider running security setup)"
fi

log_step "Initializing Vault with enhanced security..."

# Check if Vault is already initialized
if vault status 2>&1 | grep -q "Initialized.*true"; then
    log_error "Vault is already initialized"
    exit 1
fi

# Create secure directories
mkdir -p /opt/vault
chmod 700 /opt/vault

# Initialize with 5 key shares, threshold of 3
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /opt/vault/init.json

# Set secure permissions
chmod 600 /opt/vault/init.json

log_info "✅ Vault initialized successfully!"
log_info "Keys saved to: /opt/vault/init.json"
log_warn "IMPORTANT: Backup this file immediately and store the keys securely!"

# Extract root token
ROOT_TOKEN=$(jq -r '.root_token' /opt/vault/init.json)

# Store root token securely if security system is available
if [[ "$SECURE_MODE" == "true" ]]; then
    log_step "Storing root token securely..."
    "$SECURITY_SCRIPTS_DIR/secure-token-manager.sh" init 2>/dev/null || true
    "$SECURITY_SCRIPTS_DIR/secure-token-manager.sh" store root-token "$ROOT_TOKEN" "Initial root token" 2>/dev/null || {
        log_warn "Could not store token securely, storing in /root/.vault/root-token"
        mkdir -p /root/.vault
        echo "$ROOT_TOKEN" > /root/.vault/root-token
        chmod 600 /root/.vault/root-token
    }
else
    # Fallback to traditional storage
    mkdir -p /root/.vault
    echo "$ROOT_TOKEN" > /root/.vault/root-token
    chmod 600 /root/.vault/root-token
    log_info "Root token saved to: /root/.vault/root-token"
fi

# Display masked token for logging
MASKED_TOKEN=$(echo "$ROOT_TOKEN" | head -c 8)***$(echo "$ROOT_TOKEN" | tail -c 5)
log_info "Initial Root Token: $MASKED_TOKEN"

# Auto-unseal with first 3 keys
log_step "Unsealing Vault..."
for i in 0 1 2; do
  KEY=$(jq -r ".unseal_keys_b64[$i]" /opt/vault/init.json)
  vault operator unseal "$KEY" >/dev/null
  log_info "Unseal key $((i+1)) applied"
done

# Verify unsealing
if vault status | grep -q "Sealed.*false"; then
    log_info "✅ Vault unsealed and ready!"
else
    log_error "❌ Vault unsealing failed"
    exit 1
fi

# Enable audit logging if security system is available
if [[ "$SECURE_MODE" == "true" ]] && [[ -x "$SECURITY_SCRIPTS_DIR/audit-logger.sh" ]]; then
    log_step "Enabling audit logging..."
    export VAULT_TOKEN="$ROOT_TOKEN"
    "$SECURITY_SCRIPTS_DIR/audit-logger.sh" enable 2>/dev/null || {
        log_warn "Could not enable audit logging automatically"
    }
fi

# Provide next steps
echo ""
log_info "🎉 Vault initialization complete!"
echo ""
echo "Next steps:"
echo "1. Login with: vault login $ROOT_TOKEN"
echo "2. Configure policies and authentication methods"
echo "3. Set up applications to use Vault"

if [[ "$SECURE_MODE" != "true" ]]; then
    echo "4. Consider running the security initialization:"
    echo "   cd $VAULT_DIR/security && ./init-security.sh"
fi

echo ""
log_warn "CRITICAL SECURITY REMINDERS:"
echo "- Distribute and securely store the 5 unseal keys"
echo "- Store the initialization data (/opt/vault/init.json) in a secure location"
echo "- Remove the root token from this system after initial setup"
echo "- Use limited-privilege tokens for day-to-day operations"
echo "- Enable audit logging and monitoring"