#!/bin/bash
# Simple test script for deployment scripts - validates basic functionality
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Record test result
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
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
        if bash -n "$script_path" 2>/dev/null; then
            record_test "syntax_$script_name" "PASS" "Script syntax is valid"
        else
            record_test "syntax_$script_name" "FAIL" "Script has syntax errors"
        fi
    else
        record_test "syntax_$script_name" "FAIL" "Script does not exist"
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

# Test individual scripts
test_individual_scripts() {
    log_info "Testing individual scripts..."
    
    local scripts=("install-consul.sh" "install-nomad.sh" "deploy-vault-job.sh" "deploy-traefik-job.sh" "verify-deployment.sh" "deploy-all.sh" "common.sh" "config-templates.sh")
    
    for script in "${scripts[@]}"; do
        test_script_exists "$script"
        test_script_syntax "$script"
    done
}

# Test idempotency structure
test_idempotency_structure() {
    log_info "Testing idempotency structure..."
    
    local scripts=("install-consul.sh" "install-nomad.sh")
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            # Check for idempotent patterns
            local idempotent_patterns=0
            
            # Check for service status checks
            if grep -q "systemctl.*is-active\|systemctl.*is-enabled" "$script_path"; then
                ((idempotent_patterns++))
            fi
            
            # Check for file existence checks
            if grep -q "if.*-f\|if.*-d" "$script_path"; then
                ((idempotent_patterns++))
            fi
            
            # Check for version checks
            if grep -q "version.*installed\|already.*installed" "$script_path"; then
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

# Main test function
main() {
    log_info "=== Simple Deployment Scripts Test ==="
    log_info "Testing deployment scripts for basic functionality"
    
    init_common_environment
    
    # Run basic tests
    test_common_functions
    test_individual_scripts
    test_idempotency_structure
    
    # Display summary
    echo ""
    log_info "=== TEST SUMMARY ==="
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "✅ ALL TESTS PASSED"
        echo ""
        echo "The deployment scripts appear to be ready for use!"
        echo ""
        echo "Next steps:"
        echo "1. Test scripts in a safe environment with: ./deploy-all.sh --dry-run --environment develop"
        echo "2. For production deployment: sudo ./deploy-all.sh --environment production"
        echo "3. For full verification: ./verify-deployment.sh --environment production"
        exit 0
    else
        log_error "❌ $TESTS_FAILED TESTS FAILED"
        exit 1
    fi
}

# Run tests
main "$@"