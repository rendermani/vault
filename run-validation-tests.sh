#!/bin/bash

# Cloudya Vault Deployment Validation Script
# This script runs comprehensive tests to validate the fixed automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"
RESULTS_DIR="$SCRIPT_DIR/test-results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to setup test environment
setup_test_environment() {
    print_status "Setting up test environment..."
    
    # Create results directories
    mkdir -p "$RESULTS_DIR"/{reports,logs,certificates,screenshots,backups,test-data}
    
    # Install test dependencies if package.json exists
    if [ -f "$TEST_DIR/package.json" ]; then
        print_status "Installing test dependencies..."
        cd "$TEST_DIR"
        npm install --silent
        cd "$SCRIPT_DIR"
    fi
    
    print_success "Test environment setup complete"
}

# Function to run individual test suites
run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local log_file="$RESULTS_DIR/logs/${test_name}.log"
    
    print_status "Running $test_name..."
    
    if [ -f "$test_script" ]; then
        if node "$test_script" > "$log_file" 2>&1; then
            print_success "$test_name completed successfully"
            return 0
        else
            print_error "$test_name failed (see $log_file for details)"
            return 1
        fi
    else
        print_warning "$test_name script not found: $test_script"
        return 1
    fi
}

# Function to display test results summary
display_summary() {
    local passed_tests=$1
    local total_tests=$2
    local success_rate
    
    success_rate=$(( (passed_tests * 100) / total_tests ))
    
    echo ""
    echo "=" * 80
    echo -e "${BLUE}📊 VALIDATION TEST RESULTS SUMMARY${NC}"
    echo "=" * 80
    echo ""
    
    if [ $success_rate -eq 100 ]; then
        print_success "ALL TESTS PASSED! Deployment automation validation successful."
        echo -e "${GREEN}🎉 System is ready for production deployment${NC}"
    elif [ $success_rate -ge 80 ]; then
        print_warning "Most tests passed with some minor issues"
        echo -e "${YELLOW}⚠️  Review failed tests before production deployment${NC}"
    else
        print_error "Multiple test failures detected"
        echo -e "${RED}🚨 DO NOT deploy to production until issues are resolved${NC}"
    fi
    
    echo ""
    echo "Test Results:"
    echo "  - Total Tests: $total_tests"
    echo "  - Passed: $passed_tests"
    echo "  - Failed: $((total_tests - passed_tests))"
    echo "  - Success Rate: $success_rate%"
    echo ""
    echo "Reports and logs saved to: $RESULTS_DIR"
    echo ""
}

# Main execution function
main() {
    local passed_tests=0
    local total_tests=0
    
    echo ""
    echo "🧪 CLOUDYA VAULT DEPLOYMENT VALIDATION SUITE"
    echo "=============================================="
    echo ""
    echo "Testing deployment automation fixes..."
    echo "Target endpoints:"
    echo "  - https://vault.cloudya.net"
    echo "  - https://consul.cloudya.net" 
    echo "  - https://nomad.cloudya.net"
    echo "  - https://traefik.cloudya.net"
    echo ""
    
    # Prerequisites check
    check_prerequisites
    setup_test_environment
    
    echo ""
    echo "🚀 Starting test execution..."
    echo ""
    
    # Test Suite 1: SSL Certificate Validation
    total_tests=$((total_tests + 1))
    if run_test_suite "SSL Certificate Validation" "$TEST_DIR/ssl/ssl-validator.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test Suite 2: Endpoint Health Tests
    total_tests=$((total_tests + 1))
    if run_test_suite "Endpoint Health Tests" "$TEST_DIR/integration/endpoint-tests.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test Suite 3: Performance Load Tests
    total_tests=$((total_tests + 1))
    if run_test_suite "Performance Load Tests" "$TEST_DIR/performance/load-tests.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test Suite 4: Backup & Recovery Tests
    total_tests=$((total_tests + 1))
    if run_test_suite "Backup & Recovery Tests" "$TEST_DIR/utils/backup-recovery-tests.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test Suite 5: End-to-End Deployment Validation
    total_tests=$((total_tests + 1))
    if run_test_suite "E2E Deployment Validation" "$TEST_DIR/e2e/deployment-validation.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test Suite 6: Comprehensive Test Runner (Final Report)
    total_tests=$((total_tests + 1))
    if run_test_suite "Comprehensive Test Report" "$TEST_DIR/utils/test-runner.js"; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Optional: Unit Tests (if Jest is available)
    if command -v jest &> /dev/null || [ -f "$TEST_DIR/node_modules/.bin/jest" ]; then
        print_status "Running unit tests..."
        total_tests=$((total_tests + 1))
        if cd "$TEST_DIR" && npm test > "$RESULTS_DIR/logs/unit-tests.log" 2>&1; then
            passed_tests=$((passed_tests + 1))
            print_success "Unit tests completed successfully"
        else
            print_error "Unit tests failed"
        fi
        cd "$SCRIPT_DIR"
    fi
    
    # Display final summary
    display_summary $passed_tests $total_tests
    
    # Setup monitoring (optional)
    print_status "Setting up monitoring and alerting..."
    if node "$TEST_DIR/utils/monitoring-setup.js" > "$RESULTS_DIR/logs/monitoring-setup.log" 2>&1; then
        print_success "Monitoring setup completed"
        echo ""
        echo "📊 Monitoring Dashboard: file://$RESULTS_DIR/monitoring-dashboard.html"
        echo "📋 Enable monitoring: crontab < $RESULTS_DIR/monitoring-crontab.txt"
        echo "📊 View alerts: tail -f $RESULTS_DIR/logs/alerts.log"
    else
        print_warning "Monitoring setup encountered issues (non-critical)"
    fi
    
    echo ""
    echo "🏁 Deployment validation testing complete!"
    
    # Set exit code based on test results
    if [ $passed_tests -eq $total_tests ]; then
        exit 0
    else
        exit 1
    fi
}

# Trap signals and cleanup on exit
trap 'echo ""; print_status "Test execution interrupted"; exit 1' INT TERM

# Run main function
main "$@"