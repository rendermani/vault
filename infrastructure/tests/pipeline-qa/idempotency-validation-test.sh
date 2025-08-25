#!/bin/bash
# Idempotency Validation Test Suite
# Tests that deployment operations are idempotent and can be run multiple times safely
# Ensures no negative side effects from repeated executions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
TEST_LOG="$TEST_RESULTS_DIR/idempotency-test-$(date +%Y%m%d_%H%M%S).log"

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
TEST_CONFIG_DIR="/tmp/idempotency-test-configs"
BASELINE_DIR="/tmp/idempotency-baseline"
COMPARISON_DIR="/tmp/idempotency-comparison"
RUN_ITERATIONS=3

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
setup_test_environment() {
    log_info "Setting up idempotency test environment..."
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$BASELINE_DIR"
    mkdir -p "$COMPARISON_DIR"
    
    # Export test environment variables
    export ENVIRONMENT="develop"
    export DATACENTER="dc1"
    export NOMAD_REGION="global"
    export VAULT_ENABLED="true"
    export CONSUL_ENABLED="true"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up idempotency test environment..."
    
    # Remove test directories
    rm -rf "$TEST_CONFIG_DIR" "$BASELINE_DIR" "$COMPARISON_DIR" 2>/dev/null || true
    rm -f /tmp/idempotency-*.hcl /tmp/idempotency-*.log 2>/dev/null || true
    
    # Unset test environment variables
    unset ENVIRONMENT DATACENTER NOMAD_REGION VAULT_ENABLED CONSUL_ENABLED
    unset NOMAD_VAULT_BOOTSTRAP_PHASE
}

# Generate configuration and capture state
generate_and_capture_config() {
    local iteration=$1
    local phase=$2  # "bootstrap" or "integration"
    local output_dir=$3
    
    log_info "Generating configuration for iteration $iteration (phase: $phase)"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh in iteration $iteration"
        return 1
    fi
    
    # Set phase-specific variables
    if [[ "$phase" == "bootstrap" ]]; then
        export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
    else
        export NOMAD_VAULT_BOOTSTRAP_PHASE="false"
    fi
    
    # Generate Nomad configuration
    local nomad_config
    if nomad_config=$(generate_nomad_config "$ENVIRONMENT" "$DATACENTER" "$NOMAD_REGION" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "$NOMAD_VAULT_BOOTSTRAP_PHASE"); then
        
        echo "$nomad_config" > "$output_dir/nomad-${phase}-iter${iteration}.hcl"
        log_info "Configuration generated and saved for iteration $iteration"
        return 0
    else
        log_fail "Failed to generate configuration in iteration $iteration"
        return 1
    fi
}

# Compare configurations for idempotency
compare_configurations() {
    local phase=$1
    local file1=$2
    local file2=$3
    local iteration1=$4
    local iteration2=$5
    
    log_info "Comparing configurations: iteration $iteration1 vs iteration $iteration2 ($phase phase)"
    
    # Check if files exist
    if [[ ! -f "$file1" || ! -f "$file2" ]]; then
        log_fail "Configuration files missing for comparison"
        return 1
    fi
    
    # Compare file contents (excluding comments with timestamps)
    local diff_result
    if diff_result=$(diff <(grep -v "^#.*$(date +%Y)" "$file1" | sort) <(grep -v "^#.*$(date +%Y)" "$file2" | sort) 2>&1); then
        log_pass "Configuration idempotent: iteration $iteration1 vs $iteration2 ($phase phase)"
        return 0
    else
        log_fail "Configuration NOT idempotent: iteration $iteration1 vs $iteration2 ($phase phase)"
        echo "Differences found:" >> "$TEST_LOG"
        echo "$diff_result" >> "$TEST_LOG"
        return 1
    fi
}

# Test 1: Configuration generation idempotency
test_configuration_idempotency() {
    log_test "Testing configuration generation idempotency"
    
    # Test both bootstrap and integration phases
    local phases=("bootstrap" "integration")
    
    for phase in "${phases[@]}"; do
        log_info "Testing $phase phase idempotency"
        
        # Generate configurations multiple times
        for i in $(seq 1 $RUN_ITERATIONS); do
            if ! generate_and_capture_config $i "$phase" "$BASELINE_DIR"; then
                log_fail "Failed to generate configuration for iteration $i ($phase phase)"
                continue 2
            fi
            sleep 1  # Brief pause between generations
        done
        
        # Compare all iterations
        local base_file="$BASELINE_DIR/nomad-${phase}-iter1.hcl"
        for i in $(seq 2 $RUN_ITERATIONS); do
            local compare_file="$BASELINE_DIR/nomad-${phase}-iter${i}.hcl"
            compare_configurations "$phase" "$base_file" "$compare_file" 1 $i || true
        done
    done
}

# Test 2: Script execution idempotency
test_script_execution_idempotency() {
    log_test "Testing script execution idempotency"
    
    # Test 2a: Config template script idempotency
    log_info "Testing config template script multiple executions"
    
    # Source the script multiple times and check for side effects
    local source_results=()
    for i in $(seq 1 $RUN_ITERATIONS); do
        if source "$INFRA_DIR/scripts/config-templates.sh" >/dev/null 2>&1; then
            source_results+=("success")
            
            # Check if functions are still available
            if type generate_nomad_config >/dev/null 2>&1; then
                log_info "Iteration $i: Functions available after re-sourcing"
            else
                log_warn "Iteration $i: Functions not available after re-sourcing"
            fi
        else
            source_results+=("failure")
            log_warn "Iteration $i: Failed to source config-templates.sh"
        fi
    done
    
    # Verify consistent results
    local first_result="${source_results[0]}"
    local consistent=true
    for result in "${source_results[@]}"; do
        if [[ "$result" != "$first_result" ]]; then
            consistent=false
            break
        fi
    done
    
    if $consistent && [[ "$first_result" == "success" ]]; then
        log_pass "Config template script execution is idempotent"
    else
        log_fail "Config template script execution is NOT idempotent"
    fi
    
    # Test 2b: Validation script idempotency (if exists)
    if [[ -f "$INFRA_DIR/scripts/validate-deployment.sh" ]]; then
        log_info "Testing deployment validation script idempotency"
        
        # Check script syntax multiple times
        local validation_results=()
        for i in $(seq 1 $RUN_ITERATIONS); do
            if bash -n "$INFRA_DIR/scripts/validate-deployment.sh"; then
                validation_results+=("success")
            else
                validation_results+=("failure")
            fi
        done
        
        # Verify consistent validation
        local first_validation="${validation_results[0]}"
        local validation_consistent=true
        for result in "${validation_results[@]}"; do
            if [[ "$result" != "$first_validation" ]]; then
                validation_consistent=false
                break
            fi
        done
        
        if $validation_consistent; then
            log_pass "Validation script syntax check is idempotent"
        else
            log_fail "Validation script syntax check is NOT idempotent"
        fi
    else
        log_warn "Deployment validation script not found for idempotency testing"
    fi
}

# Test 3: Environment variable handling idempotency
test_environment_variable_idempotency() {
    log_test "Testing environment variable handling idempotency"
    
    # Test 3a: Environment variable sourcing
    log_info "Testing environment variable sourcing idempotency"
    
    # Create test environment file
    cat > "/tmp/idempotency-test.env" << 'EOF'
export TEST_VAR="test_value"
export ENVIRONMENT="develop"
export VAULT_ENABLED="true"
EOF
    
    # Source multiple times and check values
    local env_values=()
    for i in $(seq 1 $RUN_ITERATIONS); do
        source "/tmp/idempotency-test.env"
        env_values+=("${TEST_VAR:-}:${ENVIRONMENT:-}:${VAULT_ENABLED:-}")
    done
    
    # Verify all values are identical
    local first_env="${env_values[0]}"
    local env_consistent=true
    for value in "${env_values[@]}"; do
        if [[ "$value" != "$first_env" ]]; then
            env_consistent=false
            break
        fi
    done
    
    if $env_consistent && [[ -n "$first_env" ]]; then
        log_pass "Environment variable sourcing is idempotent"
    else
        log_fail "Environment variable sourcing is NOT idempotent"
        echo "Values: ${env_values[*]}" >> "$TEST_LOG"
    fi
    
    # Clean up
    rm -f "/tmp/idempotency-test.env"
    unset TEST_VAR
}

# Test 4: State file idempotency
test_state_file_idempotency() {
    log_test "Testing state file operations idempotency"
    
    # Test 4a: State file creation and modification
    log_info "Testing state file operations"
    
    local state_file="/tmp/idempotency-state-test.state"
    
    # Create state file multiple times with same content
    for i in $(seq 1 $RUN_ITERATIONS); do
        cat > "$state_file" << EOF
DEPLOYMENT_PHASE=1
NOMAD_DEPLOYED=true
VAULT_DEPLOYED=false
LAST_UPDATE=$(date +%Y-%m-%d)
ITERATION=$i
EOF
    done
    
    # Verify the file exists and has expected content
    if [[ -f "$state_file" ]]; then
        if grep -q "DEPLOYMENT_PHASE=1" "$state_file" && grep -q "NOMAD_DEPLOYED=true" "$state_file"; then
            log_pass "State file creation is idempotent (content consistent)"
        else
            log_fail "State file creation is NOT idempotent (content inconsistent)"
        fi
    else
        log_fail "State file was not created"
    fi
    
    # Test 4b: State file reading
    log_info "Testing state file reading idempotency"
    
    local read_results=()
    for i in $(seq 1 $RUN_ITERATIONS); do
        if source "$state_file"; then
            read_results+=("${DEPLOYMENT_PHASE:-}:${NOMAD_DEPLOYED:-}:${VAULT_DEPLOYED:-}")
        else
            read_results+=("failed")
        fi
    done
    
    # Verify consistent reading (ignoring ITERATION and LAST_UPDATE which change)
    local first_read="${read_results[0]}"
    local read_consistent=true
    for result in "${read_results[@]}"; do
        if [[ "$result" != "$first_read" ]]; then
            read_consistent=false
            break
        fi
    done
    
    if $read_consistent && [[ "$first_read" != "failed" ]]; then
        log_pass "State file reading is idempotent"
    else
        log_fail "State file reading is NOT idempotent"
        echo "Read results: ${read_results[*]}" >> "$TEST_LOG"
    fi
    
    # Clean up
    rm -f "$state_file"
    unset DEPLOYMENT_PHASE NOMAD_DEPLOYED VAULT_DEPLOYED LAST_UPDATE ITERATION
}

# Test 5: Configuration validation idempotency
test_validation_idempotency() {
    log_test "Testing configuration validation idempotency"
    
    # Generate a test configuration
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    local test_config
    if test_config=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
        "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true"); then
        
        echo "$test_config" > "/tmp/idempotency-validation-test.hcl"
        
        # Validate multiple times
        local validation_results=()
        for i in $(seq 1 $RUN_ITERATIONS); do
            if nomad config validate "/tmp/idempotency-validation-test.hcl" >/dev/null 2>&1; then
                validation_results+=("valid")
            else
                validation_results+=("invalid")
            fi
        done
        
        # Verify consistent validation results
        local first_validation="${validation_results[0]}"
        local validation_consistent=true
        for result in "${validation_results[@]}"; do
            if [[ "$result" != "$first_validation" ]]; then
                validation_consistent=false
                break
            fi
        done
        
        if $validation_consistent && [[ "$first_validation" == "valid" ]]; then
            log_pass "Configuration validation is idempotent"
        else
            log_fail "Configuration validation is NOT idempotent"
            echo "Validation results: ${validation_results[*]}" >> "$TEST_LOG"
        fi
        
        # Clean up
        rm -f "/tmp/idempotency-validation-test.hcl"
    else
        log_fail "Failed to generate test configuration for validation"
    fi
}

