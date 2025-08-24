#!/bin/bash

# Vault Security Validation Script
# Comprehensive validation of all security components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }
log_fail() { echo -e "${RED}${BOLD}❌ $1${NC}"; }

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

# Helper function for test results
test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    if [[ "$result" == "PASS" ]]; then
        log_success "$test_name: $message"
        ((TESTS_PASSED++))
    elif [[ "$result" == "FAIL" ]]; then
        log_fail "$test_name: $message"
        ((TESTS_FAILED++))
    else
        log_warn "$test_name: $message"
        ((TESTS_WARNINGS++))
    fi
}

# Validate TLS configuration
validate_tls() {
    log_header "Validating TLS Configuration"
    
    # Check if TLS certificates exist
    local cert_file="/etc/vault.d/tls/vault-cert.pem"
    local key_file="/etc/vault.d/tls/vault-key.pem"
    local ca_file="/etc/vault.d/tls/ca-cert.pem"
    
    if [[ -f "$cert_file" ]]; then
        test_result "TLS Certificate" "PASS" "Certificate file exists"
        
        # Check certificate validity
        if openssl x509 -in "$cert_file" -noout -checkend 2592000 2>/dev/null; then
            test_result "Certificate Validity" "PASS" "Certificate valid for at least 30 days"
        else
            test_result "Certificate Validity" "FAIL" "Certificate expires within 30 days"
        fi
        
        # Check certificate permissions
        local cert_perms=$(stat -c "%a" "$cert_file" 2>/dev/null || stat -f "%Lp" "$cert_file" 2>/dev/null)
        if [[ "$cert_perms" == "644" ]]; then
            test_result "Certificate Permissions" "PASS" "Correct permissions (644)"
        else
            test_result "Certificate Permissions" "WARN" "Permissions are $cert_perms (should be 644)"
        fi
    else
        test_result "TLS Certificate" "FAIL" "Certificate file not found"
    fi
    
    if [[ -f "$key_file" ]]; then
        test_result "TLS Private Key" "PASS" "Private key file exists"
        
        # Check key permissions
        local key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || stat -f "%Lp" "$key_file" 2>/dev/null)
        if [[ "$key_perms" == "600" ]]; then
            test_result "Key Permissions" "PASS" "Correct permissions (600)"
        else
            test_result "Key Permissions" "FAIL" "Permissions are $key_perms (should be 600)"
        fi
        
        # Verify key format
        if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
            test_result "Private Key Format" "PASS" "Valid RSA private key"
        else
            test_result "Private Key Format" "FAIL" "Invalid private key format"
        fi
    else
        test_result "TLS Private Key" "FAIL" "Private key file not found"
    fi
    
    if [[ -f "$ca_file" ]]; then
        test_result "CA Certificate" "PASS" "CA certificate file exists"
    else
        test_result "CA Certificate" "WARN" "CA certificate file not found (may not be needed)"
    fi
    
    # Check TLS configuration in Vault config
    local vault_config="/Users/mlautenschlager/cloudya/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        if grep -q "tls_disable.*false" "$vault_config"; then
            test_result "Vault TLS Config" "PASS" "TLS enabled in Vault configuration"
        else
            test_result "Vault TLS Config" "WARN" "TLS may not be enabled in Vault configuration"
        fi
    fi
}

# Validate secure token management
validate_token_management() {
    log_header "Validating Secure Token Management"
    
    local secure_dir="/etc/vault.d/secure"
    local tokens_dir="/etc/vault.d/secure/tokens"
    local keys_dir="/etc/vault.d/secure/keys"
    local master_key="/etc/vault.d/secure/keys/master.key"
    
    # Check directories
    if [[ -d "$secure_dir" ]]; then
        test_result "Secure Directory" "PASS" "Secure storage directory exists"
        
        local secure_perms=$(stat -c "%a" "$secure_dir" 2>/dev/null || stat -f "%Lp" "$secure_dir" 2>/dev/null)
        if [[ "$secure_perms" == "700" ]]; then
            test_result "Secure Directory Permissions" "PASS" "Correct permissions (700)"
        else
            test_result "Secure Directory Permissions" "FAIL" "Permissions are $secure_perms (should be 700)"
        fi
    else
        test_result "Secure Directory" "FAIL" "Secure storage directory not found"
    fi
    
    if [[ -d "$tokens_dir" ]]; then
        test_result "Tokens Directory" "PASS" "Tokens storage directory exists"
    else
        test_result "Tokens Directory" "FAIL" "Tokens storage directory not found"
    fi
    
    if [[ -d "$keys_dir" ]]; then
        test_result "Keys Directory" "PASS" "Keys storage directory exists"
    else
        test_result "Keys Directory" "FAIL" "Keys storage directory not found"
    fi
    
    if [[ -f "$master_key" ]]; then
        test_result "Master Encryption Key" "PASS" "Master encryption key exists"
        
        local key_perms=$(stat -c "%a" "$master_key" 2>/dev/null || stat -f "%Lp" "$master_key" 2>/dev/null)
        if [[ "$key_perms" == "600" ]]; then
            test_result "Master Key Permissions" "PASS" "Correct permissions (600)"
        else
            test_result "Master Key Permissions" "FAIL" "Permissions are $key_perms (should be 600)"
        fi
    else
        test_result "Master Encryption Key" "FAIL" "Master encryption key not found"
    fi
    
    # Test token manager functionality
    local token_manager="$SCRIPT_DIR/secure-token-manager.sh"
    if [[ -x "$token_manager" ]]; then
        test_result "Token Manager Script" "PASS" "Script exists and is executable"
        
        # Test basic functionality
        if "$token_manager" help >/dev/null 2>&1; then
            test_result "Token Manager Function" "PASS" "Script executes without errors"
        else
            test_result "Token Manager Function" "FAIL" "Script execution failed"
        fi
    else
        test_result "Token Manager Script" "FAIL" "Script not found or not executable"
    fi
}

# Validate audit logging
validate_audit_logging() {
    log_header "Validating Audit Logging"
    
    local audit_dir="/var/log/vault/audit"
    local compliance_dir="/var/log/vault/compliance"
    local alerts_dir="/var/log/vault/alerts"
    
    # Check directories
    if [[ -d "$audit_dir" ]]; then
        test_result "Audit Directory" "PASS" "Audit logging directory exists"
        
        local audit_perms=$(stat -c "%a" "$audit_dir" 2>/dev/null || stat -f "%Lp" "$audit_dir" 2>/dev/null)
        if [[ "$audit_perms" == "750" ]]; then
            test_result "Audit Directory Permissions" "PASS" "Correct permissions (750)"
        else
            test_result "Audit Directory Permissions" "WARN" "Permissions are $audit_perms (should be 750)"
        fi
    else
        test_result "Audit Directory" "FAIL" "Audit logging directory not found"
    fi
    
    if [[ -d "$compliance_dir" ]]; then
        test_result "Compliance Directory" "PASS" "Compliance directory exists"
    else
        test_result "Compliance Directory" "FAIL" "Compliance directory not found"
    fi
    
    if [[ -d "$alerts_dir" ]]; then
        test_result "Alerts Directory" "PASS" "Alerts directory exists"
    else
        test_result "Alerts Directory" "FAIL" "Alerts directory not found"
    fi
    
    # Check logrotate configuration
    if [[ -f "/etc/logrotate.d/vault-audit" ]]; then
        test_result "Log Rotation Config" "PASS" "Logrotate configuration exists"
    else
        test_result "Log Rotation Config" "WARN" "Logrotate configuration not found"
    fi
    
    # Check rsyslog configuration
    if [[ -f "/etc/rsyslog.d/10-vault-audit.conf" ]]; then
        test_result "Rsyslog Config" "PASS" "Rsyslog configuration exists"
    else
        test_result "Rsyslog Config" "WARN" "Rsyslog configuration not found"
    fi
    
    # Test audit logger script
    local audit_script="$SCRIPT_DIR/audit-logger.sh"
    if [[ -x "$audit_script" ]]; then
        test_result "Audit Logger Script" "PASS" "Script exists and is executable"
    else
        test_result "Audit Logger Script" "FAIL" "Script not found or not executable"
    fi
    
    # Check for audit parser
    if [[ -f "/usr/local/bin/vault-audit-parser.py" ]]; then
        test_result "Audit Parser" "PASS" "Audit parser tool available"
        
        if [[ -x "/usr/local/bin/vault-audit-parser.py" ]]; then
            test_result "Audit Parser Permissions" "PASS" "Parser is executable"
        else
            test_result "Audit Parser Permissions" "FAIL" "Parser is not executable"
        fi
    else
        test_result "Audit Parser" "FAIL" "Audit parser tool not found"
    fi
}

