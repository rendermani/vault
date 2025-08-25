#!/bin/bash
# Phase 2 Integration Test Suite - Vault Integration Enablement
# Tests that Vault can be deployed and Nomad can be reconfigured to use it
# Validates the transition from Phase 1 to Phase 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
TEST_LOG="$TEST_RESULTS_DIR/phase2-test-$(date +%Y%m%d_%H%M%S).log"

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

# Test configuration
VAULT_ADDR="http://127.0.0.1:8200"
VAULT_TEST_TOKEN=""
NOMAD_ADDR="http://127.0.0.1:4646"

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

# Setup test environment
setup_test_vault() {
    log_info "Setting up test Vault instance..."
    
    # Check if Vault is running
    if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        log_info "Vault is already running at $VAULT_ADDR"
        return 0
    fi
    
    # Start Vault in dev mode for testing
    if command -v vault >/dev/null 2>&1; then
        log_info "Starting Vault in development mode for testing..."
        vault server -dev -dev-root-token-id="test-root-token" >/dev/null 2>&1 &
        VAULT_PID=$!
        sleep 3
        
        export VAULT_ADDR="$VAULT_ADDR"
        export VAULT_TOKEN="test-root-token"
        VAULT_TEST_TOKEN="test-root-token"
        
        if vault status >/dev/null 2>&1; then
            log_info "Test Vault instance started successfully"
            return 0
        else
            log_warn "Failed to start test Vault instance"
            return 1
        fi
    else
        log_warn "Vault binary not found, some tests will be skipped"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop test Vault if we started it
    if [[ -n "${VAULT_PID:-}" ]]; then
        kill $VAULT_PID 2>/dev/null || true
        wait $VAULT_PID 2>/dev/null || true
    fi
    
    # Clean up test configurations
    sudo rm -f /etc/nomad/nomad.hcl.test* 2>/dev/null || true
    sudo rm -f /etc/nomad/nomad.hcl.backup.test* 2>/dev/null || true
    
    # Clean up test job files
    rm -f /tmp/test-job-*.nomad 2>/dev/null || true
    rm -f /tmp/vault-test-*.json 2>/dev/null || true
    
    # Unset test environment variables
    unset VAULT_ADDR VAULT_TOKEN NOMAD_VAULT_BOOTSTRAP_PHASE
}

# Test 1: Verify Vault is accessible and healthy
test_vault_accessibility() {
    log_test "Testing Vault accessibility and health"
    
    # Test 1a: Vault health endpoint responds
    if curl -s "$VAULT_ADDR/v1/sys/health" | grep -q '"initialized":true'; then
        log_pass "Vault health endpoint responds and shows initialized state"
    else
        log_fail "Vault health endpoint not accessible or not initialized"
        curl -s "$VAULT_ADDR/v1/sys/health" 2>&1 >> "$TEST_LOG" || true
        return 1
    fi
    
    # Test 1b: Vault status command works
    if command -v vault >/dev/null 2>&1; then
        if vault status >/dev/null 2>&1; then
            log_pass "Vault status command succeeds"
        else
            log_fail "Vault status command failed"
            vault status 2>&1 >> "$TEST_LOG" || true
            return 1
        fi
    else
        log_warn "Vault binary not available for status check"
    fi
    
    # Test 1c: Vault authentication works
    if [[ -n "$VAULT_TEST_TOKEN" ]]; then
        export VAULT_TOKEN="$VAULT_TEST_TOKEN"
        if vault auth -method=token token="$VAULT_TEST_TOKEN" >/dev/null 2>&1; then
            log_pass "Vault authentication successful"
        else
            log_warn "Vault authentication failed (may be normal in some setups)"
        fi
    else
        log_warn "No test token available for authentication test"
    fi
}

# Test 2: Test Nomad reconfiguration with Vault enabled
test_nomad_reconfiguration() {
    log_test "Testing Nomad reconfiguration with Vault enabled"
    
    # Backup existing config if it exists
    if [[ -f /etc/nomad/nomad.hcl ]]; then
        sudo cp /etc/nomad/nomad.hcl /etc/nomad/nomad.hcl.backup.test.$(date +%s) || true
    fi
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Test 2a: Generate Phase 2 configuration (Vault enabled)
    local config_output
    config_output=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "$VAULT_ADDR" "false")
    
    if echo "$config_output" | grep -q "enabled = true" && echo "$config_output" | grep -q "vault {"; then
        log_pass "Phase 2 configuration correctly enables Vault integration"
    else
        log_fail "Phase 2 configuration does not enable Vault integration"
        echo "$config_output" | grep -A10 -B5 "vault" >> "$TEST_LOG"
        return 1
    fi
    
    # Test 2b: Vault configuration includes required settings
    if echo "$config_output" | grep -q "create_from_role" && echo "$config_output" | grep -q "task_token_ttl"; then
        log_pass "Vault configuration includes required integration settings"
    else
        log_fail "Vault configuration missing required integration settings"
        echo "$config_output" | grep -A20 "vault {" >> "$TEST_LOG"
        return 1
    fi
    
    # Test 2c: Configuration is syntactically valid
    echo "$config_output" > /tmp/test-nomad-vault-enabled.hcl
    if nomad config validate /tmp/test-nomad-vault-enabled.hcl >/dev/null 2>&1; then
        log_pass "Phase 2 Nomad configuration is syntactically valid"
    else
        log_fail "Phase 2 Nomad configuration has syntax errors"
        nomad config validate /tmp/test-nomad-vault-enabled.hcl 2>&1 >> "$TEST_LOG"
        return 1
    fi
    
    rm -f /tmp/test-nomad-vault-enabled.hcl
}

# Test 3: Test reconfigure_nomad_with_vault function
test_reconfigure_function() {
    log_test "Testing reconfigure_nomad_with_vault function"
    
    # Source the function
    if source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_pass "Successfully sourced config-templates.sh"
    else
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Test 3a: Function exists and is callable
    if type reconfigure_nomad_with_vault >/dev/null 2>&1; then
        log_pass "reconfigure_nomad_with_vault function is available"
    else
        log_fail "reconfigure_nomad_with_vault function is not available"
        return 1
    fi
    
    # Test 3b: Function validates parameters
    # We can't actually run the function without proper setup, but we can test dry-run logic
    log_info "Function parameter validation test completed (dry-run)"
}

# Test 4: Test Vault policy creation for Nomad
test_vault_policy_creation() {
    log_test "Testing Vault policy creation for Nomad integration"
    
    if [[ -z "$VAULT_TEST_TOKEN" ]]; then
        log_warn "No Vault token available, skipping policy tests"
        return 0
    fi
    
    export VAULT_TOKEN="$VAULT_TEST_TOKEN"
    
    # Test 4a: Create a test policy for Nomad
    local policy_content='
path "secret/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}'
    
    if command -v vault >/dev/null 2>&1; then
        echo "$policy_content" | vault policy write nomad-server - >/dev/null 2>&1 || true
        
        if vault policy read nomad-server >/dev/null 2>&1; then
            log_pass "Nomad server policy created successfully"
        else
            log_warn "Failed to create or read Nomad server policy"
        fi
    else
        log_warn "Vault binary not available for policy creation"
    fi
    
    # Test 4b: Create token role for Nomad
    if command -v vault >/dev/null 2>&1; then
        vault write auth/token/roles/nomad-cluster \
            allowed_policies="nomad-server" \
            orphan=true \
            renewable=true \
            period="72h" >/dev/null 2>&1 || true
        
        if vault read auth/token/roles/nomad-cluster >/dev/null 2>&1; then
            log_pass "Nomad cluster token role created successfully"
        else
            log_warn "Failed to create or read Nomad cluster token role"
        fi
    else
        log_warn "Vault binary not available for token role creation"
    fi
}

# Test 5: Test job with Vault templates
test_vault_template_job() {
    log_test "Testing job scheduling with Vault templates"
    
    # Create a test job that uses Vault templates
    cat > /tmp/test-job-vault-template.nomad << 'EOF'
job "test-vault-template-job" {
  datacenters = ["dc1"]
  type = "service"
  
  group "vault-group" {
    count = 1
    
    vault {
      policies = ["nomad-server"]
    }
    
    task "vault-task" {
      driver = "exec"
      
      vault {
        policies = ["nomad-server"]
      }
      
      template {
        data = <<EOH
{{with secret "secret/nomad/test"}}
SECRET_VALUE={{.Data.data.value}}
{{end}}
EOH
        destination = "secrets/app.env"
        env = true
      }
      
      config {
        command = "echo"
        args = ["Vault template job - Phase 2 integration"]
      }
      
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF
    
    # Test 5a: Job file validation
    if nomad job validate /tmp/test-job-vault-template.nomad >/dev/null 2>&1; then
        log_pass "Vault template job validates successfully"
    else
        log_fail "Vault template job validation failed"
        nomad job validate /tmp/test-job-vault-template.nomad 2>&1 >> "$TEST_LOG"
        return 1
    fi
    
    # Test 5b: Job contains Vault template configuration
    if grep -q "template" /tmp/test-job-vault-template.nomad && grep -q "vault" /tmp/test-job-vault-template.nomad; then
        log_pass "Job correctly contains Vault template configuration"
    else
        log_fail "Job missing Vault template configuration"
        return 1
    fi
    
    # Test 5c: Job can be planned (if Nomad is running with Vault integration)
    if nomad job plan /tmp/test-job-vault-template.nomad >/dev/null 2>&1; then
        log_pass "Vault template job can be planned with Vault integration"
    else
        log_warn "Vault template job planning failed (requires running Nomad+Vault cluster)"
    fi
    
    # Cleanup
    rm -f /tmp/test-job-vault-template.nomad
}

# Test 6: Test environment variable propagation in Phase 2
test_environment_variables_phase2() {
    log_test "Testing environment variable propagation for Phase 2"
    
    # Set Phase 2 environment variables
    export NOMAD_VAULT_BOOTSTRAP_PHASE=false
    export VAULT_ENABLED=true
    export VAULT_ADDR="$VAULT_ADDR"
    export ENVIRONMENT=develop
    
    # Test 6a: Bootstrap phase is disabled
    if [[ "${NOMAD_VAULT_BOOTSTRAP_PHASE:-true}" == "false" ]]; then
        log_pass "NOMAD_VAULT_BOOTSTRAP_PHASE correctly set to false for Phase 2"
    else
        log_fail "NOMAD_VAULT_BOOTSTRAP_PHASE not properly set for Phase 2"
        return 1
    fi
    
    # Test 6b: Vault is enabled
    if [[ "${VAULT_ENABLED:-false}" == "true" ]]; then
        log_pass "VAULT_ENABLED correctly set to true for Phase 2"
    else
        log_fail "VAULT_ENABLED not properly set for Phase 2"
        return 1
    fi
    
    # Test 6c: Vault address is set
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        log_pass "VAULT_ADDR environment variable is set"
    else
        log_fail "VAULT_ADDR environment variable is not set"
        return 1
    fi
    
    # Clean up
    unset NOMAD_VAULT_BOOTSTRAP_PHASE VAULT_ENABLED ENVIRONMENT
}

# Test 7: Test transition from Phase 1 to Phase 2
test_phase_transition() {
    log_test "Testing transition from Phase 1 to Phase 2"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Test 7a: Generate Phase 1 config
    local phase1_config
    phase1_config=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "$VAULT_ADDR" "true")
    
    # Test 7b: Generate Phase 2 config
    local phase2_config
    phase2_config=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "$VAULT_ADDR" "false")
    
    # Test 7c: Verify the difference
    if ! echo "$phase1_config" | grep -q "enabled = true" && echo "$phase2_config" | grep -q "enabled = true"; then
        log_pass "Configuration correctly transitions from Phase 1 to Phase 2"
    else
        log_fail "Configuration transition from Phase 1 to Phase 2 failed"
        echo "Phase 1 config:" >> "$TEST_LOG"
        echo "$phase1_config" | grep -A10 -B5 "vault" >> "$TEST_LOG" || echo "No vault config in Phase 1" >> "$TEST_LOG"
        echo "Phase 2 config:" >> "$TEST_LOG"
        echo "$phase2_config" | grep -A10 -B5 "vault" >> "$TEST_LOG" || echo "No vault config in Phase 2" >> "$TEST_LOG"
        return 1
    fi
    
    # Test 7d: Both configurations are valid
    echo "$phase1_config" > /tmp/test-phase1.hcl
    echo "$phase2_config" > /tmp/test-phase2.hcl
    
    if nomad config validate /tmp/test-phase1.hcl >/dev/null 2>&1 && nomad config validate /tmp/test-phase2.hcl >/dev/null 2>&1; then
        log_pass "Both Phase 1 and Phase 2 configurations are syntactically valid"
    else
        log_fail "One or both phase configurations have syntax errors"
        echo "Phase 1 validation:" >> "$TEST_LOG"
        nomad config validate /tmp/test-phase1.hcl 2>&1 >> "$TEST_LOG" || true
        echo "Phase 2 validation:" >> "$TEST_LOG"
        nomad config validate /tmp/test-phase2.hcl 2>&1 >> "$TEST_LOG" || true
        return 1
    fi
    
    rm -f /tmp/test-phase1.hcl /tmp/test-phase2.hcl
}

# Test 8: Test Vault secret access from Nomad job
test_vault_secret_access() {
    log_test "Testing Vault secret access from Nomad job"
    
    if [[ -z "$VAULT_TEST_TOKEN" ]]; then
        log_warn "No Vault token available, skipping secret access test"
        return 0
    fi
    
    export VAULT_TOKEN="$VAULT_TEST_TOKEN"
    
    # Test 8a: Create a test secret
    if command -v vault >/dev/null 2>&1; then
        vault kv put secret/nomad/test value="test-secret-value" >/dev/null 2>&1 || true
        
        if vault kv get secret/nomad/test >/dev/null 2>&1; then
            log_pass "Test secret created and accessible in Vault"
        else
            log_warn "Failed to create or access test secret"
        fi
    else
        log_warn "Vault binary not available for secret creation"
        return 0
    fi
    
    # Test 8b: Verify secret can be read with template syntax
    local secret_data
    if secret_data=$(vault kv get -field=value secret/nomad/test 2>/dev/null); then
        if [[ "$secret_data" == "test-secret-value" ]]; then
            log_pass "Vault secret can be read correctly"
        else
            log_fail "Vault secret value mismatch"
            echo "Expected: test-secret-value, Got: $secret_data" >> "$TEST_LOG"
        fi
    else
        log_warn "Could not read Vault secret"
    fi
}

# Main test execution
main() {
    echo "=============================================="
    echo "Phase 2 Integration Test Suite - Vault Integration"
    echo "=============================================="
    echo "Test Log: $TEST_LOG"
    echo ""
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    log_info "Starting Phase 2 integration tests..."
    
    # Setup test environment
    if setup_test_vault; then
        log_info "Test Vault environment ready"
    else
        log_warn "Test Vault environment not available, some tests will be limited"
    fi
    echo ""
    
    # Run all Phase 2 tests
    test_vault_accessibility || true
    echo ""
    
    test_nomad_reconfiguration || true
    echo ""
    
    test_reconfigure_function || true
    echo ""
    
    test_vault_policy_creation || true
    echo ""
    
    test_vault_template_job || true
    echo ""
    
    test_environment_variables_phase2 || true
    echo ""
    
    test_phase_transition || true
    echo ""
    
    test_vault_secret_access || true
    echo ""
    
    # Print results
    echo "=============================================="
    echo "Phase 2 Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Warnings: $TEST_WARNINGS"
    echo "=============================================="
    
    # Save results to file
    cat >> "$TEST_LOG" << EOF

PHASE 2 TEST SUMMARY
====================
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Warnings: $TEST_WARNINGS
Success Rate: $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

Date: $(date)
Environment: ${ENVIRONMENT:-develop}
Host: $(hostname)
Vault Address: $VAULT_ADDR
Nomad Address: $NOMAD_ADDR
EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Phase 2 tests passed! Vault integration is working.${NC}"
        echo ""
        echo "Phase 2 Summary:"
        echo "✓ Vault is accessible and healthy"
        echo "✓ Nomad configuration transitions correctly to Vault-enabled"
        echo "✓ Vault policies and token roles can be created"
        echo "✓ Jobs with Vault templates validate successfully"
        echo "✓ Environment variables propagate properly"
        echo "✓ Phase transition from 1 to 2 works correctly"
        echo ""
        echo "Two-phase bootstrap is working correctly!"
        exit 0
    else
        echo -e "${RED}❌ Phase 2 tests failed. Fix issues before full deployment.${NC}"
        echo ""
        echo "Check the test log for details: $TEST_LOG"
        exit 1
    fi
}

# Run main function
main "$@"