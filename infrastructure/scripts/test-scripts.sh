#!/bin/bash
# Test script for deployment scripts - validates idempotency and error handling
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Test configuration
TEST_ENVIRONMENT="test-$(date +%s)"
TEST_RESULTS_DIR="${LOGS_DIR}/test-results"

# Test tracking (compatible with older bash versions)
TEST_RESULTS_FILE="$(mktemp)"
TESTS_RUN=()
TESTS_PASSED=0
TESTS_FAILED=0

# Record test result
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_RUN+=("$test_name")
    echo "$test_name:$result:$message" >> "$TEST_RESULTS_FILE"
    
    case "$result" in
        "PASS")
            ((TESTS_PASSED++))
            log_success "✓ $test_name: $message"
            ;;
        "FAIL")
            ((TESTS_FAILED++))
            log_error "✗ $test_name: $message"
            ;;
        "WARN")
            log_warning "⚠ $test_name: $message"
            ;;
    esac
}

# Test script exists and is executable
test_script_exists() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [[ -f "$script_path" ]]; then
        if [[ -x "$script_path" ]]; then
            record_test "exists_$script_name" "PASS" "Script exists and is executable"
        else
            record_test "exists_$script_name" "FAIL" "Script exists but is not executable"
        fi
    else
        record_test "exists_$script_name" "FAIL" "Script does not exist"
    fi
}

# Test script syntax
test_script_syntax() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [[ -f "$script_path" ]]; then
        if bash -n "$script_path"; then
            record_test "syntax_$script_name" "PASS" "Script syntax is valid"
        else
            record_test "syntax_$script_name" "FAIL" "Script has syntax errors"
        fi
    else
        record_test "syntax_$script_name" "FAIL" "Script does not exist"
    fi
}

# Test script help output
test_script_help() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [[ -f "$script_path" ]]; then
        if timeout 10 bash "$script_path" --help &>/dev/null; then
            record_test "help_$script_name" "PASS" "Script provides help output"
        else
            record_test "help_$script_name" "WARN" "Script may not support --help flag"
        fi
    else
        record_test "help_$script_name" "FAIL" "Script does not exist"
    fi
}

# Test dry-run functionality
test_script_dry_run() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    if [[ -f "$script_path" ]]; then
        # Test if script supports dry-run
        if grep -q "dry.run\|DRY_RUN" "$script_path"; then
            if timeout 30 bash "$script_path" --dry-run --environment develop &>/dev/null; then
                record_test "dryrun_$script_name" "PASS" "Script supports dry-run mode"
            else
                record_test "dryrun_$script_name" "FAIL" "Script supports dry-run but execution failed"
            fi
        else
            record_test "dryrun_$script_name" "WARN" "Script does not appear to support dry-run mode"
        fi
    else
        record_test "dryrun_$script_name" "FAIL" "Script does not exist"
    fi
}

# Test common functions
test_common_functions() {
    log_info "Testing common functions..."
    
    # Test logging functions
    if declare -f log_info &>/dev/null; then
        record_test "common_logging" "PASS" "Logging functions are available"
    else
        record_test "common_logging" "FAIL" "Logging functions not available"
    fi
    
    # Test utility functions
    if declare -f check_command &>/dev/null; then
        record_test "common_utilities" "PASS" "Utility functions are available"
    else
        record_test "common_utilities" "FAIL" "Utility functions not available"
    fi
    
    # Test architecture detection
    local arch
    arch=$(get_architecture)
    if [[ -n "$arch" && "$arch" != "unknown" ]]; then
        record_test "common_architecture" "PASS" "Architecture detection works: $arch"
    else
        record_test "common_architecture" "FAIL" "Architecture detection failed"
    fi
    
    # Test OS detection
    local os
    os=$(get_os)
    if [[ -n "$os" && "$os" != "unknown" ]]; then
        record_test "common_os" "PASS" "OS detection works: $os"
    else
        record_test "common_os" "FAIL" "OS detection failed"
    fi
    
    # Test environment validation
    if validate_environment "develop"; then
        record_test "common_env_validation" "PASS" "Environment validation works"
    else
        record_test "common_env_validation" "FAIL" "Environment validation failed"
    fi
}

