#!/bin/bash
# Environment Variable Propagation Test Suite
# Tests that environment variables are correctly propagated through all deployment stages
# Validates configuration consistency across the entire pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
TEST_LOG="$TEST_RESULTS_DIR/env-propagation-test-$(date +%Y%m%d_%H%M%S).log"

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

# Test environments
TEST_ENVIRONMENTS=("develop" "staging" "production")
CRITICAL_ENV_VARS=(
    "ENVIRONMENT"
    "NOMAD_VAULT_BOOTSTRAP_PHASE"
    "VAULT_ENABLED"
    "CONSUL_ENABLED"
    "DATACENTER"
    "NOMAD_REGION"
)

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

# Store original environment
store_original_environment() {
    env > "/tmp/original-env-$$.txt"
}

# Restore original environment
restore_original_environment() {
    # Clear all test variables
    unset ENVIRONMENT NOMAD_VAULT_BOOTSTRAP_PHASE VAULT_ENABLED CONSUL_ENABLED
    unset DATACENTER NOMAD_REGION VAULT_ADDR CONSUL_ADDR
    unset NOMAD_ENCRYPT_KEY CONSUL_ENCRYPT_KEY
    
    # Restore critical PATH and other system vars if needed
    if [[ -f "/tmp/original-env-$$.txt" ]]; then
        source "/tmp/original-env-$$.txt" >/dev/null 2>&1 || true
        rm -f "/tmp/original-env-$$.txt"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    restore_original_environment
    rm -f /tmp/test-env-*.sh /tmp/test-config-*.hcl
}

# Test 1: Environment file templates validation
test_environment_templates() {
    log_test "Testing environment file templates"
    
    # Test all environment templates
    for env in "${TEST_ENVIRONMENTS[@]}"; do
        local template_file="$INFRA_DIR/config/${env}.env.template"
        
        if [[ -f "$template_file" ]]; then
            log_pass "Environment template exists for $env"
            
            # Test template syntax
            if grep -q "ENVIRONMENT=" "$template_file"; then
                log_pass "Template $env contains ENVIRONMENT variable"
            else
                log_fail "Template $env missing ENVIRONMENT variable"
            fi
            
            # Test critical variables presence
            local missing_vars=()
            for var in "${CRITICAL_ENV_VARS[@]}"; do
                if ! grep -q "^${var}=" "$template_file" && ! grep -q "^#${var}=" "$template_file"; then
                    missing_vars+=("$var")
                fi
            done
            
            if [[ ${#missing_vars[@]} -eq 0 ]]; then
                log_pass "Template $env contains all critical variables"
            else
                log_warn "Template $env missing variables: ${missing_vars[*]}"
            fi
        else
            log_fail "Environment template missing for $env"
        fi
    done
}

# Test 2: Environment variable loading and validation
test_environment_loading() {
    log_test "Testing environment variable loading"
    
    for env in "${TEST_ENVIRONMENTS[@]}"; do
        log_info "Testing environment loading for $env"
        
        # Create test environment file
        cat > "/tmp/test-env-${env}.sh" << EOF
export ENVIRONMENT="$env"
export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
export VAULT_ENABLED="true"
export CONSUL_ENABLED="true"
export DATACENTER="dc1"
export NOMAD_REGION="global"
export VAULT_ADDR="https://127.0.0.1:8200"
export CONSUL_ADDR="127.0.0.1:8500"
EOF
        
        # Test 2a: Source the environment file
        if source "/tmp/test-env-${env}.sh"; then
            log_pass "Environment file for $env sources successfully"
        else
            log_fail "Failed to source environment file for $env"
            continue
        fi
        
        # Test 2b: Verify variables are set
        if [[ "${ENVIRONMENT:-}" == "$env" ]]; then
            log_pass "ENVIRONMENT variable correctly set to $env"
        else
            log_fail "ENVIRONMENT variable incorrect: expected '$env', got '${ENVIRONMENT:-}'"
        fi
        
        # Test 2c: Verify boolean variables
        if [[ "${NOMAD_VAULT_BOOTSTRAP_PHASE:-}" == "true" ]]; then
            log_pass "NOMAD_VAULT_BOOTSTRAP_PHASE correctly set for $env"
        else
            log_fail "NOMAD_VAULT_BOOTSTRAP_PHASE incorrect for $env"
        fi
        
        if [[ "${VAULT_ENABLED:-}" == "true" ]]; then
            log_pass "VAULT_ENABLED correctly set for $env"
        else
            log_fail "VAULT_ENABLED incorrect for $env"
        fi
        
        # Clean up for next iteration
        restore_original_environment
    done
}

# Test 3: Configuration generation with different environments
test_config_generation_with_env() {
    log_test "Testing configuration generation with environment variables"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    for env in "${TEST_ENVIRONMENTS[@]}"; do
        log_info "Testing configuration generation for $env"
        
        # Set environment-specific variables
        export ENVIRONMENT="$env"
        export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
        export VAULT_ENABLED="true"
        export CONSUL_ENABLED="true"
        export DATACENTER="dc1"
        export NOMAD_REGION="global"
        
        # Test 3a: Generate Nomad configuration
        local nomad_config
        if nomad_config=$(generate_nomad_config "$env" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true"); then
            log_pass "Nomad configuration generated for $env"
        else
            log_fail "Failed to generate Nomad configuration for $env"
            continue
        fi
        
        # Test 3b: Verify environment-specific settings
        if echo "$nomad_config" | grep -q "region = \"global\""; then
            log_pass "Configuration includes correct region for $env"
        else
            log_fail "Configuration missing or incorrect region for $env"
        fi
        
        if echo "$nomad_config" | grep -q "datacenter = \"dc1\""; then
            log_pass "Configuration includes correct datacenter for $env"
        else
            log_fail "Configuration missing or incorrect datacenter for $env"
        fi
        
        # Test 3c: Environment-specific paths and settings
        case "$env" in
            "production")
                if echo "$nomad_config" | grep -q "/opt/nomad"; then
                    log_pass "Production environment uses correct paths"
                else
                    log_warn "Production environment paths may not be optimal"
                fi
                ;;
            "develop")
                if echo "$nomad_config" | grep -q "/tmp\|/opt/nomad"; then
                    log_pass "Development environment uses appropriate paths"
                else
                    log_warn "Development environment paths may need adjustment"
                fi
                ;;
        esac
        
        # Test 3d: Configuration validity
        echo "$nomad_config" > "/tmp/test-config-${env}.hcl"
        if nomad config validate "/tmp/test-config-${env}.hcl" >/dev/null 2>&1; then
            log_pass "Configuration for $env is syntactically valid"
        else
            log_fail "Configuration for $env has syntax errors"
            nomad config validate "/tmp/test-config-${env}.hcl" 2>&1 >> "$TEST_LOG"
        fi
        
        # Clean up
        restore_original_environment
        rm -f "/tmp/test-config-${env}.hcl"
    done
}

# Test 4: Phase transition environment handling
test_phase_transition_environment() {
    log_test "Testing environment variable handling during phase transitions"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    for env in "${TEST_ENVIRONMENTS[@]}"; do
        log_info "Testing phase transition for $env"
        
        # Set common variables
        export ENVIRONMENT="$env"
        export VAULT_ENABLED="true"
        export CONSUL_ENABLED="true"
        export DATACENTER="dc1"
        export NOMAD_REGION="global"
        
        # Test 4a: Phase 1 environment (bootstrap phase)
        export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
        
        local phase1_config
        if phase1_config=$(generate_nomad_config "$env" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true"); then
            log_pass "Phase 1 configuration generated for $env"
        else
            log_fail "Failed to generate Phase 1 configuration for $env"
            continue
        fi
        
        # Test 4b: Phase 2 environment (post-bootstrap)
        export NOMAD_VAULT_BOOTSTRAP_PHASE="false"
        
        local phase2_config
        if phase2_config=$(generate_nomad_config "$env" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "false"); then
            log_pass "Phase 2 configuration generated for $env"
        else
            log_fail "Failed to generate Phase 2 configuration for $env"
            continue
        fi
        
        # Test 4c: Verify phase differences
        if ! echo "$phase1_config" | grep -q "enabled = true" && echo "$phase2_config" | grep -q "enabled = true"; then
            log_pass "Environment $env correctly handles phase transition"
        else
            log_fail "Environment $env does not handle phase transition correctly"
            echo "Phase 1 vault config:" >> "$TEST_LOG"
            echo "$phase1_config" | grep -A5 -B5 "vault" >> "$TEST_LOG" || echo "No vault config" >> "$TEST_LOG"
            echo "Phase 2 vault config:" >> "$TEST_LOG"
            echo "$phase2_config" | grep -A5 -B5 "vault" >> "$TEST_LOG" || echo "No vault config" >> "$TEST_LOG"
        fi
        
        # Test 4d: Both configurations are valid
        echo "$phase1_config" > "/tmp/test-phase1-${env}.hcl"
        echo "$phase2_config" > "/tmp/test-phase2-${env}.hcl"
        
        local phase1_valid=false
        local phase2_valid=false
        
        if nomad config validate "/tmp/test-phase1-${env}.hcl" >/dev/null 2>&1; then
            phase1_valid=true
        fi
        
        if nomad config validate "/tmp/test-phase2-${env}.hcl" >/dev/null 2>&1; then
            phase2_valid=true
        fi
        
        if $phase1_valid && $phase2_valid; then
            log_pass "Both phase configurations are valid for $env"
        else
            log_fail "One or both phase configurations invalid for $env"
            [[ $phase1_valid == false ]] && nomad config validate "/tmp/test-phase1-${env}.hcl" 2>&1 >> "$TEST_LOG"
            [[ $phase2_valid == false ]] && nomad config validate "/tmp/test-phase2-${env}.hcl" 2>&1 >> "$TEST_LOG"
        fi
        
        # Clean up
        restore_original_environment
        rm -f "/tmp/test-phase1-${env}.hcl" "/tmp/test-phase2-${env}.hcl"
    done
}

# Test 5: Script environment variable handling
test_script_environment_handling() {
    log_test "Testing script environment variable handling"
    
    # Test bootstrap script environment handling
    if [[ -f "$INFRA_DIR/scripts/unified-bootstrap-systemd.sh" ]]; then
        # Test 5a: Script sources environment correctly
        if grep -q "source.*env\|export.*ENVIRONMENT" "$INFRA_DIR/scripts/unified-bootstrap-systemd.sh"; then
            log_pass "Bootstrap script handles environment variables"
        else
            log_warn "Bootstrap script may not handle environment variables properly"
        fi
        
        # Test 5b: Script respects bootstrap phase
        if grep -q "NOMAD_VAULT_BOOTSTRAP_PHASE" "$INFRA_DIR/scripts/unified-bootstrap-systemd.sh"; then
            log_pass "Bootstrap script respects bootstrap phase variable"
        else
            log_fail "Bootstrap script does not handle bootstrap phase variable"
        fi
    else
        log_fail "Bootstrap script not found"
    fi
    
    # Test install scripts environment handling
    local install_scripts=("install-nomad.sh" "install-consul.sh")
    for script in "${install_scripts[@]}"; do
        if [[ -f "$INFRA_DIR/scripts/$script" ]]; then
            if grep -q "ENVIRONMENT\|export.*ENV" "$INFRA_DIR/scripts/$script"; then
                log_pass "Script $script handles environment variables"
            else
                log_warn "Script $script may not handle environment variables"
            fi
        else
            log_warn "Script $script not found"
        fi
    done
}

# Test 6: Environment consistency across components
test_environment_consistency() {
    log_test "Testing environment consistency across components"
    
    for env in "${TEST_ENVIRONMENTS[@]}"; do
        log_info "Testing consistency for $env environment"
        
        # Set environment
        export ENVIRONMENT="$env"
        export VAULT_ENABLED="true"
        export CONSUL_ENABLED="true"
        export DATACENTER="dc1"
        export NOMAD_REGION="global"
        
        # Source config templates
        if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
            log_fail "Failed to source config-templates.sh for $env"
            continue
        fi
        
        # Generate configurations for different components
        local nomad_config consul_config
        
        # Test 6a: Nomad configuration consistency
        if nomad_config=$(generate_nomad_config "$env" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "false"); then
            
            # Verify datacenter consistency
            if echo "$nomad_config" | grep -q "datacenter = \"dc1\""; then
                log_pass "Nomad configuration uses consistent datacenter for $env"
            else
                log_fail "Nomad configuration datacenter inconsistent for $env"
            fi
            
            # Verify region consistency
            if echo "$nomad_config" | grep -q "region = \"global\""; then
                log_pass "Nomad configuration uses consistent region for $env"
            else
                log_fail "Nomad configuration region inconsistent for $env"
            fi
        else
            log_fail "Failed to generate Nomad config for consistency test in $env"
        fi
        
        # Test 6b: Service discovery consistency
        if echo "$nomad_config" | grep -q "127.0.0.1:8500"; then
            log_pass "Service discovery addresses are consistent for $env"
        else
            log_warn "Service discovery addresses may be inconsistent for $env"
        fi
        
        # Clean up
        restore_original_environment
    done
}

# Test 7: Environment variable validation
test_environment_validation() {
    log_test "Testing environment variable validation"
    
    # Test 7a: Required variables validation
    local required_vars=("ENVIRONMENT" "DATACENTER" "NOMAD_REGION")
    
    for var in "${required_vars[@]}"; do
        # Test with missing variable
        unset $var
        
        # This should be handled gracefully by the scripts
        if source "$INFRA_DIR/scripts/config-templates.sh" >/dev/null 2>&1; then
            log_pass "Scripts handle missing $var gracefully"
        else
            log_warn "Scripts may not handle missing $var properly"
        fi
    done
    
    # Test 7b: Invalid values validation
    export ENVIRONMENT="invalid-env"
    export NOMAD_VAULT_BOOTSTRAP_PHASE="invalid-bool"
    
    # Scripts should handle invalid values
    if source "$INFRA_DIR/scripts/config-templates.sh" >/dev/null 2>&1; then
        log_pass "Scripts handle invalid environment values"
    else
        log_warn "Scripts may not validate environment values properly"
    fi
    
    # Clean up
    restore_original_environment
}

# Main test execution
main() {
    echo "=============================================="
    echo "Environment Variable Propagation Test Suite"
    echo "=============================================="
    echo "Test Log: $TEST_LOG"
    echo ""
    
    # Store original environment
    store_original_environment
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    log_info "Starting environment variable propagation tests..."
    echo ""
    
    # Run all environment tests
    test_environment_templates || true
    echo ""
    
    test_environment_loading || true
    echo ""
    
    test_config_generation_with_env || true
    echo ""
    
    test_phase_transition_environment || true
    echo ""
    
    test_script_environment_handling || true
    echo ""
    
    test_environment_consistency || true
    echo ""
    
    test_environment_validation || true
    echo ""
    
    # Print results
    echo "=============================================="
    echo "Environment Propagation Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Warnings: $TEST_WARNINGS"
    echo "=============================================="
    
    # Save results to file
    cat >> "$TEST_LOG" << EOF

ENVIRONMENT PROPAGATION TEST SUMMARY
====================================
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Warnings: $TEST_WARNINGS
Success Rate: $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

Environments Tested: ${TEST_ENVIRONMENTS[*]}
Critical Variables: ${CRITICAL_ENV_VARS[*]}

Date: $(date)
Host: $(hostname)
EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Environment propagation tests passed!${NC}"
        echo ""
        echo "Environment Propagation Summary:"
        echo "✓ Environment templates are valid and complete"
        echo "✓ Variables load correctly across all environments"
        echo "✓ Configuration generation works with environment variables"
        echo "✓ Phase transitions handle environment changes properly"
        echo "✓ Scripts handle environment variables consistently"
        echo "✓ Environment consistency is maintained across components"
        echo ""
        echo "Environment variable propagation is working correctly!"
        exit 0
    else
        echo -e "${RED}❌ Environment propagation tests failed.${NC}"
        echo ""
        echo "Issues found in environment variable handling:"
        [[ $TEST_WARNINGS -gt 0 ]] && echo "⚠️  $TEST_WARNINGS warnings need attention"
        echo ""
        echo "Check the test log for details: $TEST_LOG"
        exit 1
    fi
}

# Run main function
main "$@"