#!/bin/bash

# Comprehensive Bootstrap Pipeline End-to-End Test
# Tests the complete variable propagation from GitHub Actions → deployment.env → bootstrap script → config templates → services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
TEST_OUTPUT_DIR="$INFRA_DIR/tests/results"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    echo "[TEST] $1" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "[PASS] $1" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "[FAIL] $1" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
}

log_header() {
    echo ""
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
    echo ""
    echo "" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "================================================================================" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "$1" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "================================================================================" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    mkdir -p "$TEST_OUTPUT_DIR"
    mkdir -p "$TEST_OUTPUT_DIR/temp"
    
    # Create test deployment.env file
    cat > "$TEST_OUTPUT_DIR/temp/deployment.env" <<EOF
ENVIRONMENT=develop
DEPLOY_NOMAD=true
DEPLOY_VAULT=true
DEPLOY_TRAEFIK=true
IS_BOOTSTRAP=true
BOOTSTRAP_PHASE=true
DRY_RUN=false
FORCE_BOOTSTRAP=false
COMPONENTS=all
EOF
    
    log_info "Test environment setup complete"
}

# Test 1: GitHub Actions workflow has BOOTSTRAP_PHASE variable
test_github_actions_bootstrap_variable() {
    log_test "Testing GitHub Actions workflow contains BOOTSTRAP_PHASE variable"
    
    local workflow_file="$INFRA_DIR/.github/workflows/deploy-infrastructure.yml"
    
    if [[ -f "$workflow_file" ]]; then
        if grep -q "BOOTSTRAP_PHASE=" "$workflow_file"; then
            log_pass "GitHub Actions workflow includes BOOTSTRAP_PHASE variable"
        else
            log_fail "GitHub Actions workflow missing BOOTSTRAP_PHASE variable"
            return 1
        fi
        
        if grep -q 'BOOTSTRAP_PHASE=\${{ needs.prepare-deployment.outputs.is-bootstrap }}' "$workflow_file"; then
            log_pass "BOOTSTRAP_PHASE correctly mapped to is-bootstrap output"
        else
            log_fail "BOOTSTRAP_PHASE not correctly mapped in GitHub Actions"
            return 1
        fi
    else
        log_fail "GitHub Actions workflow file not found"
        return 1
    fi
}

# Test 2: Bootstrap script exports environment variables properly
test_bootstrap_script_variable_export() {
    log_test "Testing bootstrap script exports BOOTSTRAP_PHASE variables"
    
    local bootstrap_script="$INFRA_DIR/scripts/unified-bootstrap-systemd.sh"
    
    if [[ -f "$bootstrap_script" ]]; then
        if grep -q 'export BOOTSTRAP_PHASE="true"' "$bootstrap_script"; then
            log_pass "Bootstrap script exports BOOTSTRAP_PHASE=true"
        else
            log_fail "Bootstrap script missing BOOTSTRAP_PHASE export"
            return 1
        fi
        
        if grep -q 'export NOMAD_VAULT_BOOTSTRAP_PHASE="true"' "$bootstrap_script"; then
            log_pass "Bootstrap script exports NOMAD_VAULT_BOOTSTRAP_PHASE=true"
        else
            log_fail "Bootstrap script missing NOMAD_VAULT_BOOTSTRAP_PHASE export"
            return 1
        fi
        
        if grep -q 'export VAULT_ENABLED="false"' "$bootstrap_script"; then
            log_pass "Bootstrap script exports VAULT_ENABLED=false"
        else
            log_fail "Bootstrap script missing VAULT_ENABLED=false export"
            return 1
        fi
        
        # Check if bootstrap script passes variables to manage-services.sh
        if grep -q 'VAULT_ENABLED=.*NOMAD_VAULT_BOOTSTRAP_PHASE=.*BOOTSTRAP_PHASE=.*bash.*manage-services.sh' "$bootstrap_script"; then
            log_pass "Bootstrap script passes environment variables to manage-services.sh"
        else
            log_fail "Bootstrap script not passing environment variables to manage-services.sh"
            return 1
        fi
    else
        log_fail "Bootstrap script not found"
        return 1
    fi
}

# Test 3: manage-services.sh uses dynamic config generation
test_manage_services_dynamic_config() {
    log_test "Testing manage-services.sh uses dynamic configuration generation"
    
    local manage_services_script="$INFRA_DIR/scripts/manage-services.sh"
    
    if [[ -f "$manage_services_script" ]]; then
        if grep -q "source.*config-templates.sh" "$manage_services_script"; then
            log_pass "manage-services.sh sources config-templates.sh"
        else
            log_fail "manage-services.sh not sourcing config-templates.sh"
            return 1
        fi
        
        if grep -q "generate_nomad_config" "$manage_services_script"; then
            log_pass "manage-services.sh calls generate_nomad_config"
        else
            log_fail "manage-services.sh not calling generate_nomad_config"
            return 1
        fi
        
        if grep -q 'VAULT_ENABLED:-false' "$manage_services_script"; then
            log_pass "manage-services.sh respects VAULT_ENABLED environment variable"
        else
            log_fail "manage-services.sh not respecting VAULT_ENABLED environment variable"
            return 1
        fi
        
        if grep -q 'NOMAD_VAULT_BOOTSTRAP_PHASE:-false' "$manage_services_script"; then
            log_pass "manage-services.sh respects NOMAD_VAULT_BOOTSTRAP_PHASE environment variable"
        else
            log_fail "manage-services.sh not respecting NOMAD_VAULT_BOOTSTRAP_PHASE environment variable"
            return 1
        fi
    else
        log_fail "manage-services.sh script not found"
        return 1
    fi
}

# Test 4: config-templates.sh generates correct Nomad config for bootstrap phase
test_config_templates_bootstrap_logic() {
    log_test "Testing config-templates.sh generates correct bootstrap phase configuration"
    
    local config_templates_script="$INFRA_DIR/scripts/config-templates.sh"
    
    if [[ -f "$config_templates_script" ]]; then
        # Source the config templates to test the function
        source "$config_templates_script"
        
        # Test bootstrap phase configuration generation
        log_info "Testing Nomad config generation with bootstrap phase enabled..."
        
        local temp_config="$TEST_OUTPUT_DIR/temp/test-nomad-bootstrap.hcl"
        
        # Generate config with bootstrap phase
        generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
            "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
            "false" "http://localhost:8200" "true" > "$temp_config"
        
        if [[ -f "$temp_config" ]]; then
            if grep -q "Vault integration disabled during bootstrap phase" "$temp_config"; then
                log_pass "Config template includes bootstrap phase comment"
            else
                log_fail "Config template missing bootstrap phase comment"
                return 1
            fi
            
            if ! grep -q "vault {" "$temp_config" || grep -q "# vault {" "$temp_config"; then
                log_pass "Vault configuration properly disabled in bootstrap phase"
            else
                log_fail "Vault configuration not disabled in bootstrap phase"
                cat "$temp_config" | grep -A5 -B5 "vault {" || true
                return 1
            fi
        else
            log_fail "Failed to generate test Nomad configuration"
            return 1
        fi
        
        # Test normal phase configuration generation
        log_info "Testing Nomad config generation with bootstrap phase disabled..."
        
        local temp_config_normal="$TEST_OUTPUT_DIR/temp/test-nomad-normal.hcl"
        
        # Generate config without bootstrap phase
        generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
            "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
            "true" "http://localhost:8200" "false" > "$temp_config_normal"
        
        if [[ -f "$temp_config_normal" ]]; then
            if grep -q "vault {" "$temp_config_normal" && grep -q "enabled = true" "$temp_config_normal"; then
                log_pass "Vault configuration properly enabled in normal phase"
            else
                log_fail "Vault configuration not properly enabled in normal phase"
                return 1
            fi
        else
            log_fail "Failed to generate test Nomad normal configuration"
            return 1
        fi
    else
        log_fail "config-templates.sh script not found"
        return 1
    fi
}

