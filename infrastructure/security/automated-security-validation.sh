#!/bin/bash

# Automated Security Validation Script for Infrastructure Hive
# Performs comprehensive security checks across Vault, Nomad, and Traefik
# Generates detailed security assessment report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-develop}"
REPORT_FILE="$SCRIPT_DIR/security-validation-report-$(date +%Y%m%d-%H%M%S).json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Test results tracking
declare -A TEST_RESULTS
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0
CRITICAL_ISSUES=0
MAJOR_ISSUES=0
MINOR_ISSUES=0

# Logging functions
log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Test result tracking
record_test() {
    local test_name="$1"
    local result="$2"
    local severity="$3"
    local message="$4"
    local fix_required="${5:-false}"
    
    TEST_RESULTS["$test_name"]="$result|$severity|$message|$fix_required"
    
    case $result in
        "PASS")
            log_success "$test_name: $message"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            case $severity in
                "CRITICAL")
                    log_critical "$test_name: $message"
                    ((CRITICAL_ISSUES++))
                    ;;
                "MAJOR")
                    log_error "$test_name: $message"
                    ((MAJOR_ISSUES++))
                    ;;
                "MINOR")
                    log_warning "$test_name: $message"
                    ((MINOR_ISSUES++))
                    ;;
            esac
            ((TESTS_FAILED++))
            ;;
        "WARNING")
            log_warning "$test_name: $message"
            ((TESTS_WARNING++))
            ;;
    esac
}

# TLS Security Validation
validate_tls_security() {
    log_header "VALIDATING TLS SECURITY CONFIGURATION"
    
    # Check Vault TLS configuration
    log_step "Checking Vault TLS configuration..."
    
    local vault_config="$INFRA_DIR/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        if grep -q "tls_disable.*false" "$vault_config" 2>/dev/null; then
            record_test "Vault TLS Enabled" "PASS" "LOW" "TLS is enabled in Vault configuration"
        else
            record_test "Vault TLS Enabled" "FAIL" "CRITICAL" "TLS is disabled in Vault configuration" "true"
        fi
        
        # Check TLS version
        if grep -q "tls_min_version.*tls1[23]" "$vault_config" 2>/dev/null; then
            record_test "Vault TLS Version" "PASS" "LOW" "Strong TLS version configured"
        else
            record_test "Vault TLS Version" "FAIL" "MAJOR" "TLS version not specified or too weak" "true"
        fi
        
        # Check cipher suites
        if grep -q "tls_cipher_suites" "$vault_config" 2>/dev/null; then
            record_test "Vault Cipher Suites" "PASS" "LOW" "Custom cipher suites configured"
        else
            record_test "Vault Cipher Suites" "WARNING" "MINOR" "Default cipher suites in use"
        fi
        
        # Check certificate paths
        local cert_file=$(grep "tls_cert_file" "$vault_config" | cut -d'"' -f2 2>/dev/null || echo "")
        local key_file=$(grep "tls_key_file" "$vault_config" | cut -d'"' -f2 2>/dev/null || echo "")
        
        if [[ -n "$cert_file" && -n "$key_file" ]]; then
            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                # Check certificate validity
                if openssl x509 -in "$cert_file" -noout -checkend 2592000 2>/dev/null; then
                    record_test "Vault Certificate Validity" "PASS" "LOW" "Certificate valid for >30 days"
                else
                    record_test "Vault Certificate Validity" "FAIL" "MAJOR" "Certificate expires within 30 days" "true"
                fi
                
                # Check key permissions
                local key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || stat -f "%A" "$key_file" 2>/dev/null || echo "000")
                if [[ "$key_perms" == "600" ]]; then
                    record_test "Vault Key Permissions" "PASS" "LOW" "Private key has secure permissions"
                else
                    record_test "Vault Key Permissions" "FAIL" "MAJOR" "Private key permissions too permissive ($key_perms)" "true"
                fi
            else
                record_test "Vault Certificate Files" "FAIL" "CRITICAL" "Certificate or key files not found" "true"
            fi
        else
            record_test "Vault Certificate Configuration" "FAIL" "CRITICAL" "Certificate paths not configured" "true"
        fi
    else
        record_test "Vault Configuration" "FAIL" "CRITICAL" "Vault configuration file not found" "true"
    fi
    
    # Check environment-specific configurations
    local env_config="$INFRA_DIR/vault/config/environments/${ENVIRONMENT}.hcl"
    if [[ -f "$env_config" ]]; then
        if [[ "$ENVIRONMENT" == "production" ]]; then
            if grep -q "tls_min_version.*tls13" "$env_config" 2>/dev/null; then
                record_test "Production TLS 1.3" "PASS" "LOW" "Production uses TLS 1.3"
            else
                record_test "Production TLS 1.3" "FAIL" "MAJOR" "Production should enforce TLS 1.3" "true"
            fi
            
            if grep -q "tls_require_and_verify_client_cert.*true" "$env_config" 2>/dev/null; then
                record_test "Production Mutual TLS" "PASS" "LOW" "Mutual TLS enabled for production"
            else
                record_test "Production Mutual TLS" "FAIL" "MAJOR" "Mutual TLS not enabled for production" "true"
            fi
        fi
    fi
}

# Network Security Validation
validate_network_security() {
    log_header "VALIDATING NETWORK SECURITY"
    
    log_step "Checking service binding configuration..."
    
    # Check Vault listener binding
    local vault_config="$INFRA_DIR/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        local vault_address=$(grep "address.*=" "$vault_config" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
        if [[ "$vault_address" == "0.0.0.0:8200" ]]; then
            record_test "Vault Network Binding" "FAIL" "CRITICAL" "Vault bound to all interfaces (0.0.0.0)" "true"
        elif [[ "$vault_address" =~ ^127\.0\.0\.1:|^localhost: ]]; then
            record_test "Vault Network Binding" "PASS" "LOW" "Vault bound to localhost interface"
        elif [[ -n "$vault_address" ]]; then
            record_test "Vault Network Binding" "PASS" "LOW" "Vault bound to specific interface: $vault_address"
        else
            record_test "Vault Network Binding" "WARNING" "MINOR" "Could not determine Vault binding address"
        fi
    fi
    
    # Check Nomad configuration
    local nomad_config="$INFRA_DIR/nomad/config/nomad-server.hcl"
    if [[ -f "$nomad_config" ]]; then
        if grep -q "bind_addr.*0.0.0.0" "$nomad_config" 2>/dev/null; then
            record_test "Nomad Network Binding" "FAIL" "MAJOR" "Nomad bound to all interfaces (0.0.0.0)" "true"
        else
            record_test "Nomad Network Binding" "PASS" "LOW" "Nomad binding appears secure"
        fi
    fi
    
    # Check API addresses
    log_step "Checking API endpoint security..."
    
    if grep -q "api_addr.*http://" "$vault_config" 2>/dev/null; then
        record_test "Vault API HTTP" "FAIL" "CRITICAL" "Vault API configured for HTTP instead of HTTPS" "true"
    elif grep -q "api_addr.*https://" "$vault_config" 2>/dev/null; then
        record_test "Vault API HTTPS" "PASS" "LOW" "Vault API properly configured for HTTPS"
    fi
}

# Token and Secret Management Security
validate_token_security() {
    log_header "VALIDATING TOKEN AND SECRET MANAGEMENT"
    
    log_step "Checking secure token manager..."
    
    local token_manager="$INFRA_DIR/vault/security/secure-token-manager.sh"
    if [[ -f "$token_manager" && -x "$token_manager" ]]; then
        record_test "Token Manager Present" "PASS" "LOW" "Secure token manager script available"
        
        # Check encryption implementation
        if grep -q "aes-256-cbc" "$token_manager" && grep -q "pbkdf2" "$token_manager"; then
            record_test "Token Encryption" "PASS" "LOW" "Strong encryption (AES-256-CBC + PBKDF2) implemented"
        else
            record_test "Token Encryption" "FAIL" "MAJOR" "Weak or missing token encryption" "true"
        fi
        
        # Check iteration count
        if grep -q "iter 100000" "$token_manager"; then
            record_test "PBKDF2 Iterations" "PASS" "LOW" "Strong PBKDF2 iteration count (100,000)"
        else
            record_test "PBKDF2 Iterations" "WARNING" "MINOR" "PBKDF2 iteration count not verified"
        fi
        
        # Check secure directories
        if grep -q "chmod 700" "$token_manager"; then
            record_test "Token Directory Permissions" "PASS" "LOW" "Secure directory permissions enforced"
        else
            record_test "Token Directory Permissions" "WARNING" "MINOR" "Directory permissions not explicitly set"
        fi
    else
        record_test "Token Manager Present" "FAIL" "MAJOR" "Secure token manager not found or not executable" "true"
    fi
    
    # Check for plaintext tokens in configuration
    log_step "Scanning for plaintext tokens..."
    
    local plaintext_found=false
    
    # Check common token patterns in config files
    if find "$INFRA_DIR" -name "*.hcl" -o -name "*.yml" -o -name "*.yaml" | xargs grep -l "hvs\." 2>/dev/null; then
        record_test "Plaintext Vault Tokens" "FAIL" "CRITICAL" "Plaintext Vault tokens found in configuration" "true"
        plaintext_found=true
    fi
    
    if find "$INFRA_DIR" -name "*.sh" | xargs grep -l "VAULT_TOKEN.*=" 2>/dev/null | head -5; then
        # Check if these are just variable assignments or actual token values
        local suspicious_tokens=$(find "$INFRA_DIR" -name "*.sh" | xargs grep "VAULT_TOKEN.*=.*hvs\." 2>/dev/null | wc -l)
        if [[ $suspicious_tokens -gt 0 ]]; then
            record_test "Script Token Exposure" "FAIL" "CRITICAL" "Hardcoded tokens found in scripts" "true"
            plaintext_found=true
        fi
    fi
    
    if [[ "$plaintext_found" == "false" ]]; then
        record_test "Token Security Scan" "PASS" "LOW" "No plaintext tokens found in configurations"
    fi
    
    # Check bootstrap token security
    log_step "Checking bootstrap token security..."
    
    local bootstrap_script="$INFRA_DIR/scripts/unified-bootstrap.sh"
    if [[ -f "$bootstrap_script" ]]; then
        # Check for temporary token cleanup
        if grep -q "rm.*bootstrap-tokens" "$bootstrap_script" || grep -q "trap.*rm" "$bootstrap_script"; then
            record_test "Bootstrap Token Cleanup" "PASS" "LOW" "Bootstrap token cleanup implemented"
        else
            record_test "Bootstrap Token Cleanup" "FAIL" "MAJOR" "Bootstrap token cleanup not implemented" "true"
        fi
        
        # Check for secure temporary directories
        if grep -q "/tmp/bootstrap-tokens" "$bootstrap_script"; then
            record_test "Bootstrap Token Storage" "WARNING" "MINOR" "Bootstrap tokens stored in /tmp (consider more secure location)"
        fi
    fi
}

# Audit and Logging Security
validate_audit_logging() {
    log_header "VALIDATING AUDIT AND LOGGING"
    
    log_step "Checking Vault audit configuration..."
    
    local vault_config="$INFRA_DIR/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        # Check if audit devices are configured (even if commented)
        if grep -q '^audit "file"' "$vault_config" 2>/dev/null; then
            record_test "Vault File Audit" "PASS" "LOW" "File audit device configured"
        elif grep -q '^# audit "file"' "$vault_config" 2>/dev/null; then
            record_test "Vault File Audit" "FAIL" "MAJOR" "File audit device commented out" "true"
        else
            record_test "Vault File Audit" "FAIL" "MAJOR" "File audit device not configured" "true"
        fi
        
        if grep -q '^audit "syslog"' "$vault_config" 2>/dev/null; then
            record_test "Vault Syslog Audit" "PASS" "LOW" "Syslog audit device configured"
        elif grep -q '^# audit "syslog"' "$vault_config" 2>/dev/null; then
            record_test "Vault Syslog Audit" "WARNING" "MINOR" "Syslog audit device available but commented"
        fi
        
        # Check logging configuration
        if grep -q "log_format.*json" "$vault_config" 2>/dev/null; then
            record_test "Vault JSON Logging" "PASS" "LOW" "JSON logging format configured"
        else
            record_test "Vault JSON Logging" "WARNING" "MINOR" "JSON logging format not configured"
        fi
        
        if grep -q "log_rotate_duration" "$vault_config" 2>/dev/null; then
            record_test "Vault Log Rotation" "PASS" "LOW" "Log rotation configured"
        else
            record_test "Vault Log Rotation" "WARNING" "MINOR" "Log rotation not configured"
        fi
    fi
    
    # Check audit logger script
    local audit_logger="$INFRA_DIR/vault/security/audit-logger.sh"
    if [[ -f "$audit_logger" && -x "$audit_logger" ]]; then
        record_test "Audit Logger Script" "PASS" "LOW" "Audit logging script available"
    else
        record_test "Audit Logger Script" "WARNING" "MINOR" "Audit logging script not found"
    fi
}

# Access Control and Policies
validate_access_control() {
    log_header "VALIDATING ACCESS CONTROL AND POLICIES"
    
    log_step "Checking Vault policies..."
    
    local policies_dir="$INFRA_DIR/vault/policies"
    if [[ -d "$policies_dir" ]]; then
        # Check admin policy
        local admin_policy="$policies_dir/admin.hcl"
        if [[ -f "$admin_policy" ]]; then
            if grep -q 'path "auth/token/root"' "$admin_policy" && grep -q 'capabilities.*deny' "$admin_policy"; then
                record_test "Admin Root Protection" "PASS" "LOW" "Admin policy protects root token creation"
            else
                record_test "Admin Root Protection" "FAIL" "MAJOR" "Admin policy lacks root token protection" "true"
            fi
            
            # Check for overly broad permissions
            if grep -q 'path "\*"' "$admin_policy"; then
                local capabilities=$(grep -A 1 'path "\*"' "$admin_policy" | grep capabilities)
                if [[ -n "$capabilities" ]]; then
                    record_test "Admin Policy Scope" "WARNING" "MINOR" "Admin policy uses wildcard path - review scope"
                fi
            fi
        else
            record_test "Admin Policy Present" "FAIL" "MAJOR" "Admin policy not found" "true"
        fi
        
        # Check other essential policies
        local essential_policies=("developer.hcl" "operations.hcl" "ci-cd.hcl")
        local missing_policies=0
        
        for policy in "${essential_policies[@]}"; do
            if [[ ! -f "$policies_dir/$policy" ]]; then
                ((missing_policies++))
            fi
        done
        
        if [[ $missing_policies -eq 0 ]]; then
            record_test "Essential Policies" "PASS" "LOW" "All essential policies present"
        elif [[ $missing_policies -lt 3 ]]; then
            record_test "Essential Policies" "WARNING" "MINOR" "$missing_policies essential policies missing"
        else
            record_test "Essential Policies" "FAIL" "MAJOR" "Most essential policies missing" "true"
        fi
    else
        record_test "Policies Directory" "FAIL" "CRITICAL" "Vault policies directory not found" "true"
    fi
    
    # Check ACL configuration in Nomad
    local nomad_config="$INFRA_DIR/nomad/config/nomad-server.hcl"
    if [[ -f "$nomad_config" ]]; then
        if grep -q "acl.*enabled.*true" "$nomad_config" 2>/dev/null; then
            record_test "Nomad ACL Enabled" "PASS" "LOW" "Nomad ACLs are enabled"
        else
            record_test "Nomad ACL Enabled" "FAIL" "MAJOR" "Nomad ACLs not enabled" "true"
        fi
    fi
}

# System Security Configuration
validate_system_security() {
    log_header "VALIDATING SYSTEM SECURITY CONFIGURATION"
    
    log_step "Checking memory security..."
    
    local vault_config="$INFRA_DIR/vault/config/vault.hcl"
    if [[ -f "$vault_config" ]]; then
        if grep -q "disable_mlock.*false" "$vault_config" 2>/dev/null; then
            record_test "Memory Locking" "PASS" "LOW" "Memory locking enabled (mlock)"
        else
            record_test "Memory Locking" "WARNING" "MINOR" "Memory locking disabled"
        fi
    fi
    
    # Check service user configuration
    log_step "Checking service user security..."
    
    local deploy_script="$INFRA_DIR/vault/scripts/deploy-vault.sh"
    if [[ -f "$deploy_script" ]]; then
        if grep -q "User=vault" "$deploy_script" && grep -q "Group=vault" "$deploy_script"; then
            record_test "Vault Service User" "PASS" "LOW" "Vault runs as dedicated service user"
        elif grep -q "User=root" "$deploy_script"; then
            record_test "Vault Service User" "FAIL" "MAJOR" "Vault configured to run as root" "true"
        else
            record_test "Vault Service User" "WARNING" "MINOR" "Service user configuration unclear"
        fi
        
        # Check systemd security features
        if grep -q "ProtectSystem=full" "$deploy_script"; then
            record_test "Systemd Hardening" "PASS" "LOW" "Systemd security features enabled"
        else
            record_test "Systemd Hardening" "WARNING" "MINOR" "Systemd security features not verified"
        fi
    fi
    
    # Check file permissions on critical files
    log_step "Checking file permissions..."
    
    local critical_files=(
        "$INFRA_DIR/vault/config/vault.hcl:644"
        "$INFRA_DIR/vault/policies/admin.hcl:644"
        "$INFRA_DIR/vault/security/secure-token-manager.sh:755"
    )
    
    for file_perm in "${critical_files[@]}"; do
        local file_path="${file_perm%:*}"
        local expected_perm="${file_perm#*:}"
        local file_name=$(basename "$file_path")
        
        if [[ -f "$file_path" ]]; then
            local actual_perm=$(stat -c "%a" "$file_path" 2>/dev/null || stat -f "%A" "$file_path" 2>/dev/null || echo "000")
            if [[ "$actual_perm" == "$expected_perm" ]]; then
                record_test "File Permissions: $file_name" "PASS" "LOW" "Correct permissions ($expected_perm)"
            else
                record_test "File Permissions: $file_name" "WARNING" "MINOR" "Permissions $actual_perm (expected $expected_perm)"
            fi
        fi
    done
}

# Environment-Specific Security
validate_environment_security() {
    log_header "VALIDATING ENVIRONMENT-SPECIFIC SECURITY"
    
    log_step "Checking environment isolation..."
    
    # Check environment directories exist
    local env_dirs=("develop" "staging" "production")
    local missing_envs=0
    
    for env in "${env_dirs[@]}"; do
        if [[ ! -d "$INFRA_DIR/environments/$env" ]]; then
            ((missing_envs++))
        fi
    done
    
    if [[ $missing_envs -eq 0 ]]; then
        record_test "Environment Isolation" "PASS" "LOW" "All environment directories present"
    else
        record_test "Environment Isolation" "WARNING" "MINOR" "$missing_envs environment directories missing"
    fi
    
    # Check current environment configuration
    local env_config="$INFRA_DIR/vault/config/environments/${ENVIRONMENT}.hcl"
    if [[ -f "$env_config" ]]; then
        record_test "Environment Config" "PASS" "LOW" "Environment-specific configuration found"
        
        # Environment-specific checks
        case $ENVIRONMENT in
            "production")
                if grep -q "ui.*false" "$env_config" 2>/dev/null; then
                    record_test "Production UI Disabled" "PASS" "LOW" "UI properly disabled in production"
                else
                    record_test "Production UI Disabled" "FAIL" "MAJOR" "UI should be disabled in production" "true"
                fi
                ;;
            "develop")
                if grep -q "tls_disable.*false" "$env_config" 2>/dev/null; then
                    record_test "Development TLS" "PASS" "LOW" "TLS enabled even in development"
                else
                    record_test "Development TLS" "WARNING" "MINOR" "Consider enabling TLS in development"
                fi
                ;;
        esac
    else
        record_test "Environment Config" "WARNING" "MINOR" "Environment-specific configuration not found"
    fi
}

# Bootstrap Security Validation
validate_bootstrap_security() {
    log_header "VALIDATING BOOTSTRAP SECURITY"
    
    log_step "Checking bootstrap process security..."
    
    local bootstrap_script="$INFRA_DIR/scripts/unified-bootstrap.sh"
    if [[ -f "$bootstrap_script" ]]; then
        # Check for proper service sequencing
        if grep -q "deploy_nomad" "$bootstrap_script" && grep -q "deploy_vault" "$bootstrap_script" && grep -q "deploy_traefik" "$bootstrap_script"; then
            record_test "Bootstrap Sequencing" "PASS" "LOW" "Proper service deployment sequencing"
        else
            record_test "Bootstrap Sequencing" "WARNING" "MINOR" "Bootstrap sequencing not clear"
        fi
        
        # Check for health checks
        if grep -q "check_service_health" "$bootstrap_script" || grep -q "health" "$bootstrap_script"; then
            record_test "Bootstrap Health Checks" "PASS" "LOW" "Health checks implemented in bootstrap"
        else
            record_test "Bootstrap Health Checks" "WARNING" "MINOR" "Health checks not found in bootstrap"
        fi
        
        # Check for cleanup on failure
        if grep -q "cleanup" "$bootstrap_script" && grep -q "trap.*cleanup" "$bootstrap_script"; then
            record_test "Bootstrap Cleanup" "PASS" "LOW" "Cleanup on failure implemented"
        else
            record_test "Bootstrap Cleanup" "WARNING" "MINOR" "Cleanup on failure not implemented"
        fi
        
        # Check for secure temporary file handling
        if grep -q "mktemp" "$bootstrap_script"; then
            record_test "Secure Temp Files" "PASS" "LOW" "Secure temporary file creation"
        else
            record_test "Secure Temp Files" "WARNING" "MINOR" "Temporary file security not verified"
        fi
    else
        record_test "Bootstrap Script Present" "FAIL" "MAJOR" "Bootstrap script not found" "true"
    fi
}

# Compliance and Documentation Check
validate_compliance() {
    log_header "VALIDATING COMPLIANCE AND DOCUMENTATION"
    
    log_step "Checking security documentation..."
    
    local docs_dir="$INFRA_DIR/vault/docs"
    local required_docs=(
        "SECURITY_RUNBOOK.md"
        "INCIDENT_RESPONSE_PLAN.md"
        "OPERATIONS_MANUAL.md"
    )
    
    local missing_docs=0
    
    for doc in "${required_docs[@]}"; do
        if [[ -f "$docs_dir/$doc" ]]; then
            record_test "Documentation: $doc" "PASS" "LOW" "Required documentation present"
        else
            record_test "Documentation: $doc" "WARNING" "MINOR" "Required documentation missing"
            ((missing_docs++))
        fi
    done
    
    # Check security policies
    local security_policies="$INFRA_DIR/security/security-policies.yaml"
    if [[ -f "$security_policies" ]]; then
        if grep -q "SOC2\|ISO 27001\|PCI DSS\|GDPR" "$security_policies"; then
            record_test "Compliance Standards" "PASS" "LOW" "Compliance standards documented"
        else
            record_test "Compliance Standards" "WARNING" "MINOR" "Compliance standards not clearly defined"
        fi
    else
        record_test "Security Policies" "WARNING" "MINOR" "Security policies document not found"
    fi
}

# Generate comprehensive JSON report
generate_json_report() {
    log_step "Generating detailed security assessment report..."
    
    local overall_status="SECURE"
    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        overall_status="CRITICAL"
    elif [[ $MAJOR_ISSUES -gt 0 ]]; then
        overall_status="MAJOR_ISSUES"
    elif [[ $MINOR_ISSUES -gt 0 ]]; then
        overall_status="MINOR_ISSUES"
    fi
    
    local production_ready="false"
    if [[ $CRITICAL_ISSUES -eq 0 && $MAJOR_ISSUES -eq 0 ]]; then
        production_ready="true"
    fi
    
    cat > "$REPORT_FILE" << EOF
{
  "security_assessment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "overall_status": "$overall_status",
    "production_ready": $production_ready,
    "summary": {
      "tests_passed": $TESTS_PASSED,
      "tests_failed": $TESTS_FAILED,
      "tests_warning": $TESTS_WARNING,
      "critical_issues": $CRITICAL_ISSUES,
      "major_issues": $MAJOR_ISSUES,
      "minor_issues": $MINOR_ISSUES
    },
    "test_results": {
EOF
    
    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result_data="${TEST_RESULTS[$test_name]}"
        local result="${result_data%%|*}"
        local temp="${result_data#*|}"
        local severity="${temp%%|*}"
        local temp2="${temp#*|}"
        local message="${temp2%%|*}"
        local fix_required="${temp2#*|}"
        
        if [[ "$first" == "false" ]]; then
            echo "," >> "$REPORT_FILE"
        fi
        first=false
        
        cat >> "$REPORT_FILE" << EOF
      "$test_name": {
        "result": "$result",
        "severity": "$severity",
        "message": "$message",
        "fix_required": $fix_required
      }
EOF
    done
    
    cat >> "$REPORT_FILE" << EOF
    },
    "recommendations": {
      "critical": [
        "Enable TLS encryption across all services",
        "Implement secure bootstrap token handling",
        "Enable audit logging by default",
        "Restrict network bindings to specific interfaces"
      ],
      "major": [
        "Configure certificate monitoring and renewal",
        "Implement comprehensive security monitoring",
        "Complete backup and recovery validation"
      ],
      "minor": [
        "Update documentation and procedures",
        "Enhance monitoring and alerting",
        "Implement security training programs"
      ]
    },
    "next_steps": {
      "immediate": "Address all critical security issues",
      "short_term": "Resolve major security issues within 1 week", 
      "long_term": "Implement continuous security monitoring and compliance"
    }
  }
}
EOF
}

# Generate human-readable summary
generate_summary() {
    log_header "SECURITY ASSESSMENT SUMMARY"
    
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Assessment Time:${NC} $(date)"
    echo -e "${WHITE}Total Tests:${NC} $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))"
    echo ""
    
    echo -e "${WHITE}Results Summary:${NC}"
    echo -e "  ${GREEN}✅ Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}❌ Failed:${NC} $TESTS_FAILED"
    echo -e "  ${YELLOW}⚠️  Warnings:${NC} $TESTS_WARNING"
    echo ""
    
    echo -e "${WHITE}Issue Severity Breakdown:${NC}"
    echo -e "  ${RED}🔴 Critical:${NC} $CRITICAL_ISSUES"
    echo -e "  ${YELLOW}🟠 Major:${NC} $MAJOR_ISSUES"
    echo -e "  ${BLUE}🟡 Minor:${NC} $MINOR_ISSUES"
    echo ""
    
    # Production readiness assessment
    if [[ $CRITICAL_ISSUES -eq 0 && $MAJOR_ISSUES -eq 0 ]]; then
        echo -e "${GREEN}${WHITE}PRODUCTION READY:${NC} ${GREEN}✅ YES${NC}"
        echo -e "This infrastructure meets security requirements for production deployment."
    elif [[ $CRITICAL_ISSUES -eq 0 ]]; then
        echo -e "${YELLOW}${WHITE}PRODUCTION READY:${NC} ${YELLOW}⚠️  WITH FIXES${NC}"
        echo -e "Address major issues before production deployment."
    else
        echo -e "${RED}${WHITE}PRODUCTION READY:${NC} ${RED}❌ NO${NC}"
        echo -e "Critical security issues must be resolved before production deployment."
    fi
    
    echo ""
    echo -e "${WHITE}Detailed Report:${NC} $REPORT_FILE"
    
    # Show immediate action items if any critical issues
    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        echo ""
        echo -e "${RED}${WHITE}IMMEDIATE ACTION REQUIRED:${NC}"
        echo -e "${RED}Critical security issues found that require immediate attention:${NC}"
        
        for test_name in "${!TEST_RESULTS[@]}"; do
            local result_data="${TEST_RESULTS[$test_name]}"
            local result="${result_data%%|*}"
            local temp="${result_data#*|}"
            local severity="${temp%%|*}"
            local message="${temp#*|*|}"
            local fix_required="${message#*|}"
            message="${message%%|*}"
            
            if [[ "$result" == "FAIL" && "$severity" == "CRITICAL" ]]; then
                echo -e "  ${RED}• $test_name:${NC} $message"
            fi
        done
    fi
}

# Main execution function
main() {
    log_header "INFRASTRUCTURE HIVE SECURITY VALIDATION"
    echo -e "${WHITE}Comprehensive security assessment for: $ENVIRONMENT${NC}"
    echo ""
    
    # Initialize test results
    TEST_RESULTS=()
    
    # Run all security validations
    validate_tls_security
    validate_network_security  
    validate_token_security
    validate_audit_logging
    validate_access_control
    validate_system_security
    validate_environment_security
    validate_bootstrap_security
    validate_compliance
    
    # Generate reports
    generate_json_report
    generate_summary
    
    # Return appropriate exit code
    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Script usage
usage() {
    cat << EOF
Infrastructure Hive Security Validation Script

Usage: $0 [ENVIRONMENT]

Arguments:
  ENVIRONMENT    Environment to validate (develop|staging|production)
                 Default: develop

Examples:
  $0 develop     # Validate development environment
  $0 production  # Validate production environment

This script performs comprehensive security validation across:
- TLS and encryption configuration
- Network security settings
- Token and secret management
- Audit logging configuration
- Access control and policies
- System security hardening
- Environment-specific security
- Bootstrap process security
- Compliance and documentation

Generates both human-readable summary and detailed JSON report.
EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    develop|staging|production)
        ENVIRONMENT="$1"
        ;;
    "")
        # Use default environment
        ;;
    *)
        echo "Error: Invalid environment '$1'"
        usage
        exit 1
        ;;
esac

# Run main function
main "$@"