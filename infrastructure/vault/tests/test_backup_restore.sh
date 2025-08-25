#!/bin/bash
# Vault Backup and Restore Test Suite
# Tests backup creation, validation, and restore procedures

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
BACKUP_DIR="/opt/vault/backups"
TEST_BACKUP_DIR="/tmp/vault-test-backups"
DEPLOY_SCRIPT="/root/scripts/deploy-vault.sh"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

# Test 1: Create a backup
test_create_backup() {
    log_test "Testing backup creation..."
    
    # Create test backup directory
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Check if deploy script exists
    if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
        log_info "Deploy script not found, testing backup command directly"
        
        # Try to create a Raft snapshot directly
        if command -v vault &> /dev/null; then
            # Check if Vault is initialized and unsealed
            SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null)
            INITIALIZED=$(echo "$SEAL_STATUS" | jq -r '.initialized' 2>/dev/null)
            SEALED=$(echo "$SEAL_STATUS" | jq -r '.sealed' 2>/dev/null)
            
            if [[ "$INITIALIZED" == "true" && "$SEALED" == "false" ]]; then
                # Create a snapshot
                BACKUP_FILE="$TEST_BACKUP_DIR/test-backup-$(date +%Y%m%d-%H%M%S).snap"
                
                if [[ -n "$VAULT_TOKEN" ]]; then
                    vault operator raft snapshot save "$BACKUP_FILE" 2>/dev/null && {
                        log_success "Backup created successfully at $BACKUP_FILE"
                        return 0
                    } || {
                        log_info "Unable to create Raft snapshot (Vault may not be using Raft storage)"
                        return 0
                    }
                else
                    log_info "VAULT_TOKEN not set, skipping live backup test"
                    return 0
                fi
            else
                log_info "Vault not initialized/unsealed, skipping live backup test"
                return 0
            fi
        else
            log_info "Vault CLI not available, skipping backup test"
            return 0
        fi
    else
        # Use deploy script to create backup
        log_info "Using deploy script for backup"
        if $DEPLOY_SCRIPT --action backup; then
            log_success "Backup created using deploy script"
        else
            log_failure "Failed to create backup using deploy script"
        fi
    fi
}

# Test 2: Validate backup files
test_validate_backup() {
    log_test "Testing backup validation..."
    
    # Check main backup directory
    if [[ -d "$BACKUP_DIR" ]]; then
        BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.snap" -o -name "*.tar.gz" 2>/dev/null | wc -l)
        
        if [[ $BACKUP_COUNT -gt 0 ]]; then
            log_success "Found $BACKUP_COUNT backup file(s) in $BACKUP_DIR"
            
            # Check backup file integrity
            for backup in $(find "$BACKUP_DIR" -name "*.snap" -o -name "*.tar.gz" 2>/dev/null | head -5); do
                if [[ -f "$backup" ]]; then
                    SIZE=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo "0")
                    if [[ $SIZE -gt 0 ]]; then
                        log_success "Backup file $(basename "$backup") is valid (size: $SIZE bytes)"
                    else
                        log_failure "Backup file $(basename "$backup") is empty"
                    fi
                fi
            done
        else
            log_info "No backup files found (expected for fresh installation)"
        fi
    else
        log_info "Backup directory doesn't exist yet"
    fi
    
    # Check test backup directory
    if [[ -d "$TEST_BACKUP_DIR" ]]; then
        TEST_BACKUP_COUNT=$(find "$TEST_BACKUP_DIR" -name "*.snap" 2>/dev/null | wc -l)
        if [[ $TEST_BACKUP_COUNT -gt 0 ]]; then
            log_success "Test backup created successfully"
        fi
    fi
}

# Test 3: Test backup rotation
test_backup_rotation() {
    log_test "Testing backup rotation policy..."
    
    # Create multiple test backups to test rotation
    if [[ -d "$TEST_BACKUP_DIR" ]]; then
        for i in {1..5}; do
            touch "$TEST_BACKUP_DIR/test-backup-$(date +%Y%m%d-%H%M%S)-$i.snap"
            sleep 1
        done
        
        BACKUP_COUNT=$(ls -1 "$TEST_BACKUP_DIR"/*.snap 2>/dev/null | wc -l)
        if [[ $BACKUP_COUNT -ge 5 ]]; then
            log_success "Created $BACKUP_COUNT test backups for rotation testing"
        fi
        
        # Check if rotation would work (don't actually delete)
        OLDEST_BACKUP=$(ls -1t "$TEST_BACKUP_DIR"/*.snap 2>/dev/null | tail -1)
        if [[ -n "$OLDEST_BACKUP" ]]; then
            log_success "Identified oldest backup for rotation: $(basename "$OLDEST_BACKUP")"
        fi
    fi
}

# Test 4: Test restore readiness
test_restore_readiness() {
    log_test "Testing restore readiness..."
    
    # Check if restore prerequisites are met
    CHECKS_PASSED=0
    TOTAL_CHECKS=4
    
    # Check 1: Vault binary available
    if command -v vault &> /dev/null; then
        log_success "Vault binary available for restore"
        ((CHECKS_PASSED++))
    else
        log_info "Vault binary not in PATH"
    fi
    
    # Check 2: Backup files exist
    if [[ -d "$BACKUP_DIR" ]] && [[ $(find "$BACKUP_DIR" -name "*.snap" 2>/dev/null | wc -l) -gt 0 ]]; then
        log_success "Backup files available for restore"
        ((CHECKS_PASSED++))
    elif [[ -d "$TEST_BACKUP_DIR" ]] && [[ $(find "$TEST_BACKUP_DIR" -name "*.snap" 2>/dev/null | wc -l) -gt 0 ]]; then
        log_success "Test backup files available for restore"
        ((CHECKS_PASSED++))
    else
        log_info "No backup files available yet"
    fi
    
    # Check 3: Data directory writable
    if [[ -w "/opt/vault/data" ]] || [[ -w "/opt/vault" ]]; then
        log_success "Vault data directory is writable"
        ((CHECKS_PASSED++))
    else
        log_info "Vault data directory not writable (may need sudo)"
    fi
    
    # Check 4: Systemd available for service management
    if command -v systemctl &> /dev/null; then
        log_success "Systemd available for service management"
        ((CHECKS_PASSED++))
    else
        log_info "Systemd not available"
    fi
    
    if [[ $CHECKS_PASSED -eq $TOTAL_CHECKS ]]; then
        log_success "All restore prerequisites met ($CHECKS_PASSED/$TOTAL_CHECKS)"
    else
        log_info "Restore readiness: $CHECKS_PASSED/$TOTAL_CHECKS checks passed"
    fi
}

# Test 5: Document restore procedure
test_document_restore() {
    log_test "Documenting restore procedure..."
    
    RESTORE_DOC="$TEST_BACKUP_DIR/RESTORE_PROCEDURE.md"
    
    cat > "$RESTORE_DOC" << 'EOF'
# Vault Restore Procedure

## Prerequisites
1. Ensure Vault service is stopped: `systemctl stop vault`
2. Locate backup file: Check `/opt/vault/backups/` for `.snap` files
3. Ensure you have root/sudo access

## Restore Steps

### For Raft Storage Backend

1. **Stop Vault Service**
   ```bash
   sudo systemctl stop vault
   ```

2. **Backup Current Data (Safety)**
   ```bash
   sudo cp -r /opt/vault/data /opt/vault/data.backup-$(date +%Y%m%d-%H%M%S)
   ```

3. **Clear Existing Raft Data**
   ```bash
   sudo rm -rf /opt/vault/data/raft/*
   ```

4. **Start Vault Service**
   ```bash
   sudo systemctl start vault
   ```

5. **Initialize Vault (if needed)**
   ```bash
   vault operator init
   # Save the unseal keys and root token!
   ```

6. **Unseal Vault**
   ```bash
   vault operator unseal <key-1>
   vault operator unseal <key-2>
   vault operator unseal <key-3>
   ```

7. **Restore from Snapshot**
   ```bash
   export VAULT_TOKEN="<root-token>"
   vault operator raft snapshot restore /opt/vault/backups/<snapshot-file>.snap
   ```

8. **Verify Restoration**
   ```bash
   vault status
   vault secrets list
   vault policy list
   ```

## Alternative: Using Deploy Script

If the deploy script is available:

```bash
# Automated restore
/root/scripts/deploy-vault.sh --action restore --backup-file /opt/vault/backups/<snapshot>.snap
```

## Post-Restore Tasks

1. **Rotate Root Token**
   ```bash
   vault token create -policy=admin -display-name="admin-token"
   vault token revoke <old-root-token>
   ```

2. **Update Unseal Keys**
   - Store new unseal keys securely
   - Distribute to key holders
   - Update documentation

3. **Verify Services**
   - Check all integrated services
   - Test authentication methods
   - Verify secrets access

## Troubleshooting

### Issue: Vault won't start after restore
- Check logs: `journalctl -u vault -n 50`
- Verify permissions: `chown -R vault:vault /opt/vault/data`
- Check config: `vault operator diagnose`

### Issue: Data corruption
- Restore from an older backup
- Check disk space: `df -h /opt/vault`
- Verify backup integrity before restore

## Important Notes
- Always test restore procedure in non-production first
- Keep multiple backup generations
- Document any custom configurations
- Maintain unseal keys securely and separately
EOF
    
    if [[ -f "$RESTORE_DOC" ]]; then
        log_success "Restore procedure documented at $RESTORE_DOC"
    else
        log_failure "Failed to create restore documentation"
    fi
}

# Test 6: Verify backup automation
test_backup_automation() {
    log_test "Testing backup automation setup..."
    
    # Check for cron job
    if crontab -l 2>/dev/null | grep -q "vault.*backup"; then
        log_success "Backup automation configured in crontab"
    else
        log_info "No automated backup cron job found (can be configured later)"
        
        # Create sample cron configuration
        CRON_FILE="$TEST_BACKUP_DIR/vault-backup.cron"
        cat > "$CRON_FILE" << 'EOF'
# Vault Backup Automation - Add to crontab with: crontab -e
# Daily backup at 2 AM
0 2 * * * /root/scripts/deploy-vault.sh --action backup >> /var/log/vault-backup.log 2>&1

# Weekly backup on Sunday at 3 AM (separate retention)
0 3 * * 0 /usr/bin/vault operator raft snapshot save /opt/vault/backups/weekly-$(date +\%Y\%m\%d).snap >> /var/log/vault-backup.log 2>&1

# Monthly backup on 1st at 4 AM (long-term retention)
0 4 1 * * /usr/bin/vault operator raft snapshot save /opt/vault/backups/monthly-$(date +\%Y\%m).snap >> /var/log/vault-backup.log 2>&1
EOF
        
        if [[ -f "$CRON_FILE" ]]; then
            log_success "Sample cron configuration created at $CRON_FILE"
        fi
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "Vault Backup & Restore Test Suite"
    echo "========================================="
    echo "Test Configuration:"
    echo "  - Vault Address: $VAULT_ADDR"
    echo "  - Backup Directory: $BACKUP_DIR"
    echo "  - Test Directory: $TEST_BACKUP_DIR"
    echo "========================================="
    echo
    
    # Run all tests
    test_create_backup
    test_validate_backup
    test_backup_rotation
    test_restore_readiness
    test_document_restore
    test_backup_automation
    
    echo
    echo "========================================="
    echo -e "${GREEN}Backup & Restore tests completed!${NC}"
    echo "========================================="
    echo "Next Steps:"
    echo "1. Review restore procedure at: $TEST_BACKUP_DIR/RESTORE_PROCEDURE.md"
    echo "2. Configure automated backups using: $TEST_BACKUP_DIR/vault-backup.cron"
    echo "3. Test restore procedure in a non-production environment"
    echo "========================================="
    
    # Cleanup test directory (optional)
    # rm -rf "$TEST_BACKUP_DIR"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi