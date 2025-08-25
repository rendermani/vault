#!/bin/bash

# Test Framework for Infrastructure Testing
# Provides common testing utilities and assertions

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test suite configuration
TEST_TIMEOUT=${TEST_TIMEOUT:-300}
TEST_RETRY_COUNT=${TEST_RETRY_COUNT:-3}
TEST_RETRY_DELAY=${TEST_RETRY_DELAY:-5}

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

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

log_test_start() {
    echo -e "${CYAN}[TEST]${NC} Starting: $1" >&2
}

log_test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" >&2
    ((TESTS_PASSED++))
}

log_test_fail() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
    ((TESTS_FAILED++))
}

log_test_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1" >&2
    ((TESTS_SKIPPED++))
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        log_error "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$not_expected" != "$actual" ]]; then
        return 0
    else
        log_error "$message: expected not '$not_expected', got '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        log_error "$message: '$haystack' does not contain '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        log_error "$message: '$haystack' contains '$needle'"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        return 0
    else
        log_error "$message: condition is not true"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [[ "$condition" == "false" ]] || [[ "$condition" != "0" ]]; then
        return 0
    else
        log_error "$message: condition is not false"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File does not exist}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        log_error "$message: '$file'"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory does not exist}"
    
    if [[ -d "$dir" ]]; then
        return 0
    else
        log_error "$message: '$dir'"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command failed}"
    
    if eval "$command" >/dev/null 2>&1; then
        return 0
    else
        log_error "$message: '$command'"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-Command unexpectedly succeeded}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        return 0
    else
        log_error "$message: '$command'"
        return 1
    fi
}

assert_http_status() {
    local url="$1"
    local expected_status="$2"
    local message="${3:-HTTP status check failed}"
    
    local actual_status
    actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$actual_status" == "$expected_status" ]]; then
        return 0
    else
        log_error "$message: expected $expected_status, got $actual_status for URL $url"
        return 1
    fi
}

assert_service_running() {
    local service_name="$1"
    local message="${2:-Service is not running}"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        return 0
    else
        log_error "$message: '$service_name'"
        return 1
    fi
}

assert_port_open() {
    local host="$1"
    local port="$2"
    local message="${3:-Port is not open}"
    
    if nc -z "$host" "$port" 2>/dev/null; then
        return 0
    else
        log_error "$message: $host:$port"
        return 1
    fi
}

# Test execution functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    local timeout="${3:-$TEST_TIMEOUT}"
    
    ((TESTS_TOTAL++))
    log_test_start "$test_name"
    
    local start_time
    start_time=$(date +%s)
    
    if timeout "$timeout" bash -c "$test_function" 2>&1; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_test_pass "$test_name (${duration}s)"
        return 0
    else
        local exit_code=$?
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [[ $exit_code -eq 124 ]]; then
            log_test_fail "$test_name - TIMEOUT after ${timeout}s"
        else
            log_test_fail "$test_name (${duration}s)"
        fi
        return $exit_code
    fi
}

run_test_with_retry() {
    local test_name="$1"
    local test_function="$2"
    local max_retries="${3:-$TEST_RETRY_COUNT}"
    local retry_delay="${4:-$TEST_RETRY_DELAY}"
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_warning "Retrying $test_name (attempt $attempt/$max_retries)"
            sleep "$retry_delay"
        fi
        
        if run_test "$test_name" "$test_function"; then
            return 0
        fi
        
        ((attempt++))
    done
    
    log_error "$test_name failed after $max_retries attempts"
    return 1
}

skip_test() {
    local test_name="$1"
    local reason="${2:-No reason provided}"
    
    ((TESTS_TOTAL++))
    log_test_skip "$test_name - $reason"
}

# Test suite management
print_test_summary() {
    echo
    echo "========================================="
    echo "Test Suite Summary"
    echo "========================================="
    echo "Total Tests:  $TESTS_TOTAL"
    echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped:      ${YELLOW}$TESTS_SKIPPED${NC}"
    echo "========================================="
    
    local success_rate=0
    if [[ $TESTS_TOTAL -gt 0 ]]; then
        success_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    fi
    
    echo "Success Rate: ${success_rate}%"
    echo
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Utility functions for infrastructure testing
wait_for_service() {
    local service_name="$1"
    local timeout="${2:-60}"
    local check_interval="${3:-5}"
    
    log_info "Waiting for service '$service_name' to be ready (timeout: ${timeout}s)"
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            log_success "Service '$service_name' is ready"
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        log_debug "Waiting for service '$service_name'... (${elapsed}/${timeout}s)"
    done
    
    log_error "Service '$service_name' did not start within ${timeout}s"
    return 1
}

wait_for_http_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-60}"
    local check_interval="${4:-5}"
    
    log_info "Waiting for HTTP endpoint '$url' (timeout: ${timeout}s)"
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        
        if [[ "$status" == "$expected_status" ]]; then
            log_success "HTTP endpoint '$url' is ready (status: $status)"
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        log_debug "Waiting for HTTP endpoint '$url'... (${elapsed}/${timeout}s, status: $status)"
    done
    
    log_error "HTTP endpoint '$url' did not respond with status $expected_status within ${timeout}s"
    return 1
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-60}"
    local check_interval="${4:-2}"
    
    log_info "Waiting for port $host:$port (timeout: ${timeout}s)"
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            log_success "Port $host:$port is open"
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        log_debug "Waiting for port $host:$port... (${elapsed}/${timeout}s)"
    done
    
    log_error "Port $host:$port did not open within ${timeout}s"
    return 1
}

# Configuration and environment helpers
load_test_config() {
    local config_file="${1:-test_config.env}"
    
    if [[ -f "$config_file" ]]; then
        log_info "Loading test configuration from $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_warning "Test configuration file '$config_file' not found, using defaults"
    fi
}

setup_test_environment() {
    log_info "Setting up test environment"
    
    # Set default test environment variables
    export TEST_ENV="${TEST_ENV:-test}"
    export NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
    export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
    export TRAEFIK_URL="${TRAEFIK_URL:-http://localhost:80}"
    
    # Create temporary directory for test artifacts
    export TEST_TEMP_DIR="${TEST_TEMP_DIR:-/tmp/infrastructure_tests_$$}"
    mkdir -p "$TEST_TEMP_DIR"
    
    log_info "Test environment ready"
    log_debug "TEST_TEMP_DIR: $TEST_TEMP_DIR"
    log_debug "NOMAD_ADDR: $NOMAD_ADDR"
    log_debug "VAULT_ADDR: $VAULT_ADDR"
    log_debug "TRAEFIK_URL: $TRAEFIK_URL"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment"
    
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
        log_debug "Removed temporary directory: $TEST_TEMP_DIR"
    fi
}

# Signal handlers for cleanup
trap cleanup_test_environment EXIT
trap 'log_error "Test interrupted"; exit 130' INT TERM

# Initialize test environment on sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced
    setup_test_environment
fi