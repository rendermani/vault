#!/bin/bash
# Pipeline QA Test Suite Runner
# Executes all pipeline tests in sequence and provides comprehensive reporting
# Master test runner for the complete two-phase bootstrap pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_RESULTS_DIR="$SCRIPT_DIR/results"
MASTER_LOG="$TEST_RESULTS_DIR/master-pipeline-test-$(date +%Y%m%d_%H%M%S).log"
SUMMARY_REPORT="$TEST_RESULTS_DIR/pipeline-qa-summary-$(date +%Y%m%d_%H%M%S).md"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test suite configuration
TESTS=(
    "phase1-nomad-bootstrap-test.sh|Phase 1: Nomad Bootstrap Tests|Critical"
    "phase2-vault-integration-test.sh|Phase 2: Vault Integration Tests|Critical"
    "environment-propagation-test.sh|Environment Variable Propagation Tests|High"
    "failure-rollback-test.sh|Failure Scenarios and Rollback Tests|High"
    "idempotency-validation-test.sh|Idempotency Validation Tests|High"
    "ci-cd-integration-test.sh|CI/CD Integration Tests|Medium"
)

# Test results tracking
declare -A TEST_RESULTS
declare -A TEST_DURATIONS
declare -A TEST_DETAILS

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Logging functions
log_header() {
    local msg="$1"
    echo ""
    echo -e "${BOLD}${CYAN}================================================${NC}"
    echo -e "${BOLD}${CYAN} $msg${NC}"
    echo -e "${BOLD}${CYAN}================================================${NC}"
    echo "$msg" >> "$MASTER_LOG"
    echo "================================================" >> "$MASTER_LOG"
}

log_test_start() {
    local msg="$1"
    echo ""
    echo -e "${BLUE}🧪 Starting: ${BOLD}$msg${NC}"
    echo "$(date): Starting $msg" >> "$MASTER_LOG"
}

log_test_pass() {
    local msg="$1"
    echo -e "${GREEN}✅ PASSED: $msg${NC}"
    echo "$(date): PASSED $msg" >> "$MASTER_LOG"
}

log_test_fail() {
    local msg="$1"
    echo -e "${RED}❌ FAILED: $msg${NC}"
    echo "$(date): FAILED $msg" >> "$MASTER_LOG"
}

log_test_warn() {
    local msg="$1"
    echo -e "${YELLOW}⚠️  WARNING: $msg${NC}"
    echo "$(date): WARNING $msg" >> "$MASTER_LOG"
}

log_info() {
    local msg="$1"
    echo -e "${BLUE}ℹ️  $msg${NC}"
    echo "$(date): INFO $msg" >> "$MASTER_LOG"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}🎉 $msg${NC}"
    echo "$(date): SUCCESS $msg" >> "$MASTER_LOG"
}

