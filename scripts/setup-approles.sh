#!/bin/bash
# Setup AppRoles for services

set -e

export VAULT_ADDR="http://127.0.0.1:8200"

# Check if logged in
if ! vault token lookup >/dev/null 2>&1; then
  echo "Please login to Vault first: vault login <token>"
  exit 1
fi

echo "Setting up AppRoles..."

# Enable AppRole auth method
vault auth enable approle || echo "AppRole already enabled"

# Enable KV v2 secrets engine
vault secrets enable -version=2 kv || echo "KV v2 already enabled"

# Services to configure
SERVICES=("grafana" "prometheus" "loki" "minio" "traefik" "nomad")

for SERVICE in "${SERVICES[@]}"; do
  echo "Configuring AppRole for: $SERVICE"
  
  # Create policy
  cat > /tmp/${SERVICE}-policy.hcl <<EOF
path "kv/data/${SERVICE}/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/${SERVICE}/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

  # Write policy
  vault policy write ${SERVICE}-policy /tmp/${SERVICE}-policy.hcl
  
  # Create AppRole
  vault write auth/approle/role/${SERVICE}-role \
    token_policies="${SERVICE}-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=720h \
    secret_id_num_uses=0
  
  # Get Role ID
  ROLE_ID=$(vault read -field=role_id auth/approle/role/${SERVICE}-role/role-id)
  
  # Generate Secret ID
  SECRET_ID=$(vault write -field=secret_id auth/approle/role/${SERVICE}-role/secret-id)
  
  # Save credentials
  cat > /opt/vault/${SERVICE}-approle.txt <<EOF
Service: $SERVICE
Role ID: $ROLE_ID
Secret ID: $SECRET_ID
EOF
  
  chmod 600 /opt/vault/${SERVICE}-approle.txt
  
  echo "  Role ID saved to: /opt/vault/${SERVICE}-approle.txt"
  
  # Cleanup temp file
  rm -f /tmp/${SERVICE}-policy.hcl
done

echo ""
echo "AppRole setup complete!"
echo "Credentials saved in: /opt/vault/*-approle.txt"
echo ""
echo "IMPORTANT: Distribute these credentials securely to each service"