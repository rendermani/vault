#!/bin/bash

# Security Hardening Script
# Automates firewall configuration, system updates, and security scanning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[SECURITY]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${YELLOW}[STEP]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Configure firewall
configure_firewall() {
    log_step "Configuring firewall rules..."
    
    # Install ufw if not present
    if ! command -v ufw >/dev/null 2>&1; then
        log_info "Installing UFW firewall..."
        apt-get update -qq
        apt-get install -y ufw
    fi
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH access (adjust port if needed)
    SSH_PORT="${SSH_PORT:-22}"
    ufw allow "$SSH_PORT"/tcp comment 'SSH'
    
    # HTTP/HTTPS for Traefik
    ufw allow 80/tcp comment 'HTTP (Traefik)'
    ufw allow 443/tcp comment 'HTTPS (Traefik)'
    
    # HashiCorp services (localhost only by default)
    case "$ENVIRONMENT" in
        production)
            # Production: restrict to localhost and specific IPs
            ufw allow from 127.0.0.1 to any port 8200 comment 'Vault (localhost)'
            ufw allow from 127.0.0.1 to any port 4646 comment 'Nomad (localhost)'
            ufw allow from 127.0.0.1 to any port 8500 comment 'Consul (localhost)'
            ufw allow from 127.0.0.1 to any port 8080 comment 'Traefik Dashboard (localhost)'
            ;;
        staging|develop)
            # Development: allow broader access for testing
            ufw allow 8200/tcp comment 'Vault'
            ufw allow 4646/tcp comment 'Nomad'
            ufw allow 8500/tcp comment 'Consul'
            ufw allow 8080/tcp comment 'Traefik Dashboard'
            ;;
    esac
    
    # Monitoring services (if enabled)
    if [ "${ENABLE_MONITORING:-false}" == "true" ]; then
        ufw allow from 127.0.0.1 to any port 9090 comment 'Prometheus'
        ufw allow from 127.0.0.1 to any port 3000 comment 'Grafana'
    fi
    
    # Enable UFW
    ufw --force enable
    
    log_success "Firewall configured successfully"
    ufw status numbered
}

# Configure fail2ban
setup_fail2ban() {
    log_step "Setting up Fail2ban..."
    
    # Install fail2ban if not present
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "Installing Fail2ban..."
        apt-get update -qq
        apt-get install -y fail2ban
    fi
    
    # Create custom configuration
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = ${FAIL2BAN_BANTIME:-3600}
findtime = ${FAIL2BAN_FINDTIME:-600}
maxretry = ${FAIL2BAN_MAXRETRY:-3}
backend = auto
banaction = ufw
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${SSH_PORT:-22}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[traefik-auth]
enabled = true
port = 80,443
filter = traefik-auth
logpath = /var/log/traefik/access.log
maxretry = 5
bantime = 3600

[vault-auth]
enabled = true
port = 8200
filter = vault-auth
logpath = /var/log/vault/vault.log
maxretry = 3
bantime = 7200
EOF

    # Create custom Traefik filter
    cat > /etc/fail2ban/filter.d/traefik-auth.conf <<EOF
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .* HTTP/.*" (401|403) .*$
ignoreregex =
EOF

    # Create custom Vault filter
    cat > /etc/fail2ban/filter.d/vault-auth.conf <<EOF
[Definition]
failregex = ^.*"remote_address":"<HOST>".*"type":"request".*"error":".*permission denied.*$
            ^.*"remote_address":"<HOST>".*"type":"request".*"error":".*invalid request.*$
ignoreregex =
EOF

    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2ban configured and started"
    fail2ban-client status
}

# Configure SSH security
harden_ssh() {
    log_step "Hardening SSH configuration..."
    
    # Backup original configuration
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
    
    # Apply security settings
    cat > /etc/ssh/sshd_config.security <<EOF
# Security hardening settings
Protocol 2
Port ${SSH_PORT:-22}
PermitRootLogin ${SSH_PERMIT_ROOT_LOGIN:-yes}
PubkeyAuthentication yes
PasswordAuthentication ${SSH_PASSWORD_AUTH:-no}
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries ${SSH_MAX_AUTH_TRIES:-3}
LoginGraceTime ${SSH_LOGIN_GRACE_TIME:-60}
MaxStartups 10:30:100
MaxSessions 10
EOF

    # Merge with existing configuration
    grep -v -E '^(Protocol|Port|PermitRootLogin|PubkeyAuthentication|PasswordAuthentication|ChallengeResponseAuthentication|UsePAM|X11Forwarding|PrintMotd|ClientAlive|MaxAuth|LoginGrace|MaxStart|MaxSessions)' /etc/ssh/sshd_config > /tmp/sshd_config.base
    cat /tmp/sshd_config.base /etc/ssh/sshd_config.security > /etc/ssh/sshd_config.new
    
    # Validate configuration
    if sshd -t -f /etc/ssh/sshd_config.new; then
        mv /etc/ssh/sshd_config.new /etc/ssh/sshd_config
        systemctl reload sshd
        log_success "SSH configuration hardened"
    else
        log_error "SSH configuration validation failed"
        return 1
    fi
    
    # Clean up
    rm -f /etc/ssh/sshd_config.security /tmp/sshd_config.base
}

