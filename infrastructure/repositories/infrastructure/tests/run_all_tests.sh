#!/bin/bash

# Master Test Runner for Infrastructure Test Suite
# Executes all infrastructure tests in the correct order

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-$SCRIPT_DIR/results}"
TEST_CONFIG_FILE="${TEST_CONFIG_FILE:-$SCRIPT_DIR/test_config.env}"
PARALLEL_EXECUTION="${PARALLEL_EXECUTION:-false}"
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test execution tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test suite definitions
declare -A TEST_SUITES=(
    ["integration"]="Nomad-Vault-Traefik Integration Tests"
    ["environment"]="Multi-Environment Deployment Tests" 
    ["bootstrap"]="Bootstrap and Dependency Resolution Tests"
    ["secrets"]="Secret Management and Rotation Tests"
)

# Test execution order (dependencies considered)
TEST_ORDER=("integration" "environment" "bootstrap" "secrets")

# Individual test files in execution order
declare -A TEST_FILES=(
    ["integration"]="nomad_cluster_formation_test.sh vault_nomad_deployment_test.sh traefik_vault_secret_integration_test.sh"
    ["environment"]="multi_environment_deployment_test.sh"
    ["bootstrap"]="token_lifecycle_test.sh circular_dependency_test.sh"
    ["secrets"]="secret_management_rotation_test.sh"
)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

log_test_suite() {
    echo -e "${CYAN}[SUITE]${NC} $1" >&2
}

# Utility functions
setup_test_environment() {
    log_info "Setting up test environment"
    
    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Load test configuration if available
    if [[ -f "$TEST_CONFIG_FILE" ]]; then
        log_info "Loading test configuration from $TEST_CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$TEST_CONFIG_FILE"
    else
        log_warning "Test configuration file not found: $TEST_CONFIG_FILE"
        log_info "Using default configuration"
    fi
    
    # Set default environment variables
    export TEST_ENV="${TEST_ENV:-test}"
    export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
    export NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
    export TRAEFIK_URL="${TRAEFIK_URL:-http://localhost:80}"
    export TEST_TIMEOUT="${TEST_TIMEOUT:-600}"
    export DEBUG="${DEBUG:-false}"
    
    log_info "Test environment configured:"
    log_info "  TEST_ENV: $TEST_ENV"
    log_info "  VAULT_ADDR: $VAULT_ADDR"
    log_info "  NOMAD_ADDR: $NOMAD_ADDR"
    log_info "  TRAEFIK_URL: $TRAEFIK_URL"
    log_info "  Results: $TEST_RESULTS_DIR"
}

check_prerequisites() {
    log_info "Checking test prerequisites"
    
    local missing_deps=()
    
    # Check required commands
    local required_commands=("curl" "jq" "timeout" "bc")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check optional commands (warn if missing)
    local optional_commands=("vault" "nomad" "docker")
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_warning "Optional command not found: $cmd (some tests may be skipped)"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and retry"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

run_test_file() {
    local suite="$1"
    local test_file="$2"
    local test_path="$SCRIPT_DIR/$suite/$test_file"
    
    if [[ ! -f "$test_path" ]]; then
        log_error "Test file not found: $test_path"
        return 1
    fi
    
    # Make test file executable
    chmod +x "$test_path"
    
    log_info "Running test: $test_file"
    
    # Create result files
    local result_file="$TEST_RESULTS_DIR/${suite}_${test_file%.sh}_result.txt"
    local output_file="$TEST_RESULTS_DIR/${suite}_${test_file%.sh}_output.txt"
    
    local start_time end_time duration
    start_time=$(date +%s)
    
    # Run the test with timeout
    local exit_code=0
    if timeout "$TEST_TIMEOUT" "$test_path" > "$output_file" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    # Process results
    if [[ $exit_code -eq 0 ]]; then
        echo "PASSED" > "$result_file"
        log_success "Test passed: $test_file (${duration}s)"
        ((PASSED_TESTS++))
    elif [[ $exit_code -eq 124 ]]; then
        echo "TIMEOUT" > "$result_file"
        log_error "Test timed out: $test_file (${TEST_TIMEOUT}s)"
        ((FAILED_TESTS++))
    else
        echo "FAILED" > "$result_file"
        log_error "Test failed: $test_file (exit code: $exit_code, duration: ${duration}s)"
        ((FAILED_TESTS++))
    fi
    
    # Add metadata to result file
    {
        echo "EXIT_CODE=$exit_code"
        echo "DURATION=${duration}s"
        echo "TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >> "$result_file"
    
    ((TOTAL_TESTS++))
    
    return $exit_code
}

run_test_suite() {
    local suite="$1"
    local suite_description="${TEST_SUITES[$suite]}"
    
    log_test_suite "$suite_description"
    
    local files="${TEST_FILES[$suite]}"
    local suite_start_time suite_end_time suite_duration
    local suite_passed=0 suite_failed=0
    
    suite_start_time=$(date +%s)
    
    # Run tests in the suite
    for test_file in $files; do
        if run_test_file "$suite" "$test_file"; then
            ((suite_passed++))
        else
            ((suite_failed++))
        fi
        
        # Brief pause between tests
        sleep 1
    done
    
    suite_end_time=$(date +%s)
    suite_duration=$((suite_end_time - suite_start_time))
    
    # Suite summary
    echo
    log_info "Suite '$suite' completed:"
    log_info "  Passed: $suite_passed"
    log_info "  Failed: $suite_failed"
    log_info "  Duration: ${suite_duration}s"
    echo
    
    return $([[ $suite_failed -eq 0 ]])
}

run_all_tests_sequential() {
    log_info "Running tests sequentially"
    
    local failed_suites=()
    
    for suite in "${TEST_ORDER[@]}"; do
        if ! run_test_suite "$suite"; then
            failed_suites+=("$suite")
        fi
    done
    
    if [[ ${#failed_suites[@]} -gt 0 ]]; then
        log_warning "Failed test suites: ${failed_suites[*]}"
        return 1
    fi
    
    return 0
}

run_all_tests_parallel() {
    log_info "Running tests in parallel (limited parallelization)"
    
    # Note: Some tests have dependencies, so we can't run everything in parallel
    # We'll run suites that don't depend on each other in parallel
    
    local pids=()
    local failed_suites=()
    
    # Group 1: Integration tests (foundation)
    run_test_suite "integration" &
    pids+=($!)
    
    # Wait for integration tests to complete before proceeding
    wait "${pids[@]}"
    
    # Check integration test results
    local integration_result_files=("$TEST_RESULTS_DIR"/integration_*_result.txt)
    for result_file in "${integration_result_files[@]}"; do
        if [[ -f "$result_file" ]] && grep -q "FAILED\|TIMEOUT" "$result_file"; then
            log_warning "Integration tests failed - skipping dependent tests"
            return 1
        fi
    done
    
    # Group 2: Environment and Bootstrap tests (can run in parallel)
    pids=()
    run_test_suite "environment" &
    pids+=($!)
    run_test_suite "bootstrap" &
    pids+=($!)
    
    # Wait for group 2
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed_suites+=("environment_or_bootstrap")
        fi
    done
    
    # Group 3: Secrets tests (depends on others)
    if ! run_test_suite "secrets"; then
        failed_suites+=("secrets")
    fi
    
    if [[ ${#failed_suites[@]} -gt 0 ]]; then
        log_warning "Failed test suites: ${failed_suites[*]}"
        return 1
    fi
    
    return 0
}

generate_test_report() {
    log_info "Generating comprehensive test report"
    
    local report_file="$TEST_RESULTS_DIR/test_report.html"
    local summary_file="$TEST_RESULTS_DIR/test_summary.json"
    
    # Generate JSON summary
    local end_time
    end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    cat > "$summary_file" <<EOF
{
  "test_run": {
    "started_at": "$TEST_START_TIME",
    "completed_at": "$end_time",
    "duration": "${TEST_DURATION}s",
    "parallel_execution": $PARALLEL_EXECUTION
  },
  "results": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))
  },
  "environment": {
    "test_env": "${TEST_ENV}",
    "vault_addr": "${VAULT_ADDR}",
    "nomad_addr": "${NOMAD_ADDR}",
    "traefik_url": "${TRAEFIK_URL}"
  }
}
EOF
    
    # Generate HTML report
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Infrastructure Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 15px; border-radius: 5px; }
        .passed { background: #d4edda; color: #155724; }
        .failed { background: #f8d7da; color: #721c24; }
        .skipped { background: #fff3cd; color: #856404; }
        .suite { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .test-file { margin: 10px 0; padding: 10px; background: #f9f9f9; border-radius: 3px; }
        pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Infrastructure Test Report</h1>
        <p>Generated: $end_time</p>
        <p>Test Environment: ${TEST_ENV}</p>
    </div>
    
    <div class="summary">
        <div class="metric passed">
            <h3>$PASSED_TESTS</h3>
            <p>Passed</p>
        </div>
        <div class="metric failed">
            <h3>$FAILED_TESTS</h3>
            <p>Failed</p>
        </div>
        <div class="metric skipped">
            <h3>$SKIPPED_TESTS</h3>
            <p>Skipped</p>
        </div>
        <div class="metric">
            <h3>$TOTAL_TESTS</h3>
            <p>Total</p>
        </div>
    </div>
EOF
    
    # Add test suite details
    for suite in "${TEST_ORDER[@]}"; do
        local suite_description="${TEST_SUITES[$suite]}"
        
        cat >> "$report_file" <<EOF
    <div class="suite">
        <h2>$suite_description</h2>
EOF
        
        local files="${TEST_FILES[$suite]}"
        for test_file in $files; do
            local result_file="$TEST_RESULTS_DIR/${suite}_${test_file%.sh}_result.txt"
            local output_file="$TEST_RESULTS_DIR/${suite}_${test_file%.sh}_output.txt"
            
            if [[ -f "$result_file" ]]; then
                local result
                result=$(head -1 "$result_file")
                local duration
                duration=$(grep "DURATION=" "$result_file" | cut -d'=' -f2)
                
                local status_class=""
                case "$result" in
                    "PASSED") status_class="passed" ;;
                    "FAILED") status_class="failed" ;;
                    "TIMEOUT") status_class="failed" ;;
                    *) status_class="skipped" ;;
                esac
                
                cat >> "$report_file" <<EOF
        <div class="test-file $status_class">
            <h4>$test_file - $result ($duration)</h4>
EOF
                
                if [[ "$result" != "PASSED" ]] && [[ -f "$output_file" ]]; then
                    cat >> "$report_file" <<EOF
            <pre>$(tail -20 "$output_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>
EOF
                fi
                
                cat >> "$report_file" <<EOF
        </div>
EOF
            fi
        done
        
        cat >> "$report_file" <<EOF
    </div>
EOF
    done
    
    cat >> "$report_file" <<EOF
</body>
</html>
EOF
    
    log_success "Test report generated:"
    log_info "  HTML Report: $report_file"
    log_info "  JSON Summary: $summary_file"
}

print_final_summary() {
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi
    
    log_header "FINAL TEST RESULTS"
    
    echo -e "${BLUE}Test Execution Summary:${NC}"
    echo -e "  Total Tests:    ${TOTAL_TESTS}"
    echo -e "  Passed:         ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "  Failed:         ${RED}${FAILED_TESTS}${NC}"
    echo -e "  Skipped:        ${YELLOW}${SKIPPED_TESTS}${NC}"
    echo -e "  Success Rate:   ${success_rate}%"
    echo -e "  Duration:       ${TEST_DURATION}s"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "ALL TESTS PASSED! ✅"
        echo -e "${GREEN}Infrastructure test suite completed successfully.${NC}"
        return 0
    else
        log_error "SOME TESTS FAILED! ❌"
        echo -e "${RED}Please review failed tests and fix issues before deployment.${NC}"
        return 1
    fi
}

cleanup() {
    log_info "Cleaning up test environment"
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Clean up temporary test files if not in debug mode
    if [[ "${DEBUG:-false}" != "true" ]]; then
        find "$TEST_RESULTS_DIR" -name "*.tmp" -delete 2>/dev/null || true
    fi
}

# Main execution
main() {
    local start_time end_time
    start_time=$(date +%s)
    TEST_START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Set up signal handlers
    trap cleanup EXIT
    trap 'log_error "Test execution interrupted"; exit 130' INT TERM
    
    log_header "INFRASTRUCTURE TEST SUITE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --parallel)
                PARALLEL_EXECUTION="true"
                shift
                ;;
            --sequential)
                PARALLEL_EXECUTION="false"
                shift
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            --config)
                TEST_CONFIG_FILE="$2"
                shift 2
                ;;
            --results-dir)
                TEST_RESULTS_DIR="$2"
                shift 2
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --parallel          Run tests in parallel where possible"
                echo "  --sequential        Run tests sequentially (default)"
                echo "  --timeout SECONDS   Set test timeout (default: 600)"
                echo "  --config FILE       Use custom test configuration file"
                echo "  --results-dir DIR   Custom results directory"
                echo "  --debug             Enable debug output"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Setup and prerequisites
    setup_test_environment || exit 1
    check_prerequisites || exit 1
    
    log_info "Starting infrastructure test execution"
    log_info "Execution mode: $([ "$PARALLEL_EXECUTION" == "true" ] && echo "parallel" || echo "sequential")"
    
    # Run tests
    local test_success=true
    if [[ "$PARALLEL_EXECUTION" == "true" ]]; then
        run_all_tests_parallel || test_success=false
    else
        run_all_tests_sequential || test_success=false
    fi
    
    # Calculate duration
    end_time=$(date +%s)
    TEST_DURATION=$((end_time - start_time))
    
    # Generate reports and summary
    generate_test_report
    print_final_summary
    
    # Exit with appropriate code
    if $test_success; then
        exit 0
    else
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi