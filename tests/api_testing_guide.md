# Vault API Testing Guide

## Overview

This guide provides comprehensive instructions for testing HashiCorp Vault's REST API endpoints. It covers all major API categories and provides practical examples for validation and troubleshooting.

## Prerequisites

### Required Tools
- `curl` - Command-line HTTP client
- `jq` - JSON processor for parsing responses
- `bash` - For running test scripts
- Vault CLI (optional, for advanced operations)

### Environment Setup

```bash
# Set Vault server address
export VAULT_ADDR="http://127.0.0.1:8200"

# Set authentication token (when available)
export VAULT_TOKEN="your-vault-token-here"

# Verify tools are available
curl --version
jq --version
```

## API Testing Categories

### 1. Core System & Health Endpoints

These endpoints are essential for basic Vault operation and should always be accessible.

#### Health Check
```bash
# Basic health check
curl -s "$VAULT_ADDR/v1/sys/health" | jq .

# Expected responses:
# - 200: Vault is initialized, unsealed, and active
# - 429: Vault is unsealed but standby
# - 473: Vault is in disaster recovery mode
# - 501: Vault is not initialized
# - 503: Vault is sealed
```

#### Seal Status
```bash
# Get seal status
curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq .

# Key fields:
# - "sealed": true/false
# - "initialized": true/false
# - "unseal_progress": number of unseal keys provided
# - "unseal_nonce": current unseal attempt nonce
```

#### Leader Information
```bash
# Get cluster leader info
curl -s "$VAULT_ADDR/v1/sys/leader" | jq .

# Returns:
# - "ha_enabled": true/false
# - "is_self": true if this node is leader
# - "leader_address": cluster leader address
```

### 2. Authentication Endpoints

These endpoints manage authentication methods and tokens.

#### List Authentication Methods
```bash
# Requires authentication
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/auth" | jq .
```

#### Token Operations
```bash
# Look up current token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/auth/token/lookup-self" | jq .

# Renew current token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST "$VAULT_ADDR/v1/auth/token/renew-self" | jq .

# Create new token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d '{"policies": ["default"], "ttl": "1h"}' \
     "$VAULT_ADDR/v1/auth/token/create" | jq .
```

### 3. Secrets Engine Endpoints

Test various secrets engines and their capabilities.

#### List Mounted Secrets Engines
```bash
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/mounts" | jq .
```

#### KV Secrets Engine (Version 2)
```bash
# List secrets
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/secret/metadata?list=true" | jq .

# Read secret
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/secret/data/myapp/config" | jq .

# Write secret
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d '{"data": {"password": "secret123"}}' \
     "$VAULT_ADDR/v1/secret/data/myapp/config" | jq .
```

#### PKI Secrets Engine
```bash
# Get CA certificate (public, no auth required)
curl -s "$VAULT_ADDR/v1/pki/ca/pem"

# List PKI roles (requires auth)
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/pki/roles?list=true" | jq .
```

#### Transit Secrets Engine
```bash
# List encryption keys
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/transit/keys?list=true" | jq .

# Encrypt data
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d "{\"plaintext\": \"$(echo -n 'hello world' | base64)\"}" \
     "$VAULT_ADDR/v1/transit/encrypt/my-key" | jq .
```

### 4. Policy Management Endpoints

Test policy creation and management.

```bash
# List all policies
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/policies/acl?list=true" | jq .

# Read specific policy
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/policies/acl/default" | jq .

# Create/update policy
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X PUT -d '{"policy": "path \"secret/data/*\" { capabilities = [\"read\", \"list\"] }"}' \
     "$VAULT_ADDR/v1/sys/policies/acl/readonly-policy"
```

### 5. Audit & Monitoring Endpoints

Test audit devices and monitoring capabilities.

```bash
# List audit devices
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/audit" | jq .

# Get Prometheus metrics
curl -s "$VAULT_ADDR/v1/sys/metrics"

# Get JSON metrics
curl -s "$VAULT_ADDR/v1/sys/metrics?format=json" | jq .

# Get request counters
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/internal/counters/requests" | jq .
```

### 6. Storage & Raft Endpoints

Test Raft consensus and storage operations.

```bash
# Get Raft configuration
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/storage/raft/configuration" | jq .

# Get autopilot state
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/storage/raft/autopilot/state" | jq .

# Take Raft snapshot (downloads binary data)
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/storage/raft/snapshot" > vault-snapshot.snap
```

### 7. High Availability & Replication

Test HA and replication features (Enterprise).

```bash
# Get HA status
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/ha-status" | jq .

# Get replication status
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/replication/status" | jq .
```

### 8. Administration Endpoints

Test administrative operations.

```bash
# Check initialization status
curl -s "$VAULT_ADDR/v1/sys/init" | jq .

# Initialize Vault (only if uninitialized)
curl -s -X POST -d '{"secret_shares": 5, "secret_threshold": 3}' \
     "$VAULT_ADDR/v1/sys/init" | jq .

# Unseal Vault
curl -s -X POST -d '{"key": "your-unseal-key"}' \
     "$VAULT_ADDR/v1/sys/unseal" | jq .

# Seal Vault (requires root token)
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST "$VAULT_ADDR/v1/sys/seal"
```

## Response Code Interpretation

### Success Codes (2xx)
- **200 OK**: Request succeeded
- **204 No Content**: Request succeeded, no response body

### Client Error Codes (4xx)
- **400 Bad Request**: Invalid request parameters
- **401 Unauthorized**: Authentication required
- **403 Forbidden**: Insufficient permissions
- **404 Not Found**: Endpoint or resource not found
- **429 Too Many Requests**: Rate limited

### Server Error Codes (5xx)
- **500 Internal Server Error**: Vault server error
- **501 Not Implemented**: Feature not available
- **503 Service Unavailable**: Vault is sealed or unavailable

### Vault-Specific Codes
- **473**: Vault in disaster recovery mode
- **501**: Vault not initialized (for health endpoint)

## Testing Strategies

### 1. Progressive Testing
1. Start with unauthenticated endpoints (health, seal-status)
2. Test authentication and token operations
3. Test secrets engines and policies
4. Test advanced features (audit, replication)

### 2. Error Scenario Testing
```bash
# Test invalid endpoints
curl -s "$VAULT_ADDR/v1/invalid/endpoint"

# Test without authentication
curl -s "$VAULT_ADDR/v1/sys/mounts"

# Test with invalid token
curl -s -H "X-Vault-Token: invalid-token" \
     "$VAULT_ADDR/v1/sys/mounts"
```

### 3. Performance Testing
```bash
# Test response times
time curl -s "$VAULT_ADDR/v1/sys/health"

# Test concurrent requests
for i in {1..10}; do
  curl -s "$VAULT_ADDR/v1/sys/health" &
done
wait
```

## Automation Scripts

### Basic Health Check Script
```bash
#!/bin/bash
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}

echo "Testing Vault API accessibility..."

# Test health endpoint
if curl -s --connect-timeout 5 "$VAULT_ADDR/v1/sys/health" >/dev/null; then
    echo "✓ Vault is accessible"
    
    # Get health details
    HEALTH=$(curl -s "$VAULT_ADDR/v1/sys/health")
    INITIALIZED=$(echo "$HEALTH" | jq -r '.initialized')
    SEALED=$(echo "$HEALTH" | jq -r '.sealed')
    
    echo "  - Initialized: $INITIALIZED"
    echo "  - Sealed: $SEALED"
else
    echo "✗ Vault is not accessible"
    exit 1
fi
```

### Token Validation Script
```bash
#!/bin/bash
if [[ -z "$VAULT_TOKEN" ]]; then
    echo "VAULT_TOKEN not set"
    exit 1
fi

# Test token validity
RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
           "$VAULT_ADDR/v1/auth/token/lookup-self")

if echo "$RESPONSE" | jq -e '.data.id' >/dev/null; then
    echo "✓ Token is valid"
    TTL=$(echo "$RESPONSE" | jq -r '.data.ttl')
    echo "  - TTL: $TTL seconds"
else
    echo "✗ Token is invalid"
    exit 1
fi
```

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Ensure Vault is running
   - Check VAULT_ADDR environment variable
   - Verify network connectivity

2. **403 Forbidden**
   - Check token validity
   - Verify policy permissions
   - Ensure token has required capabilities

3. **503 Service Unavailable**
   - Vault may be sealed
   - Check seal status
   - Provide unseal keys if needed

4. **404 Not Found**
   - Verify endpoint path
   - Check if secrets engine is mounted
   - Ensure feature is enabled

### Debug Commands
```bash
# Enable verbose curl output
curl -v "$VAULT_ADDR/v1/sys/health"

# Check response headers only
curl -I "$VAULT_ADDR/v1/sys/health"

# Save response to file
curl -s "$VAULT_ADDR/v1/sys/health" > response.json

# Test with timeout
curl --connect-timeout 5 --max-time 10 "$VAULT_ADDR/v1/sys/health"
```

## Security Considerations

1. **Use HTTPS**: Always use HTTPS in production
2. **Token Security**: Keep tokens secure, rotate regularly
3. **Network Security**: Limit API access to authorized networks
4. **Audit Logging**: Enable audit devices for compliance
5. **Rate Limiting**: Configure rate limits to prevent abuse

## Best Practices

1. **Test Incrementally**: Start with basic endpoints
2. **Validate Responses**: Always check response codes and content
3. **Handle Errors**: Implement proper error handling
4. **Monitor Performance**: Track API response times
5. **Document Results**: Keep detailed test logs
6. **Automate Testing**: Use scripts for routine testing

## Resources

- [Vault API Documentation](https://www.vaultproject.io/api-docs)
- [Vault CLI Documentation](https://www.vaultproject.io/docs/commands)
- [Vault Authentication Methods](https://www.vaultproject.io/docs/auth)
- [Vault Secrets Engines](https://www.vaultproject.io/docs/secrets)

---

Generated by Vault API Testing Specialist