# System security updates
configure_automatic_updates() {
    log_step "Configuring automatic security updates..."
    
    # Install unattended-upgrades if not present
    if ! dpkg -l | grep -q unattended-upgrades; then
        log_info "Installing unattended-upgrades..."
        apt-get update -qq
        apt-get install -y unattended-upgrades apt-listchanges
    fi
    
    # Configure unattended upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:30";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";

Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";

// Do not upgrade these packages
Unattended-Upgrade::Package-Blacklist {
    "vault";
    "nomad";
    "consul";
};
EOF

    # Configure automatic upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Enable the service
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    log_success "Automatic security updates configured"
}

# Install and configure security tools
install_security_tools() {
    log_step "Installing security monitoring tools..."
    
    # Install security tools
    apt-get update -qq
    apt-get install -y \
        rkhunter \
        chkrootkit \
        lynis \
        aide \
        logwatch \
        auditd \
        clamav \
        clamav-daemon
    
    # Configure rkhunter
    rkhunter --update
    rkhunter --propupd
    
    # Configure aide (file integrity monitoring)
    aideinit
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    
    # Configure auditd
    cat > /etc/audit/rules.d/audit.rules <<EOF
# File system auditing
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes

# HashiCorp service configurations
-w /opt/vault/config -p wa -k vault_config
-w /opt/nomad/config -p wa -k nomad_config
-w /opt/consul/config -p wa -k consul_config

# System calls
-a always,exit -F arch=b64 -S execve -k exec_commands
-a always,exit -F arch=b32 -S execve -k exec_commands

# Network connections
-a always,exit -F arch=b64 -S connect -k network_connect
-a always,exit -F arch=b32 -S connect -k network_connect
EOF

    # Start services
    systemctl enable auditd
    systemctl start auditd
    
    # Update ClamAV database
    systemctl stop clamav-freshclam
    freshclam
    systemctl start clamav-freshclam
    systemctl enable clamav-daemon
    
    log_success "Security tools installed and configured"
}

# Create security monitoring script
create_security_monitoring() {
    log_step "Creating security monitoring script..."
    
    cat > /etc/security-monitor.sh <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/security-monitor.log"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"

log() {
    echo "[$(date)] SECURITY MONITOR: $1" | tee -a "$LOG_FILE"
}

# Check for suspicious processes
check_processes() {
    log "Checking for suspicious processes..."
    
    # Check for processes listening on unexpected ports
    SUSPICIOUS_PORTS=$(ss -tuln | grep -v -E ':(22|80|443|8200|4646|8500|8080|9090|3000|53|123)' | grep LISTEN || true)
    
    if [ ! -z "$SUSPICIOUS_PORTS" ]; then
        log "WARNING: Processes listening on unexpected ports:"
        echo "$SUSPICIOUS_PORTS" | tee -a "$LOG_FILE"
    fi
    
    # Check for high CPU/memory usage
    HIGH_CPU=$(ps aux | awk '$3 > 80 {print $0}' | head -10)
    if [ ! -z "$HIGH_CPU" ]; then
        log "WARNING: Processes with high CPU usage:"
        echo "$HIGH_CPU" | tee -a "$LOG_FILE"
    fi
}

# Check file integrity
check_file_integrity() {
    log "Running file integrity check..."
    
    if command -v aide >/dev/null 2>&1; then
        if aide --check > /tmp/aide-report.txt 2>&1; then
            log "File integrity check passed"
        else
            log "WARNING: File integrity violations detected"
            cat /tmp/aide-report.txt | tee -a "$LOG_FILE"
        fi
    fi
}

# Check for rootkits
check_rootkits() {
    log "Checking for rootkits..."
    
    if command -v rkhunter >/dev/null 2>&1; then
        if rkhunter --check --sk > /tmp/rkhunter-report.txt 2>&1; then
            log "Rootkit check passed"
        else
            log "WARNING: Potential rootkits detected"
            cat /tmp/rkhunter-report.txt | tee -a "$LOG_FILE"
        fi
    fi
    
    if command -v chkrootkit >/dev/null 2>&1; then
        CHKROOTKIT_OUTPUT=$(chkrootkit 2>/dev/null | grep INFECTED || true)
        if [ ! -z "$CHKROOTKIT_OUTPUT" ]; then
            log "WARNING: chkrootkit found infections:"
            echo "$CHKROOTKIT_OUTPUT" | tee -a "$LOG_FILE"
        fi
    fi
}

# Check system vulnerabilities
check_vulnerabilities() {
    log "Running vulnerability scan..."
    
    if command -v lynis >/dev/null 2>&1; then
        lynis audit system --quiet > /tmp/lynis-report.txt 2>&1 || true
        WARNINGS=$(grep -c "Warning" /tmp/lynis-report.txt || echo "0")
        SUGGESTIONS=$(grep -c "Suggestion" /tmp/lynis-report.txt || echo "0")
        
        log "Lynis scan completed: $WARNINGS warnings, $SUGGESTIONS suggestions"
        
        if [ "$WARNINGS" -gt 10 ]; then
            log "WARNING: High number of security warnings detected"
        fi
    fi
}

# Check HashiCorp services security
check_hashicorp_security() {
    log "Checking HashiCorp services security..."
    
    # Check Vault seal status
    if command -v vault >/dev/null 2>&1; then
        if vault status >/dev/null 2>&1; then
            if vault status | grep -q "Sealed.*false"; then
                log "Vault is unsealed and accessible"
            else
                log "WARNING: Vault is sealed"
            fi
        else
            log "WARNING: Cannot connect to Vault"
        fi
    fi
    
    # Check Nomad ACL
    if command -v nomad >/dev/null 2>&1; then
        if nomad status >/dev/null 2>&1; then
            if nomad acl bootstrap 2>&1 | grep -q "already bootstrapped"; then
                log "Nomad ACL is properly bootstrapped"
            else
                log "WARNING: Nomad ACL may not be configured"
            fi
        else
            log "WARNING: Cannot connect to Nomad"
        fi
    fi
}

# Main monitoring check
main() {
    log "=== Security monitoring check started ==="
    
    check_processes
    check_file_integrity
    check_rootkits
    check_vulnerabilities
    check_hashicorp_security
    
    # Generate report summary
    WARNINGS=$(grep -c "WARNING" "$LOG_FILE" | tail -1 || echo "0")
    
    if [ "$WARNINGS" -gt 0 ]; then
        log "=== Security check completed with $WARNINGS warnings ==="
        
        # Send alert email if configured
        if command -v mail >/dev/null 2>&1 && [ ! -z "$ALERT_EMAIL" ]; then
            tail -100 "$LOG_FILE" | mail -s "CloudYa Security Alert - $WARNINGS Warnings" "$ALERT_EMAIL"
            log "Alert email sent to $ALERT_EMAIL"
        fi
    else
        log "=== Security check completed successfully ==="
    fi
    
    # Rotate log file if it gets too large
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        touch "$LOG_FILE"
    fi
}

main "$@"
EOF
    
    chmod +x /etc/security-monitor.sh
    
    # Add to cron (run twice daily)
    echo "0 6,18 * * * root /etc/security-monitor.sh" > /etc/cron.d/security-monitor
    
    log_success "Security monitoring script created"
}

# Configure system hardening
system_hardening() {
    log_step "Applying system hardening..."
    
    # Disable unnecessary services
    SERVICES_TO_DISABLE=(
        "cups"
        "avahi-daemon"
        "bluetooth"
        "whoopsie"
        "apport"
    )
    
    for service in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl disable "$service" || true
            systemctl stop "$service" || true
            log_info "Disabled service: $service"
        fi
    done
    
    # Set file permissions
    chmod 700 /root
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /boot/grub/grub.cfg 2>/dev/null || true
    
    # Configure kernel parameters
    cat > /etc/sysctl.d/99-security.conf <<EOF
# Network security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Memory protection
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.core_pattern = |/bin/false

# File system security
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
    
    # Apply kernel parameters
    sysctl -p /etc/sysctl.d/99-security.conf
    
    log_success "System hardening applied"
}

# Main execution
main() {
    log_info "Starting security hardening for environment: $ENVIRONMENT"
    
    check_root
    
    configure_firewall
    setup_fail2ban
    harden_ssh
    configure_automatic_updates
    install_security_tools
    create_security_monitoring
    system_hardening
    
    # Run initial security scan
    log_step "Running initial security scan..."
    /etc/security-monitor.sh
    
    log_success "Security hardening completed successfully!"
    log_info ""
    log_info "Security measures implemented:"
    log_info "  ✓ Firewall (UFW) configured"
    log_info "  ✓ Fail2ban protection enabled"
    log_info "  ✓ SSH hardened"
    log_info "  ✓ Automatic security updates enabled"
    log_info "  ✓ Security monitoring tools installed"
    log_info "  ✓ System hardening applied"
    log_info ""
    log_info "Security monitoring:"
    log_info "  - Runs twice daily (6 AM and 6 PM)"
    log_info "  - Logs to /var/log/security-monitor.log"
    log_info "  - Manual scan: /etc/security-monitor.sh"
    log_info ""
    log_info "Firewall status:"
    ufw status
}

# Handle command line arguments
case "${1:-harden}" in
    harden)
        main
        ;;
    firewall)
        check_root
        configure_firewall
        ;;
    ssh)
        check_root
        harden_ssh
        ;;
    monitor)
        /etc/security-monitor.sh
        ;;
    status)
        log_info "Security status:"
        ufw status
        systemctl status fail2ban --no-pager -l || true
        systemctl status unattended-upgrades --no-pager -l || true
        ;;
    *)
        echo "Usage: $0 {harden|firewall|ssh|monitor|status}"
        echo ""
        echo "Commands:"
        echo "  harden    - Apply full security hardening (default)"
        echo "  firewall  - Configure firewall only"
        echo "  ssh       - Harden SSH configuration only"
        echo "  monitor   - Run security monitoring check"
        echo "  status    - Show security services status"
        exit 1
        ;;
esac