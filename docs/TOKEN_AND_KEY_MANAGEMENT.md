# 🔐 Token and Key Management Guide

## 📍 Critical Storage Locations

### Root Token Location
The Vault root token is the master administrative token that provides complete access to Vault.

**Primary Storage:**
```bash
# Root token is stored here after initialization
/root/.vault/root-token

# To retrieve:
sudo cat /root/.vault/root-token
```

**Secure Storage (if security system is enabled):**
```bash
# Encrypted storage location
/etc/vault.d/secure/tokens/root-token.enc

# To retrieve:
sudo /vault/security/secure-token-manager.sh retrieve root-token
```

### Unseal Keys Location
Vault requires 3 out of 5 unseal keys to unseal the Vault after startup.

**Primary Storage:**
```bash
# All initialization data including unseal keys
/opt/vault/init.json

# To view unseal keys:
sudo jq -r '.unseal_keys_b64[]' /opt/vault/init.json

# To get specific key (0-4):
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json
```

### Initialization Data Structure
The `/opt/vault/init.json` contains:
```json
{
  "unseal_keys_b64": [
    "key1-base64-encoded",
    "key2-base64-encoded", 
    "key3-base64-encoded",
    "key4-base64-encoded",
    "key5-base64-encoded"
  ],
  "unseal_keys_hex": ["hex-encoded-keys"],
  "unseal_shares": 5,
  "unseal_threshold": 3,
  "recovery_keys_b64": null,
  "recovery_keys_hex": null,
  "recovery_keys_shares": 0,
  "recovery_keys_threshold": 0,
  "root_token": "hvs.XXXXXXXXXXXXXXXXX"
}
```

## 🗂️ Complete File Inventory

### Essential Files and Their Locations

| File/Directory | Location | Purpose | Access Method |
|----------------|----------|---------|---------------|
| **Root Token** | `/root/.vault/root-token` | Master admin token | `sudo cat /root/.vault/root-token` |
| **Init Data** | `/opt/vault/init.json` | All keys and tokens | `sudo cat /opt/vault/init.json` |
| **Secure Tokens** | `/etc/vault.d/secure/tokens/` | Encrypted token storage | `secure-token-manager.sh` |
| **Token Metadata** | `/etc/vault.d/secure/tokens/*.meta` | Token usage tracking | JSON format |
| **Encryption Keys** | `/etc/vault.d/secure/keys/master.key` | Master encryption key | Protected file |
| **Backups** | `/etc/vault.d/secure/backup/` | Token backups | Timestamped dirs |

### Backup Locations

| Backup Type | Location Pattern | Retention |
|-------------|------------------|-----------|
| **Token Backups** | `/etc/vault.d/secure/backup/tokens-backup-YYYYMMDD-HHMMSS.tar.gz` | 90 days |
| **Rotation Backups** | `/etc/vault.d/secure/backup/rotation-TOKEN-YYYYMMDD-HHMMSS/` | 90 days |
| **Deletion Backups** | `/etc/vault.d/secure/backup/deleted-TOKEN-YYYYMMDD-HHMMSS/` | 365 days |
| **System Backups** | `/backups/vault/YYYYMMDD-HHMMSS/` | 30 days |

## 🛠️ Token Retrieval Procedures

### Method 1: Direct File Access (Root Token)
```bash
# Retrieve root token directly
export VAULT_TOKEN=$(sudo cat /root/.vault/root-token)
echo "Root token: $VAULT_TOKEN"

# Use with Vault CLI
vault auth -method=token token=$VAULT_TOKEN
```

### Method 2: Secure Token Manager
```bash
# Initialize secure storage (first time only)
sudo /vault/security/secure-token-manager.sh init

# Retrieve any stored token
sudo /vault/security/secure-token-manager.sh retrieve root-token

# List all available tokens
sudo /vault/security/secure-token-manager.sh list

# Generate masked version for logging
sudo /vault/security/secure-token-manager.sh mask "$(sudo cat /root/.vault/root-token)"
```

### Method 3: From Initialization File
```bash
# Extract root token from init file
export VAULT_TOKEN=$(sudo jq -r '.root_token' /opt/vault/init.json)

# Extract unseal keys
for i in {0..2}; do
  KEY=$(sudo jq -r ".unseal_keys_b64[$i]" /opt/vault/init.json)
  echo "Unseal key $((i+1)): $KEY"
done
```

## 🔄 Key Rotation Procedures

### Root Token Rotation
```bash
# 1. Generate new root token
export VAULT_TOKEN=$(sudo cat /root/.vault/root-token)
NEW_ROOT_TOKEN=$(vault write -field=token auth/token/create policies=root ttl=0)

# 2. Store new token securely
sudo /vault/security/secure-token-manager.sh rotate root-token "$NEW_ROOT_TOKEN" "Rotated on $(date)"

# 3. Update root token file
echo "$NEW_ROOT_TOKEN" | sudo tee /root/.vault/root-token > /dev/null
sudo chmod 600 /root/.vault/root-token

# 4. Test new token
export VAULT_TOKEN="$NEW_ROOT_TOKEN"
vault auth -method=token token=$VAULT_TOKEN
```

### Unseal Key Rotation
```bash
# This requires generating new unseal keys (advanced procedure)
# Should only be performed during planned maintenance

# 1. Backup current state
sudo /vault/scripts/deploy-vault.sh --action backup

# 2. Start rekey operation
vault operator rekey -init -key-shares=5 -key-threshold=3

# 3. Follow prompts to provide current unseal keys
# 4. Distribute new unseal keys securely
# 5. Update /opt/vault/init.json with new keys
```

## 🔒 Security Best Practices

### Token Security
1. **Never log raw tokens** - always mask them:
   ```bash
   # Good: Masked token
   TOKEN_MASKED=$(sudo /vault/security/secure-token-manager.sh mask "$TOKEN")
   echo "Using token: $TOKEN_MASKED"
   
   # Bad: Raw token in logs
   echo "Using token: $TOKEN"  # NEVER DO THIS
   ```

2. **Use time-limited tokens** for daily operations:
   ```bash
   # Create limited-time token
   vault write auth/token/create ttl=8h policies=admin-policy
   ```

3. **Store tokens encrypted**:
   ```bash
   # Store with description
   sudo /vault/security/secure-token-manager.sh store my-token "hvs.XXXXX" "Daily operations token"
   ```

### Key Distribution Security
1. **Distribute unseal keys to separate individuals**
2. **Use secure channels** (encrypted communication)
3. **Never store all keys in one location**
4. **Regular key rotation schedule**

## 🚨 Emergency Access Procedures

### Lost Root Token
```bash
# 1. Check if token exists in secure storage
sudo /vault/security/secure-token-manager.sh list

# 2. If available, retrieve from secure storage
sudo /vault/security/secure-token-manager.sh retrieve root-token

# 3. If not available, check init file
sudo jq -r '.root_token' /opt/vault/init.json

# 4. Last resort: Generate new root token using unseal keys
vault operator generate-root -init
# Follow prompts to provide unseal keys
```

### Cannot Unseal Vault
```bash
# 1. Check unseal keys from init file
sudo jq -r '.unseal_keys_b64[]' /opt/vault/init.json

# 2. Unseal with first 3 keys
for i in {0..2}; do
  KEY=$(sudo jq -r ".unseal_keys_b64[$i]" /opt/vault/init.json)
  vault operator unseal "$KEY"
done

# 3. Verify unsealed status
vault status
```

### Corrupted Token Storage
```bash
# 1. List available backups
ls -la /etc/vault.d/secure/backup/

# 2. Restore from latest backup
sudo /vault/security/secure-token-manager.sh restore \
  /etc/vault.d/secure/backup/tokens-backup-YYYYMMDD-HHMMSS.tar.gz force

# 3. Verify restoration
sudo /vault/security/secure-token-manager.sh list
```

## 📊 Token Usage Monitoring

### Usage Statistics
```bash
# View token usage statistics
sudo /vault/security/secure-token-manager.sh monitor

# Sample output:
# Token Statistics:
#   Total tokens: 5
#   Total accesses: 147
#   Unused tokens: 1
#   Warning: Unused token older than 30 days: old-token
```

### Audit Token Access
```bash
# View token metadata
sudo cat /etc/vault.d/secure/tokens/root-token.meta

# Example metadata:
{
  "name": "root-token",
  "description": "Initial root token",
  "created": "2024-01-15T10:30:00Z",
  "last_accessed": "2024-01-15T14:22:15Z",
  "access_count": 5,
  "token_hash": "sha256hash..."
}
```

## 🔧 Automation Scripts

### Daily Token Health Check
```bash
#!/bin/bash
# /vault/scripts/daily-token-check.sh

# Check token accessibility
if sudo /vault/security/secure-token-manager.sh retrieve root-token >/dev/null 2>&1; then
    echo "✅ Root token accessible"
else
    echo "❌ Root token not accessible"
    exit 1
fi

# Check unseal keys
if sudo test -f /opt/vault/init.json; then
    echo "✅ Unseal keys available"
else
    echo "❌ Unseal keys missing"
    exit 1
fi

# Monitor usage
sudo /vault/security/secure-token-manager.sh monitor
```

### Token Cleanup Script
```bash
#!/bin/bash
# /vault/scripts/token-cleanup.sh

echo "Starting token cleanup..."

# Clean up old backups
sudo /vault/security/secure-token-manager.sh cleanup

# Remove unused tokens older than 90 days
# (Implementation would check metadata and prompt for deletion)

echo "Token cleanup completed"
```

## 📚 Quick Reference Commands

### Most Common Commands
```bash
# Get root token
sudo cat /root/.vault/root-token

# Get first unseal key
sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json

# List stored tokens
sudo /vault/security/secure-token-manager.sh list

# Unseal vault
vault operator unseal $(sudo jq -r '.unseal_keys_b64[0]' /opt/vault/init.json)
vault operator unseal $(sudo jq -r '.unseal_keys_b64[1]' /opt/vault/init.json)
vault operator unseal $(sudo jq -r '.unseal_keys_b64[2]' /opt/vault/init.json)

# Login with root token
vault login $(sudo cat /root/.vault/root-token)
```

---

## ⚠️ CRITICAL WARNINGS

1. **BACKUP IMMEDIATELY**: After initialization, immediately backup `/opt/vault/init.json` and `/root/.vault/root-token` to secure offline storage
2. **DISTRIBUTE KEYS**: Never store all 5 unseal keys in one location
3. **ROTATE REGULARLY**: Rotate root token every 90 days
4. **MONITOR ACCESS**: Regularly check token usage logs
5. **SECURE STORAGE**: Use the secure token manager for production environments

**Remember: Loss of both root token and unseal keys means permanent loss of access to Vault data!**

---
*Last Updated: $(date)*
*Document Version: 1.0*