log_error() {
    local msg="$1"
    echo -e "${RED}💥 $msg${NC}"
    echo "$(date): ERROR $msg" >> "$MASTER_LOG"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Clean up any test artifacts
    rm -f /tmp/pipeline-test-*.tmp 2>/dev/null || true
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check required binaries
    local required_bins=("bash" "nomad" "curl")
    for bin in "${required_bins[@]}"; do
        if command -v "$bin" >/dev/null 2>&1; then
            log_info "✓ Found required binary: $bin"
        else
            log_error "✗ Missing required binary: $bin"
            missing_deps+=("$bin")
        fi
    done
    
    # Check test scripts exist
    for test_spec in "${TESTS[@]}"; do
        IFS='|' read -r script_name description priority <<< "$test_spec"
        local script_path="$SCRIPT_DIR/$script_name"
        
        if [[ -f "$script_path" ]]; then
            log_info "✓ Found test script: $script_name"
            
            # Check if executable
            if [[ -x "$script_path" ]]; then
                log_info "✓ Test script is executable: $script_name"
            else
                log_info "Making test script executable: $script_name"
                chmod +x "$script_path"
            fi
        else
            log_error "✗ Missing test script: $script_name"
            missing_deps+=("$script_name")
        fi
    done
    
    # Check infrastructure directory structure
    local required_dirs=(
        "$INFRA_DIR/scripts"
        "$INFRA_DIR/config"
        "$TEST_RESULTS_DIR"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "✓ Found required directory: $dir"
        else
            log_error "✗ Missing required directory: $dir"
            missing_deps+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies and ensure all test scripts are present."
        exit 1
    else
        log_success "All prerequisites satisfied!"
    fi
}

# Run individual test suite
run_test_suite() {
    local script_name="$1"
    local description="$2"
    local priority="$3"
    local script_path="$SCRIPT_DIR/$script_name"
    
    log_test_start "$description"
    
    local start_time=$(date +%s)
    local test_log="$TEST_RESULTS_DIR/${script_name%.sh}-$(date +%Y%m%d_%H%M%S).log"
    
    # Run the test
    local exit_code=0
    if bash "$script_path" > "$test_log" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Store results
    TEST_DURATIONS["$script_name"]=$duration
    
    # Parse test results from log
    local test_passed=0
    local test_failed=0
    local test_warnings=0
    
    if [[ -f "$test_log" ]]; then
        test_passed=$(grep -c "\[PASS\]" "$test_log" 2>/dev/null || echo "0")
        test_failed=$(grep -c "\[FAIL\]" "$test_log" 2>/dev/null || echo "0")
        test_warnings=$(grep -c "\[WARN\]" "$test_log" 2>/dev/null || echo "0")
    fi
    
    # Determine overall test result
    if [[ $exit_code -eq 0 && $test_failed -eq 0 ]]; then
        TEST_RESULTS["$script_name"]="PASSED"
        log_test_pass "$description (${duration}s)"
        ((PASSED_TESTS++))
    elif [[ $test_warnings -gt 0 && $test_failed -eq 0 ]]; then
        TEST_RESULTS["$script_name"]="WARNING"
        log_test_warn "$description (${duration}s) - $test_warnings warnings"
        ((WARNING_TESTS++))
    else
        TEST_RESULTS["$script_name"]="FAILED"
        log_test_fail "$description (${duration}s) - $test_failed failures"
        ((FAILED_TESTS++))
    fi
    
    # Store detailed results
    TEST_DETAILS["$script_name"]="Passed: $test_passed, Failed: $test_failed, Warnings: $test_warnings, Duration: ${duration}s, Priority: $priority"
    
    ((TOTAL_TESTS++))
    
    # Copy test log to master log
    echo "" >> "$MASTER_LOG"
    echo "=== $description Test Log ===" >> "$MASTER_LOG"
    cat "$test_log" >> "$MASTER_LOG"
    echo "=== End $description Test Log ===" >> "$MASTER_LOG"
    echo "" >> "$MASTER_LOG"
}

# Generate summary report
generate_summary_report() {
    log_header "Generating Summary Report"
    
    cat > "$SUMMARY_REPORT" << EOF
# Pipeline QA Test Summary Report

**Generated:** $(date)  
**Host:** $(hostname)  
**Infrastructure Path:** $INFRA_DIR  

## Executive Summary

| Metric | Value |
|--------|-------|
| Total Test Suites | $TOTAL_TESTS |
| Passed | $PASSED_TESTS |
| Failed | $FAILED_TESTS |
| Warnings | $WARNING_TESTS |
| Success Rate | $(( (PASSED_TESTS + WARNING_TESTS) * 100 / TOTAL_TESTS ))% |

EOF
    
    # Add test results table
    cat >> "$SUMMARY_REPORT" << EOF
## Test Suite Results

| Test Suite | Status | Duration | Details |
|------------|---------|----------|---------|
EOF
    
    for test_spec in "${TESTS[@]}"; do
        IFS='|' read -r script_name description priority <<< "$test_spec"
        local status="${TEST_RESULTS[$script_name]:-UNKNOWN}"
        local duration="${TEST_DURATIONS[$script_name]:-0}"
        local details="${TEST_DETAILS[$script_name]:-N/A}"
        
        local status_emoji=""
        case "$status" in
            "PASSED") status_emoji="✅" ;;
            "FAILED") status_emoji="❌" ;;
            "WARNING") status_emoji="⚠️" ;;
            *) status_emoji="❓" ;;
        esac
        
        echo "| $description | $status_emoji $status | ${duration}s | $details |" >> "$SUMMARY_REPORT"
    done
    
    # Add recommendations
    cat >> "$SUMMARY_REPORT" << EOF

## Test Categories

### Phase 1: Nomad Bootstrap Tests
- **Purpose:** Validate that Nomad can start without Vault dependency
- **Coverage:** Configuration generation, service startup, simple job scheduling
- **Status:** ${TEST_RESULTS["phase1-nomad-bootstrap-test.sh"]:-NOT_RUN}

### Phase 2: Vault Integration Tests  
- **Purpose:** Validate Vault integration and configuration reconfiguration
- **Coverage:** Vault accessibility, policy creation, template jobs, phase transition
- **Status:** ${TEST_RESULTS["phase2-vault-integration-test.sh"]:-NOT_RUN}

### Environment Variable Propagation Tests
- **Purpose:** Ensure environment variables are correctly propagated through all stages
- **Coverage:** Template loading, config generation, phase transitions, consistency
- **Status:** ${TEST_RESULTS["environment-propagation-test.sh"]:-NOT_RUN}

### Failure Scenarios and Rollback Tests
- **Purpose:** Validate system handles failures and can rollback gracefully
- **Coverage:** Config backup/restore, failure handling, state consistency, network issues
- **Status:** ${TEST_RESULTS["failure-rollback-test.sh"]:-NOT_RUN}

### Idempotency Validation Tests
- **Purpose:** Ensure deployment operations can be run multiple times safely
- **Coverage:** Config generation, script execution, environment handling, validation
- **Status:** ${TEST_RESULTS["idempotency-validation-test.sh"]:-NOT_RUN}

### CI/CD Integration Tests
- **Purpose:** Validate integration with continuous deployment pipelines
- **Coverage:** GitHub Actions, secrets management, automated testing, multi-environment
- **Status:** ${TEST_RESULTS["ci-cd-integration-test.sh"]:-NOT_RUN}

## Recommendations

EOF
    
    # Add specific recommendations based on results
    if [[ $FAILED_TESTS -eq 0 && $WARNING_TESTS -eq 0 ]]; then
        cat >> "$SUMMARY_REPORT" << EOF
🎉 **All tests passed!** The two-phase bootstrap pipeline is ready for production deployment.

### Next Steps:
1. Deploy to development environment for final validation
2. Set up monitoring and alerting
3. Configure production CI/CD pipelines
4. Document operational procedures
EOF
    elif [[ $FAILED_TESTS -eq 0 && $WARNING_TESTS -gt 0 ]]; then
        cat >> "$SUMMARY_REPORT" << EOF
⚠️ **Tests passed with warnings.** Address warnings before production deployment.

### Action Items:
1. Review and resolve all warnings in test logs
2. Update documentation where indicated
3. Consider implementing suggested improvements
4. Proceed with caution to development environment
EOF
    else
        cat >> "$SUMMARY_REPORT" << EOF
❌ **Critical issues found.** Do not proceed to production until all failures are resolved.

### Critical Actions Required:
1. Fix all failing tests immediately
2. Review test logs for specific failure details
3. Re-run full test suite after fixes
4. Consider additional testing in isolated environment

### Failed Test Suites:
EOF
        
        for test_spec in "${TESTS[@]}"; do
            IFS='|' read -r script_name description priority <<< "$test_spec"
            if [[ "${TEST_RESULTS[$script_name]}" == "FAILED" ]]; then
                echo "- **$description** ($priority priority)" >> "$SUMMARY_REPORT"
            fi
        done
    fi
    
    # Add log locations
    cat >> "$SUMMARY_REPORT" << EOF

## Log Files

- **Master Log:** $MASTER_LOG
- **Summary Report:** $SUMMARY_REPORT
- **Individual Test Logs:** $TEST_RESULTS_DIR/

## Test Command Reference

