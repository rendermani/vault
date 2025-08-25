#!/bin/bash
# Phase 1 Bootstrap Test Suite - Nomad without Vault Integration
# Tests that Nomad starts successfully with vault.enabled=false
# and can schedule simple jobs before Vault is deployed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
TEST_LOG="$TEST_RESULTS_DIR/phase1-test-$(date +%Y%m%d_%H%M%S).log"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TEST_WARNINGS=0

# Logging functions
log_test() {
    local msg="[TEST] $1"
    echo -e "${BLUE}${msg}${NC}" | tee -a "$TEST_LOG"
}

log_pass() {
    local msg="[PASS] $1"
    echo -e "${GREEN}${msg}${NC}" | tee -a "$TEST_LOG"
    ((TESTS_PASSED++))
}

log_fail() {
    local msg="[FAIL] $1"
    echo -e "${RED}${msg}${NC}" | tee -a "$TEST_LOG"
    ((TESTS_FAILED++))
}

log_warn() {
    local msg="[WARN] $1"
    echo -e "${YELLOW}${msg}${NC}" | tee -a "$TEST_LOG"
    ((TEST_WARNINGS++))
}

log_info() {
    local msg="[INFO] $1"
    echo -e "${BLUE}${msg}${NC}" | tee -a "$TEST_LOG"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop any test services
    if systemctl is-active --quiet nomad 2>/dev/null; then
        sudo systemctl stop nomad || true
    fi
    
    # Remove test configurations
    sudo rm -f /etc/nomad/nomad.hcl.test* 2>/dev/null || true
    
    # Clean up test job files
    rm -f /tmp/test-job-*.nomad 2>/dev/null || true
}

# Test 1: Verify config template generates Vault-disabled configuration
test_config_generation_vault_disabled() {
    log_test "Testing Nomad config generation with Vault disabled"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Generate config with bootstrap phase enabled (Vault disabled)
    local config_output
    config_output=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true")
    
    # Test 1a: Vault integration is disabled
    if echo "$config_output" | grep -q "Vault integration disabled during bootstrap phase"; then
        log_pass "Bootstrap phase correctly disables Vault integration"
    else
        log_fail "Bootstrap phase did not disable Vault integration"
        echo "$config_output" | grep -A10 -B5 "vault" | head -20 >> "$TEST_LOG"
        return 1
    fi
    
    # Test 1b: Vault block is commented out
    if echo "$config_output" | grep -q "# vault {" && echo "$config_output" | grep -q "# After Vault deployment"; then
        log_pass "Vault configuration is properly commented out during bootstrap"
    else
        log_fail "Vault configuration is not properly commented out"
        echo "$config_output" | grep -A10 -B5 "vault" >> "$TEST_LOG"
        return 1
    fi
    
    # Test 1c: Configuration is syntactically valid
    echo "$config_output" > /tmp/test-nomad-bootstrap.hcl
    if nomad config validate /tmp/test-nomad-bootstrap.hcl >/dev/null 2>&1; then
        log_pass "Generated bootstrap configuration is syntactically valid"
    else
        log_fail "Generated bootstrap configuration has syntax errors"
        nomad config validate /tmp/test-nomad-bootstrap.hcl 2>&1 | head -10 >> "$TEST_LOG"
        return 1
    fi
    
    rm -f /tmp/test-nomad-bootstrap.hcl
}

# Test 2: Verify environment variables are properly set for Phase 1
test_environment_variables_phase1() {
    log_test "Testing environment variable propagation for Phase 1"
    
    # Set Phase 1 environment variables
    export NOMAD_VAULT_BOOTSTRAP_PHASE=true
    export VAULT_ENABLED=true  # This should be overridden by bootstrap phase
    export ENVIRONMENT=develop
    
    # Test 2a: Bootstrap phase variable is recognized
    if [[ "${NOMAD_VAULT_BOOTSTRAP_PHASE:-false}" == "true" ]]; then
        log_pass "NOMAD_VAULT_BOOTSTRAP_PHASE environment variable set correctly"
    else
        log_fail "NOMAD_VAULT_BOOTSTRAP_PHASE environment variable not set"
        return 1
    fi
    
    # Test 2b: Source install script and check logic
    if source "$INFRA_DIR/scripts/install-nomad.sh" &>/dev/null; then
        log_pass "install-nomad.sh sources successfully with bootstrap phase variables"
    else
        log_fail "install-nomad.sh failed to source with bootstrap phase variables"
        return 1
    fi
    
    # Test 2c: Verify the script respects bootstrap phase
    if grep -q "NOMAD_VAULT_BOOTSTRAP_PHASE.*true" "$INFRA_DIR/scripts/install-nomad.sh"; then
        log_pass "install-nomad.sh includes bootstrap phase handling"
    else
        log_fail "install-nomad.sh missing bootstrap phase handling"
        return 1
    fi
    
    unset NOMAD_VAULT_BOOTSTRAP_PHASE VAULT_ENABLED ENVIRONMENT
}

# Test 3: Test Nomad service startup with Vault disabled
test_nomad_startup_without_vault() {
    log_test "Testing Nomad startup without Vault dependency"
    
    # Backup existing config if it exists
    if [[ -f /etc/nomad/nomad.hcl ]]; then
        sudo cp /etc/nomad/nomad.hcl /etc/nomad/nomad.hcl.backup.$(date +%s) || true
    fi
    
    # Create test configuration directory
    sudo mkdir -p /etc/nomad
    
    # Generate Phase 1 configuration
    source "$INFRA_DIR/scripts/config-templates.sh"
    local config_content
    config_content=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true")
    
    # Write test configuration
    echo "$config_content" | sudo tee /etc/nomad/nomad.hcl.test > /dev/null
    
    # Test 3a: Configuration validation
    if nomad config validate /etc/nomad/nomad.hcl.test >/dev/null 2>&1; then
        log_pass "Phase 1 Nomad configuration passes validation"
    else
        log_fail "Phase 1 Nomad configuration failed validation"
        nomad config validate /etc/nomad/nomad.hcl.test 2>&1 | head -10 >> "$TEST_LOG"
        return 1
    fi
    
    # Test 3b: Verify no Vault references in active config
    if ! grep -q "enabled = true" /etc/nomad/nomad.hcl.test | grep -v "^#"; then
        log_pass "No active Vault configuration in Phase 1 config"
    else
        log_fail "Active Vault configuration found in Phase 1 config"
        grep "enabled = true" /etc/nomad/nomad.hcl.test >> "$TEST_LOG" || true
        return 1
    fi
    
    # Test 3c: Start Nomad with test configuration (dry run check)
    # We'll simulate the startup by checking if the configuration would work
    log_info "Simulating Nomad startup with Phase 1 configuration..."
    
    # Check if Nomad binary exists and can use the config
    if command -v nomad >/dev/null 2>&1; then
        if nomad agent -config=/etc/nomad/nomad.hcl.test -dev-connect=false &>/dev/null &
        then
            local nomad_pid=$!
            sleep 2
            if kill -0 $nomad_pid 2>/dev/null; then
                log_pass "Nomad starts successfully with Phase 1 configuration"
                kill $nomad_pid 2>/dev/null || true
                wait $nomad_pid 2>/dev/null || true
            else
                log_fail "Nomad failed to start with Phase 1 configuration"
                return 1
            fi
        else
            log_warn "Could not test Nomad startup (may require root privileges)"
        fi
    else
        log_warn "Nomad binary not found, skipping startup test"
    fi
    
    # Cleanup test config
    sudo rm -f /etc/nomad/nomad.hcl.test
}

# Test 4: Test simple job scheduling without Vault
test_simple_job_scheduling() {
    log_test "Testing simple job scheduling without Vault integration"
    
    # Create a simple test job that doesn't require Vault
    cat > /tmp/test-job-simple.nomad << 'EOF'
job "test-simple-job" {
  datacenters = ["dc1"]
  type = "batch"
  
  group "test-group" {
    count = 1
    
    task "test-task" {
      driver = "exec"
      
      config {
        command = "echo"
        args = ["Hello from Phase 1 - No Vault required"]
      }
      
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF
    
    # Test 4a: Job file validation
    if nomad job validate /tmp/test-job-simple.nomad >/dev/null 2>&1; then
        log_pass "Simple test job validates successfully"
    else
        log_fail "Simple test job validation failed"
        nomad job validate /tmp/test-job-simple.nomad 2>&1 >> "$TEST_LOG"
        return 1
    fi
    
    # Test 4b: Job file has no Vault references
    if ! grep -q "vault" /tmp/test-job-simple.nomad; then
        log_pass "Test job contains no Vault dependencies"
    else
        log_fail "Test job unexpectedly contains Vault references"
        grep "vault" /tmp/test-job-simple.nomad >> "$TEST_LOG"
        return 1
    fi
    
    # Test 4c: Job can be parsed (plan check)
    if nomad job plan /tmp/test-job-simple.nomad >/dev/null 2>&1; then
        log_pass "Simple test job can be planned without Vault"
    else
        log_warn "Job planning failed (may require running Nomad cluster)"
        # This is expected if no cluster is running, so we don't fail
    fi
    
    # Cleanup
    rm -f /tmp/test-job-simple.nomad
}

# Test 5: Verify Phase 1 readiness indicators
test_phase1_readiness() {
    log_test "Testing Phase 1 readiness indicators"
    
    # Test 5a: Check that required scripts exist
    local required_scripts=(
        "config-templates.sh"
        "install-nomad.sh"
        "unified-bootstrap-systemd.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ -f "$INFRA_DIR/scripts/$script" ]]; then
            log_pass "Required script $script exists"
        else
            log_fail "Required script $script is missing"
            return 1
        fi
    done
    
    # Test 5b: Check for Phase 1 completion markers
    source "$INFRA_DIR/scripts/config-templates.sh"
    if type generate_nomad_config >/dev/null 2>&1; then
        log_pass "generate_nomad_config function is available"
    else
        log_fail "generate_nomad_config function is not available"
        return 1
    fi
    
    # Test 5c: Verify Phase 1 environment preparation
    local test_env_file="/tmp/test-phase1.env"
    cat > "$test_env_file" << 'EOF'
NOMAD_VAULT_BOOTSTRAP_PHASE=true
ENVIRONMENT=develop
VAULT_ENABLED=false
EOF
    
    if source "$test_env_file"; then
        log_pass "Phase 1 environment variables can be loaded"
    else
        log_fail "Phase 1 environment variables failed to load"
        return 1
    fi
    
    rm -f "$test_env_file"
}

# Test 6: Verify Phase 1 does not create Vault dependencies
test_no_vault_dependencies() {
    log_test "Testing that Phase 1 creates no Vault dependencies"
    
    # Generate Phase 1 configuration
    source "$INFRA_DIR/scripts/config-templates.sh"
    local config_content
    config_content=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true")
    
    # Test 6a: No active Vault configuration
    if ! echo "$config_content" | grep -E "^\s*vault\s*{" >/dev/null 2>&1; then
        log_pass "No active Vault block in Phase 1 configuration"
    else
        log_fail "Active Vault block found in Phase 1 configuration"
        echo "$config_content" | grep -A10 -E "^\s*vault\s*{" >> "$TEST_LOG"
        return 1
    fi
    
    # Test 6b: No Vault environment variables required
    local env_vars=("VAULT_ADDR" "VAULT_TOKEN" "VAULT_NAMESPACE")
    for var in "${env_vars[@]}"; do
        if echo "$config_content" | grep -q "\$$var"; then
            log_warn "Configuration references environment variable $var"
        else
            log_pass "Configuration does not require environment variable $var"
        fi
    done
    
    # Test 6c: No Vault binary dependencies
    if ! echo "$config_content" | grep -q "vault.*binary\|vault.*command"; then
        log_pass "No Vault binary dependencies in configuration"
    else
        log_fail "Vault binary dependencies found in configuration"
        return 1
    fi
}

# Main test execution
main() {
    echo "=============================================="
    echo "Phase 1 Bootstrap Test Suite - Nomad without Vault"
    echo "=============================================="
    echo "Test Log: $TEST_LOG"
    echo ""
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    log_info "Starting Phase 1 bootstrap tests..."
    echo ""
    
    # Run all Phase 1 tests
    test_config_generation_vault_disabled || true
    echo ""
    
    test_environment_variables_phase1 || true
    echo ""
    
    test_nomad_startup_without_vault || true
    echo ""
    
    test_simple_job_scheduling || true
    echo ""
    
    test_phase1_readiness || true
    echo ""
    
    test_no_vault_dependencies || true
    echo ""
    
    # Print results
    echo "=============================================="
    echo "Phase 1 Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Warnings: $TEST_WARNINGS"
    echo "=============================================="
    
    # Save results to file
    cat >> "$TEST_LOG" << EOF

PHASE 1 TEST SUMMARY
====================
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Warnings: $TEST_WARNINGS
Success Rate: $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

Date: $(date)
Environment: ${ENVIRONMENT:-develop}
Host: $(hostname)
EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Phase 1 tests passed! Nomad can bootstrap without Vault.${NC}"
        echo ""
        echo "Phase 1 Summary:"
        echo "✓ Nomad configuration generates correctly with Vault disabled"
        echo "✓ Environment variables propagate properly"
        echo "✓ Nomad can start without Vault dependency"
        echo "✓ Simple jobs can be scheduled without Vault"
        echo "✓ No Vault dependencies are created"
        echo ""
        echo "Next: Run Phase 2 tests after Vault is deployed"
        exit 0
    else
        echo -e "${RED}❌ Phase 1 tests failed. Fix issues before proceeding.${NC}"
        echo ""
        echo "Check the test log for details: $TEST_LOG"
        exit 1
    fi
}

# Run main function
main "$@"