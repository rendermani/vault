#!/usr/bin/env bash
# Security Validation Automation
# Comprehensive security testing and validation of all implemented automations
#
# This script validates that all security issues have been properly addressed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/var/log/cloudya-security"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloudya.net:8200}"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-https://consul.cloudya.net:8500}"
NOMAD_ADDR="${NOMAD_ADDR:-https://nomad.cloudya.net:4646}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SECURITY-VALIDATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/security-validation.log"
}

log_success() {
    echo -e "${GREEN}[SECURITY-VALIDATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/security-validation.log"
}

log_warning() {
    echo -e "${YELLOW}[SECURITY-VALIDATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/security-validation.log"
}

log_error() {
    echo -e "${RED}[SECURITY-VALIDATION]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_DIR/security-validation.log" >&2
}

# Initialize test results tracking
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Test result tracker
record_test_result() {
    local test_name="$1"
    local result="$2"  # PASS, FAIL, WARNING
    local details="${3:-}"
    
    TEST_RESULTS["$test_name"]="$result"
    ((TOTAL_TESTS++))
    
    case "$result" in
        "PASS")
            ((PASSED_TESTS++))
            log_success "✅ $test_name"
            ;;
        "FAIL")
            ((FAILED_TESTS++))
            log_error "❌ $test_name - $details"
            ;;
        "WARNING")
            ((WARNING_TESTS++))
            log_warning "⚠️ $test_name - $details"
            ;;
    esac
}

# CRITICAL SECURITY TESTS

# Test 1: Verify hardcoded credentials are removed
test_hardcoded_credentials_removed() {
    log_info "Testing: Hardcoded credentials removal..."
    
    local issues_found=0
    
    # Check docker-compose.production.yml for hardcoded basic auth
    if grep -q "\$\$2y\$\$10\$\$2b2cu2a6YjdwQqN3QP1PxOqUf7w7VgLhvx6xXPB.XD9QqQ5U9Q2a2" "$PROJECT_ROOT/docker-compose.production.yml" 2>/dev/null; then
        ((issues_found++))
    fi
    
    # Check for default Grafana password
    if grep -q "GF_SECURITY_ADMIN_PASSWORD=admin" "$PROJECT_ROOT" -r 2>/dev/null; then
        ((issues_found++))
    fi
    
    # Check for other hardcoded passwords
    if grep -r "password.*=" "$PROJECT_ROOT" --include="*.yml" --include="*.yaml" --exclude-dir=".git" | grep -v "password_policy\|password_file\|password_hash" >/dev/null 2>&1; then
        ((issues_found++))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        record_test_result "Hardcoded Credentials Removal" "PASS"
    else
        record_test_result "Hardcoded Credentials Removal" "FAIL" "$issues_found hardcoded credentials found"
    fi
}

# Test 2: Verify Vault secret storage
test_vault_secret_storage() {
    log_info "Testing: Vault secret storage..."
    
    local missing_secrets=()
    local required_secrets=(
        "secret/cloudya/traefik/admin"
        "secret/cloudya/grafana/admin"
        "secret/cloudya/prometheus/admin"
        "secret/cloudya/consul/admin"
    )
    
    for secret in "${required_secrets[@]}"; do
        if ! vault kv get "$secret" >/dev/null 2>&1; then
            missing_secrets+=("$secret")
        fi
    done
    
    if [[ ${#missing_secrets[@]} -eq 0 ]]; then
        record_test_result "Vault Secret Storage" "PASS"
    else
        record_test_result "Vault Secret Storage" "FAIL" "Missing secrets: ${missing_secrets[*]}"
    fi
}

# Test 3: Verify auto-unseal configuration
test_auto_unseal_configuration() {
    log_info "Testing: Auto-unseal configuration..."
    
    # Check if auto-unseal is configured in vault.hcl
    local vault_config="$PROJECT_ROOT/infrastructure/vault/config/vault.hcl"
    
    if [[ -f "$vault_config" ]] && grep -q "seal.*transit\|seal.*awskms\|seal.*azurekeyvault\|seal.*gcpckms" "$vault_config"; then
        record_test_result "Auto-unseal Configuration" "PASS"
    else
        record_test_result "Auto-unseal Configuration" "WARNING" "Auto-unseal not configured, manual unsealing required"
    fi
}

# Test 4: Verify TLS configuration strength
test_tls_configuration() {
    log_info "Testing: TLS configuration strength..."
    
    local tls_issues=0
    
    # Check Vault TLS configuration
    local vault_config="$PROJECT_ROOT/infrastructure/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        if ! grep -q "tls_min_version.*tls13\|tls_min_version.*TLSv1_3" "$vault_config"; then
            ((tls_issues++))
        fi
        
        if ! grep -q "tls_require_and_verify_client_cert.*true" "$vault_config"; then
            ((tls_issues++))
        fi
    else
        ((tls_issues++))
    fi
    
    # Check if SSL certificates exist
    local cert_dir="$PROJECT_ROOT/automation/ssl-certs/services"
    local required_certs=("vault.crt" "consul.crt" "nomad.crt" "traefik.crt")
    
    for cert in "${required_certs[@]}"; do
        if [[ ! -f "$cert_dir/$cert" ]]; then
            ((tls_issues++))
        fi
    done
    
    if [[ $tls_issues -eq 0 ]]; then
        record_test_result "TLS Configuration" "PASS"
    else
        record_test_result "TLS Configuration" "FAIL" "$tls_issues TLS configuration issues found"
    fi
}

# Test 5: Verify ACL configurations
test_acl_configurations() {
    log_info "Testing: ACL configurations..."
    
    local acl_issues=0
    
    # Test Consul ACLs
    export CONSUL_HTTP_TOKEN=$(vault kv get -field=token secret/cloudya/consul/bootstrap 2>/dev/null || echo "")
    if [[ -n "$CONSUL_HTTP_TOKEN" ]]; then
        if ! consul acl policy list >/dev/null 2>&1; then
            ((acl_issues++))
        fi
    else
        ((acl_issues++))
    fi
    
    # Test Nomad ACLs
    export NOMAD_TOKEN=$(vault kv get -field=token secret/cloudya/nomad/bootstrap 2>/dev/null || echo "")
    if [[ -n "$NOMAD_TOKEN" ]]; then
        if ! nomad acl policy list >/dev/null 2>&1; then
            ((acl_issues++))
        fi
    else
        ((acl_issues++))
    fi
    
    if [[ $acl_issues -eq 0 ]]; then
        record_test_result "ACL Configurations" "PASS"
    else
        record_test_result "ACL Configurations" "FAIL" "$acl_issues ACL configuration issues found"
    fi
}

# Test 6: Verify secret rotation is working
test_secret_rotation() {
    log_info "Testing: Secret rotation functionality..."
    
    local rotation_issues=0
    
    # Check if rotation configuration exists
    if ! vault kv list rotation/config/ >/dev/null 2>&1; then
        ((rotation_issues++))
    fi
    
    # Check if rotation scripts exist and are executable
    local rotation_scripts=(
        "$PROJECT_ROOT/automation/rotation-scripts/rotation-engine.sh"
        "$PROJECT_ROOT/automation/rotation-scripts/rotate-tokens.sh"
        "$PROJECT_ROOT/automation/rotation-scripts/monitor-rotation.sh"
    )
    
    for script in "${rotation_scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            ((rotation_issues++))
        fi
    done
    
    # Check if systemd timers are active
    local rotation_timers=("secret-rotation.timer" "token-rotation.timer" "rotation-monitoring.timer")
    for timer in "${rotation_timers[@]}"; do
        if ! systemctl is-active "$timer" >/dev/null 2>&1; then
            ((rotation_issues++))
        fi
    done
    
    if [[ $rotation_issues -eq 0 ]]; then
        record_test_result "Secret Rotation" "PASS"
    else
        record_test_result "Secret Rotation" "FAIL" "$rotation_issues secret rotation issues found"
    fi
}

# Test 7: Verify network security (no services bound to 0.0.0.0)
test_network_security() {
    log_info "Testing: Network security configuration..."
    
    local network_issues=0
    
    # Check docker-compose for proper port binding
    if grep -q "- \"80:\|- \"443:\|- \"8080:\|- \"8200:\|- \"8500:\|- \"4646:" "$PROJECT_ROOT/docker-compose.production.yml" | grep -v "127.0.0.1:"; then
        ((network_issues++))
    fi
    
    # Check if services are properly isolated
    if ! grep -q "networks:" "$PROJECT_ROOT/docker-compose.production.yml"; then
        ((network_issues++))
    fi
    
    if [[ $network_issues -eq 0 ]]; then
        record_test_result "Network Security" "PASS"
    else
        record_test_result "Network Security" "FAIL" "$network_issues network security issues found"
    fi
}

# Test 8: Verify audit logging is enabled
test_audit_logging() {
    log_info "Testing: Audit logging configuration..."
    
    local audit_issues=0
    
    # Check Vault audit logging
    if ! vault audit list >/dev/null 2>&1; then
        ((audit_issues++))
    fi
    
    # Check if audit log files exist
    if [[ ! -f "/vault/logs/audit.log" ]] && [[ ! -f "/opt/cloudya-data/vault/logs/audit.log" ]]; then
        ((audit_issues++))
    fi
    
    if [[ $audit_issues -eq 0 ]]; then
        record_test_result "Audit Logging" "PASS"
    else
        record_test_result "Audit Logging" "WARNING" "$audit_issues audit logging issues found"
    fi
}

# Test 9: Verify Vault Agent is working
test_vault_agent() {
    log_info "Testing: Vault Agent functionality..."
    
    local agent_issues=0
    
    # Check if Vault Agent configuration exists
    if [[ ! -f "$PROJECT_ROOT/infrastructure/vault/agent/agent.hcl" ]]; then
        ((agent_issues++))
    fi
    
    # Check if AppRole credentials exist
    if [[ ! -f "$PROJECT_ROOT/infrastructure/vault/agent/role_id" ]] || [[ ! -f "$PROJECT_ROOT/infrastructure/vault/agent/secret_id" ]]; then
        ((agent_issues++))
    fi
    
    # Check if secret templates exist
    if [[ ! -d "$PROJECT_ROOT/automation/templates" ]]; then
        ((agent_issues++))
    fi
    
    # Check if secrets directory exists and has proper permissions
    if [[ ! -d "/opt/cloudya-infrastructure/secrets" ]]; then
        ((agent_issues++))
    elif [[ "$(stat -c %a /opt/cloudya-infrastructure/secrets 2>/dev/null)" != "750" ]]; then
        ((agent_issues++))
    fi
    
    if [[ $agent_issues -eq 0 ]]; then
        record_test_result "Vault Agent" "PASS"
    else
        record_test_result "Vault Agent" "FAIL" "$agent_issues Vault Agent issues found"
    fi
}

# Test 10: Verify certificate management
test_certificate_management() {
    log_info "Testing: Certificate management..."
    
    local cert_issues=0
    
    # Check if PKI is configured in Vault
    if ! vault secrets list | grep -q "pki/"; then
        ((cert_issues++))
    fi
    
    # Check certificate files exist and are valid
    local cert_dir="$PROJECT_ROOT/automation/ssl-certs/services"
    local required_certs=("vault.crt" "consul.crt" "nomad.crt" "traefik.crt")
    
    for cert in "${required_certs[@]}"; do
        if [[ ! -f "$cert_dir/$cert" ]]; then
            ((cert_issues++))
        elif ! openssl x509 -in "$cert_dir/$cert" -noout -text >/dev/null 2>&1; then
            ((cert_issues++))
        fi
    done
    
    # Check certificate rotation automation
    if [[ ! -x "$PROJECT_ROOT/automation/ssl-scripts/rotate-certificates.sh" ]]; then
        ((cert_issues++))
    fi
    
    if [[ $cert_issues -eq 0 ]]; then
        record_test_result "Certificate Management" "PASS"
    else
        record_test_result "Certificate Management" "FAIL" "$cert_issues certificate management issues found"
    fi
}

# Test 11: Service health and accessibility
test_service_health() {
    log_info "Testing: Service health and accessibility..."
    
    local health_issues=0
    
    # Test Vault
    if ! vault status >/dev/null 2>&1; then
        ((health_issues++))
    fi
    
    # Test Consul (if accessible)
    if [[ -n "${CONSUL_HTTP_TOKEN:-}" ]]; then
        if ! consul members >/dev/null 2>&1; then
            ((health_issues++))
        fi
    fi
    
    # Test Nomad (if accessible)
    if [[ -n "${NOMAD_TOKEN:-}" ]]; then
        if ! nomad status >/dev/null 2>&1; then
            ((health_issues++))
        fi
    fi
    
    if [[ $health_issues -eq 0 ]]; then
        record_test_result "Service Health" "PASS"
    else
        record_test_result "Service Health" "WARNING" "$health_issues services not accessible (may be expected)"
    fi
}

# Test 12: Compliance with security standards
test_security_compliance() {
    log_info "Testing: Security compliance..."
    
    local compliance_issues=0
    
    # Check file permissions on sensitive files
    local sensitive_files=(
        "/opt/cloudya-infrastructure/secrets"
        "$PROJECT_ROOT/infrastructure/vault/agent/role_id"
        "$PROJECT_ROOT/infrastructure/vault/agent/secret_id"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [[ -e "$file" ]]; then
            local perms=$(stat -c %a "$file" 2>/dev/null || echo "000")
            if [[ "$perms" != "600" ]] && [[ "$perms" != "700" ]] && [[ "$perms" != "750" ]]; then
                ((compliance_issues++))
            fi
        fi
    done
    
    # Check for weak configurations
    if grep -r "VAULT_SKIP_VERIFY=true" "$PROJECT_ROOT" --include="*.yml" --include="*.sh" --include="*.env" | grep -v "development" >/dev/null 2>&1; then
        ((compliance_issues++))
    fi
    
    # Check for default/weak passwords in configuration
    if grep -r "password.*changeme\|password.*admin\|password.*123" "$PROJECT_ROOT" --include="*.yml" --include="*.sh" >/dev/null 2>&1; then
        ((compliance_issues++))
    fi
    
    if [[ $compliance_issues -eq 0 ]]; then
        record_test_result "Security Compliance" "PASS"
    else
        record_test_result "Security Compliance" "FAIL" "$compliance_issues compliance issues found"
    fi
}

# Test 13: Backup and recovery capabilities
test_backup_recovery() {
    log_info "Testing: Backup and recovery capabilities..."
    
    local backup_issues=0
    
    # Check if backup scripts exist
    local backup_scripts=(
        "$PROJECT_ROOT/infrastructure/scripts/backup-restore.sh"
        "$PROJECT_ROOT/automation/ssl-scripts/monitor-certificates.sh"
    )
    
    for script in "${backup_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            ((backup_issues++))
        fi
    done
    
    # Check if backup directories exist
    local backup_dirs=(
        "/opt/cloudya-backups"
        "/var/log/cloudya-security"
    )
    
    for dir in "${backup_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            ((backup_issues++))
        fi
    done
    
    if [[ $backup_issues -eq 0 ]]; then
        record_test_result "Backup Recovery" "PASS"
    else
        record_test_result "Backup Recovery" "WARNING" "$backup_issues backup/recovery issues found"
    fi
}

# Test 14: Monitoring and alerting
test_monitoring_alerting() {
    log_info "Testing: Monitoring and alerting..."
    
    local monitoring_issues=0
    
    # Check monitoring scripts exist
    local monitoring_scripts=(
        "$PROJECT_ROOT/automation/rotation-scripts/monitor-rotation.sh"
        "$PROJECT_ROOT/automation/ssl-scripts/monitor-certificates.sh"
        "$PROJECT_ROOT/automation/acl-scripts/acl-health-check.sh"
    )
    
    for script in "${monitoring_scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            ((monitoring_issues++))
        fi
    done
    
    # Check if systemd timers for monitoring are active
    local monitoring_timers=("rotation-monitoring.timer" "cert-rotation.timer")
    for timer in "${monitoring_timers[@]}"; do
        if ! systemctl list-timers | grep -q "$timer"; then
            ((monitoring_issues++))
        fi
    done
    
    if [[ $monitoring_issues -eq 0 ]]; then
        record_test_result "Monitoring Alerting" "PASS"
    else
        record_test_result "Monitoring Alerting" "WARNING" "$monitoring_issues monitoring issues found"
    fi
}

# Test 15: Documentation and procedures
test_documentation() {
    log_info "Testing: Documentation completeness..."
    
    local doc_issues=0
    
    # Check if key documentation exists
    local required_docs=(
        "$PROJECT_ROOT/automation/README.md"
        "$LOG_DIR/security-automation.log"
    )
    
    for doc in "${required_docs[@]}"; do
        if [[ ! -f "$doc" ]]; then
            ((doc_issues++))
        fi
    done
    
    if [[ $doc_issues -eq 0 ]]; then
        record_test_result "Documentation" "PASS"
    else
        record_test_result "Documentation" "WARNING" "$doc_issues documentation items missing"
    fi
}

# Generate comprehensive security report
generate_security_report() {
    log_info "Generating comprehensive security validation report..."
    
    local report_file="$LOG_DIR/security-validation-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "validation_summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "warning_tests": $WARNING_TESTS,
    "success_rate": $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)
  },
  "test_results": {
EOF

    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "    ," >> "$report_file"
        fi
        
        echo "    \"$test_name\": \"${TEST_RESULTS[$test_name]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
  },
  "security_status": {
    "critical_issues_resolved": $(if [[ $FAILED_TESTS -eq 0 ]]; then echo "true"; else echo "false"; fi),
    "hardcoded_credentials": "$(if [[ "${TEST_RESULTS[Hardcoded Credentials Removal]:-}" == "PASS" ]]; then echo "removed"; else echo "present"; fi)",
    "vault_integration": "$(if [[ "${TEST_RESULTS[Vault Secret Storage]:-}" == "PASS" ]]; then echo "active"; else echo "inactive"; fi)",
    "tls_security": "$(if [[ "${TEST_RESULTS[TLS Configuration]:-}" == "PASS" ]]; then echo "strong"; else echo "weak"; fi)",
    "acl_enforcement": "$(if [[ "${TEST_RESULTS[ACL Configurations]:-}" == "PASS" ]]; then echo "enabled"; else echo "disabled"; fi)",
    "secret_rotation": "$(if [[ "${TEST_RESULTS[Secret Rotation]:-}" == "PASS" ]]; then echo "automated"; else echo "manual"; fi)"
  },
  "recommendations": [
EOF

    local recommendations=()
    
    if [[ "${TEST_RESULTS[Auto-unseal Configuration]:-}" != "PASS" ]]; then
        recommendations+=("Configure auto-unseal for Vault to eliminate manual unsealing requirements")
    fi
    
    if [[ "${TEST_RESULTS[Audit Logging]:-}" != "PASS" ]]; then
        recommendations+=("Enable comprehensive audit logging for all services")
    fi
    
    if [[ "${TEST_RESULTS[Service Health]:-}" == "WARNING" ]]; then
        recommendations+=("Verify all services are accessible and properly configured")
    fi
    
    if [[ "${TEST_RESULTS[Monitoring Alerting]:-}" != "PASS" ]]; then
        recommendations+=("Complete monitoring and alerting system configuration")
    fi
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        recommendations+=("All security measures are properly implemented")
    fi
    
    local first_rec=true
    for rec in "${recommendations[@]}"; do
        if [[ "$first_rec" == "true" ]]; then
            first_rec=false
        else
            echo "    ," >> "$report_file"
        fi
        echo "    \"$rec\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
  ],
  "next_steps": [
    "Review failed tests and address any remaining issues",
    "Schedule regular security validation runs",
    "Monitor secret rotation automation",
    "Update incident response procedures",
    "Plan quarterly security audits"
  ]
}
EOF

    log_success "Security validation report generated: $report_file"
    echo "$report_file"
}

# Print summary to console
print_summary() {
    echo ""
    echo "======================================"
    echo "SECURITY VALIDATION SUMMARY"
    echo "======================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Warnings: $WARNING_TESTS"
    echo ""
    
    local success_rate=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "0.0")
    echo "Success Rate: ${success_rate}%"
    echo ""
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✅ SECURITY VALIDATION PASSED${NC}"
        echo "All critical security issues have been resolved!"
    else
        echo -e "${RED}❌ SECURITY VALIDATION FAILED${NC}"
        echo "Critical security issues found. Review the report for details."
    fi
    
    if [[ $WARNING_TESTS -gt 0 ]]; then
        echo -e "${YELLOW}⚠️ $WARNING_TESTS warnings found - review recommended${NC}"
    fi
    
    echo "======================================"
}

# Main execution
main() {
    log_info "Starting comprehensive security validation..."
    log_info "============================================="
    
    # Run all security tests
    test_hardcoded_credentials_removed
    test_vault_secret_storage
    test_auto_unseal_configuration
    test_tls_configuration
    test_acl_configurations
    test_secret_rotation
    test_network_security
    test_audit_logging
    test_vault_agent
    test_certificate_management
    test_service_health
    test_security_compliance
    test_backup_recovery
    test_monitoring_alerting
    test_documentation
    
    # Generate report
    local report_file=$(generate_security_report)
    
    # Print summary
    print_summary
    
    log_info "Detailed report available at: $report_file"
    log_info "Security validation completed"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi