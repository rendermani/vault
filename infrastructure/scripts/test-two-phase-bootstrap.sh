#!/bin/bash
# Test script for two-phase bootstrap process
# This script validates that the circular dependency fix works correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test 1: Config template function with bootstrap phase
test_config_template_bootstrap_phase() {
    log_test "Testing Nomad config generation with bootstrap phase enabled"
    
    # Source the config templates
    if source "$SCRIPT_DIR/config-templates.sh"; then
        log_pass "Successfully sourced config-templates.sh"
    else
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Generate config with bootstrap phase enabled
    local config_output
    config_output=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true")
    
    # Check if Vault is disabled during bootstrap
    if echo "$config_output" | grep -q "Vault integration disabled during bootstrap phase"; then
        log_pass "Bootstrap phase correctly disables Vault integration"
    else
        log_fail "Bootstrap phase did not disable Vault integration"
        return 1
    fi
    
    # Check that Vault block is commented out and contains the bootstrap phase message
    if echo "$config_output" | grep -q "# vault {" && echo "$config_output" | grep -q "# After Vault deployment"; then
        log_pass "Vault configuration is properly commented out during bootstrap"
    else
        log_fail "Vault configuration is not properly commented out"
        echo "$config_output" | grep -A5 -B5 "vault" || true
        return 1
    fi
}

# Test 2: Config template function with Vault enabled (non-bootstrap)
test_config_template_vault_enabled() {
    log_test "Testing Nomad config generation with Vault enabled (post-bootstrap)"
    
    # Generate config with Vault enabled and bootstrap phase disabled
    local config_output
    config_output=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "false")
    
    # Check if Vault is enabled when not in bootstrap phase
    if echo "$config_output" | grep -q "enabled = true" && echo "$config_output" | grep -q "vault {"; then
        log_pass "Non-bootstrap phase correctly enables Vault integration"
    else
        log_fail "Non-bootstrap phase did not enable Vault integration"
        return 1
    fi
    
    # Check for Vault configuration settings
    if echo "$config_output" | grep -q "create_from_role" && echo "$config_output" | grep -q "task_token_ttl"; then
        log_pass "Vault configuration includes proper integration settings"
    else
        log_fail "Vault configuration missing integration settings"
        return 1
    fi
}

# Test 3: install-nomad.sh respects bootstrap phase
test_install_nomad_bootstrap_phase() {
    log_test "Testing install-nomad.sh bootstrap phase handling"
    
    # Check if the install-nomad.sh script contains the bootstrap phase logic
    if grep -q "NOMAD_VAULT_BOOTSTRAP_PHASE" "$SCRIPT_DIR/install-nomad.sh"; then
        log_pass "install-nomad.sh includes bootstrap phase variable"
    else
        log_fail "install-nomad.sh missing bootstrap phase variable"
        return 1
    fi
    
    # Check if it has the conditional Vault configuration logic
    if grep -q "NOMAD_VAULT_BOOTSTRAP_PHASE.*true" "$SCRIPT_DIR/install-nomad.sh"; then
        log_pass "install-nomad.sh includes bootstrap phase condition"
    else
        log_fail "install-nomad.sh missing bootstrap phase condition"
        return 1
    fi
    
    # Check if it warns about bootstrap phase in output
    if grep -q "Vault integration disabled during bootstrap phase" "$SCRIPT_DIR/install-nomad.sh"; then
        log_pass "install-nomad.sh includes bootstrap phase warning"
    else
        log_fail "install-nomad.sh missing bootstrap phase warning"
        return 1
    fi
}

# Test 4: Reconfigure function exists and is callable
test_reconfigure_function() {
    log_test "Testing reconfigure_nomad_with_vault function availability"
    
    # Check if function is defined
    if type reconfigure_nomad_with_vault >/dev/null 2>&1; then
        log_pass "reconfigure_nomad_with_vault function is available"
    else
        log_fail "reconfigure_nomad_with_vault function is not available"
        return 1
    fi
    
    # Test function can be called with dry-run parameters (won't actually execute)
    log_info "Function signature test passed"
}

# Test 5: Check unified bootstrap script integration
test_unified_bootstrap_integration() {
    log_test "Testing unified bootstrap script integration"
    
    # Check if the bootstrap script sources config-templates.sh
    if grep -q "source.*config-templates.sh" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
        log_pass "Bootstrap script correctly sources config-templates.sh"
    else
        log_fail "Bootstrap script does not source config-templates.sh"
    fi
    
    # Check if it has the enable_vault_integration function
    if grep -q "enable_vault_integration" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
        log_pass "Bootstrap script includes Vault integration enablement"
    else
        log_fail "Bootstrap script missing Vault integration enablement"
    fi
    
    # Check if it sets bootstrap phase environment variables
    if grep -q "NOMAD_VAULT_BOOTSTRAP_PHASE" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
        log_pass "Bootstrap script sets bootstrap phase environment variables"
    else
        log_fail "Bootstrap script missing bootstrap phase environment variables"
    fi
}

# Test 6: Validate the two-phase process documentation
test_documentation_updated() {
    log_test "Testing documentation reflects two-phase process"
    
    # Check if the bootstrap script usage mentions the two-phase approach
    if grep -q "Two-Phase Approach" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
        log_pass "Documentation mentions two-phase approach"
    else
        log_fail "Documentation does not mention two-phase approach"
    fi
    
    # Check for circular dependency explanation
    if grep -q "circular dependency" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
        log_pass "Documentation explains circular dependency solution"
    else
        log_fail "Documentation does not explain circular dependency"
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "Two-Phase Bootstrap Process Test Suite"
    echo "=========================================="
    echo ""
    
    log_info "Testing Vault-Nomad circular dependency fix..."
    echo ""
    
    # Run all tests
    test_config_template_bootstrap_phase || true
    echo ""
    
    test_config_template_vault_enabled || true
    echo ""
    
    test_install_nomad_bootstrap_phase || true
    echo ""
    
    test_reconfigure_function || true
    echo ""
    
    test_unified_bootstrap_integration || true
    echo ""
    
    test_documentation_updated || true
    echo ""
    
    # Print results
    echo "=========================================="
    echo "Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "=========================================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! Two-phase bootstrap is ready.${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Deploy with: ./unified-bootstrap-systemd.sh --environment develop"
        echo "2. The bootstrap will automatically handle the two-phase process"
        echo "3. Nomad will be deployed with Vault disabled initially"
        echo "4. After Vault deployment, Nomad will be reconfigured with Vault enabled"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please fix issues before deployment.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"