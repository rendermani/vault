#!/bin/bash

# Test script to verify two-phase bootstrap configuration generation
# This validates that Vault integration is properly disabled/enabled in different phases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

# Test configuration generation
test_configuration_generation() {
    local test_name="$1"
    local vault_enabled="$2"
    local bootstrap_phase="$3"
    local expected_vault_enabled="$4"
    
    log_header "TEST: $test_name"
    log_info "Parameters: vault_enabled=$vault_enabled, bootstrap_phase=$bootstrap_phase"
    log_info "Expected: Vault enabled=$expected_vault_enabled"
    
    # Source config templates
    if [[ -f "$SCRIPT_DIR/config-templates.sh" ]]; then
        source "$SCRIPT_DIR/config-templates.sh"
    else
        log_error "config-templates.sh not found: $SCRIPT_DIR/config-templates.sh"
        return 1
    fi
    
    # Create temporary file for test
    local temp_config=$(mktemp)
    
    # Generate configuration
    generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
        "both" "test-encrypt-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
        "$vault_enabled" "http://localhost:8200" "$bootstrap_phase" > "$temp_config"
    
    # Check if configuration is valid
    log_info "Generated configuration:"
    if grep -A10 -B2 "vault {" "$temp_config"; then
        # Check if Vault is enabled/disabled as expected
        if grep -A5 -B5 "vault {" "$temp_config" | grep -q "enabled = $expected_vault_enabled"; then
            log_success "✅ Configuration correct: Vault enabled = $expected_vault_enabled"
        else
            log_error "❌ Configuration incorrect: Expected Vault enabled = $expected_vault_enabled"
            log_error "Actual configuration:"
            grep -A10 -B2 "vault {" "$temp_config"
            rm "$temp_config"
            return 1
        fi
    else
        if [[ "$expected_vault_enabled" == "false" ]]; then
            log_success "✅ Configuration correct: No vault block found (expected for disabled state)"
        else
            log_error "❌ Configuration incorrect: No vault block found but expected enabled = $expected_vault_enabled"
            rm "$temp_config"
            return 1
        fi
    fi
    
    # Cleanup
    rm "$temp_config"
    echo ""
    return 0
}

# Main test execution
main() {
    log_header "TWO-PHASE BOOTSTRAP CONFIGURATION TEST"
    echo ""
    
    local tests_passed=0
    local tests_failed=0
    
    # Test 1: Bootstrap Phase 1 (should disable Vault)
    if test_configuration_generation "Phase 1 - Bootstrap with Vault disabled" "false" "true" "false"; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 2: Bootstrap Phase 1 even when vault_enabled=true (should still disable)
    if test_configuration_generation "Phase 1 - Bootstrap overrides vault_enabled=true" "true" "true" "false"; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 3: Phase 2 - Vault integration enabled
    if test_configuration_generation "Phase 2 - Vault integration enabled" "true" "false" "true"; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    
    # Test 4: Normal operation with Vault disabled
    if test_configuration_generation "Normal operation - Vault disabled" "false" "false" "false"; then
        tests_passed=$((tests_passed + 1))
    else
        tests_failed=$((tests_failed + 1))
    fi
    
    # Summary
    log_header "TEST SUMMARY"
    echo -e "${WHITE}Tests Passed:${NC} ${GREEN}$tests_passed${NC}"
    echo -e "${WHITE}Tests Failed:${NC} ${RED}$tests_failed${NC}"
    
    if [[ $tests_failed -eq 0 ]]; then
        log_success "🎉 ALL TESTS PASSED! Two-phase bootstrap configuration is working correctly."
        return 0
    else
        log_error "❌ Some tests failed. Configuration generation needs fixes."
        return 1
    fi
}

# Execute main function
main "$@"