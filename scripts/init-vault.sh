#!/bin/bash
# Initialize Vault and save keys securely

set -e

export VAULT_ADDR="http://127.0.0.1:8200"

echo "Initializing Vault..."

# Initialize with 5 key shares, threshold of 3
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /opt/vault/init.json

# Set secure permissions
chmod 600 /opt/vault/init.json

echo "Vault initialized successfully!"
echo "Keys saved to: /opt/vault/init.json"
echo ""
echo "IMPORTANT: Backup this file immediately and store the keys securely!"
echo ""

# Extract and display root token (for initial setup only)
ROOT_TOKEN=$(jq -r '.root_token' /opt/vault/init.json)
echo "Initial Root Token: $ROOT_TOKEN"
echo ""

# Auto-unseal with first 3 keys
echo "Unsealing Vault..."
for i in 0 1 2; do
  KEY=$(jq -r ".unseal_keys_b64[$i]" /opt/vault/init.json)
  vault operator unseal "$KEY"
done

echo ""
echo "Vault unsealed and ready!"
echo "Login with: vault login $ROOT_TOKEN"