\`\`\`bash
# Run all tests
$SCRIPT_DIR/run-all-pipeline-tests.sh

# Run individual test suites
$SCRIPT_DIR/phase1-nomad-bootstrap-test.sh
$SCRIPT_DIR/phase2-vault-integration-test.sh
$SCRIPT_DIR/environment-propagation-test.sh
$SCRIPT_DIR/failure-rollback-test.sh
$SCRIPT_DIR/idempotency-validation-test.sh
$SCRIPT_DIR/ci-cd-integration-test.sh
\`\`\`

---
*Generated by Pipeline QA Test Suite v1.0*
EOF

    log_success "Summary report generated: $SUMMARY_REPORT"
}

# Display final results
display_final_results() {
    echo ""
    echo ""
    log_header "Final Test Results"
    
    # Display summary table
    echo -e "${BOLD}Test Suite Summary:${NC}"
    echo ""
    printf "%-45s %-10s %-8s %s\n" "Test Suite" "Status" "Duration" "Priority"
    echo "$(printf '%.0s-' {1..80})"
    
    for test_spec in "${TESTS[@]}"; do
        IFS='|' read -r script_name description priority <<< "$test_spec"
        local status="${TEST_RESULTS[$script_name]:-UNKNOWN}"
        local duration="${TEST_DURATIONS[$script_name]:-0}s"
        
        local status_color=""
        case "$status" in
            "PASSED") status_color="${GREEN}" ;;
            "FAILED") status_color="${RED}" ;;
            "WARNING") status_color="${YELLOW}" ;;
            *) status_color="${NC}" ;;
        esac
        
        printf "%-45s ${status_color}%-10s${NC} %-8s %s\n" "$description" "$status" "$duration" "$priority"
    done
    
    echo ""
    echo -e "${BOLD}Overall Results:${NC}"
    echo "  Total Test Suites: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS" 
    echo "  Warnings: $WARNING_TESTS"
    echo "  Success Rate: $(( (PASSED_TESTS + WARNING_TESTS) * 100 / TOTAL_TESTS ))%"
    
    echo ""
    echo -e "${BOLD}Generated Files:${NC}"
    echo "  Master Log: $MASTER_LOG"
    echo "  Summary Report: $SUMMARY_REPORT"
    echo "  Test Results Directory: $TEST_RESULTS_DIR"
    
    echo ""
    
    # Final status determination
    if [[ $FAILED_TESTS -eq 0 && $WARNING_TESTS -eq 0 ]]; then
        log_success "🎉 ALL TESTS PASSED! Two-phase bootstrap pipeline is ready for deployment!"
        echo ""
        echo -e "${GREEN}${BOLD}✓ Phase 1 (Nomad Bootstrap) validated${NC}"
        echo -e "${GREEN}${BOLD}✓ Phase 2 (Vault Integration) validated${NC}"
        echo -e "${GREEN}${BOLD}✓ Environment propagation validated${NC}"
        echo -e "${GREEN}${BOLD}✓ Failure handling validated${NC}"
        echo -e "${GREEN}${BOLD}✓ Idempotency validated${NC}"
        echo -e "${GREEN}${BOLD}✓ CI/CD integration validated${NC}"
        echo ""
        echo "🚀 Ready to deploy to development environment!"
        return 0
    elif [[ $FAILED_TESTS -eq 0 && $WARNING_TESTS -gt 0 ]]; then
        log_test_warn "Tests completed with warnings. Review before production deployment."
        echo ""
        echo -e "${YELLOW}⚠️  Address $WARNING_TESTS warning(s) before production deployment${NC}"
        echo "📋 Check summary report for details: $SUMMARY_REPORT"
        return 0
    else
        log_error "💥 CRITICAL ISSUES FOUND! Do not proceed to production."
        echo ""
        echo -e "${RED}${BOLD}❌ $FAILED_TESTS test suite(s) failed${NC}"
        [[ $WARNING_TESTS -gt 0 ]] && echo -e "${YELLOW}⚠️  $WARNING_TESTS test suite(s) have warnings${NC}"
        echo ""
        echo -e "${RED}🛑 Fix all failures before proceeding!${NC}"
        echo "📋 Check logs for details: $MASTER_LOG"
        return 1
    fi
}

# Main test execution
main() {
    # Setup cleanup trap
    trap cleanup EXIT
    
    log_header "Pipeline QA Test Suite Runner"
    echo ""
    echo "🔬 Comprehensive testing of the two-phase bootstrap deployment pipeline"
    echo "📁 Infrastructure Directory: $INFRA_DIR"
    echo "📊 Results Directory: $TEST_RESULTS_DIR"
    echo "📝 Master Log: $MASTER_LOG"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize master log
    cat > "$MASTER_LOG" << EOF
Pipeline QA Test Suite Execution Log
====================================
Start Time: $(date)
Host: $(hostname)
Infrastructure Directory: $INFRA_DIR
Results Directory: $TEST_RESULTS_DIR

EOF
    
    log_header "Running Test Suites"
    
    # Run each test suite
    for test_spec in "${TESTS[@]}"; do
        IFS='|' read -r script_name description priority <<< "$test_spec"
        run_test_suite "$script_name" "$description" "$priority"
    done
    
    # Generate summary report
    generate_summary_report
    
    # Display final results
    display_final_results
}

# Run main function
main "$@"