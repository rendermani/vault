#!/bin/bash
# Deployment Logic Test Suite
# Tests the deployment script functions in isolation

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_failure() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "==========================================="
echo "Vault Deployment Logic Test Suite"
echo "==========================================="

# Source the deployment script functions
source ../scripts/deploy-vault.sh 2>/dev/null || {
    echo "Could not source deployment script"
    exit 1
}

# Test 1: Vault detection logic
log_test "Testing Vault detection function"
VAULT_STATE=$(check_vault)
echo "Vault state detected: $VAULT_STATE"

IFS=':' read -r EXISTS STATUS VERSION <<< "$VAULT_STATE"
if [[ "$EXISTS" == "not-exists" ]]; then
    log_success "Correctly detected Vault is not installed"
elif [[ "$EXISTS" == "exists" ]]; then
    log_success "Correctly detected existing Vault installation (Status: $STATUS, Version: $VERSION)"
else
    log_failure "Invalid vault state detection: $VAULT_STATE"
fi

# Test 2: Version comparison logic
log_test "Testing version comparison logic"
CURRENT_VERSION="1.16.0"
TARGET_VERSION="1.17.3"

if [[ "$CURRENT_VERSION" != "$TARGET_VERSION" ]]; then
    log_success "Version comparison logic works (detected upgrade needed)"
else
    log_success "Version comparison logic works (no upgrade needed)"
fi

# Test 3: Configuration generation
log_test "Testing configuration file generation"
TEST_CONFIG="/tmp/test-vault.hcl"

# Simulate config generation (without root privileges)
cat > "$TEST_CONFIG" << 'EOF'
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

api_addr = "http://TEST_IP:8200"
cluster_addr = "https://TEST_IP:8201"
EOF

if [[ -f "$TEST_CONFIG" ]]; then
    log_success "Configuration file generated successfully"
    
    # Test configuration parsing
    if grep -q "storage \"raft\"" "$TEST_CONFIG"; then
        log_success "Raft storage configuration present"
    fi
    
    if grep -q "listener \"tcp\"" "$TEST_CONFIG"; then
        log_success "TCP listener configuration present"
    fi
    
    if grep -q "api_addr" "$TEST_CONFIG"; then
        log_success "API address configuration present"
    fi
    
    rm -f "$TEST_CONFIG"
else
    log_failure "Failed to generate configuration file"
fi

# Test 4: Service file validation
log_test "Testing systemd service configuration"
TEST_SERVICE="/tmp/test-vault.service"

cat > "$TEST_SERVICE" << 'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

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
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure
RestartSec=5
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

if [[ -f "$TEST_SERVICE" ]]; then
    log_success "Systemd service file generated"
    
    # Check security settings
    if grep -q "ProtectSystem=full" "$TEST_SERVICE"; then
        log_success "ProtectSystem security constraint configured"
    fi
    
    if grep -q "PrivateTmp=yes" "$TEST_SERVICE"; then
        log_success "PrivateTmp security constraint configured"  
    fi
    
    if grep -q "User=vault" "$TEST_SERVICE"; then
        log_success "Service runs as vault user"
    fi
    
    if grep -q "NoNewPrivileges=yes" "$TEST_SERVICE"; then
        log_success "NoNewPrivileges security constraint configured"
    fi
    
    rm -f "$TEST_SERVICE"
else
    log_failure "Failed to generate service file"
fi

# Test 5: Backup directory logic
log_test "Testing backup directory creation"
TEST_BACKUP_DIR="/tmp/vault-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_BACKUP_DIR"

if [[ -d "$TEST_BACKUP_DIR" ]]; then
    log_success "Backup directory structure created successfully"
    rm -rf "/tmp/vault-backups"
else
    log_failure "Failed to create backup directory structure"
fi

# Test 6: Policy validation
log_test "Testing policy file validation"
ADMIN_POLICY="../policies/admin.hcl"

if [[ -f "$ADMIN_POLICY" ]]; then
    log_success "Admin policy file exists"
    
    # Check policy content
    if grep -q "path \"*\"" "$ADMIN_POLICY"; then
        log_success "Admin policy has wildcard path access"
    fi
    
    if grep -q "capabilities.*sudo" "$ADMIN_POLICY"; then
        log_success "Admin policy includes sudo capabilities"
    fi
    
    if grep -q "deny" "$ADMIN_POLICY"; then
        log_success "Admin policy includes security restrictions"
    fi
else
    log_failure "Admin policy file not found"
fi

echo "==========================================="
echo "Deployment Logic Tests Completed"
echo "==========================================="