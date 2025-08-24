#!/bin/bash
# Vault Deployment Integration Test Suite
# Tests installation, upgrade, and API accessibility

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
VAULT_VERSION="1.17.3"
TEST_RESULTS=()
FAILED_TESTS=0

# Helper functions
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TEST_RESULTS+=("✅ $1")
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    TEST_RESULTS+=("❌ $1")
    ((FAILED_TESTS++))
}

# Test 1: Check Vault binary installation
test_vault_binary() {
    log_test "Testing Vault binary installation..."
    
    if command -v vault &> /dev/null; then
        INSTALLED_VERSION=$(vault version | grep -oP 'Vault v\K[0-9.]+' || echo "unknown")
        if [[ "$INSTALLED_VERSION" == "$VAULT_VERSION" ]]; then
            log_success "Vault binary installed (version $INSTALLED_VERSION)"
        else
            log_failure "Vault version mismatch (expected: $VAULT_VERSION, found: $INSTALLED_VERSION)"
        fi
    else
        log_failure "Vault binary not found in PATH"
    fi
}

# Test 2: Check Vault service status
test_vault_service() {
    log_test "Testing Vault service status..."
    
    if systemctl is-active --quiet vault; then
        log_success "Vault service is running"
    else
        log_failure "Vault service is not running"
    fi
    
    if systemctl is-enabled --quiet vault; then
        log_success "Vault service is enabled"
    else
        log_failure "Vault service is not enabled"
    fi
}

# Test 3: Check Vault API accessibility
test_vault_api() {
    log_test "Testing Vault API accessibility..."
    
    if curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" | grep -q "200\|429\|473\|501\|503"; then
        log_success "Vault API is accessible at $VAULT_ADDR"
        
        # Get detailed health status
        HEALTH_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/health")
        if [[ -n "$HEALTH_RESPONSE" ]]; then
            log_success "Vault health endpoint responding with data"
        fi
    else
        log_failure "Vault API is not accessible at $VAULT_ADDR"
    fi
}

# Test 4: Check Vault configuration
test_vault_config() {
    log_test "Testing Vault configuration..."
    
    CONFIG_FILE="/etc/vault.d/vault.hcl"
    if [[ -f "$CONFIG_FILE" ]]; then
        log_success "Vault configuration file exists"
        
        # Check for required configuration elements
        if grep -q "storage \"raft\"" "$CONFIG_FILE"; then
            log_success "Raft storage backend configured"
        else
            log_failure "Raft storage backend not configured"
        fi
        
        if grep -q "listener \"tcp\"" "$CONFIG_FILE"; then
            log_success "TCP listener configured"
        else
            log_failure "TCP listener not configured"
        fi
        
        if grep -q "api_addr" "$CONFIG_FILE"; then
            log_success "API address configured"
        else
            log_failure "API address not configured"
        fi
    else
        log_failure "Vault configuration file not found at $CONFIG_FILE"
    fi
}

# Test 5: Check Vault data directory
test_vault_data() {
    log_test "Testing Vault data directory..."
    
    DATA_DIR="/opt/vault/data"
    if [[ -d "$DATA_DIR" ]]; then
        log_success "Vault data directory exists"
        
        # Check permissions
        OWNER=$(stat -c '%U' "$DATA_DIR")
        if [[ "$OWNER" == "vault" ]]; then
            log_success "Data directory owned by vault user"
        else
            log_failure "Data directory not owned by vault user (owned by: $OWNER)"
        fi
        
        # Check for Raft data
        if [[ -d "$DATA_DIR/raft" ]]; then
            log_success "Raft storage directory exists"
        else
            log_failure "Raft storage directory not found"
        fi
    else
        log_failure "Vault data directory not found at $DATA_DIR"
    fi
}

# Test 6: Check Vault seal status
test_vault_seal_status() {
    log_test "Testing Vault seal status..."
    
    SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null)
    if [[ -n "$SEAL_STATUS" ]]; then
        SEALED=$(echo "$SEAL_STATUS" | jq -r '.sealed' 2>/dev/null)
        INITIALIZED=$(echo "$SEAL_STATUS" | jq -r '.initialized' 2>/dev/null)
        
        if [[ "$INITIALIZED" == "true" ]]; then
            log_success "Vault is initialized"
        elif [[ "$INITIALIZED" == "false" ]]; then
            log_success "Vault is not initialized (expected for fresh install)"
        else
            log_failure "Unable to determine initialization status"
        fi
        
        if [[ "$SEALED" == "true" ]]; then
            log_success "Vault is sealed (expected state)"
        elif [[ "$SEALED" == "false" ]]; then
            log_success "Vault is unsealed and operational"
        else
            log_failure "Unable to determine seal status"
        fi
    else
        log_failure "Unable to retrieve seal status"
    fi
}

# Test 7: Check backup directory
test_backup_directory() {
    log_test "Testing backup directory..."
    
    BACKUP_DIR="/opt/vault/backups"
    if [[ -d "$BACKUP_DIR" ]]; then
        log_success "Backup directory exists"
        
        # Check if any backups exist
        BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.snap" 2>/dev/null | wc -l)
        if [[ $BACKUP_COUNT -gt 0 ]]; then
            log_success "Found $BACKUP_COUNT backup snapshot(s)"
        else
            log_success "No backups yet (expected for fresh install)"
        fi
    else
        log_failure "Backup directory not found at $BACKUP_DIR"
    fi
}

# Test 8: Check systemd unit file
test_systemd_unit() {
    log_test "Testing systemd unit configuration..."
    
    UNIT_FILE="/etc/systemd/system/vault.service"
    if [[ -f "$UNIT_FILE" ]]; then
        log_success "Systemd unit file exists"
        
        # Check for security constraints
        if grep -q "ProtectSystem=full" "$UNIT_FILE"; then
            log_success "ProtectSystem security constraint configured"
        else
            log_failure "ProtectSystem security constraint not configured"
        fi
        
        if grep -q "PrivateTmp=yes" "$UNIT_FILE"; then
            log_success "PrivateTmp security constraint configured"
        else
            log_failure "PrivateTmp security constraint not configured"
        fi
        
        if grep -q "User=vault" "$UNIT_FILE"; then
            log_success "Service runs as vault user"
        else
            log_failure "Service not configured to run as vault user"
        fi
    else
        log_failure "Systemd unit file not found at $UNIT_FILE"
    fi
}

# Test 9: Network connectivity test
test_network_connectivity() {
    log_test "Testing network connectivity..."
    
    # Test localhost
    if nc -zv 127.0.0.1 8200 &>/dev/null; then
        log_success "Vault listening on localhost:8200"
    else
        log_failure "Vault not listening on localhost:8200"
    fi
    
    # Test all interfaces
    if nc -zv 0.0.0.0 8200 &>/dev/null; then
        log_success "Vault listening on all interfaces"
    else
        # This might be expected based on configuration
        log_success "Vault not listening on all interfaces (may be expected)"
    fi
}

# Test 10: Verify audit capabilities
test_audit_capabilities() {
    log_test "Testing audit log capabilities..."
    
    AUDIT_DIR="/opt/vault/audit"
    if [[ -d "$AUDIT_DIR" ]]; then
        log_success "Audit directory exists"
        
        # Check permissions
        OWNER=$(stat -c '%U' "$AUDIT_DIR")
        PERMS=$(stat -c '%a' "$AUDIT_DIR")
        if [[ "$OWNER" == "vault" && "$PERMS" == "700" ]]; then
            log_success "Audit directory has correct permissions"
        else
            log_failure "Audit directory permissions incorrect (owner: $OWNER, perms: $PERMS)"
        fi
    else
        log_success "Audit directory not yet created (will be created when audit is enabled)"
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "Vault Deployment Integration Test Suite"
    echo "========================================="
    echo "Test Configuration:"
    echo "  - Vault Address: $VAULT_ADDR"
    echo "  - Expected Version: $VAULT_VERSION"
    echo "========================================="
    echo
    
    # Run all tests
    test_vault_binary
    test_vault_service
    test_vault_api
    test_vault_config
    test_vault_data
    test_vault_seal_status
    test_backup_directory
    test_systemd_unit
    test_network_connectivity
    test_audit_capabilities
    
    # Print summary
    echo
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    echo "========================================="
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}$FAILED_TESTS test(s) failed${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi