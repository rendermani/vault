#!/bin/bash

# SSL Configuration Validation Script
# Validates SSL certificate configuration and tests domain accessibility

set -euo pipefail

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
    "vault.cloudya.net:8200"
    "consul.cloudya.net:8500"
    "traefik.cloudya.net:8080"
    "nomad.cloudya.net:4646"
    "metrics.cloudya.net:9090"
    "grafana.cloudya.net:3000"
    "logs.cloudya.net:3100"
    "storage.cloudya.net:9000"
    "api.cloudya.net:80"
    "app.cloudya.net:80"
    "cloudya.net:80"
)

TIMEOUT=10
DETAILED_OUTPUT=${DETAILED_OUTPUT:-false}

# Functions
check_domain_ssl() {
    local domain_port=$1
    local domain=${domain_port%%:*}
    local port=${domain_port##*:}
    
    log_info "Checking SSL configuration for $domain..."
    
    # Check if domain resolves
    if ! nslookup "$domain" &> /dev/null; then
        log_error "Domain $domain does not resolve"
        return 1
    fi
    
    # Check SSL certificate
    local ssl_info
    if ssl_info=$(echo | timeout "$TIMEOUT" openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -text 2>/dev/null); then
        
        # Extract certificate information
        local issuer
        issuer=$(echo "$ssl_info" | grep "Issuer:" | head -1 | sed 's/.*Issuer: //')
        
        local subject
        subject=$(echo "$ssl_info" | grep "Subject:" | head -1 | sed 's/.*Subject: //')
        
        local not_after
        not_after=$(echo "$ssl_info" | grep "Not After" | sed 's/.*Not After : //')
        
        # Check if it's a Let's Encrypt certificate
        if echo "$issuer" | grep -qi "let's encrypt"; then
            log_success "$domain has valid Let's Encrypt SSL certificate"
            
            if [[ "$DETAILED_OUTPUT" == "true" ]]; then
                echo "  Issuer: $issuer"
                echo "  Subject: $subject" 
                echo "  Expires: $not_after"
            fi
            
            # Check certificate expiry
            local expiry_epoch
            expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
            local current_epoch
            current_epoch=$(date +%s)
            local days_until_expiry
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 ]]; then
                log_warning "$domain certificate expires in $days_until_expiry days"
            fi
            
        else
            log_warning "$domain has SSL certificate but NOT from Let's Encrypt"
            if [[ "$DETAILED_OUTPUT" == "true" ]]; then
                echo "  Issuer: $issuer"
            fi
        fi
        
        return 0
    else
        log_error "$domain does not have valid SSL certificate or is not accessible"
        return 1
    fi
}

check_https_redirect() {
    local domain=$1
    
    log_info "Checking HTTP to HTTPS redirect for $domain..."
    
    local response_code
    if response_code=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time "$TIMEOUT" "http://$domain" 2>/dev/null); then
        if [[ "$response_code" == "200" ]]; then
            # Check if final URL is HTTPS
            local final_url
            final_url=$(curl -s -L -w "%{url_effective}" -o /dev/null --max-time "$TIMEOUT" "http://$domain" 2>/dev/null)
            if [[ "$final_url" =~ ^https:// ]]; then
                log_success "$domain properly redirects HTTP to HTTPS"
                return 0
            else
                log_warning "$domain does not redirect to HTTPS (final URL: $final_url)"
                return 1
            fi
        elif [[ "$response_code" =~ ^30[0-9]$ ]]; then
            log_success "$domain returns redirect status ($response_code)"
            return 0
        else
            log_warning "$domain returns status $response_code"
            return 1
        fi
    else
        log_error "$domain is not accessible via HTTP"
        return 1
    fi
}

check_ssl_grade() {
    local domain=$1
    
    log_info "Checking SSL configuration quality for $domain..."
    
    # Use SSL Labs API (rate limited - use sparingly)
    if command -v curl &> /dev/null && [[ "${CHECK_SSL_GRADE:-false}" == "true" ]]; then
        log_info "Initiating SSL Labs test for $domain (this may take a few minutes)..."
        
        # Start assessment
        local assess_url="https://api.ssllabs.com/api/v3/analyze?host=$domain&publish=off&startNew=on"
        curl -s "$assess_url" > /dev/null
        
        # Wait for completion (simplified check)
        sleep 60
        
        # Get results
        local results_url="https://api.ssllabs.com/api/v3/analyze?host=$domain"
        local grade
        if grade=$(curl -s "$results_url" | grep -o '"grade":"[A-F][+-]*"' | head -1 | cut -d'"' -f4 2>/dev/null); then
            if [[ -n "$grade" ]]; then
                case "$grade" in
                    "A+"|"A")
                        log_success "$domain SSL grade: $grade"
                        ;;
                    "B"|"C")
                        log_warning "$domain SSL grade: $grade (consider improvements)"
                        ;;
                    *)
                        log_error "$domain SSL grade: $grade (needs improvement)"
                        ;;
                esac
            else
                log_info "$domain SSL grade check in progress or unavailable"
            fi
        else
            log_info "Could not retrieve SSL grade for $domain"
        fi
    else
        log_info "SSL grade check disabled (set CHECK_SSL_GRADE=true to enable)"
    fi
}

check_traefik_health() {
    log_info "Checking Traefik health and configuration..."
    
    # Check Traefik API
    if curl -f -s "http://localhost:8080/ping" &> /dev/null; then
        log_success "Traefik API is accessible"
    else
        log_error "Traefik API is not accessible"
        return 1
    fi
    
    # Check Traefik dashboard (if configured)
    if curl -f -s -k "https://traefik.cloudya.net" &> /dev/null; then
        log_success "Traefik dashboard is accessible via HTTPS"
    else
        log_warning "Traefik dashboard is not accessible via HTTPS"
    fi
    
    # Check certificate resolver status
    if curl -s "http://localhost:8080/api/http/routers" | grep -q "letsencrypt"; then
        log_success "Let's Encrypt certificate resolver is configured"
    else
        log_warning "Let's Encrypt certificate resolver may not be properly configured"
    fi
}

check_acme_storage() {
    log_info "Checking ACME certificate storage..."
    
    local acme_file="/opt/nomad/volumes/traefik-certs/acme.json"
    
    if [[ -f "$acme_file" ]]; then
        local file_size
        file_size=$(stat -f%z "$acme_file" 2>/dev/null || stat -c%s "$acme_file" 2>/dev/null || echo "0")
        
        if [[ "$file_size" -gt 10 ]]; then
            log_success "ACME storage file exists and contains data ($file_size bytes)"
            
            # Check if file contains certificates
            if grep -q "certificates" "$acme_file" 2>/dev/null; then
                local cert_count
                cert_count=$(grep -o '"certificates":\[' "$acme_file" | wc -l 2>/dev/null || echo "0")
                log_info "ACME storage contains certificate data"
            else
                log_info "ACME storage is empty (certificates will be generated on first request)"
            fi
        else
            log_info "ACME storage file exists but is empty"
        fi
        
        # Check permissions
        local perms
        perms=$(stat -f%Mp%Lp "$acme_file" 2>/dev/null || stat -c"%a" "$acme_file" 2>/dev/null || echo "unknown")
        if [[ "$perms" == "600" ]]; then
            log_success "ACME storage has correct permissions (600)"
        else
            log_warning "ACME storage permissions: $perms (should be 600)"
        fi
    else
        log_error "ACME storage file not found: $acme_file"
        return 1
    fi
}

generate_report() {
    local total_domains=${#DOMAINS[@]}
    local ssl_success=0
    local redirect_success=0
    
    echo
    log_info "Generating SSL validation report..."
    echo
    
    # Header
    printf "%-25s %-15s %-15s %-20s\n" "Domain" "SSL Status" "HTTPS Redirect" "Notes"
    printf "%-25s %-15s %-15s %-20s\n" "------" "----------" "--------------" "-----"
    
    for domain_port in "${DOMAINS[@]}"; do
        local domain=${domain_port%%:*}
        local ssl_status="✗ Failed"
        local redirect_status="✗ Failed"
        local notes=""
        
        # Check SSL
        if check_domain_ssl "$domain_port" &> /dev/null; then
            ssl_status="✓ Valid"
            ((ssl_success++))
        fi
        
        # Check redirect
        if check_https_redirect "$domain" &> /dev/null; then
            redirect_status="✓ Working"
            ((redirect_success++))
        fi
        
        printf "%-25s %-15s %-15s %-20s\n" "$domain" "$ssl_status" "$redirect_status" "$notes"
    done
    
    echo
    echo "Summary:"
    echo "  SSL Certificates: $ssl_success/$total_domains working"
    echo "  HTTPS Redirects:  $redirect_success/$total_domains working"
    echo
    
    if [[ $ssl_success -eq $total_domains ]] && [[ $redirect_success -eq $total_domains ]]; then
        log_success "All SSL configurations are working correctly!"
        return 0
    else
        log_warning "Some SSL configurations need attention"
        return 1
    fi
}

show_recommendations() {
    echo
    log_info "SSL Configuration Recommendations:"
    echo
    echo "1. Security Headers:"
    echo "   - Ensure HSTS is enabled with long max-age"
    echo "   - Implement Content Security Policy"
    echo "   - Use secure cookies for applications"
    echo
    echo "2. Certificate Management:"
    echo "   - Monitor certificate expiration (automated)"
    echo "   - Test certificate renewal process"
    echo "   - Keep ACME storage backed up"
    echo
    echo "3. Performance:"
    echo "   - Enable HTTP/2"
    echo "   - Use OCSP stapling"
    echo "   - Optimize cipher suites"
    echo
    echo "4. Monitoring:"
    echo "   - Set up alerts for certificate expiration"
    echo "   - Monitor SSL Labs grade periodically"
    echo "   - Track SSL handshake performance"
}

# Main execution
main() {
    echo "================================================"
    echo "Cloudya Infrastructure SSL Validation"
    echo "================================================"
    echo
    
    check_traefik_health
    echo
    
    check_acme_storage
    echo
    
    log_info "Checking SSL configuration for all domains..."
    echo
    
    for domain_port in "${DOMAINS[@]}"; do
        domain=${domain_port%%:*}
        
        check_domain_ssl "$domain_port"
        check_https_redirect "$domain"
        
        # Optional SSL grade check
        if [[ "${CHECK_SSL_GRADE:-false}" == "true" ]]; then
            check_ssl_grade "$domain"
        fi
        
        echo
    done
    
    generate_report
    
    if [[ "${SHOW_RECOMMENDATIONS:-true}" == "true" ]]; then
        show_recommendations
    fi
    
    echo "================================================"
    echo "SSL Validation Complete"
    echo "================================================"
}

# Handle command line arguments
case "${1:-validate}" in
    "validate")
        main
        ;;
    "report")
        generate_report
        ;;
    "traefik")
        check_traefik_health
        ;;
    "acme")
        check_acme_storage
        ;;
    *)
        echo "Usage: $0 {validate|report|traefik|acme}"
        echo "  validate - Run complete SSL validation"
        echo "  report   - Generate SSL status report only"
        echo "  traefik  - Check Traefik health only"
        echo "  acme     - Check ACME storage only"
        echo
        echo "Environment variables:"
        echo "  DETAILED_OUTPUT=true     - Show detailed certificate info"
        echo "  CHECK_SSL_GRADE=true     - Check SSL Labs grade (rate limited)"
        echo "  SHOW_RECOMMENDATIONS=false - Skip recommendations"
        exit 1
        ;;
esac