# Test configuration templates
test_configuration_templates() {
    log_info "Testing configuration templates..."
    
    source "$SCRIPT_DIR/config-templates.sh"
    
    # Test Consul config generation
    if declare -f generate_consul_config &>/dev/null; then
        local consul_config
        consul_config=$(generate_consul_config "develop" "dc1" "/tmp/consul/data" "/tmp/consul/config" "/tmp/consul/logs" "server" "test-key")
        if [[ -n "$consul_config" ]] && echo "$consul_config" | grep -q "datacenter.*dc1"; then
            record_test "template_consul" "PASS" "Consul configuration template works"
        else
            record_test "template_consul" "FAIL" "Consul configuration template failed"
        fi
    else
        record_test "template_consul" "FAIL" "Consul configuration template function not available"
    fi
    
    # Test Nomad config generation
    if declare -f generate_nomad_config &>/dev/null; then
        local nomad_config
        nomad_config=$(generate_nomad_config "develop")
        if [[ -n "$nomad_config" ]] && echo "$nomad_config" | grep -q "datacenter.*dc1"; then
            record_test "template_nomad" "PASS" "Nomad configuration template works"
        else
            record_test "template_nomad" "FAIL" "Nomad configuration template failed"
        fi
    else
        record_test "template_nomad" "FAIL" "Nomad configuration template function not available"
    fi
    
    # Test Vault config generation
    if declare -f generate_vault_config &>/dev/null; then
        local vault_config
        vault_config=$(generate_vault_config "develop" "/tmp/vault/data" "/tmp/vault/logs" "http://localhost:8200" "http://localhost:8201")
        if [[ -n "$vault_config" ]] && echo "$vault_config" | grep -q "ui.*true"; then
            record_test "template_vault" "PASS" "Vault configuration template works"
        else
            record_test "template_vault" "FAIL" "Vault configuration template failed"
        fi
    else
        record_test "template_vault" "FAIL" "Vault configuration template function not available"
    fi
}

# Test individual scripts
test_individual_scripts() {
    log_info "Testing individual scripts..."
    
    local scripts=("install-consul.sh" "install-nomad.sh" "deploy-vault-job.sh" "deploy-traefik-job.sh" "verify-deployment.sh" "deploy-all.sh")
    
    for script in "${scripts[@]}"; do
        test_script_exists "$script"
        test_script_syntax "$script"
        test_script_help "$script"
        test_script_dry_run "$script"
    done
}

# Test error handling
test_error_handling() {
    log_info "Testing error handling..."
    
    # Test with invalid environment
    local test_script="$SCRIPT_DIR/deploy-vault-job.sh"
    if [[ -f "$test_script" ]]; then
        if ! timeout 10 bash "$test_script" --environment invalid --dry-run 2>/dev/null; then
            record_test "error_invalid_env" "PASS" "Script properly rejects invalid environment"
        else
            record_test "error_invalid_env" "FAIL" "Script should reject invalid environment"
        fi
    else
        record_test "error_invalid_env" "FAIL" "Test script not available"
    fi
    
    # Test with missing parameters
    if [[ -f "$test_script" ]]; then
        if ! timeout 10 bash "$test_script" --email invalid-email --dry-run 2>/dev/null; then
            record_test "error_invalid_email" "PASS" "Script properly validates email format"
        else
            record_test "error_invalid_email" "WARN" "Script may not validate email format"
        fi
    fi
}

# Test idempotency (can only test structure, not full execution)
test_idempotency_structure() {
    log_info "Testing idempotency structure..."
    
    local scripts=("install-consul.sh" "install-nomad.sh")
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            # Check for idempotent patterns
            local idempotent_patterns=0
            
            # Check for service status checks
            if grep -q "systemctl.*is-active\|systemctl.*is-enabled\|service.*status" "$script_path"; then
                ((idempotent_patterns++))
            fi
            
            # Check for file existence checks
            if grep -q "if.*-f\|if.*-d\|if.*test.*-" "$script_path"; then
                ((idempotent_patterns++))
            fi
            
            # Check for version checks
            if grep -q "version.*installed\|already.*installed\|existing.*version" "$script_path"; then
                ((idempotent_patterns++))
            fi
            
            if [[ $idempotent_patterns -ge 2 ]]; then
                record_test "idempotent_$script" "PASS" "Script shows idempotent patterns ($idempotent_patterns found)"
            else
                record_test "idempotent_$script" "WARN" "Script may not be fully idempotent ($idempotent_patterns patterns found)"
            fi
        else
            record_test "idempotent_$script" "FAIL" "Script not available for testing"
        fi
    done
}