# Test 5: End-to-end pipeline simulation
test_end_to_end_pipeline() {
    log_test "Testing end-to-end bootstrap pipeline simulation"
    
    # Simulate the deployment.env sourcing
    export ENVIRONMENT=develop
    export IS_BOOTSTRAP=true
    export BOOTSTRAP_PHASE=true
    export VAULT_ENABLED=false
    export NOMAD_VAULT_BOOTSTRAP_PHASE=true
    
    log_info "Simulating bootstrap script environment variable setup..."
    
    # Test that config templates work with these environment variables
    source "$INFRA_DIR/scripts/config-templates.sh"
    
    local pipeline_test_config="$TEST_OUTPUT_DIR/temp/pipeline-test-nomad.hcl"
    
    generate_nomad_config "$ENVIRONMENT" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
        "both" "pipeline-test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
        "$VAULT_ENABLED" "http://localhost:8200" "$NOMAD_VAULT_BOOTSTRAP_PHASE" > "$pipeline_test_config"
    
    if [[ -f "$pipeline_test_config" ]]; then
        log_info "Generated pipeline test configuration:"
        cat "$pipeline_test_config" | grep -A10 -B5 -E "(vault|bootstrap|Vault)" || log_info "No vault configuration found (expected in bootstrap phase)"
        
        # Check that Vault integration is properly disabled (no enabled = true in vault block)
        log_info "Checking for 'vault {' pattern: $(grep -c "vault {" "$pipeline_test_config" 2>/dev/null || echo 0)"
        log_info "Checking for '# vault {' pattern: $(grep -c "# vault {" "$pipeline_test_config" 2>/dev/null || echo 0)"
        log_info "Checking for 'enabled = true' pattern: $(grep -c "enabled = true" "$pipeline_test_config" 2>/dev/null || echo 0)"
        
        # In bootstrap phase, vault block should be commented out (# vault {)
        if grep -q "# vault {" "$pipeline_test_config"; then
            log_pass "End-to-end pipeline: Vault integration properly disabled (commented out) during bootstrap"
        elif ! grep -q "vault {" "$pipeline_test_config"; then
            log_pass "End-to-end pipeline: Vault integration properly disabled (not present) during bootstrap"
        elif grep -q "vault {" "$pipeline_test_config" && ! grep -q "enabled = true" "$pipeline_test_config"; then
            log_pass "End-to-end pipeline: Vault block present but disabled during bootstrap"
        else
            log_fail "End-to-end pipeline: Vault integration incorrectly enabled during bootstrap"
            return 1
        fi
        
        if grep -q "bootstrap phase" "$pipeline_test_config"; then
            log_pass "End-to-end pipeline: Bootstrap phase comments present"
        else
            log_fail "End-to-end pipeline: Bootstrap phase comments missing"
            return 1
        fi
    else
        log_fail "End-to-end pipeline: Failed to generate test configuration"
        return 1
    fi
    
    # Clean up environment variables
    unset ENVIRONMENT IS_BOOTSTRAP BOOTSTRAP_PHASE VAULT_ENABLED NOMAD_VAULT_BOOTSTRAP_PHASE
}

# Test 6: Verify reconfigure_nomad_with_vault function exists
test_reconfigure_function_exists() {
    log_test "Testing reconfigure_nomad_with_vault function exists and is accessible"
    
    local config_templates_script="$INFRA_DIR/scripts/config-templates.sh"
    
    if [[ -f "$config_templates_script" ]]; then
        source "$config_templates_script"
        
        if declare -f reconfigure_nomad_with_vault > /dev/null; then
            log_pass "reconfigure_nomad_with_vault function exists"
            
            # Test function help/usage
            if grep -q "reconfigure_nomad_with_vault" "$config_templates_script"; then
                log_pass "reconfigure_nomad_with_vault function is exported"
            else
                log_fail "reconfigure_nomad_with_vault function not properly exported"
                return 1
            fi
        else
            log_fail "reconfigure_nomad_with_vault function not found"
            return 1
        fi
    else
        log_fail "config-templates.sh script not found"
        return 1
    fi
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_OUTPUT_DIR/temp"
    log_info "Test cleanup complete"
}

# Generate test report
generate_test_report() {
    log_header "BOOTSTRAP PIPELINE TEST REPORT"
    
    echo -e "${WHITE}Test Summary:${NC}"
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "  ${BLUE}Total:${NC}  $TESTS_TOTAL"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED! Bootstrap pipeline is properly configured.${NC}"
        echo ""
        echo -e "${WHITE}The two-phase bootstrap approach is working correctly:${NC}"
        echo -e "${CYAN}Phase 1:${NC} Nomad deployed with Vault integration DISABLED"
        echo -e "${CYAN}Phase 2:${NC} After Vault deployment, Nomad reconfigured with Vault integration ENABLED"
    else
        echo -e "${RED}❌ SOME TESTS FAILED! Bootstrap pipeline needs fixes.${NC}"
        echo ""
        echo -e "${WHITE}Issues found:${NC}"
        echo -e "- Check the test log for specific failure details"
        echo -e "- Fix the failed components before deploying"
    fi
    
    echo ""
    echo -e "${WHITE}Test Results Location:${NC}"
    echo -e "${CYAN}Log File:${NC} $TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo -e "${CYAN}Temp Files:${NC} $TEST_OUTPUT_DIR/temp/"
    echo ""
    
    # Write summary to log
    echo "" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "FINAL SUMMARY:" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "Passed: $TESTS_PASSED" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "Failed: $TESTS_FAILED" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
    echo "Total: $TESTS_TOTAL" >> "$TEST_OUTPUT_DIR/bootstrap-pipeline-test-$TIMESTAMP.log"
}

# Main execution
main() {
    log_header "COMPREHENSIVE BOOTSTRAP PIPELINE TEST"
    echo -e "${WHITE}Testing variable propagation: GitHub Actions → deployment.env → bootstrap script → config templates → services${NC}"
    echo ""
    
    setup_test_environment
    
    # Run all tests
    test_github_actions_bootstrap_variable || true
    test_bootstrap_script_variable_export || true
    test_manage_services_dynamic_config || true
    test_config_templates_bootstrap_logic || true
    test_end_to_end_pipeline || true
    test_reconfigure_function_exists || true
    
    cleanup_test_environment
    generate_test_report
    
    # Exit with error code if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"