#!/bin/bash
# SSL Certificate Validation and Monitoring Script
# Comprehensive SSL certificate testing and automated renewal monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/ssl-certificate-validator.log}"

# Configuration
DOMAINS=(
    "traefik.cloudya.net"
    "vault.cloudya.net"
    "consul.cloudya.net"
    "nomad.cloudya.net"
    "grafana.cloudya.net"
    "prometheus.cloudya.net"
)

# Certificate validation thresholds (days)
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=7
RENEWAL_THRESHOLD=60

# Notification settings
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_ALERTS="${EMAIL_ALERTS:-admin@cloudya.net}"
ALERT_LEVEL="${ALERT_LEVEL:-critical}"  # critical, warning, info

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC}  $timestamp - $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $timestamp - $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $timestamp - $message" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}[OK]${NC}    $timestamp - $message" | tee -a "$LOG_FILE" ;;
        DEBUG) 
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $timestamp - $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
}

# Check if required tools are installed
check_prerequisites() {
    local tools=("openssl" "curl" "dig" "nc")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Missing required tools: ${missing[*]}"
        log INFO "Install with: apt-get install ${missing[*]} (Ubuntu/Debian)"
        exit 1
    fi
}

# Test DNS resolution
test_dns_resolution() {
    local domain="$1"
    local dns_servers=("8.8.8.8" "1.1.1.1" "9.9.9.9")
    local resolved=false
    
    for dns in "${dns_servers[@]}"; do
        if dig +short @"$dns" "$domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >/dev/null; then
            local ip=$(dig +short @"$dns" "$domain" A | head -1)
            log SUCCESS "DNS resolution for $domain: $ip (via $dns)"
            resolved=true
            break
        fi
    done
    
    if [[ "$resolved" == "false" ]]; then
        log ERROR "DNS resolution failed for $domain"
        return 1
    fi
    
    return 0
}

# Test connectivity to domain and port
test_connectivity() {
    local domain="$1"
    local port="${2:-443}"
    local timeout="${3:-10}"
    
    if nc -z -w "$timeout" "$domain" "$port" 2>/dev/null; then
        log SUCCESS "Connectivity to $domain:$port successful"
        return 0
    else
        log ERROR "Cannot connect to $domain:$port"
        return 1
    fi
}

# Get certificate information
get_certificate_info() {
    local domain="$1"
    local port="${2:-443}"
    local timeout="${3:-10}"
    
    # Get certificate using OpenSSL
    local cert_info
    cert_info=$(timeout "$timeout" openssl s_client -connect "$domain:$port" \
                -servername "$domain" -showcerts </dev/null 2>/dev/null | \
                openssl x509 -noout -dates -subject -issuer -text 2>/dev/null)
    
    if [[ -z "$cert_info" ]]; then
        log ERROR "Failed to retrieve certificate for $domain"
        return 1
    fi
    
    echo "$cert_info"
    return 0
}

# Parse certificate dates and calculate days until expiry
parse_certificate_dates() {
    local cert_info="$1"
    local domain="$2"
    
    # Extract dates
    local not_before=$(echo "$cert_info" | grep "notBefore=" | cut -d= -f2-)
    local not_after=$(echo "$cert_info" | grep "notAfter=" | cut -d= -f2-)
    
    if [[ -z "$not_before" ]] || [[ -z "$not_after" ]]; then
        log ERROR "Could not parse certificate dates for $domain"
        return 1
    fi
    
    # Convert to epoch timestamps
    local before_epoch after_epoch current_epoch
    before_epoch=$(date -d "$not_before" +%s 2>/dev/null) || {
        log ERROR "Invalid certificate start date for $domain: $not_before"
        return 1
    }
    
    after_epoch=$(date -d "$not_after" +%s 2>/dev/null) || {
        log ERROR "Invalid certificate end date for $domain: $not_after"
        return 1
    }
    
    current_epoch=$(date +%s)
    
    # Calculate days
    local days_until_expiry=$(( (after_epoch - current_epoch) / 86400 ))
    local days_since_issued=$(( (current_epoch - before_epoch) / 86400 ))
    
    # Certificate validity info
    local cert_age=$days_since_issued
    local cert_remaining=$days_until_expiry
    
    echo "VALID_FROM:$not_before"
    echo "VALID_UNTIL:$not_after"
    echo "DAYS_UNTIL_EXPIRY:$cert_remaining"
    echo "CERT_AGE:$cert_age"
    
    return 0
}

# Extract certificate subject and issuer information
extract_certificate_details() {
    local cert_info="$1"
    
    local subject issuer san
    subject=$(echo "$cert_info" | grep "subject=" | cut -d= -f2-)
    issuer=$(echo "$cert_info" | grep "issuer=" | cut -d= -f2-)
    san=$(echo "$cert_info" | grep -A 1 "Subject Alternative Name:" | tail -1 | sed 's/^[[:space:]]*//')
    
    echo "SUBJECT:$subject"
    echo "ISSUER:$issuer"
    echo "SAN:$san"
}

# Check certificate chain validation
validate_certificate_chain() {
    local domain="$1"
    local port="${2:-443}"
    
    # Get full certificate chain
    local cert_chain
    cert_chain=$(timeout 10 openssl s_client -connect "$domain:$port" \
                 -servername "$domain" -showcerts </dev/null 2>/dev/null)
    
    if [[ -z "$cert_chain" ]]; then
        log ERROR "Failed to retrieve certificate chain for $domain"
        return 1
    fi
    
    # Extract and validate each certificate in the chain
    local cert_count
    cert_count=$(echo "$cert_chain" | grep -c "BEGIN CERTIFICATE" || echo "0")
    
    if [[ $cert_count -eq 0 ]]; then
        log ERROR "No certificates found in chain for $domain"
        return 1
    fi
    
    # Test chain validation
    if echo "$cert_chain" | openssl verify -CApath /etc/ssl/certs/ >/dev/null 2>&1; then
        log SUCCESS "Certificate chain validation passed for $domain ($cert_count certificates)"
        return 0
    else
        log WARN "Certificate chain validation failed for $domain"
        return 1
    fi
}

# Test SSL/TLS configuration security
test_ssl_security() {
    local domain="$1"
    local port="${2:-443}"
    
    log INFO "Testing SSL/TLS security for $domain:$port"
    
    # Test supported protocols
    local protocols=("ssl2" "ssl3" "tls1" "tls1_1" "tls1_2" "tls1_3")
    local supported_protocols=()
    local insecure_protocols=()
    
    for protocol in "${protocols[@]}"; do
        if timeout 5 openssl s_client -connect "$domain:$port" \
           -servername "$domain" -"$protocol" </dev/null >/dev/null 2>&1; then
            supported_protocols+=("$protocol")
            
            # Check for insecure protocols
            case "$protocol" in
                ssl2|ssl3|tls1|tls1_1)
                    insecure_protocols+=("$protocol")
                    ;;
            esac
        fi
    done
    
    if [[ ${#insecure_protocols[@]} -gt 0 ]]; then
        log WARN "Insecure protocols supported: ${insecure_protocols[*]}"
    fi
    
    if [[ ${#supported_protocols[@]} -gt 0 ]]; then
        log INFO "Supported protocols: ${supported_protocols[*]}"
    fi
    
    # Test cipher suites (basic check)
    local cipher_info
    cipher_info=$(timeout 10 openssl s_client -connect "$domain:$port" \
                  -servername "$domain" -cipher 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA' \
                  </dev/null 2>/dev/null | grep "Cipher")
    
    if [[ -n "$cipher_info" ]]; then
        log INFO "Cipher: $cipher_info"
    fi
    
    return 0
}

# Check OCSP stapling
check_ocsp_stapling() {
    local domain="$1"
    local port="${2:-443}"
    
    local ocsp_response
    ocsp_response=$(timeout 10 openssl s_client -connect "$domain:$port" \
                    -servername "$domain" -status </dev/null 2>/dev/null | \
                    grep "OCSP response:" | head -1)
    
    if [[ -n "$ocsp_response" ]] && [[ "$ocsp_response" != *"no response sent"* ]]; then
        log SUCCESS "OCSP stapling enabled for $domain"
    else
        log WARN "OCSP stapling not enabled for $domain"
    fi
}

# Generate security recommendations
generate_security_recommendations() {
    local domain="$1"
    local cert_info="$2"
    local days_until_expiry="$3"
    
    local recommendations=()
    
    # Check certificate age and renewal
    if [[ $days_until_expiry -le $CRITICAL_THRESHOLD ]]; then
        recommendations+=("CRITICAL: Certificate expires in $days_until_expiry days - IMMEDIATE RENEWAL REQUIRED")
    elif [[ $days_until_expiry -le $WARNING_THRESHOLD ]]; then
        recommendations+=("WARNING: Certificate expires in $days_until_expiry days - Plan renewal soon")
    elif [[ $days_until_expiry -le $RENEWAL_THRESHOLD ]]; then
        recommendations+=("INFO: Certificate expires in $days_until_expiry days - Consider renewal planning")
    fi
    
    # Check issuer
    local issuer=$(echo "$cert_info" | grep "issuer=" | cut -d= -f2-)
    if [[ "$issuer" == *"Let's Encrypt"* ]]; then
        recommendations+=("INFO: Using Let's Encrypt (free, automated renewal recommended)")
    elif [[ "$issuer" == *"self signed"* ]] || [[ "$issuer" == *"localhost"* ]]; then
        recommendations+=("WARNING: Self-signed certificate detected - not suitable for production")
    fi
    
    # Check key size and algorithm
    local key_info=$(echo "$cert_info" | grep -E "Public-Key:|RSA Public-Key:|EC Public-Key:")
    if [[ "$key_info" == *"1024 bit"* ]]; then
        recommendations+=("WARNING: 1024-bit key detected - upgrade to 2048-bit or higher")
    elif [[ "$key_info" == *"2048 bit"* ]]; then
        recommendations+=("INFO: 2048-bit RSA key (acceptable)")
    elif [[ "$key_info" == *"256 bit"* ]] && [[ "$key_info" == *"EC"* ]]; then
        recommendations+=("GOOD: 256-bit EC key (recommended)")
    fi
    
    # Output recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        log INFO "Security recommendations for $domain:"
        for rec in "${recommendations[@]}"; do
            case "$rec" in
                CRITICAL:*) log ERROR "  $rec" ;;
                WARNING:*)  log WARN "  $rec" ;;
                GOOD:*)     log SUCCESS "  $rec" ;;
                *)          log INFO "  $rec" ;;
            esac
        done
    fi
}

# Send alert notifications
send_alert() {
    local level="$1"
    local domain="$2"
    local message="$3"
    
    # Only send alerts for configured levels
    case "$ALERT_LEVEL" in
        critical)
            [[ "$level" != "CRITICAL" ]] && return
            ;;
        warning)
            [[ "$level" != "CRITICAL" && "$level" != "WARNING" ]] && return
            ;;
        info)
            # Send all alerts
            ;;
    esac
    
    local alert_message="[$level] SSL Certificate Alert for $domain: $message"
    
    # Slack notification
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"$alert_message\"}" \
             "$SLACK_WEBHOOK" >/dev/null 2>&1 || log WARN "Failed to send Slack notification"
    fi
    
    # Email notification
    if [[ -n "$EMAIL_ALERTS" ]] && command -v mail >/dev/null 2>&1; then
        echo "$alert_message" | mail -s "SSL Certificate Alert: $domain" "$EMAIL_ALERTS" || \
            log WARN "Failed to send email notification"
    fi
    
    log INFO "Alert sent: $alert_message"
}

# Comprehensive certificate validation for a single domain
validate_single_certificate() {
    local domain="$1"
    local port="${2:-443}"
    
    log INFO "=== Validating certificate for $domain:$port ==="
    
    # Step 1: DNS resolution
    if ! test_dns_resolution "$domain"; then
        send_alert "CRITICAL" "$domain" "DNS resolution failed"
        return 1
    fi
    
    # Step 2: Connectivity test
    if ! test_connectivity "$domain" "$port"; then
        send_alert "CRITICAL" "$domain" "Connection failed on port $port"
        return 1
    fi
    
    # Step 3: Get certificate information
    local cert_info
    if ! cert_info=$(get_certificate_info "$domain" "$port"); then
        send_alert "CRITICAL" "$domain" "Failed to retrieve certificate"
        return 1
    fi
    
    # Step 4: Parse certificate details
    local cert_details cert_dates
    cert_details=$(extract_certificate_details "$cert_info")
    cert_dates=$(parse_certificate_dates "$cert_info" "$domain")
    
    if [[ $? -ne 0 ]]; then
        send_alert "CRITICAL" "$domain" "Failed to parse certificate information"
        return 1
    fi
    
    # Extract key information
    local days_until_expiry valid_until valid_from subject issuer
    days_until_expiry=$(echo "$cert_dates" | grep "DAYS_UNTIL_EXPIRY:" | cut -d: -f2)
    valid_until=$(echo "$cert_dates" | grep "VALID_UNTIL:" | cut -d: -f2-)
    valid_from=$(echo "$cert_dates" | grep "VALID_FROM:" | cut -d: -f2-)
    subject=$(echo "$cert_details" | grep "SUBJECT:" | cut -d: -f2-)
    issuer=$(echo "$cert_details" | grep "ISSUER:" | cut -d: -f2-)
    
    # Display certificate information
    log INFO "Certificate Details:"
    log INFO "  Subject: $subject"
    log INFO "  Issuer: $issuer"
    log INFO "  Valid From: $valid_from"
    log INFO "  Valid Until: $valid_until"
    log INFO "  Days Until Expiry: $days_until_expiry"
    
    # Step 5: Certificate chain validation
    validate_certificate_chain "$domain" "$port"
    
    # Step 6: SSL/TLS security testing
    test_ssl_security "$domain" "$port"
    
    # Step 7: OCSP stapling check
    check_ocsp_stapling "$domain" "$port"
    
    # Step 8: Generate recommendations and alerts
    generate_security_recommendations "$domain" "$cert_info" "$days_until_expiry"
    
    # Send alerts based on expiry
    if [[ $days_until_expiry -le $CRITICAL_THRESHOLD ]]; then
        send_alert "CRITICAL" "$domain" "Certificate expires in $days_until_expiry days"
    elif [[ $days_until_expiry -le $WARNING_THRESHOLD ]]; then
        send_alert "WARNING" "$domain" "Certificate expires in $days_until_expiry days"
    fi
    
    log INFO "=== Validation completed for $domain ==="
    return 0
}

# Generate comprehensive report
generate_report() {
    local report_file="${1:-$PROJECT_ROOT/reports/ssl-certificate-report-$(date +%Y%m%d_%H%M%S).md}"
    local report_dir
    report_dir=$(dirname "$report_file")
    
    mkdir -p "$report_dir"
    
    cat > "$report_file" <<EOF
# SSL Certificate Validation Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Report Type:** Comprehensive SSL Certificate Analysis  
**Domains Tested:** ${#DOMAINS[@]}

## Executive Summary

This report contains the SSL certificate validation results for all CloudYa infrastructure domains.

| Domain | Status | Days Until Expiry | Issuer | Recommendations |
|--------|--------|-------------------|---------|----------------|
EOF
    
    # Add domain results to report
    for domain in "${DOMAINS[@]}"; do
        log INFO "Generating report data for $domain..."
        
        local status="❌ Failed"
        local days="Unknown"
        local issuer="Unknown"
        local recommendations="Connection failed"
        
        if test_connectivity "$domain" 443 5 >/dev/null 2>&1; then
            local cert_info
            if cert_info=$(get_certificate_info "$domain" 443 10 2>/dev/null); then
                local cert_dates cert_details
                cert_dates=$(parse_certificate_dates "$cert_info" "$domain" 2>/dev/null)
                cert_details=$(extract_certificate_details "$cert_info" 2>/dev/null)
                
                if [[ -n "$cert_dates" ]] && [[ -n "$cert_details" ]]; then
                    days=$(echo "$cert_dates" | grep "DAYS_UNTIL_EXPIRY:" | cut -d: -f2)
                    issuer=$(echo "$cert_details" | grep "ISSUER:" | cut -d: -f2- | sed 's/.*CN=//;s/,.*//;s/\/.*//;')
                    
                    if [[ $days -le $CRITICAL_THRESHOLD ]]; then
                        status="🔴 Critical"
                        recommendations="IMMEDIATE RENEWAL REQUIRED"
                    elif [[ $days -le $WARNING_THRESHOLD ]]; then
                        status="🟡 Warning"
                        recommendations="Plan renewal soon"
                    else
                        status="✅ Valid"
                        recommendations="Monitor regularly"
                    fi
                fi
            fi
        fi
        
        echo "| $domain | $status | $days | $issuer | $recommendations |" >> "$report_file"
    done
    
    cat >> "$report_file" <<EOF

## Detailed Analysis

$(tail -200 "$LOG_FILE" | grep "$(date '+%Y-%m-%d')")

## Recommendations

1. **Critical Actions:** Address all certificates expiring within $CRITICAL_THRESHOLD days
2. **Warning Actions:** Plan renewal for certificates expiring within $WARNING_THRESHOLD days  
3. **Monitoring:** Set up automated monitoring with $RENEWAL_THRESHOLD-day advance notice
4. **Security:** Ensure all certificates use strong encryption (RSA 2048+ or EC 256+)
5. **Automation:** Implement automated certificate renewal where possible

## Next Steps

1. Review all failed validations
2. Address critical and warning status certificates
3. Set up automated renewal processes
4. Schedule next validation run

---
**Generated by:** SSL Certificate Validator  
**Log File:** $LOG_FILE  
**Script:** $0
EOF
    
    log SUCCESS "Report generated: $report_file"
}

# Create monitoring cron job
create_monitoring_cron() {
    local cron_file="/etc/cron.d/ssl-certificate-monitoring"
    
    cat > /tmp/ssl-certificate-monitoring <<EOF
# SSL Certificate Monitoring for CloudYa
# Run certificate validation twice daily and weekly reports

PATH=/usr/local/bin:/usr/bin:/bin
SHELL=/bin/bash

# Daily certificate check (06:00 and 18:00)
0 6,18 * * * root $SCRIPT_DIR/ssl-certificate-validator.sh validate-all >> /var/log/ssl-certificate-validator.log 2>&1

# Weekly comprehensive report (Sunday 08:00)
0 8 * * 0 root $SCRIPT_DIR/ssl-certificate-validator.sh report >> /var/log/ssl-certificate-validator.log 2>&1

# Monthly security audit (1st day of month, 09:00)
0 9 1 * * root $SCRIPT_DIR/ssl-certificate-validator.sh security-audit >> /var/log/ssl-certificate-validator.log 2>&1
EOF
    
    log INFO "Cron job configuration created at /tmp/ssl-certificate-monitoring"
    log INFO "To install: sudo mv /tmp/ssl-certificate-monitoring $cron_file"
    log INFO "Then restart cron: sudo systemctl restart cron"
}

# Main execution function
main() {
    log INFO "Starting SSL Certificate Validator"
    
    # Ensure log file exists
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    check_prerequisites
    
    local failed_domains=()
    local success_count=0
    
    for domain in "${DOMAINS[@]}"; do
        if validate_single_certificate "$domain"; then
            ((success_count++))
        else
            failed_domains+=("$domain")
        fi
        
        # Add separator between domains
        echo "" | tee -a "$LOG_FILE"
    done
    
    # Summary
    log INFO "=== VALIDATION SUMMARY ==="
    log INFO "Total domains: ${#DOMAINS[@]}"
    log SUCCESS "Successful validations: $success_count"
    
    if [[ ${#failed_domains[@]} -gt 0 ]]; then
        log ERROR "Failed validations: ${#failed_domains[@]} (${failed_domains[*]})"
    fi
    
    log INFO "Validation completed at $(date)"
}

# Handle command line arguments
case "${1:-validate-all}" in
    validate-all)
        main
        ;;
    validate)
        if [[ -z "${2:-}" ]]; then
            log ERROR "Usage: $0 validate <domain>"
            exit 1
        fi
        validate_single_certificate "$2" "${3:-443}"
        ;;
    report)
        generate_report "${2:-}"
        ;;
    security-audit)
        log INFO "Performing comprehensive security audit..."
        main
        generate_report
        ;;
    test-connectivity)
        if [[ -z "${2:-}" ]]; then
            log ERROR "Usage: $0 test-connectivity <domain> [port]"
            exit 1
        fi
        test_connectivity "$2" "${3:-443}"
        ;;
    setup-monitoring)
        create_monitoring_cron
        ;;
    *)
        echo "Usage: $0 {validate-all|validate <domain>|report|security-audit|test-connectivity <domain>|setup-monitoring}"
        echo ""
        echo "Commands:"
        echo "  validate-all             - Validate all configured domains"
        echo "  validate <domain>        - Validate specific domain"
        echo "  report                   - Generate comprehensive report"
        echo "  security-audit           - Full security audit with report"
        echo "  test-connectivity <domain> - Test connectivity to domain"
        echo "  setup-monitoring         - Create monitoring cron jobs"
        echo ""
        echo "Environment Variables:"
        echo "  DEBUG=true              - Enable debug logging"
        echo "  ALERT_LEVEL=critical    - Set alert level (critical|warning|info)"
        echo "  SLACK_WEBHOOK=<url>     - Slack webhook for notifications"
        echo "  EMAIL_ALERTS=<email>    - Email address for alerts"
        exit 1
        ;;
esac