# Test security patterns
test_security_patterns() {
    log_info "Testing security patterns..."
    
    local scripts=("install-consul.sh" "install-nomad.sh" "deploy-vault-job.sh")
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            local security_patterns=0
            
            # Check for permission settings
            if grep -q "chmod\|chown\|permission" "$script_path"; then
                ((security_patterns++))
            fi
            
            # Check for user creation
            if grep -q "useradd\|adduser\|create.*user" "$script_path"; then
                ((security_patterns++))
            fi
            
            # Check for secure defaults
            if grep -q "security\|secure\|tls\|ssl" "$script_path"; then
                ((security_patterns++))
            fi
            
            if [[ $security_patterns -ge 2 ]]; then
                record_test "security_$script" "PASS" "Script follows security patterns ($security_patterns found)"
            else
                record_test "security_$script" "WARN" "Script may need more security considerations ($security_patterns patterns found)"
            fi
        else
            record_test "security_$script" "FAIL" "Script not available for testing"
        fi
    done
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/test-report-$(date +%Y%m%d_%H%M%S).md"
    
    create_directory "$TEST_RESULTS_DIR"
    
    cat > "$report_file" <<EOF
# Deployment Scripts Test Report

**Generated:** $(date)  
**Test Environment:** $TEST_ENVIRONMENT

## Summary

- **Total Tests:** ${#TESTS_RUN[@]}
- **Passed:** $TESTS_PASSED
- **Failed:** $TESTS_FAILED
- **Overall Status:** $([ $TESTS_FAILED -eq 0 ] && echo "✅ ALL TESTS PASSED" || echo "❌ SOME TESTS FAILED")

## Test Results

EOF
    
    # Group tests by category
    local categories=("exists" "syntax" "help" "dryrun" "common" "template" "error" "idempotent" "security")
    
    for category in "${categories[@]}"; do
        local found_tests=false
        
        for test_name in "${TESTS_RUN[@]}"; do
            if [[ "$test_name" == ${category}_* ]] || [[ "$test_name" == *_${category} ]]; then
                if [[ "$found_tests" == "false" ]]; then
                    echo "### $(echo ${category^} | sed 's/_/ /g') Tests" >> "$report_file"
                    echo "" >> "$report_file"
                    found_tests=true
                fi
                
                local result="${TEST_RESULTS[$test_name]%%:*}"
                local message="${TEST_RESULTS[$test_name]#*:}"
                
                case "$result" in
                    "PASS")
                        echo "- ✅ **$test_name**: $message" >> "$report_file"
                        ;;
                    "FAIL")
                        echo "- ❌ **$test_name**: $message" >> "$report_file"
                        ;;
                    "WARN")
                        echo "- ⚠️ **$test_name**: $message" >> "$report_file"
                        ;;
                esac
            fi
        done
        
        if [[ "$found_tests" == "true" ]]; then
            echo "" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" <<EOF

## Recommendations

EOF
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        cat >> "$report_file" <<EOF
✅ **All tests passed!** The deployment scripts appear to be ready for use.

### Next Steps:
1. Test scripts in a development environment
2. Verify idempotency by running scripts multiple times
3. Test error scenarios and recovery
4. Review security configurations
5. Update documentation as needed
EOF
    else
        cat >> "$report_file" <<EOF
❌ **Some tests failed.** Please address the following issues:

### Failed Tests:
EOF
        
        for test_name in "${TESTS_RUN[@]}"; do
            local result="${TEST_RESULTS[$test_name]%%:*}"
            local message="${TEST_RESULTS[$test_name]#*:}"
            
            if [[ "$result" == "FAIL" ]]; then
                echo "- **$test_name**: $message" >> "$report_file"
            fi
        done
        
        cat >> "$report_file" <<EOF

### Action Items:
1. Fix failed tests before deployment
2. Review script syntax and logic
3. Ensure all required scripts are present
4. Test error handling thoroughly
5. Validate security configurations
EOF
    fi
    
    cat >> "$report_file" <<EOF

## Test Environment Details

- **Project Root:** $PROJECT_ROOT
- **Scripts Directory:** $SCRIPT_DIR
- **Logs Directory:** $LOGS_DIR
- **Test Results Directory:** $TEST_RESULTS_DIR

---
*Generated by deployment scripts test suite*
EOF
    
    log_success "Test report generated: $report_file"
    
    # Display summary
    echo ""
    log_info "=== TEST SUMMARY ==="
    echo "Total Tests: ${#TESTS_RUN[@]}"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    else
        echo -e "${RED}❌ $TESTS_FAILED TESTS FAILED${NC}"
    fi
    
    echo "Full report: $report_file"
}

# Main test function
main() {
    log_info "=== Deployment Scripts Test Suite ==="
    log_info "Testing deployment scripts for idempotency and error handling"
    
    init_common_environment
    
    # Run all tests
    test_common_functions
    test_configuration_templates
    test_individual_scripts
    test_error_handling
    test_idempotency_structure
    test_security_patterns
    
    # Generate report
    generate_test_report
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "=== All tests passed! ==="
        exit 0
    else
        log_error "=== $TESTS_FAILED tests failed ==="
        exit 1
    fi
}

# Run tests
main "$@"