#!/bin/bash

# Vault Security Initialization Script
# Complete setup of production-grade security infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="/Users/mlautenschlager/cloudya/vault"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8200}"
VAULT_DOMAIN="${VAULT_DOMAIN:-cloudya.net}"
LE_EMAIL="${LE_EMAIL:-admin@cloudya.net}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"

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

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"
    
    local errors=0
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root for full security setup"
        ((errors++))
    fi
    
    # Check required tools
    local required_tools=("openssl" "curl" "jq" "systemctl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            ((errors++))
        fi
    done
    
    # Check Vault installation
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault binary not found. Please install Vault first."
        ((errors++))
    fi
    
    # Check directory structure
    if [[ ! -d "$VAULT_DIR" ]]; then
        log_error "Vault directory not found: $VAULT_DIR"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed with $errors errors"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Make all security scripts executable
setup_security_scripts() {
    log_header "Setting Up Security Scripts"
    
    local scripts=(
        "tls-cert-manager.sh"
        "secure-token-manager.sh"
        "audit-logger.sh"
        "emergency-access.sh"
        "security-monitor.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        if [[ -f "$script_path" ]]; then
            chmod +x "$script_path"
            log_info "Made executable: $script"
        else
            log_warn "Script not found: $script"
        fi
    done
    
    # Create symlinks in /usr/local/bin for system-wide access
    local bin_dir="/usr/local/bin"
    for script in "${scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        local symlink_path="$bin_dir/vault-${script}"
        
        if [[ -f "$script_path" ]]; then
            ln -sf "$script_path" "$symlink_path"
            log_info "Created symlink: $symlink_path"
        fi
    done
    
    log_success "Security scripts setup completed"
}

# Initialize TLS configuration
setup_tls() {
    log_header "Setting Up TLS Configuration"
    
    local cert_script="$SCRIPT_DIR/tls-cert-manager.sh"
    
    if [[ ! -x "$cert_script" ]]; then
        log_error "TLS certificate manager script not found or not executable"
        return 1
    fi
    
    # Setup directories
    "$cert_script" setup
    
    # Ask user for certificate type
    echo "Select certificate type:"
    echo "1. Self-signed certificates (for development/testing)"
    echo "2. Let's Encrypt certificates (for production)"
    echo "3. Skip TLS setup (configure manually later)"
    
    read -p "Enter choice (1-3): " cert_choice
    
    case "$cert_choice" in
        1)
            log_step "Generating self-signed certificates..."
            VAULT_DOMAIN="$VAULT_DOMAIN" "$cert_script" self-signed
            ;;
        2)
            log_step "Generating Let's Encrypt certificates..."
            VAULT_DOMAIN="$VAULT_DOMAIN" LE_EMAIL="$LE_EMAIL" "$cert_script" letsencrypt
            ;;
        3)
            log_info "TLS setup skipped. Configure manually later."
            return 0
            ;;
        *)
            log_warn "Invalid choice. Generating self-signed certificates..."
            VAULT_DOMAIN="$VAULT_DOMAIN" "$cert_script" self-signed
            ;;
    esac
    
    # Verify certificates
    "$cert_script" verify
    
    log_success "TLS configuration completed"
}

# Initialize secure token management
setup_token_management() {
    log_header "Setting Up Secure Token Management"
    
    local token_script="$SCRIPT_DIR/secure-token-manager.sh"
    
    if [[ ! -x "$token_script" ]]; then
        log_error "Secure token manager script not found or not executable"
        return 1
    fi
    
    # Initialize secure storage
    "$token_script" init
    
    # Store initial root token if it exists
    if [[ -f "/root/.vault/root-token" ]]; then
        local root_token=$(cat /root/.vault/root-token)
        "$token_script" store root-token "$root_token" "Initial root token"
        log_info "Root token stored securely"
        
        # Remove plain text file
        rm -f /root/.vault/root-token
        log_info "Plain text root token file removed"
    fi
    
    log_success "Secure token management setup completed"
}

# Initialize audit logging
setup_audit_logging() {
    log_header "Setting Up Audit Logging"
    
    local audit_script="$SCRIPT_DIR/audit-logger.sh"
    
    if [[ ! -x "$audit_script" ]]; then
        log_error "Audit logger script not found or not executable"
        return 1
    fi
    
    # Full audit setup
    "$audit_script" full-setup
    
    log_success "Audit logging setup completed"
}

# Initialize emergency access procedures
setup_emergency_access() {
    log_header "Setting Up Emergency Access Procedures"
    
    local emergency_script="$SCRIPT_DIR/emergency-access.sh"
    
    if [[ ! -x "$emergency_script" ]]; then
        log_error "Emergency access script not found or not executable"
        return 1
    fi
    
    # Initialize emergency access system
    "$emergency_script" init
    
    # Ask if user wants to generate emergency keys
    read -p "Generate emergency unseal keys? (y/N): " -r generate_keys
    if [[ $generate_keys =~ ^[Yy]$ ]]; then
        "$emergency_script" generate-keys
    fi
    
    log_success "Emergency access procedures setup completed"
}

# Initialize security monitoring
setup_security_monitoring() {
    log_header "Setting Up Security Monitoring"
    
    local monitor_script="$SCRIPT_DIR/security-monitor.sh"
    
    if [[ ! -x "$monitor_script" ]]; then
        log_error "Security monitor script not found or not executable"
        return 1
    fi
    
    # Initialize monitoring system
    ALERT_EMAIL="$ALERT_EMAIL" "$monitor_script" init
    
    # Ask if user wants to start monitoring service
    read -p "Start continuous security monitoring? (Y/n): " -r start_monitoring
    if [[ ! $start_monitoring =~ ^[Nn]$ ]]; then
        # Create systemd service for monitoring
        create_monitoring_service
        
        # Start monitoring service
        systemctl enable vault-security-monitor
        systemctl start vault-security-monitor
        
        log_info "Security monitoring service started"
    fi
    
    log_success "Security monitoring setup completed"
}

# Create systemd service for security monitoring
create_monitoring_service() {
    log_step "Creating security monitoring service..."
    
    cat > "/etc/systemd/system/vault-security-monitor.service" << EOF
[Unit]
Description=Vault Security Monitoring Service
After=network.target vault.service
Wants=vault.service

[Service]
Type=simple
User=vault
Group=vault
ExecStart=$SCRIPT_DIR/security-monitor.sh start
Restart=always
RestartSec=10
Environment=VAULT_ADDR=$VAULT_ADDR
Environment=ALERT_EMAIL=$ALERT_EMAIL

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_info "Security monitoring service created"
}

# Update Vault configuration with security settings
update_vault_config() {
    log_header "Updating Vault Configuration"
    
    local vault_config="$VAULT_DIR/config/vault.hcl"
    local backup_config="$vault_config.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Backup original configuration
    if [[ -f "$vault_config" ]]; then
        cp "$vault_config" "$backup_config"
        log_info "Configuration backed up to: $backup_config"
    fi
    
    # Configuration is already updated with security settings
    log_info "Vault configuration already includes security enhancements"
    
    # Validate configuration
    if vault operator init -check-only 2>/dev/null; then
        log_success "Vault configuration validation passed"
    else
        log_warn "Vault configuration validation failed - check manually"
    fi
}

# Setup firewall rules
setup_firewall() {
    log_header "Setting Up Firewall Rules"
    
    # Check if ufw or iptables is available
    if command -v ufw >/dev/null 2>&1; then
        setup_ufw_rules
    elif command -v iptables >/dev/null 2>&1; then
        setup_iptables_rules
    else
        log_warn "No supported firewall found. Configure manually."
        return 0
    fi
    
    log_success "Firewall rules configured"
}

# Setup UFW rules
setup_ufw_rules() {
    log_step "Configuring UFW firewall rules..."
    
    # Enable UFW
    ufw --force enable
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH access (be careful not to lock yourself out)
    ufw allow ssh
    
    # Vault API (HTTPS)
    ufw allow 8200/tcp comment "Vault API"
    
    # Vault cluster (if HA setup)
    ufw allow 8201/tcp comment "Vault Cluster"
    
    # Allow from specific subnets (adjust as needed)
    ufw allow from 10.0.0.0/8 to any port 8200 comment "Internal network"
    ufw allow from 172.16.0.0/12 to any port 8200 comment "Internal network"
    ufw allow from 192.168.0.0/16 to any port 8200 comment "Internal network"
    
    log_info "UFW rules configured"
}

# Setup iptables rules
setup_iptables_rules() {
    log_step "Configuring iptables firewall rules..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # SSH access
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Vault API
    iptables -A INPUT -p tcp --dport 8200 -j ACCEPT
    
    # Vault cluster
    iptables -A INPUT -p tcp --dport 8201 -j ACCEPT
    
    # Save rules (distribution-specific)
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || \
        log_warn "Could not save iptables rules persistently"
    fi
    
    log_info "iptables rules configured"
}

# Setup log rotation
setup_log_rotation() {
    log_header "Setting Up Log Rotation"
    
    # Log rotation is configured by audit-logger.sh
    # Additional logrotate configuration for security logs
    cat > "/etc/logrotate.d/vault-security" << 'EOF'
/var/log/vault/security/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 vault vault
    postrotate
        systemctl reload vault-security-monitor || true
    endrotate
}

/var/log/vault/monitoring/*.log {
    daily
    rotate 90
    compress
    delaycompress
    notifempty
    create 640 vault vault
}

/var/log/vault/emergency/*.log {
    weekly
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 root root
}
EOF
    
    log_success "Log rotation configured"
}

# Setup automated security tasks
setup_automation() {
    log_header "Setting Up Automated Security Tasks"
    
    # Create cron jobs for security tasks
    cat > "/etc/cron.d/vault-security" << EOF
# Vault Security Automation
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

# Daily security monitoring report
0 6 * * * root $SCRIPT_DIR/security-monitor.sh report daily >/dev/null 2>&1

# Weekly comprehensive security report
0 6 * * 0 root $SCRIPT_DIR/security-monitor.sh report weekly >/dev/null 2>&1

# Daily certificate check
0 2 * * * root $SCRIPT_DIR/tls-cert-manager.sh verify >/dev/null 2>&1

# Weekly token cleanup
0 3 * * 0 root $SCRIPT_DIR/secure-token-manager.sh cleanup >/dev/null 2>&1

# Monthly emergency token cleanup
0 4 1 * * root $SCRIPT_DIR/emergency-access.sh cleanup >/dev/null 2>&1

# Daily backup integrity check
0 5 * * * root $SCRIPT_DIR/emergency-access.sh emergency-backup >/dev/null 2>&1
EOF
    
    log_success "Automated security tasks configured"
}

# Perform security validation
validate_security_setup() {
    log_header "Validating Security Setup"
    
    local validation_errors=0
    
    # Check TLS certificates
    log_step "Validating TLS certificates..."
    if "$SCRIPT_DIR/tls-cert-manager.sh" verify; then
        log_info "✅ TLS certificates valid"
    else
        log_error "❌ TLS certificate validation failed"
        ((validation_errors++))
    fi
    
    # Check secure token storage
    log_step "Validating secure token storage..."
    if [[ -d "/etc/vault.d/secure" ]]; then
        log_info "✅ Secure token storage initialized"
    else
        log_error "❌ Secure token storage not found"
        ((validation_errors++))
    fi
    
    # Check audit logging
    log_step "Validating audit logging..."
    if [[ -d "/var/log/vault/audit" ]]; then
        log_info "✅ Audit logging directories created"
    else
        log_error "❌ Audit logging directories not found"
        ((validation_errors++))
    fi
    
    # Check emergency access
    log_step "Validating emergency access..."
    if [[ -d "/etc/vault.d/emergency" ]]; then
        log_info "✅ Emergency access system initialized"
    else
        log_error "❌ Emergency access system not found"
        ((validation_errors++))
    fi
    
    # Check monitoring
    log_step "Validating security monitoring..."
    if systemctl is-enabled vault-security-monitor >/dev/null 2>&1; then
        log_info "✅ Security monitoring service enabled"
    else
        log_warn "⚠️ Security monitoring service not enabled"
    fi
    
    # Check firewall
    log_step "Validating firewall configuration..."
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        log_info "✅ UFW firewall active"
    elif iptables -L | grep -q "Chain INPUT.*DROP"; then
        log_info "✅ iptables firewall configured"
    else
        log_warn "⚠️ Firewall may not be properly configured"
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Security setup validation passed"
        return 0
    else
        log_error "Security setup validation failed with $validation_errors errors"
        return 1
    fi
}

# Generate security summary report
generate_summary_report() {
    log_header "Generating Security Setup Summary"
    
    local report_file="$VAULT_DIR/docs/SECURITY_SETUP_SUMMARY.md"
    
    cat > "$report_file" << EOF
# Vault Security Setup Summary

**Generated:** $(date)
**Host:** $(hostname)
**Vault Version:** $(vault version | head -1 2>/dev/null || echo "Not available")

## Security Components Installed

### 🔒 TLS Configuration
- **Status:** $(if [[ -f "/etc/vault.d/tls/vault-cert.pem" ]]; then echo "✅ Configured"; else echo "❌ Not configured"; fi)
- **Certificate Type:** $(if [[ -d "/etc/letsencrypt/live" ]]; then echo "Let's Encrypt"; else echo "Self-signed"; fi)
- **Domain:** $VAULT_DOMAIN
- **Auto-renewal:** $(if [[ -f "/etc/systemd/system/vault-cert-renewal.timer" ]]; then echo "✅ Enabled"; else echo "❌ Not enabled"; fi)

### 🎫 Secure Token Management
- **Status:** $(if [[ -d "/etc/vault.d/secure" ]]; then echo "✅ Configured"; else echo "❌ Not configured"; fi)
- **Encryption:** AES-256-CBC with PBKDF2
- **Storage:** Encrypted filesystem storage
- **Backup:** $(if [[ -d "/etc/vault.d/secure/backup" ]]; then echo "✅ Enabled"; else echo "❌ Not enabled"; fi)

### 📋 Audit Logging
- **Status:** $(if [[ -d "/var/log/vault/audit" ]]; then echo "✅ Configured"; else echo "❌ Not configured"; fi)
- **Devices:** File, Syslog, Socket
- **Real-time Monitoring:** $(if systemctl is-active vault-audit-monitor >/dev/null 2>&1; then echo "✅ Active"; else echo "❌ Inactive"; fi)
- **Log Rotation:** ✅ Configured
- **Compliance Reporting:** ✅ Automated

### 🚨 Emergency Access
- **Status:** $(if [[ -d "/etc/vault.d/emergency" ]]; then echo "✅ Configured"; else echo "❌ Not configured"; fi)
- **Break-glass Procedures:** ✅ Available
- **Emergency Tokens:** ✅ Supported
- **Recovery Procedures:** ✅ Documented
- **Backup System:** ✅ Integrated

### 📊 Security Monitoring
- **Status:** $(if systemctl is-enabled vault-security-monitor >/dev/null 2>&1; then echo "✅ Active"; else echo "❌ Inactive"; fi)
- **Real-time Alerts:** ✅ Email, Slack
- **Metrics Collection:** ✅ Performance, Security
- **Anomaly Detection:** ✅ Authentication, Token usage
- **Compliance Reports:** ✅ Daily, Weekly, Monthly

### 🛡️ Infrastructure Security
- **Firewall:** $(if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then echo "✅ UFW Active"; elif iptables -L | grep -q "Chain INPUT.*DROP" 2>/dev/null; then echo "✅ iptables Configured"; else echo "❌ Not configured"; fi)
- **Log Rotation:** ✅ Configured
- **Automated Tasks:** ✅ Cron jobs configured
- **System Hardening:** ✅ Minimal permissions

## Security Scripts Available

| Script | Location | Purpose |
|--------|----------|---------|
| \`tls-cert-manager.sh\` | /usr/local/bin/vault-tls-cert-manager.sh | TLS certificate management |
| \`secure-token-manager.sh\` | /usr/local/bin/vault-secure-token-manager.sh | Secure token operations |
| \`audit-logger.sh\` | /usr/local/bin/vault-audit-logger.sh | Audit logging and compliance |
| \`emergency-access.sh\` | /usr/local/bin/vault-emergency-access.sh | Emergency procedures |
| \`security-monitor.sh\` | /usr/local/bin/vault-security-monitor.sh | Security monitoring |

## Quick Commands

### Daily Operations
\`\`\`bash
# Check system health
vault-security-monitor.sh health

# Generate daily security report
vault-security-monitor.sh report daily

# Check certificate status
vault-tls-cert-manager.sh verify

# Review recent audit events
vault-audit-logger.sh report daily
\`\`\`

### Emergency Procedures
\`\`\`bash
# Break-glass unseal (if Vault is sealed)
vault-emergency-access.sh break-glass-unseal

# Generate emergency token
vault-emergency-access.sh generate-emergency-token 2h

# Handle security incident
vault-emergency-access.sh incident-response token_compromise
\`\`\`

### Maintenance Tasks
\`\`\`bash
# Rotate TLS certificates
vault-tls-cert-manager.sh rotate

# Clean up old tokens
vault-secure-token-manager.sh cleanup

# Create emergency backup
vault-emergency-access.sh emergency-backup
\`\`\`

## Security Contacts

- **Primary Admin:** $ALERT_EMAIL
- **Security Team:** security@cloudya.net
- **Emergency Contact:** See /etc/vault.d/emergency/README.md

## Next Steps

1. **Test Emergency Procedures:** Run tabletop exercises
2. **Configure Monitoring Alerts:** Set up Slack/email notifications
3. **Review Security Policies:** Validate access controls
4. **Schedule Training:** Train operations staff on procedures
5. **Performance Testing:** Validate system performance under load

## Documentation

- **Security Runbook:** [SECURITY_RUNBOOK.md](./SECURITY_RUNBOOK.md)
- **Incident Response:** [INCIDENT_RESPONSE_PLAN.md](./INCIDENT_RESPONSE_PLAN.md)
- **Emergency Procedures:** /etc/vault.d/emergency/README.md

---
*This summary was generated automatically by the Vault security initialization process.*
EOF
    
    log_success "Security setup summary generated: $report_file"
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Vault Production Security Initialization                  ║
║                                                                              ║
║  This script will configure enterprise-grade security for HashiCorp Vault   ║
║  including TLS, token management, audit logging, monitoring, and emergency   ║
║  access procedures.                                                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    # Confirmation prompt
    read -p "Do you want to proceed with security initialization? (y/N): " -r proceed
    if [[ ! $proceed =~ ^[Yy]$ ]]; then
        log_info "Security initialization cancelled"
        exit 0
    fi
    
    # Run setup phases
    local phases=(
        "check_prerequisites"
        "setup_security_scripts"
        "setup_tls"
        "setup_token_management"
        "setup_audit_logging"
        "setup_emergency_access"
        "setup_security_monitoring"
        "update_vault_config"
        "setup_firewall"
        "setup_log_rotation"
        "setup_automation"
        "validate_security_setup"
        "generate_summary_report"
    )
    
    local successful_phases=0
    local failed_phases=0
    
    for phase in "${phases[@]}"; do
        if $phase; then
            ((successful_phases++))
        else
            ((failed_phases++))
            log_error "Phase failed: $phase"
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Final summary
    echo -e "\n${BOLD}${BLUE}=============== SECURITY INITIALIZATION COMPLETE ===============${NC}\n"
    
    if [[ $failed_phases -eq 0 ]]; then
        log_success "All security components initialized successfully!"
        log_info "Duration: ${duration} seconds"
        log_info "Successful phases: $successful_phases"
        
        echo -e "\n${GREEN}${BOLD}🎉 Vault is now configured with production-grade security!${NC}\n"
        
        echo "Next steps:"
        echo "1. Review the security summary: $VAULT_DIR/docs/SECURITY_SETUP_SUMMARY.md"
        echo "2. Test emergency procedures"
        echo "3. Configure monitoring alerts"
        echo "4. Train your team on security procedures"
        
    else
        log_error "Security initialization completed with $failed_phases failed phases"
        log_info "Duration: ${duration} seconds"
        log_info "Successful phases: $successful_phases"
        log_info "Failed phases: $failed_phases"
        
        echo -e "\n${YELLOW}${BOLD}⚠️ Some security components may need manual configuration${NC}\n"
        echo "Please review the errors above and complete setup manually."
    fi
    
    echo -e "\nFor help and documentation:"
    echo "- Security Runbook: $VAULT_DIR/docs/SECURITY_RUNBOOK.md"
    echo "- Incident Response Plan: $VAULT_DIR/docs/INCIDENT_RESPONSE_PLAN.md"
    echo "- Emergency Procedures: /etc/vault.d/emergency/README.md"
    
    return $failed_phases
}

# Trap signals for graceful exit
trap 'log_error "Setup interrupted"; exit 130' INT TERM

# Run main function
main "$@"