# Validate emergency access
validate_emergency_access() {
    log_header "Validating Emergency Access"
    
    local emergency_dir="/etc/vault.d/emergency"
    local keys_dir="/etc/vault.d/emergency/keys"
    local tokens_dir="/etc/vault.d/emergency/tokens"
    local break_glass_log="/var/log/vault/emergency/break-glass.log"
    
    # Check directories
    if [[ -d "$emergency_dir" ]]; then
        test_result "Emergency Directory" "PASS" "Emergency access directory exists"
        
        local emergency_perms=$(stat -c "%a" "$emergency_dir" 2>/dev/null || stat -f "%Lp" "$emergency_dir" 2>/dev/null)
        if [[ "$emergency_perms" == "700" ]]; then
            test_result "Emergency Directory Permissions" "PASS" "Correct permissions (700)"
        else
            test_result "Emergency Directory Permissions" "FAIL" "Permissions are $emergency_perms (should be 700)"
        fi
    else
        test_result "Emergency Directory" "FAIL" "Emergency access directory not found"
    fi
    
    if [[ -d "$keys_dir" ]]; then
        test_result "Emergency Keys Directory" "PASS" "Emergency keys directory exists"
    else
        test_result "Emergency Keys Directory" "FAIL" "Emergency keys directory not found"
    fi
    
    if [[ -d "$tokens_dir" ]]; then
        test_result "Emergency Tokens Directory" "PASS" "Emergency tokens directory exists"
    else
        test_result "Emergency Tokens Directory" "FAIL" "Emergency tokens directory not found"
    fi
    
    # Check documentation
    if [[ -f "$emergency_dir/README.md" ]]; then
        test_result "Emergency Documentation" "PASS" "Emergency procedures documentation exists"
    else
        test_result "Emergency Documentation" "WARN" "Emergency procedures documentation not found"
    fi
    
    # Test emergency access script
    local emergency_script="$SCRIPT_DIR/emergency-access.sh"
    if [[ -x "$emergency_script" ]]; then
        test_result "Emergency Access Script" "PASS" "Script exists and is executable"
    else
        test_result "Emergency Access Script" "FAIL" "Script not found or not executable"
    fi
    
    # Check break-glass log directory
    local break_glass_dir=$(dirname "$break_glass_log")
    if [[ -d "$break_glass_dir" ]]; then
        test_result "Break-glass Log Directory" "PASS" "Break-glass log directory exists"
    else
        test_result "Break-glass Log Directory" "WARN" "Break-glass log directory not found"
    fi
}

# Validate security monitoring
validate_security_monitoring() {
    log_header "Validating Security Monitoring"
    
    local monitor_dir="/var/log/vault/monitoring"
    local metrics_dir="/var/log/vault/metrics"
    local alerts_dir="/var/log/vault/alerts"
    
    # Check directories
    if [[ -d "$monitor_dir" ]]; then
        test_result "Monitoring Directory" "PASS" "Monitoring directory exists"
    else
        test_result "Monitoring Directory" "FAIL" "Monitoring directory not found"
    fi
    
    if [[ -d "$metrics_dir" ]]; then
        test_result "Metrics Directory" "PASS" "Metrics directory exists"
    else
        test_result "Metrics Directory" "FAIL" "Metrics directory not found"
    fi
    
    if [[ -d "$alerts_dir" ]]; then
        test_result "Security Alerts Directory" "PASS" "Security alerts directory exists"
    else
        test_result "Security Alerts Directory" "FAIL" "Security alerts directory not found"
    fi
    
    # Check monitoring configuration
    if [[ -f "$monitor_dir/config.json" ]]; then
        test_result "Monitoring Config" "PASS" "Monitoring configuration exists"
        
        # Validate JSON format
        if jq . "$monitor_dir/config.json" >/dev/null 2>&1; then
            test_result "Config JSON Format" "PASS" "Configuration is valid JSON"
        else
            test_result "Config JSON Format" "FAIL" "Configuration JSON is invalid"
        fi
    else
        test_result "Monitoring Config" "FAIL" "Monitoring configuration not found"
    fi
    
    # Test security monitor script
    local monitor_script="$SCRIPT_DIR/security-monitor.sh"
    if [[ -x "$monitor_script" ]]; then
        test_result "Security Monitor Script" "PASS" "Script exists and is executable"
    else
        test_result "Security Monitor Script" "FAIL" "Script not found or not executable"
    fi
    
    # Check systemd service
    if [[ -f "/etc/systemd/system/vault-security-monitor.service" ]]; then
        test_result "Monitoring Service" "PASS" "Systemd service file exists"
        
        if systemctl is-enabled vault-security-monitor >/dev/null 2>&1; then
            test_result "Service Enabled" "PASS" "Monitoring service is enabled"
        else
            test_result "Service Enabled" "WARN" "Monitoring service is not enabled"
        fi
        
        if systemctl is-active vault-security-monitor >/dev/null 2>&1; then
            test_result "Service Active" "PASS" "Monitoring service is running"
        else
            test_result "Service Active" "WARN" "Monitoring service is not running"
        fi
    else
        test_result "Monitoring Service" "WARN" "Systemd service file not found"
    fi
}

# Validate system configuration
validate_system_config() {
    log_header "Validating System Configuration"
    
    # Check Vault configuration
    local vault_config="/Users/mlautenschlager/cloudya/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        test_result "Vault Config File" "PASS" "Vault configuration file exists"
        
        # Check for security-related settings
        if grep -q "disable_mlock.*false" "$vault_config"; then
            test_result "Memory Lock" "PASS" "Memory locking enabled"
        else
            test_result "Memory Lock" "WARN" "Memory locking disabled"
        fi
        
        if grep -q "log_format.*json" "$vault_config"; then
            test_result "JSON Logging" "PASS" "JSON logging format configured"
        else
            test_result "JSON Logging" "WARN" "JSON logging format not configured"
        fi
        
        if grep -q "log_file" "$vault_config"; then
            test_result "Log File Config" "PASS" "Log file path configured"
        else
            test_result "Log File Config" "WARN" "Log file path not configured"
        fi
    else
        test_result "Vault Config File" "FAIL" "Vault configuration file not found"
    fi
    
    # Check script permissions
    local scripts=("tls-cert-manager.sh" "secure-token-manager.sh" "audit-logger.sh" "emergency-access.sh" "security-monitor.sh")
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -x "$script_path" ]]; then
            test_result "$script Permissions" "PASS" "Script is executable"
        else
            test_result "$script Permissions" "FAIL" "Script not found or not executable"
        fi
    done
    
    # Check symlinks
    local bin_dir="/usr/local/bin"
    for script in "${scripts[@]}"; do
        local symlink_path="$bin_dir/vault-${script}"
        if [[ -L "$symlink_path" ]]; then
            test_result "$script Symlink" "PASS" "System-wide symlink exists"
        else
            test_result "$script Symlink" "WARN" "System-wide symlink not found"
        fi
    done
}

# Validate firewall configuration
validate_firewall() {
    log_header "Validating Firewall Configuration"
    
    # Check UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            test_result "UFW Firewall" "PASS" "UFW is active"
            
            # Check specific rules
            if ufw status | grep -q "8200/tcp"; then
                test_result "Vault API Rule" "PASS" "Vault API port allowed"
            else
                test_result "Vault API Rule" "WARN" "Vault API port rule not found"
            fi
            
            if ufw status | grep -q "8201/tcp"; then
                test_result "Vault Cluster Rule" "PASS" "Vault cluster port allowed"
            else
                test_result "Vault Cluster Rule" "WARN" "Vault cluster port rule not found"
            fi
        else
            test_result "UFW Firewall" "WARN" "UFW is installed but not active"
        fi
    # Check iptables
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -L | grep -q "DROP"; then
            test_result "iptables Firewall" "PASS" "iptables rules configured"
            
            # Check for Vault ports
            if iptables -L | grep -q "8200"; then
                test_result "Vault API iptables Rule" "PASS" "Vault API port rule found"
            else
                test_result "Vault API iptables Rule" "WARN" "Vault API port rule not found"
            fi
        else
            test_result "iptables Firewall" "WARN" "iptables rules may not be configured"
        fi
    else
        test_result "Firewall" "WARN" "No supported firewall found"
    fi
}

# Validate cron jobs
validate_automation() {
    log_header "Validating Automation"
    
    # Check cron configuration
    if [[ -f "/etc/cron.d/vault-security" ]]; then
        test_result "Security Cron Jobs" "PASS" "Security automation cron jobs configured"
    else
        test_result "Security Cron Jobs" "WARN" "Security automation cron jobs not found"
    fi
    
    if [[ -f "/etc/cron.d/vault-compliance-reports" ]]; then
        test_result "Compliance Reporting" "PASS" "Compliance reporting cron jobs configured"
    else
        test_result "Compliance Reporting" "WARN" "Compliance reporting cron jobs not found"
    fi
    
    # Check certificate renewal
    if [[ -f "/etc/systemd/system/vault-cert-renewal.timer" ]]; then
        test_result "Cert Renewal Timer" "PASS" "Certificate renewal timer configured"
        
        if systemctl is-enabled vault-cert-renewal.timer >/dev/null 2>&1; then
            test_result "Cert Renewal Enabled" "PASS" "Certificate renewal timer enabled"
        else
            test_result "Cert Renewal Enabled" "WARN" "Certificate renewal timer not enabled"
        fi
    else
        test_result "Cert Renewal Timer" "WARN" "Certificate renewal timer not found"
    fi
}

# Validate documentation
validate_documentation() {
    log_header "Validating Documentation"
    
    local docs_dir="/Users/mlautenschlager/cloudya/vault/docs"
    
    # Check security documentation
    if [[ -f "$docs_dir/SECURITY_RUNBOOK.md" ]]; then
        test_result "Security Runbook" "PASS" "Security runbook exists"
    else
        test_result "Security Runbook" "FAIL" "Security runbook not found"
    fi
    
    if [[ -f "$docs_dir/INCIDENT_RESPONSE_PLAN.md" ]]; then
        test_result "Incident Response Plan" "PASS" "Incident response plan exists"
    else
        test_result "Incident Response Plan" "FAIL" "Incident response plan not found"
    fi
    
    if [[ -f "$docs_dir/SECURITY_SETUP_SUMMARY.md" ]]; then
        test_result "Setup Summary" "PASS" "Security setup summary exists"
    else
        test_result "Setup Summary" "WARN" "Security setup summary not found"
    fi
    
    # Check emergency documentation
    if [[ -f "/etc/vault.d/emergency/README.md" ]]; then
        test_result "Emergency Procedures Doc" "PASS" "Emergency procedures documentation exists"
    else
        test_result "Emergency Procedures Doc" "WARN" "Emergency procedures documentation not found"
    fi
}

# Generate validation report
generate_report() {
    log_header "Validation Summary"
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNINGS))
    local pass_rate=0
    
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / total_tests))
    fi
    
    echo -e "${BOLD}Security Validation Results:${NC}"
    echo -e "  ${GREEN}✅ Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}❌ Failed: $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}⚠️  Warnings: $TESTS_WARNINGS${NC}"
    echo -e "  ${BLUE}📊 Pass Rate: ${pass_rate}%${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        if [[ $TESTS_WARNINGS -eq 0 ]]; then
            log_success "All security validations passed! 🎉"
            echo "Your Vault security configuration is excellent."
        else
            log_success "Core security validations passed! ⭐"
            echo "Minor warnings found - consider addressing for optimal security."
        fi
    else
        log_fail "Security validation failed!"
        echo "Critical issues found that need immediate attention."
        echo ""
        echo "Recommended actions:"
        echo "1. Review failed tests above"
        echo "2. Run the security initialization script: ./init-security.sh"
        echo "3. Fix any configuration issues"
        echo "4. Re-run this validation script"
    fi
    
    echo ""
    echo "For detailed security procedures, see:"
    echo "- Security Runbook: $VAULT_DIR/docs/SECURITY_RUNBOOK.md"
    echo "- Incident Response Plan: $VAULT_DIR/docs/INCIDENT_RESPONSE_PLAN.md"
    
    # Create validation report file
    local report_file="$VAULT_DIR/docs/SECURITY_VALIDATION_REPORT.md"
    cat > "$report_file" << EOF
# Vault Security Validation Report

**Generated:** $(date)
**Host:** $(hostname)
**Total Tests:** $total_tests
**Pass Rate:** ${pass_rate}%

## Summary

- ✅ **Passed:** $TESTS_PASSED
- ❌ **Failed:** $TESTS_FAILED  
- ⚠️ **Warnings:** $TESTS_WARNINGS

## Status

$(if [[ $TESTS_FAILED -eq 0 ]]; then
    if [[ $TESTS_WARNINGS -eq 0 ]]; then
        echo "🎉 **EXCELLENT** - All security validations passed"
    else
        echo "⭐ **GOOD** - Core security validations passed with minor warnings"
    fi
else
    echo "❌ **NEEDS ATTENTION** - Critical security issues found"
fi)

## Next Steps

$(if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "1. Review failed validations above"
    echo "2. Run security initialization: \`./security/init-security.sh\`"
    echo "3. Fix configuration issues"
    echo "4. Re-run validation"
else
    echo "1. Address any warnings if applicable"
    echo "2. Schedule regular security reviews"
    echo "3. Test emergency procedures"
    echo "4. Train staff on security protocols"
fi)

---
*Generated by Vault Security Validation System*
EOF
    
    log_info "Detailed report saved to: $report_file"
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Main execution
main() {
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                         Vault Security Validation                           ║
║                                                                              ║
║  Comprehensive validation of all security components and configurations      ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    log_info "Starting comprehensive security validation..."
    
    # Run all validation tests
    validate_tls
    validate_token_management
    validate_audit_logging
    validate_emergency_access
    validate_security_monitoring
    validate_system_config
    validate_firewall
    validate_automation
    validate_documentation
    
    # Generate final report
    generate_report
}

# Run main function
main "$@"