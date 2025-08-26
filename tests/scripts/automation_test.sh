#!/bin/bash

# Automation Scripts Testing
# Tests all automation scripts for functionality and error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORTS_DIR="$PROJECT_ROOT/tests/reports"
LOG_FILE="$REPORTS_DIR/automation_test_report.log"
JSON_REPORT="$REPORTS_DIR/automation_test_report.json"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Initialize log files
mkdir -p "$REPORTS_DIR"
echo "Automation Scripts Test Report - $(date)" > "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"

# JSON report structure
cat > "$JSON_REPORT" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
  "testSuite": "Automation Scripts",
  "results": []
}
EOF

log_test_result() {
    local status="$1"
    local test_name="$2"
    local details="$3"
    local duration="${4:-0}"
    
    echo "[$status] $test_name: $details" | tee -a "$LOG_FILE"
    
    # Update JSON report
    jq --arg status "$status" \
       --arg name "$test_name" \
       --arg details "$details" \
       --arg duration "$duration" \
       '.results += [{
         "test": $name,
         "status": $status,
         "details": $details,
         "duration": ($duration | tonumber)
       }]' "$JSON_REPORT" > "$JSON_REPORT.tmp" && mv "$JSON_REPORT.tmp" "$JSON_REPORT"
    
    case "$status" in
        "PASS")
            echo -e "${GREEN}✓ $test_name${NC}"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}✗ $test_name${NC}"
            ((TESTS_FAILED++))
            ;;
        "SKIP")
            echo -e "${YELLOW}⚠ $test_name${NC}"
            ((TESTS_SKIPPED++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠ $test_name${NC}"
            ;;
    esac
    ((TESTS_RUN++))
}

test_script_exists_and_executable() {
    local script_path="$1"
    local script_name="$(basename "$script_path")"
    local test_start=$(date +%s%3N)
    
    if [ ! -f "$script_path" ]; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "FAIL" "$script_name Existence" "Script does not exist at $script_path" "$duration"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "FAIL" "$script_name Executable" "Script is not executable" "$duration"
        return 1
    fi
    
    local duration=$(($(date +%s%3N) - test_start))
    log_test_result "PASS" "$script_name Existence & Executable" "Script exists and is executable" "$duration"
    return 0
}

test_script_help_option() {
    local script_path="$1"
    local script_name="$(basename "$script_path")"
    local test_start=$(date +%s%3N)
    
    if ! "$script_path" --help >/dev/null 2>&1 && ! "$script_path" -h >/dev/null 2>&1; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "WARN" "$script_name Help Option" "Script does not support --help or -h option" "$duration"
        return 1
    fi
    
    local duration=$(($(date +%s%3N) - test_start))
    log_test_result "PASS" "$script_name Help Option" "Script supports help option" "$duration"
    return 0
}

test_script_error_handling() {
    local script_path="$1"
    local script_name="$(basename "$script_path")"
    local test_start=$(date +%s%3N)
    
    # Test with invalid arguments
    if "$script_path" --invalid-option >/dev/null 2>&1; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "FAIL" "$script_name Error Handling" "Script does not handle invalid options properly" "$duration"
        return 1
    fi
    
    local duration=$(($(date +%s%3N) - test_start))
    log_test_result "PASS" "$script_name Error Handling" "Script properly handles invalid options" "$duration"
    return 0
}

test_vault_init_script() {
    local script_path="$PROJECT_ROOT/scripts/vault-init.sh"
    
    echo -e "${BLUE}Testing Vault Initialization Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test dry-run mode
        local test_start=$(date +%s%3N)
        if "$script_path" --dry-run >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Vault Init Dry Run" "Script supports dry-run mode" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Vault Init Dry Run" "Script does not support dry-run mode" "$duration"
        fi
        
        # Test configuration validation
        test_start=$(date +%s%3N)
        if "$script_path" --validate-config >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Vault Init Config Validation" "Script supports config validation" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Vault Init Config Validation" "Script does not support config validation" "$duration"
        fi
    fi
}

test_consul_setup_script() {
    local script_path="$PROJECT_ROOT/scripts/consul-setup.sh"
    
    echo -e "${BLUE}Testing Consul Setup Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test cluster validation
        local test_start=$(date +%s%3N)
        if "$script_path" --validate-cluster >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Consul Setup Cluster Validation" "Script supports cluster validation" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Consul Setup Cluster Validation" "Script does not support cluster validation" "$duration"
        fi
        
        # Test ACL initialization
        test_start=$(date +%s%3N)
        if "$script_path" --init-acl >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Consul Setup ACL Init" "Script supports ACL initialization" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Consul Setup ACL Init" "Script does not support ACL initialization" "$duration"
        fi
    fi
}

test_nomad_deploy_script() {
    local script_path="$PROJECT_ROOT/scripts/nomad-deploy.sh"
    
    echo -e "${BLUE}Testing Nomad Deploy Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test job validation
        local test_start=$(date +%s%3N)
        if "$script_path" --validate-job >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Nomad Deploy Job Validation" "Script supports job validation" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Nomad Deploy Job Validation" "Script does not support job validation" "$duration"
        fi
        
        # Test deployment status checking
        test_start=$(date +%s%3N)
        if "$script_path" --status >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Nomad Deploy Status Check" "Script supports deployment status checking" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Nomad Deploy Status Check" "Script does not support status checking" "$duration"
        fi
    fi
}

test_traefik_config_script() {
    local script_path="$PROJECT_ROOT/scripts/traefik-config.sh"
    
    echo -e "${BLUE}Testing Traefik Config Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test configuration validation
        local test_start=$(date +%s%3N)
        if "$script_path" --validate >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Traefik Config Validation" "Script supports config validation" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Traefik Config Validation" "Script does not support config validation" "$duration"
        fi
        
        # Test SSL certificate management
        test_start=$(date +%s%3N)
        if "$script_path" --cert-check >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Traefik SSL Cert Check" "Script supports SSL certificate checking" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Traefik SSL Cert Check" "Script does not support SSL certificate checking" "$duration"
        fi
    fi
}

test_monitoring_setup_script() {
    local script_path="$PROJECT_ROOT/scripts/monitoring-setup.sh"
    
    echo -e "${BLUE}Testing Monitoring Setup Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test health check functionality
        local test_start=$(date +%s%3N)
        if "$script_path" --health-check >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Monitoring Health Check" "Script supports health check functionality" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Monitoring Health Check" "Script does not support health check functionality" "$duration"
        fi
        
        # Test alert configuration
        test_start=$(date +%s%3N)
        if "$script_path" --configure-alerts >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Monitoring Alert Configuration" "Script supports alert configuration" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Monitoring Alert Configuration" "Script does not support alert configuration" "$duration"
        fi
    fi
}

test_backup_script() {
    local script_path="$PROJECT_ROOT/scripts/backup.sh"
    
    echo -e "${BLUE}Testing Backup Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test backup verification
        local test_start=$(date +%s%3N)
        if "$script_path" --verify >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Backup Verification" "Script supports backup verification" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Backup Verification" "Script does not support backup verification" "$duration"
        fi
        
        # Test restore functionality
        test_start=$(date +%s%3N)
        if "$script_path" --test-restore >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Backup Restore Test" "Script supports restore testing" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Backup Restore Test" "Script does not support restore testing" "$duration"
        fi
    fi
}

test_log_analysis_script() {
    local script_path="$PROJECT_ROOT/scripts/log-analysis.sh"
    
    echo -e "${BLUE}Testing Log Analysis Script...${NC}"
    
    test_script_exists_and_executable "$script_path"
    
    if [ -f "$script_path" ]; then
        test_script_help_option "$script_path"
        test_script_error_handling "$script_path"
        
        # Test log parsing
        local test_start=$(date +%s%3N)
        if "$script_path" --parse-errors >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Log Analysis Error Parsing" "Script supports error log parsing" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Log Analysis Error Parsing" "Script does not support error log parsing" "$duration"
        fi
        
        # Test report generation
        test_start=$(date +%s%3N)
        if "$script_path" --generate-report >/dev/null 2>&1; then
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "PASS" "Log Analysis Report Generation" "Script supports report generation" "$duration"
        else
            local duration=$(($(date +%s%3N) - test_start))
            log_test_result "WARN" "Log Analysis Report Generation" "Script does not support report generation" "$duration"
        fi
    fi
}

test_script_dependencies() {
    echo -e "${BLUE}Testing Script Dependencies...${NC}"
    
    local test_start=$(date +%s%3N)
    local missing_deps=()
    
    # Common dependencies
    local deps=("jq" "curl" "openssl" "docker" "systemctl")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    local duration=$(($(date +%s%3N) - test_start))
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_test_result "PASS" "Script Dependencies" "All required dependencies are available" "$duration"
    else
        log_test_result "WARN" "Script Dependencies" "Missing dependencies: ${missing_deps[*]}" "$duration"
    fi
}

test_script_permissions() {
    echo -e "${BLUE}Testing Script Permissions...${NC}"
    
    local test_start=$(date +%s%3N)
    local scripts_dir="$PROJECT_ROOT/scripts"
    local permission_issues=()
    
    if [ -d "$scripts_dir" ]; then
        while IFS= read -r -d '' script; do
            local script_name="$(basename "$script")"
            local perms=$(stat -c %a "$script" 2>/dev/null || stat -f %A "$script" 2>/dev/null)
            
            # Scripts should be executable by owner (at least 700 or 755)
            if [[ "$perms" -lt 700 ]]; then
                permission_issues+=("$script_name: $perms")
            fi
        done < <(find "$scripts_dir" -name "*.sh" -type f -print0 2>/dev/null || true)
    fi
    
    local duration=$(($(date +%s%3N) - test_start))
    
    if [ ${#permission_issues[@]} -eq 0 ]; then
        log_test_result "PASS" "Script Permissions" "All scripts have appropriate permissions" "$duration"
    else
        log_test_result "FAIL" "Script Permissions" "Scripts with incorrect permissions: ${permission_issues[*]}" "$duration"
    fi
}

test_script_shellcheck() {
    echo -e "${BLUE}Testing Script Syntax with ShellCheck...${NC}"
    
    local test_start=$(date +%s%3N)
    local scripts_dir="$PROJECT_ROOT/scripts"
    local syntax_issues=()
    
    if ! command -v shellcheck >/dev/null 2>&1; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "SKIP" "ShellCheck Analysis" "shellcheck not available" "$duration"
        return
    fi
    
    if [ -d "$scripts_dir" ]; then
        while IFS= read -r -d '' script; do
            local script_name="$(basename "$script")"
            if ! shellcheck "$script" >/dev/null 2>&1; then
                syntax_issues+=("$script_name")
            fi
        done < <(find "$scripts_dir" -name "*.sh" -type f -print0 2>/dev/null || true)
    fi
    
    local duration=$(($(date +%s%3N) - test_start))
    
    if [ ${#syntax_issues[@]} -eq 0 ]; then
        log_test_result "PASS" "ShellCheck Analysis" "All scripts pass ShellCheck validation" "$duration"
    else
        log_test_result "FAIL" "ShellCheck Analysis" "Scripts with issues: ${syntax_issues[*]}" "$duration"
    fi
}

test_integration_workflow() {
    echo -e "${BLUE}Testing Integration Workflow...${NC}"
    
    local test_start=$(date +%s%3N)
    local workflow_script="$PROJECT_ROOT/scripts/integration-test.sh"
    
    if [ ! -f "$workflow_script" ]; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "SKIP" "Integration Workflow" "Integration test script not found" "$duration"
        return
    fi
    
    if "$workflow_script" --dry-run >/dev/null 2>&1; then
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "PASS" "Integration Workflow" "Integration workflow executes successfully in dry-run mode" "$duration"
    else
        local duration=$(($(date +%s%3N) - test_start))
        log_test_result "FAIL" "Integration Workflow" "Integration workflow fails in dry-run mode" "$duration"
    fi
}

# Main test execution
main() {
    echo "Starting Automation Scripts Testing"
    echo "=================================="
    echo "Project Root: $PROJECT_ROOT"
    echo "Reports Directory: $REPORTS_DIR"
    echo ""
    
    # Test individual scripts
    test_vault_init_script
    test_consul_setup_script
    test_nomad_deploy_script
    test_traefik_config_script
    test_monitoring_setup_script
    test_backup_script
    test_log_analysis_script
    
    # Test script environment and dependencies
    test_script_dependencies
    test_script_permissions
    test_script_shellcheck
    
    # Test integration workflow
    test_integration_workflow
    
    # Update final JSON report
    jq --arg total "$TESTS_RUN" \
       --arg passed "$TESTS_PASSED" \
       --arg failed "$TESTS_FAILED" \
       --arg skipped "$TESTS_SKIPPED" \
       '.summary = {
         "total": ($total | tonumber),
         "passed": ($passed | tonumber),
         "failed": ($failed | tonumber),
         "skipped": ($skipped | tonumber)
       }' "$JSON_REPORT" > "$JSON_REPORT.tmp" && mv "$JSON_REPORT.tmp" "$JSON_REPORT"
    
    # Print summary
    echo "" | tee -a "$LOG_FILE"
    echo "Test Summary:" | tee -a "$LOG_FILE"
    echo "=============" | tee -a "$LOG_FILE"
    echo "Total Tests: $TESTS_RUN" | tee -a "$LOG_FILE"
    echo "Passed: $TESTS_PASSED" | tee -a "$LOG_FILE"
    echo "Failed: $TESTS_FAILED" | tee -a "$LOG_FILE"
    echo "Skipped: $TESTS_SKIPPED" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Reports saved to:" | tee -a "$LOG_FILE"
    echo "- Log: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "- JSON: $JSON_REPORT" | tee -a "$LOG_FILE"
    
    # Return appropriate exit code
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    elif [ $TESTS_PASSED -eq 0 ]; then
        echo -e "${YELLOW}No tests passed!${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# Run main function
main "$@"