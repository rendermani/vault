#!/bin/bash

# HashiCorp Cleanup Script Test Suite
# This script tests the cleanup functionality without making destructive changes
# Author: Infrastructure Team
# Version: 1.0.0
# Date: 2025-08-25

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup-hashicorp.sh"
readonly RESTORE_SCRIPT="$SCRIPT_DIR/restore-hashicorp.sh"

# Test results
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "PASS")  echo -e "${GREEN}[PASS]${NC} $message"; ((TESTS_PASSED++)) ;;
        "FAIL")  echo -e "${RED}[FAIL]${NC} $message"; ((TESTS_FAILED++)) ;;
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
    esac
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo
    log "INFO" "Running test: $test_name"
    
    if $test_function; then
        log "PASS" "$test_name"
    else
        log "FAIL" "$test_name"
    fi
}

# Test if cleanup script exists and is executable
test_cleanup_script_exists() {
    [[ -f "$CLEANUP_SCRIPT" ]] && [[ -x "$CLEANUP_SCRIPT" ]]
}

# Test if restore script exists and is executable
test_restore_script_exists() {
    [[ -f "$RESTORE_SCRIPT" ]] && [[ -x "$RESTORE_SCRIPT" ]]
}

# Test cleanup script help functionality
test_cleanup_help() {
    "$CLEANUP_SCRIPT" --help >/dev/null 2>&1
}

# Test restore script help functionality  
test_restore_help() {
    "$RESTORE_SCRIPT" --help >/dev/null 2>&1
}

# Test cleanup script dry-run mode (requires root for full test)
test_cleanup_dry_run() {
    if [[ $EUID -eq 0 ]]; then
        "$CLEANUP_SCRIPT" --dry-run >/dev/null 2>&1
    else
        # Non-root test - just check if the script accepts the option
        "$CLEANUP_SCRIPT" --dry-run 2>&1 | grep -q "must be run as root"
    fi
}

# Test cleanup script parameter validation
test_cleanup_invalid_option() {
    ! "$CLEANUP_SCRIPT" --invalid-option >/dev/null 2>&1
}

# Test restore script parameter validation
test_restore_invalid_option() {
    ! "$RESTORE_SCRIPT" --invalid-option >/dev/null 2>&1
}

# Test script syntax by parsing without execution
test_cleanup_syntax() {
    bash -n "$CLEANUP_SCRIPT"
}

# Test restore script syntax
test_restore_syntax() {
    bash -n "$RESTORE_SCRIPT"
}

# Test backup directory creation logic (mock test)
test_backup_directory_logic() {
    # Test that backup directory naming follows expected pattern
    local expected_pattern="hashicorp-cleanup-backup-[0-9]{8}-[0-9]{6}"
    
    # Extract the backup directory creation logic from the script
    local backup_pattern=$(grep -o 'hashicorp-cleanup-backup-.*date.*' "$CLEANUP_SCRIPT" | head -1)
    
    [[ -n "$backup_pattern" ]]
}

# Test that required directories are defined
test_required_directories_defined() {
    grep -q "CONFIG_DIRS.*vault.d.*nomad.d.*consul.d" "$CLEANUP_SCRIPT" &&
    grep -q "DATA_DIRS.*var/lib/vault.*var/lib/nomad.*var/lib/consul" "$CLEANUP_SCRIPT" &&
    grep -q "OPT_DIRS.*opt/vault.*opt/nomad.*opt/consul" "$CLEANUP_SCRIPT"
}

# Test that required services are defined
test_required_services_defined() {
    grep -q 'SERVICES.*vault.*nomad.*consul' "$CLEANUP_SCRIPT"
}

# Test that required binaries are defined
test_required_binaries_defined() {
    grep -q 'BINARIES.*vault.*nomad.*consul' "$CLEANUP_SCRIPT"
}

# Test restore script can list backups (without actual backups)
test_restore_list_functionality() {
    "$RESTORE_SCRIPT" --list 2>&1 | grep -q "No backup directories found"
}

# Test logging functions exist in both scripts
test_logging_functions() {
    grep -q "^log()" "$CLEANUP_SCRIPT" &&
    grep -q "^log()" "$RESTORE_SCRIPT"
}

# Test confirmation functions exist
test_confirmation_functions() {
    grep -q "confirm_action" "$CLEANUP_SCRIPT"
}

# Test backup functions exist
test_backup_functions() {
    grep -q "backup_item" "$CLEANUP_SCRIPT" &&
    grep -q "setup_backup_dir" "$CLEANUP_SCRIPT"
}

# Test verification functions exist
test_verification_functions() {
    grep -q "verify_cleanup" "$CLEANUP_SCRIPT" &&
    grep -q "verify_restoration" "$RESTORE_SCRIPT"
}

# Test that scripts handle signals properly
test_signal_handling() {
    grep -q "set -euo pipefail" "$CLEANUP_SCRIPT" &&
    grep -q "set -euo pipefail" "$RESTORE_SCRIPT"
}

# Test documentation completeness
test_documentation_exists() {
    local doc_file="$SCRIPT_DIR/../docs/CLEANUP_RESTORE_GUIDE.md"
    [[ -f "$doc_file" ]] && [[ -s "$doc_file" ]]
}

# Performance test - check script execution time for help
test_performance_help() {
    local start_time=$(date +%s.%N)
    "$CLEANUP_SCRIPT" --help >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "1")
    
    # Should complete help in less than 2 seconds
    (( $(echo "$duration < 2" | bc -l 2>/dev/null || echo "1") ))
}

# Test that scripts don't contain hardcoded paths that might be dangerous
test_no_dangerous_hardcoded_paths() {
    ! grep -q "rm -rf /" "$CLEANUP_SCRIPT" &&
    ! grep -q "rm -rf /etc" "$CLEANUP_SCRIPT" &&
    ! grep -q "rm -rf /var" "$CLEANUP_SCRIPT"
}

# Test that backup operations come before removal operations in cleanup script
test_backup_before_removal() {
    local backup_line=$(grep -n "Creating backups" "$CLEANUP_SCRIPT" | cut -d: -f1)
    local removal_line=$(grep -n "Starting cleanup operations" "$CLEANUP_SCRIPT" | cut -d: -f1)
    
    [[ -n "$backup_line" ]] && [[ -n "$removal_line" ]] && [[ "$backup_line" -lt "$removal_line" ]]
}

# Main test runner
main() {
    echo "HashiCorp Cleanup Script Test Suite"
    echo "==================================="
    echo "Testing scripts in: $SCRIPT_DIR"
    echo
    
    # Check if bc is available for performance tests
    if ! command -v bc >/dev/null 2>&1; then
        log "WARN" "bc not available, skipping performance tests"
    fi
    
    # Basic existence tests
    run_test "Cleanup script exists and is executable" test_cleanup_script_exists
    run_test "Restore script exists and is executable" test_restore_script_exists
    
    # Help functionality tests
    run_test "Cleanup script help functionality" test_cleanup_help
    run_test "Restore script help functionality" test_restore_help
    
    # Parameter validation tests
    run_test "Cleanup script invalid option handling" test_cleanup_invalid_option
    run_test "Restore script invalid option handling" test_restore_invalid_option
    
    # Syntax tests
    run_test "Cleanup script syntax validation" test_cleanup_syntax
    run_test "Restore script syntax validation" test_restore_syntax
    
    # Logic tests
    run_test "Backup directory logic" test_backup_directory_logic
    run_test "Required directories defined" test_required_directories_defined
    run_test "Required services defined" test_required_services_defined
    run_test "Required binaries defined" test_required_binaries_defined
    
    # Functionality tests
    run_test "Restore list functionality" test_restore_list_functionality
    run_test "Logging functions exist" test_logging_functions
    run_test "Confirmation functions exist" test_confirmation_functions
    run_test "Backup functions exist" test_backup_functions
    run_test "Verification functions exist" test_verification_functions
    
    # Safety tests
    run_test "Signal handling configured" test_signal_handling
    run_test "No dangerous hardcoded paths" test_no_dangerous_hardcoded_paths
    run_test "Backup operations before removal" test_backup_before_removal
    
    # Documentation tests
    run_test "Documentation exists" test_documentation_exists
    
    # Performance tests (if bc available)
    if command -v bc >/dev/null 2>&1; then
        run_test "Help performance" test_performance_help
    fi
    
    # Advanced tests (require root)
    if [[ $EUID -eq 0 ]]; then
        run_test "Cleanup dry-run mode" test_cleanup_dry_run
    else
        log "INFO" "Skipping root-required tests (run with sudo for complete testing)"
    fi
    
    # Summary
    echo
    echo "Test Results:"
    echo "============="
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Total tests:  $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
HashiCorp Cleanup Script Test Suite

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --help, -h       Show this help message

DESCRIPTION:
    This script tests the cleanup-hashicorp.sh and restore-hashicorp.sh scripts
    to ensure they function correctly and safely.

    Tests include:
    - Script existence and permissions
    - Syntax validation
    - Parameter handling
    - Safety checks
    - Logic validation
    - Performance checks (basic)

    Some tests require root privileges for complete validation.

EXAMPLES:
    $0                    # Run all tests
    sudo $0               # Run all tests including root-required ones

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log "WARN" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run tests
main