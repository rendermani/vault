#!/bin/bash

# SSL Certificate Setup Script for Cloudya Infrastructure
# This script ensures proper SSL certificate configuration for all domains

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Configuration
DOMAINS=(
    "vault.cloudya.net"
    "consul.cloudya.net"
    "traefik.cloudya.net"
    "nomad.cloudya.net"
    "metrics.cloudya.net"
    "grafana.cloudya.net"
    "logs.cloudya.net"
    "storage.cloudya.net"
    "api.cloudya.net"
    "app.cloudya.net"
    "cloudya.net"
)

STAGING_MODE=${STAGING_MODE:-false}
CERT_DIR="/opt/nomad/volumes/traefik-certs"
CONFIG_DIR="/opt/nomad/volumes/traefik-config"
LOG_DIR="/opt/nomad/volumes/traefik-logs"

# Functions
check_prerequisites() {
    log_info "Checking prerequisites for SSL certificate setup..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

setup_directories() {
    log_info "Setting up certificate directories..."
    
    # Create necessary directories
    mkdir -p "$CERT_DIR"/{certs,private}
    mkdir -p "$CONFIG_DIR/dynamic"
    mkdir -p "$LOG_DIR"
    
    # Set proper permissions
    chmod 700 "$CERT_DIR"
    chmod 755 "$CERT_DIR/certs"
    chmod 700 "$CERT_DIR/private"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    
    # Initialize ACME storage files
    for acme_file in acme.json acme-staging.json; do
        if [[ ! -f "$CERT_DIR/$acme_file" ]]; then
            echo '{}' > "$CERT_DIR/$acme_file"
            chmod 600 "$CERT_DIR/$acme_file"
            log_success "Created ACME storage: $acme_file"
        else
            chmod 600 "$CERT_DIR/$acme_file"
            log_info "ACME storage exists: $acme_file"
        fi
    done
    
    log_success "Certificate directories setup completed"
}

create_certificate_validation_config() {
    log_info "Creating certificate validation configuration..."
    
    cat > "$CONFIG_DIR/certificate-validation.yml" << 'EOF'
# Certificate validation configuration
# This file contains settings for certificate validation and monitoring

http:
  middlewares:
    certificate-check:
      headers:
        customRequestHeaders:
          X-SSL-Check: "enabled"
        customResponseHeaders:
          X-Certificate-Status: "valid"
    
    ssl-redirect:
      redirectScheme:
        scheme: https
        permanent: true
        port: "443"
    
    hsts-headers:
      headers:
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        customResponseHeaders:
          X-Frame-Options: "DENY"
          X-Content-Type-Options: "nosniff"
          X-XSS-Protection: "1; mode=block"
          Referrer-Policy: "strict-origin-when-cross-origin"
          Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';"

tls:
  options:
    modern:
      minVersion: "VersionTLS12"
      maxVersion: "VersionTLS13"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
        - "TLS_AES_128_GCM_SHA256"
        - "TLS_AES_256_GCM_SHA384"
        - "TLS_CHACHA20_POLY1305_SHA256"
      sniStrict: true
      alpnProtocols:
        - "h2"
        - "http/1.1"
    
    intermediate:
      minVersion: "VersionTLS12"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
        - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
        - "TLS_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_RSA_WITH_AES_256_GCM_SHA384"
EOF
    
    log_success "Certificate validation configuration created"
}

create_certificate_monitoring_script() {
    log_info "Creating certificate monitoring script..."
    
    cat > "$SCRIPT_DIR/monitor-certificates.sh" << 'EOF'
#!/bin/bash

# Certificate monitoring script
# Checks certificate expiration and validity

set -euo pipefail

# Configuration
CERT_DIR="/opt/nomad/volumes/traefik-certs"
LOG_FILE="/opt/nomad/volumes/traefik-logs/certificate-monitor.log"
WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
ALERT_DAYS=30

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

check_certificate_expiry() {
    local domain=$1
    local cert_file="$CERT_DIR/certs/$domain.crt"
    
    if [[ ! -f "$cert_file" ]]; then
        log "WARNING: Certificate file not found for $domain"
        return 1
    fi
    
    # Get certificate expiry date
    local expiry_date
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_expiry -lt 0 ]]; then
        log "CRITICAL: Certificate for $domain has EXPIRED!"
        send_alert "CRITICAL" "$domain certificate has EXPIRED!"
        return 2
    elif [[ $days_until_expiry -lt $ALERT_DAYS ]]; then
        log "WARNING: Certificate for $domain expires in $days_until_expiry days"
        send_alert "WARNING" "$domain certificate expires in $days_until_expiry days"
        return 1
    else
        log "INFO: Certificate for $domain is valid for $days_until_expiry days"
        return 0
    fi
}

send_alert() {
    local level=$1
    local message=$2
    
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"[$level] SSL Certificate Alert: $message\"}" \
            "$WEBHOOK_URL" 2>/dev/null || true
    fi
}

# Main execution
DOMAINS=(
    "vault.cloudya.net"
    "consul.cloudya.net" 
    "traefik.cloudya.net"
    "nomad.cloudya.net"
    "metrics.cloudya.net"
    "grafana.cloudya.net"
    "logs.cloudya.net"
    "storage.cloudya.net"
    "api.cloudya.net"
    "app.cloudya.net"
    "cloudya.net"
)

log "Starting certificate monitoring check"

exit_code=0
for domain in "${DOMAINS[@]}"; do
    if ! check_certificate_expiry "$domain"; then
        exit_code=1
    fi
done

log "Certificate monitoring check completed with exit code: $exit_code"
exit $exit_code
EOF
    
    chmod +x "$SCRIPT_DIR/monitor-certificates.sh"
    log_success "Certificate monitoring script created"
}

create_renewal_script() {
    log_info "Creating certificate renewal script..."
    
    cat > "$SCRIPT_DIR/renew-certificates.sh" << 'EOF'
#!/bin/bash

# Certificate renewal script
# Forces certificate renewal for domains nearing expiry

set -euo pipefail

# Configuration
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TRAEFIK_JOB="traefik-production"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

restart_traefik() {
    log "Restarting Traefik to renew certificates..."
    
    if command -v nomad &> /dev/null; then
        nomad job restart "$TRAEFIK_JOB/traefik" || {
            log "ERROR: Failed to restart Traefik via Nomad"
            return 1
        }
    else
        log "ERROR: Nomad CLI not available"
        return 1
    fi
    
    # Wait for Traefik to start
    sleep 30
    
    # Verify Traefik is healthy
    if curl -f http://localhost:8080/ping &> /dev/null; then
        log "SUCCESS: Traefik restarted successfully"
        return 0
    else
        log "ERROR: Traefik health check failed after restart"
        return 1
    fi
}

force_certificate_renewal() {
    log "Forcing certificate renewal by restarting Traefik..."
    
    # Remove ACME storage to force renewal (use with caution)
    if [[ "${FORCE_RENEWAL:-false}" == "true" ]]; then
        log "WARNING: Removing ACME storage to force complete renewal"
        rm -f /opt/nomad/volumes/traefik-certs/acme.json
        echo '{}' > /opt/nomad/volumes/traefik-certs/acme.json
        chmod 600 /opt/nomad/volumes/traefik-certs/acme.json
    fi
    
    restart_traefik
}

# Main execution
log "Starting certificate renewal process"
force_certificate_renewal
log "Certificate renewal process completed"
EOF
    
    chmod +x "$SCRIPT_DIR/renew-certificates.sh"
    log_success "Certificate renewal script created"
}

setup_crontab() {
    log_info "Setting up certificate monitoring crontab..."
    
    # Create crontab entry for certificate monitoring
    local cron_file="/etc/cron.d/ssl-certificates"
    
    cat > "$cron_file" << EOF
# SSL Certificate monitoring and renewal for Cloudya infrastructure
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Check certificates daily at 2 AM
0 2 * * * root $SCRIPT_DIR/monitor-certificates.sh >> $LOG_DIR/cron-monitor.log 2>&1

# Attempt renewal weekly on Sundays at 3 AM
0 3 * * 0 root $SCRIPT_DIR/renew-certificates.sh >> $LOG_DIR/cron-renewal.log 2>&1

# Cleanup old logs monthly
0 4 1 * * root find $LOG_DIR -name "*.log" -mtime +30 -delete
EOF
    
    chmod 644 "$cron_file"
    
    # Restart cron service
    if systemctl is-active cron &> /dev/null; then
        systemctl reload cron
    elif systemctl is-active crond &> /dev/null; then
        systemctl reload crond
    fi
    
    log_success "Crontab setup completed"
}

validate_configuration() {
    log_info "Validating SSL certificate configuration..."
    
    local validation_errors=0
    
    # Check if certificate directories exist
    for dir in "$CERT_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory missing: $dir"
            ((validation_errors++))
        fi
    done
    
    # Check ACME storage files
    for acme_file in "$CERT_DIR/acme.json" "$CERT_DIR/acme-staging.json"; do
        if [[ ! -f "$acme_file" ]]; then
            log_error "ACME storage file missing: $acme_file"
            ((validation_errors++))
        else
            # Check permissions
            local perms
            perms=$(stat -c "%a" "$acme_file")
            if [[ "$perms" != "600" ]]; then
                log_error "Incorrect permissions on $acme_file: $perms (should be 600)"
                ((validation_errors++))
            fi
        fi
    done
    
    # Check if monitoring script is executable
    if [[ ! -x "$SCRIPT_DIR/monitor-certificates.sh" ]]; then
        log_error "Certificate monitoring script is not executable"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "SSL certificate configuration validation passed"
        return 0
    else
        log_error "SSL certificate configuration validation failed with $validation_errors errors"
        return 1
    fi
}

test_certificate_generation() {
    log_info "Testing certificate generation (dry run)..."
    
    if [[ "$STAGING_MODE" == "true" ]]; then
        log_info "Running in staging mode - certificates will use Let's Encrypt staging CA"
    else
        log_warning "Running in production mode - real certificates will be generated"
    fi
    
    # This would typically involve restarting Traefik and checking logs
    # For now, we'll just verify the configuration is in place
    if [[ -f "$PROJECT_ROOT/nomad/jobs/traefik-production.nomad" ]]; then
        log_success "Traefik job configuration found"
    else
        log_error "Traefik job configuration not found"
        return 1
    fi
    
    log_success "Certificate generation test completed"
}

show_status() {
    log_info "SSL Certificate Setup Status:"
    echo
    echo "Configuration:"
    echo "  - Certificate Directory: $CERT_DIR"
    echo "  - Configuration Directory: $CONFIG_DIR"
    echo "  - Log Directory: $LOG_DIR"
    echo "  - Staging Mode: $STAGING_MODE"
    echo
    echo "Domains configured:"
    for domain in "${DOMAINS[@]}"; do
        echo "  - $domain"
    done
    echo
    echo "Monitoring:"
    echo "  - Certificate monitoring: $SCRIPT_DIR/monitor-certificates.sh"
    echo "  - Certificate renewal: $SCRIPT_DIR/renew-certificates.sh"
    echo "  - Crontab: /etc/cron.d/ssl-certificates"
}

# Main execution
main() {
    log_info "Starting SSL certificate setup for Cloudya infrastructure"
    
    check_prerequisites
    setup_directories
    create_certificate_validation_config
    create_certificate_monitoring_script
    create_renewal_script
    setup_crontab
    validate_configuration
    test_certificate_generation
    show_status
    
    log_success "SSL certificate setup completed successfully!"
    log_info "Next steps:"
    echo "1. Deploy the updated Traefik configuration with: nomad job run traefik-production.nomad"
    echo "2. Monitor certificate generation in Traefik logs"
    echo "3. Verify certificates are issued: $SCRIPT_DIR/monitor-certificates.sh"
    echo "4. Check SSL configuration at: https://www.ssllabs.com/ssltest/"
}

# Handle command line arguments
case "${1:-setup}" in
    "setup")
        main
        ;;
    "monitor")
        "$SCRIPT_DIR/monitor-certificates.sh"
        ;;
    "renew")
        "$SCRIPT_DIR/renew-certificates.sh"
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 {setup|monitor|renew|status}"
        echo "  setup   - Run complete SSL certificate setup"
        echo "  monitor - Check certificate expiration status"
        echo "  renew   - Force certificate renewal"
        echo "  status  - Show current configuration status"
        exit 1
        ;;
esac