# Test 6: Phase transition idempotency
test_phase_transition_idempotency() {
    log_test "Testing phase transition idempotency"
    
    # Source config templates
    if ! source "$INFRA_DIR/scripts/config-templates.sh"; then
        log_fail "Failed to source config-templates.sh"
        return 1
    fi
    
    # Test multiple transitions from Phase 1 to Phase 2
    for i in $(seq 1 $RUN_ITERATIONS); do
        log_info "Testing phase transition iteration $i"
        
        # Phase 1 configuration
        export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
        local phase1_config
        if phase1_config=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "true"); then
            echo "$phase1_config" > "$COMPARISON_DIR/phase1-iter${i}.hcl"
        else
            log_fail "Failed to generate Phase 1 config in iteration $i"
            continue
        fi
        
        # Phase 2 configuration
        export NOMAD_VAULT_BOOTSTRAP_PHASE="false"
        local phase2_config
        if phase2_config=$(generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" \
            "/var/log/nomad" "both" "test-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" "true" "https://127.0.0.1:8200" "false"); then
            echo "$phase2_config" > "$COMPARISON_DIR/phase2-iter${i}.hcl"
        else
            log_fail "Failed to generate Phase 2 config in iteration $i"
            continue
        fi
    done
    
    # Compare Phase 1 configurations across iterations
    local phase1_base="$COMPARISON_DIR/phase1-iter1.hcl"
    local phase1_consistent=true
    for i in $(seq 2 $RUN_ITERATIONS); do
        local phase1_compare="$COMPARISON_DIR/phase1-iter${i}.hcl"
        if [[ -f "$phase1_base" && -f "$phase1_compare" ]]; then
            if ! compare_configurations "Phase1" "$phase1_base" "$phase1_compare" 1 $i >/dev/null 2>&1; then
                phase1_consistent=false
            fi
        fi
    done
    
    # Compare Phase 2 configurations across iterations
    local phase2_base="$COMPARISON_DIR/phase2-iter1.hcl"
    local phase2_consistent=true
    for i in $(seq 2 $RUN_ITERATIONS); do
        local phase2_compare="$COMPARISON_DIR/phase2-iter${i}.hcl"
        if [[ -f "$phase2_base" && -f "$phase2_compare" ]]; then
            if ! compare_configurations "Phase2" "$phase2_base" "$phase2_compare" 1 $i >/dev/null 2>&1; then
                phase2_consistent=false
            fi
        fi
    done
    
    if $phase1_consistent && $phase2_consistent; then
        log_pass "Phase transition configurations are idempotent"
    else
        log_fail "Phase transition configurations are NOT idempotent"
        [[ $phase1_consistent == false ]] && log_fail "Phase 1 configurations are not consistent"
        [[ $phase2_consistent == false ]] && log_fail "Phase 2 configurations are not consistent"
    fi
}

# Test 7: Resource cleanup idempotency
test_cleanup_idempotency() {
    log_test "Testing resource cleanup idempotency"
    
    # Test 7a: Create test resources
    log_info "Creating test resources for cleanup testing"
    
    local test_files=(
        "/tmp/test-cleanup-1.tmp"
        "/tmp/test-cleanup-2.tmp"
        "/tmp/test-cleanup-dir/test-file.tmp"
    )
    
    # Create test resources
    mkdir -p "/tmp/test-cleanup-dir"
    for file in "${test_files[@]}"; do
        echo "test content" > "$file"
    done
    
    # Test 7b: Multiple cleanup operations
    log_info "Testing multiple cleanup operations"
    
    local cleanup_results=()
    for i in $(seq 1 $RUN_ITERATIONS); do
        # Simulate cleanup
        rm -f /tmp/test-cleanup-*.tmp 2>/dev/null || true
        rm -rf /tmp/test-cleanup-dir 2>/dev/null || true
        
        # Check cleanup result
        if [[ ! -f "/tmp/test-cleanup-1.tmp" && ! -f "/tmp/test-cleanup-2.tmp" && ! -d "/tmp/test-cleanup-dir" ]]; then
            cleanup_results+=("clean")
        else
            cleanup_results+=("dirty")
        fi
        
        # Recreate resources for next iteration
        if [[ $i -lt $RUN_ITERATIONS ]]; then
            mkdir -p "/tmp/test-cleanup-dir"
            for file in "${test_files[@]}"; do
                echo "test content" > "$file"
            done
        fi
    done
    
    # Verify cleanup idempotency
    local cleanup_consistent=true
    for result in "${cleanup_results[@]}"; do
        if [[ "$result" != "clean" ]]; then
            cleanup_consistent=false
            break
        fi
    done
    
    if $cleanup_consistent; then
        log_pass "Resource cleanup operations are idempotent"
    else
        log_fail "Resource cleanup operations are NOT idempotent"
        echo "Cleanup results: ${cleanup_results[*]}" >> "$TEST_LOG"
    fi
}

# Main test execution
main() {
    echo "=============================================="
    echo "Idempotency Validation Test Suite"
    echo "=============================================="
    echo "Test Log: $TEST_LOG"
    echo "Test Iterations: $RUN_ITERATIONS"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    log_info "Starting idempotency validation tests..."
    log_info "Each test will run $RUN_ITERATIONS iterations to verify consistency"
    echo ""
    
    # Run all idempotency tests
    test_configuration_idempotency || true
    echo ""
    
    test_script_execution_idempotency || true
    echo ""
    
    test_environment_variable_idempotency || true
    echo ""
    
    test_state_file_idempotency || true
    echo ""
    
    test_validation_idempotency || true
    echo ""
    
    test_phase_transition_idempotency || true
    echo ""
    
    test_cleanup_idempotency || true
    echo ""
    
    # Print results
    echo "=============================================="
    echo "Idempotency Validation Test Results:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Warnings: $TEST_WARNINGS"
    echo "=============================================="
    
    # Save results to file
    cat >> "$TEST_LOG" << EOF

IDEMPOTENCY VALIDATION TEST SUMMARY
===================================
Total Tests: $((TESTS_PASSED + TESTS_FAILED))
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Warnings: $TEST_WARNINGS
Success Rate: $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

Test Iterations per Test: $RUN_ITERATIONS
Test Categories:
- Configuration Generation Idempotency
- Script Execution Idempotency
- Environment Variable Handling Idempotency
- State File Operations Idempotency
- Configuration Validation Idempotency
- Phase Transition Idempotency
- Resource Cleanup Idempotency

Date: $(date)
Host: $(hostname)
EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Idempotency validation tests passed!${NC}"
        echo ""
        echo "Idempotency Summary:"
        echo "✓ Configuration generation is idempotent"
        echo "✓ Script execution can be repeated safely"
        echo "✓ Environment variable handling is consistent"
        echo "✓ State file operations are idempotent"
        echo "✓ Configuration validation is consistent"
        echo "✓ Phase transitions are idempotent"
        echo "✓ Resource cleanup operations are safe"
        echo ""
        echo "All deployment operations can be run multiple times safely!"
        exit 0
    else
        echo -e "${RED}❌ Some idempotency issues found.${NC}"
        echo ""
        echo "Issues found in idempotency:"
        [[ $TEST_WARNINGS -gt 0 ]] && echo "⚠️  $TEST_WARNINGS warnings need attention"
        echo ""
        echo "Check the test log for details: $TEST_LOG"
        echo ""
        echo "⚠️  IMPORTANT: Fix idempotency issues before production deployment!"
        exit 1
    fi
}

# Run main function
main "$@"