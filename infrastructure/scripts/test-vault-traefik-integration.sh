#!/bin/bash
set -euo pipefail

# Comprehensive Test Suite for Vault-Traefik Integration
# This script validates the complete integration without making changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TEST_LOG="/var/log/vault-traefik-integration-test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result counters
TEST_PASSED=0
TEST_FAILED=0
TEST_WARNINGS=0

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${TEST_LOG}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; TEST_WARNINGS=$((TEST_WARNINGS + 1)); }
error() { log "ERROR" "${RED}$*${NC}"; TEST_FAILED=$((TEST_FAILED + 1)); }
success() { log "SUCCESS" "${GREEN}$*${NC}"; TEST_PASSED=$((TEST_PASSED + 1)); }

# Test runner function
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    info "Running test: $test_name"
    
    if $test_function; then
        success "✓ $test_name - PASSED"
        return 0
    else
        error "✗ $test_name - FAILED"
        return 1
    fi
}

# Test 1: Vault Service Health
test_vault_health() {
    if vault status >/dev/null 2>&1; then
        local vault_status
        vault_status=$(vault status -format=json)
        
        if echo "$vault_status" | jq -e '.sealed == false' >/dev/null; then
            info "Vault is unsealed and accessible"
            return 0
        else
            error "Vault is sealed"
            return 1
        fi
    else
        error "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
}

# Test 2: Nomad Service Health
test_nomad_health() {
    if nomad status >/dev/null 2>&1; then
        info "Nomad is accessible"
        return 0
    else
        error "Cannot connect to Nomad at $NOMAD_ADDR"
        return 1
    fi
}

# Test 3: Vault KV Secrets Engine
test_vault_kv_engine() {
    if vault secrets list | grep -q "^secret/"; then
        info "KV secrets engine is enabled"
        return 0
    else
        error "KV secrets engine not found"
        return 1
    fi
}

# Test 4: Traefik Policy
test_traefik_policy() {
    if vault policy read traefik-policy >/dev/null 2>&1; then
        info "Traefik policy exists"
        return 0
    else
        error "Traefik policy not found"
        return 1
    fi
}

# Test 5: Traefik Dashboard Credentials
test_traefik_credentials() {
    local temp_token
    
    # Try to get root token or use provided token
    if [ -f "/opt/vault/data/init/root-token" ]; then
        temp_token=$(cat "/opt/vault/data/init/root-token")
    elif [ ! -z "${VAULT_TOKEN:-}" ]; then
        temp_token="$VAULT_TOKEN"
    else
        warn "No Vault token available for credential test"
        return 1
    fi
    
    if VAULT_TOKEN="$temp_token" vault kv get secret/traefik/dashboard >/dev/null 2>&1; then
        info "Dashboard credentials are accessible"
        
        # Test credential format
        local auth_hash
        auth_hash=$(VAULT_TOKEN="$temp_token" vault kv get -field=auth secret/traefik/dashboard 2>/dev/null || echo "")
        
        if [[ "$auth_hash" =~ ^[a-zA-Z0-9]+:\$2[yab]\$ ]]; then
            info "Dashboard credentials are properly formatted"
            return 0
        else
            warn "Dashboard credentials exist but may not be properly formatted"
            return 1
        fi
    else
        error "Cannot access dashboard credentials"
        return 1
    fi
}

# Test 6: Traefik Service Token
test_traefik_service_token() {
    local temp_token
    
    if [ -f "/opt/vault/data/init/root-token" ]; then
        temp_token=$(cat "/opt/vault/data/init/root-token")
    elif [ ! -z "${VAULT_TOKEN:-}" ]; then
        temp_token="$VAULT_TOKEN"
    else
        warn "No Vault token available for service token test"
        return 1
    fi
    
    if VAULT_TOKEN="$temp_token" vault kv get secret/traefik/vault >/dev/null 2>&1; then
        local service_token
        service_token=$(VAULT_TOKEN="$temp_token" vault kv get -field=token secret/traefik/vault 2>/dev/null || echo "")
        
        if [ ! -z "$service_token" ]; then
            # Test if service token is valid
            if VAULT_TOKEN="$service_token" vault auth -method=token >/dev/null 2>&1; then
                info "Traefik service token is valid"
                return 0
            else
                warn "Traefik service token exists but is not valid"
                return 1
            fi
        else
            error "Traefik service token is empty"
            return 1
        fi
    else
        error "Cannot access Traefik service token"
        return 1
    fi
}

# Test 7: Host Volumes Configuration
test_host_volumes() {
    local volumes=("traefik-certs" "traefik-config" "traefik-secrets")
    local all_volumes_ok=true
    
    for volume in "${volumes[@]}"; do
        local volume_path="/opt/nomad/volumes/${volume}"
        
        if [ -d "$volume_path" ]; then
            info "Host volume exists: $volume_path"
            
            # Check permissions
            local perms
            perms=$(stat -c "%a" "$volume_path")
            
            case $volume in
                "traefik-secrets"|"traefik-certs")
                    if [ "$perms" = "700" ]; then
                        info "Correct permissions for $volume: $perms"
                    else
                        warn "Incorrect permissions for $volume: $perms (expected 700)"
                        all_volumes_ok=false
                    fi
                    ;;
                *)
                    if [ "$perms" = "755" ]; then
                        info "Correct permissions for $volume: $perms"
                    else
                        warn "Permissions for $volume: $perms (expected 755)"
                    fi
                    ;;
            esac
        else
            error "Host volume missing: $volume_path"
            all_volumes_ok=false
        fi
    done
    
    if $all_volumes_ok; then
        return 0
    else
        return 1
    fi
}

# Test 8: Template Files
test_template_files() {
    local template_dir="/opt/nomad/volumes/traefik-config/templates"
    local required_templates=("dashboard-auth.tpl" "traefik-env.tpl" "dynamic-config.tpl")
    local all_templates_ok=true
    
    if [ ! -d "$template_dir" ]; then
        error "Template directory missing: $template_dir"
        return 1
    fi
    
    for template in "${required_templates[@]}"; do
        local template_file="$template_dir/$template"
        
        if [ -f "$template_file" ]; then
            info "Template file exists: $template"
            
            # Check if template has Vault syntax
            if grep -q "{{.*secret.*}}" "$template_file"; then
                info "Template has Vault template syntax: $template"
            else
                warn "Template may not have proper Vault syntax: $template"
                all_templates_ok=false
            fi
        else
            error "Template file missing: $template_file"
            all_templates_ok=false
        fi
    done
    
    if $all_templates_ok; then
        return 0
    else
        return 1
    fi
}

# Test 9: Traefik Job Status
test_traefik_job() {
    if nomad job status traefik-vault >/dev/null 2>&1; then
        local job_status
        job_status=$(nomad job status -short traefik-vault | grep "Status" | awk '{print $3}' || echo "unknown")
        
        case $job_status in
            "running")
                info "Traefik job is running"
                
                # Check allocation health
                local alloc_count
                alloc_count=$(nomad job status traefik-vault | grep -c "running" || echo "0")
                
                if [ "$alloc_count" -gt 0 ]; then
                    info "Traefik has $alloc_count running allocations"
                    return 0
                else
                    warn "Traefik job is running but no allocations found"
                    return 1
                fi
                ;;
            "pending")
                warn "Traefik job is pending deployment"
                return 1
                ;;
            "dead")
                error "Traefik job is dead"
                return 1
                ;;
            *)
                warn "Traefik job status: $job_status"
                return 1
                ;;
        esac
    else
        error "Traefik job not found"
        return 1
    fi
}

# Test 10: Service Connectivity
test_service_connectivity() {
    local all_services_ok=true
    
    # Test HTTP endpoint
    info "Testing Traefik HTTP endpoint..."
    if curl -f -s http://localhost/ping >/dev/null 2>&1; then
        info "Traefik HTTP endpoint responding"
    else
        warn "Traefik HTTP endpoint not responding"
        all_services_ok=false
    fi
    
    # Test HTTPS endpoint (may fail if certificates aren't ready)
    info "Testing Traefik HTTPS endpoint..."
    if curl -f -s -k https://localhost/ping >/dev/null 2>&1; then
        info "Traefik HTTPS endpoint responding"
    else
        warn "Traefik HTTPS endpoint not responding (certificates may not be ready)"
        # Don't fail test for HTTPS as certificates take time
    fi
    
    # Test Vault Agent (if running)
    info "Testing Vault Agent endpoint..."
    if curl -f -s http://localhost:8100/agent/v1/cache-status >/dev/null 2>&1; then
        info "Vault Agent endpoint responding"
    else
        warn "Vault Agent endpoint not responding"
        all_services_ok=false
    fi
    
    # Test metrics endpoint
    info "Testing Traefik metrics endpoint..."
    if curl -f -s http://localhost:8082/metrics >/dev/null 2>&1; then
        info "Traefik metrics endpoint responding"
    else
        warn "Traefik metrics endpoint not responding"
        all_services_ok=false
    fi
    
    if $all_services_ok; then
        return 0
    else
        return 1
    fi
}

# Test 11: Certificate Storage
test_certificate_storage() {
    local acme_file="/opt/nomad/volumes/traefik-certs/acme.json"
    
    if [ -f "$acme_file" ]; then
        info "ACME certificate storage file exists"
        
        # Check permissions
        local perms
        perms=$(stat -c "%a" "$acme_file")
        
        if [ "$perms" = "600" ]; then
            info "ACME file has correct permissions: $perms"
            
            # Check if file is valid JSON
            if jq . "$acme_file" >/dev/null 2>&1; then
                info "ACME file is valid JSON"
                return 0
            else
                warn "ACME file is not valid JSON"
                return 1
            fi
        else
            warn "ACME file has incorrect permissions: $perms (expected 600)"
            return 1
        fi
    else
        error "ACME certificate storage file missing: $acme_file"
        return 1
    fi
}

# Test 12: Health Check Scripts
test_health_check_scripts() {
    local health_script="/usr/local/bin/vault-traefik-health-check"
    
    if [ -f "$health_script" ] && [ -x "$health_script" ]; then
        info "Health check script exists and is executable"
        
        # Try running health check
        if "$health_script" >/dev/null 2>&1; then
            info "Health check script runs successfully"
            return 0
        else
            warn "Health check script exists but fails when executed"
            return 1
        fi
    else
        warn "Health check script not found or not executable: $health_script"
        return 1
    fi
}

# Test 13: Systemd Services
test_systemd_services() {
    local services=("vault-agent" "vault-traefik-health.timer" "traefik-credential-rotation.timer")
    local all_services_ok=true
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            info "Systemd service exists: $service"
            
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                info "Service is enabled: $service"
            else
                warn "Service is not enabled: $service"
                all_services_ok=false
            fi
        else
            warn "Systemd service not found: $service"
            all_services_ok=false
        fi
    done
    
    if $all_services_ok; then
        return 0
    else
        return 1
    fi
}

# Generate test report
generate_test_report() {
    local report_file="/tmp/vault-traefik-integration-test-report.txt"
    
    cat > "$report_file" <<EOF
===============================================
Vault-Traefik Integration Test Report
===============================================
Test Date: $(date)
Test Duration: $((SECONDS))s

Test Results:
  Passed: $TEST_PASSED
  Failed: $TEST_FAILED
  Warnings: $TEST_WARNINGS
  Total: $((TEST_PASSED + TEST_FAILED))

Success Rate: $(( (TEST_PASSED * 100) / (TEST_PASSED + TEST_FAILED) ))%

System Information:
  Vault Address: $VAULT_ADDR
  Nomad Address: $NOMAD_ADDR
  Hostname: $(hostname)
  OS: $(uname -a)

Service Status:
EOF
    
    # Add service status to report
    if vault status >/dev/null 2>&1; then
        echo "  Vault: Running" >> "$report_file"
    else
        echo "  Vault: Not accessible" >> "$report_file"
    fi
    
    if nomad status >/dev/null 2>&1; then
        echo "  Nomad: Running" >> "$report_file"
    else
        echo "  Nomad: Not accessible" >> "$report_file"
    fi
    
    if nomad job status traefik-vault >/dev/null 2>&1; then
        local job_status
        job_status=$(nomad job status -short traefik-vault | grep "Status" | awk '{print $3}' || echo "unknown")
        echo "  Traefik Job: $job_status" >> "$report_file"
    else
        echo "  Traefik Job: Not found" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "Full test log: $TEST_LOG" >> "$report_file"
    echo "===============================================" >> "$report_file"
    
    info "Test report generated: $report_file"
    cat "$report_file"
}

# Main test execution function
main() {
    info "Starting Vault-Traefik Integration Test Suite"
    info "Test log: $TEST_LOG"
    
    # Create log directory
    mkdir -p "$(dirname "$TEST_LOG")"
    
    # Clear counters
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_WARNINGS=0
    
    # Start timer
    SECONDS=0
    
    # Run all tests
    info "Running comprehensive integration tests..."
    
    run_test "Vault Service Health" test_vault_health
    run_test "Nomad Service Health" test_nomad_health
    run_test "Vault KV Secrets Engine" test_vault_kv_engine
    run_test "Traefik Policy" test_traefik_policy
    run_test "Traefik Dashboard Credentials" test_traefik_credentials
    run_test "Traefik Service Token" test_traefik_service_token
    run_test "Host Volumes Configuration" test_host_volumes
    run_test "Template Files" test_template_files
    run_test "Traefik Job Status" test_traefik_job
    run_test "Service Connectivity" test_service_connectivity
    run_test "Certificate Storage" test_certificate_storage
    run_test "Health Check Scripts" test_health_check_scripts
    run_test "Systemd Services" test_systemd_services
    
    # Generate test report
    generate_test_report
    
    # Final result
    if [ $TEST_FAILED -eq 0 ]; then
        success "🎉 All tests passed! Integration is working correctly."
        
        if [ $TEST_WARNINGS -gt 0 ]; then
            warn "Note: $TEST_WARNINGS warnings were reported. Review the log for details."
        fi
        
        return 0
    else
        error "❗ $TEST_FAILED tests failed. Integration needs attention."
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi