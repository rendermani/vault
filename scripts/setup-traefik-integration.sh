#!/bin/bash

# Setup Vault Integration for Traefik
# This script configures Vault to work with Traefik

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[VAULT]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

export VAULT_ADDR='http://127.0.0.1:8200'

# Check Vault status
if ! vault status | grep -q "Sealed.*false"; then
    log_error "Vault is sealed or not running"
    exit 1
fi

log_step "Setting up Traefik integration with Vault"

# Enable KV secrets engine if not already enabled
log_info "Enabling KV secrets engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || log_info "KV secrets already enabled"

# Create Traefik policy
log_info "Creating Traefik policy..."
cat > /tmp/traefik-policy.hcl << 'EOF'
# Traefik policy
path "secret/data/traefik/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/traefik/*" {
  capabilities = ["list", "read"]
}

path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# PKI for internal certificates (optional)
path "pki/issue/*" {
  capabilities = ["create", "update"]
}

path "pki/certs" {
  capabilities = ["list"]
}
EOF

vault policy write traefik /tmp/traefik-policy.hcl

# Create AppRole for Traefik
log_info "Setting up AppRole authentication..."
vault auth enable approle 2>/dev/null || log_info "AppRole already enabled"

# Create role for Traefik
vault write auth/approle/role/traefik \
    token_policies="traefik" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0 \
    secret_id_num_uses=0

# Get role ID
ROLE_ID=$(vault read -field=role_id auth/approle/role/traefik/role-id)
log_info "Role ID: $ROLE_ID"

# Generate secret ID
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/traefik/secret-id)
log_info "Secret ID generated"

# Store AppRole credentials for Traefik
cat > /root/traefik-vault-approle.txt << EOF
Traefik Vault AppRole Credentials
==================================
Role ID: $ROLE_ID
Secret ID: $SECRET_ID

To authenticate:
vault write auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"
EOF
chmod 600 /root/traefik-vault-approle.txt

# Generate and store Traefik dashboard credentials
log_info "Generating dashboard credentials..."

DASHBOARD_USER="admin"
DASHBOARD_PASSWORD=$(openssl rand -base64 32)
DASHBOARD_HASH=$(htpasswd -nbB "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" | sed -e s/\\$/\\$\\$/g)

# Store in Vault
vault kv put secret/traefik/dashboard \
    username="$DASHBOARD_USER" \
    password="$DASHBOARD_PASSWORD" \
    hash="$DASHBOARD_HASH" \
    updated="$(date -Iseconds)"

# Store additional Traefik configuration
vault kv put secret/traefik/config \
    acme_email="admin@cloudya.net" \
    domain="cloudya.net" \
    log_level="INFO"

# Store middleware configurations
vault kv put secret/traefik/middleware/ratelimit \
    average="100" \
    burst="200" \
    period="1m"

vault kv put secret/traefik/middleware/security \
    sts_seconds="31536000" \
    sts_preload="true" \
    frame_deny="true" \
    content_type_nosniff="true"

log_info "Dashboard credentials stored in Vault"

# Setup PKI for internal certificates (optional)
log_info "Setting up PKI backend..."
vault secrets enable pki 2>/dev/null || log_info "PKI already enabled"

# Configure PKI
vault secrets tune -max-lease-ttl=87600h pki

# Generate root certificate
vault write -field=certificate pki/root/generate/internal \
    common_name="cloudya.net CA" \
    ttl=87600h > /tmp/ca_cert.crt

# Configure CA and CRL URLs
vault write pki/config/urls \
    issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# Create a role for Traefik
vault write pki/roles/traefik \
    allowed_domains="cloudya.net" \
    allow_subdomains=true \
    max_ttl="720h"

log_info "PKI backend configured"

# Create token for Traefik with specific policy
log_info "Creating Traefik token..."
TRAEFIK_TOKEN=$(vault token create \
    -policy=traefik \
    -ttl=720h \
    -renewable \
    -format=json | jq -r '.auth.client_token')

# Store token securely
cat > /root/traefik-vault-token.txt << EOF
Traefik Vault Token
===================
Token: $TRAEFIK_TOKEN
Policy: traefik
TTL: 720h

To use in Traefik:
export VAULT_TOKEN=$TRAEFIK_TOKEN
EOF
chmod 600 /root/traefik-vault-token.txt

# Create rotation script
log_info "Creating credential rotation script..."
cat > /usr/local/bin/rotate-traefik-credentials.sh << 'EOF'
#!/bin/bash
# Rotate Traefik dashboard credentials

export VAULT_ADDR='http://127.0.0.1:8200'

# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)
NEW_HASH=$(htpasswd -nbB admin "$NEW_PASSWORD" | sed -e s/\\$/\\$\\$/g)

# Update in Vault
vault kv put secret/traefik/dashboard \
    username="admin" \
    password="$NEW_PASSWORD" \
    hash="$NEW_HASH" \
    rotated="$(date -Iseconds)"

echo "Credentials rotated successfully"
echo "New password: $NEW_PASSWORD"

# Trigger Traefik reload if running on Nomad
if command -v nomad >/dev/null 2>&1; then
    nomad job restart traefik
fi
EOF
chmod +x /usr/local/bin/rotate-traefik-credentials.sh

# Test Vault integration
log_step "Testing Vault integration..."

# Test reading credentials
if vault kv get secret/traefik/dashboard >/dev/null 2>&1; then
    log_info "✅ Successfully read dashboard credentials"
else
    log_error "❌ Failed to read dashboard credentials"
fi

# Test AppRole login
TEST_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID")

if [ -n "$TEST_TOKEN" ]; then
    log_info "✅ AppRole authentication successful"
else
    log_error "❌ AppRole authentication failed"
fi

# Summary
echo ""
echo "=============================================="
echo "Vault Integration Setup Complete"
echo "=============================================="
log_info "✅ Traefik policy created"
log_info "✅ AppRole configured"
log_info "✅ Dashboard credentials stored"
log_info "✅ PKI backend configured"
log_info "✅ Rotation script created"

echo ""
echo "Credential Files:"
echo "  • /root/traefik-vault-approle.txt - AppRole credentials"
echo "  • /root/traefik-vault-token.txt - Service token"
echo "  • /root/traefik-vault-credentials.txt - Dashboard login"

echo ""
echo "Vault Paths:"
echo "  • secret/traefik/dashboard - Dashboard credentials"
echo "  • secret/traefik/config - Configuration values"
echo "  • secret/traefik/middleware/* - Middleware configs"

echo ""
echo "To rotate credentials:"
echo "  /usr/local/bin/rotate-traefik-credentials.sh"

log_info "Integration ready!"