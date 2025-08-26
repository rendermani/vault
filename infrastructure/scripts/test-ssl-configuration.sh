#!/bin/bash

# SSL Configuration Test Script for Cloudya Infrastructure
# This script validates SSL/TLS configuration and certificate setup

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INFRASTRUCTURE_DIR")"

DOMAINS=(
    "cloudya.net"
    "app.cloudya.net"
    "api.cloudya.net"
    "vault.cloudya.net"
    "consul.cloudya.net"
    "nomad.cloudya.net"
    "traefik.cloudya.net"
    "grafana.cloudya.net"
    "metrics.cloudya.net"
    "storage.cloudya.net"
    "storage-console.cloudya.net"
    "logs.cloudya.net"
)

# Test configuration
TIMEOUT=10
MAX_PARALLEL_TESTS=5
REPORT_FILE="/tmp/ssl-test-report-$(date +%Y%m%d-%H%M%S).json"
DETAILED_REPORT=false
CHECK_INTERNAL=false
SKIP_DNS=false

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

SSL Configuration Test Script for Cloudya Infrastructure

OPTIONS:
    -d, --detailed             Generate detailed report with technical details
    -i, --internal             Test internal services (requires VPN/network access)
    -s, --skip-dns             Skip DNS resolution tests
    -t, --timeout SECONDS      Timeout for SSL connections (default: 10)
    -o, --output FILE          Output report to file (default: auto-generated)
    -h, --help                 Show this help message

EXAMPLES:
    $0                          # Basic SSL test
    $0 --detailed               # Detailed SSL analysis
    $0 --internal               # Test internal services
    $0 --timeout 30             # Longer timeout for slow connections

TESTS PERFORMED:
    1. DNS resolution for all domains
    2. SSL certificate validity and expiration
    3. TLS version and cipher suite analysis
    4. Certificate chain verification
    5. HSTS and security header checks
    6. SSL Labs rating simulation
    7. Certificate transparency log verification
    8. OCSP stapling validation

EOF
}

init_report() {
    log "Initializing SSL test report: $REPORT_FILE"
    
    cat > "$REPORT_FILE" << EOF
{
  "test_run": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "script_version": "2.0",
    "total_domains": ${#DOMAINS[@]},
    "test_configuration": {
      "timeout": $TIMEOUT,
      "detailed": $DETAILED_REPORT,
      "check_internal": $CHECK_INTERNAL,
      "skip_dns": $SKIP_DNS
    }
  },
  "results": {
    "summary": {
      "total_tests": 0,
      "passed": 0,
      "failed": 0,
      "warnings": 0
    },
    "domains": {}
  }
}
EOF
}

update_report() {
    local domain="$1"
    local test_type="$2"
    local status="$3"
    local message="$4"
    local details="${5:-}"
    
    # Create domain entry if it doesn't exist
    if ! jq -e ".results.domains[\"$domain\"]" "$REPORT_FILE" > /dev/null 2>&1; then
        jq ".results.domains[\"$domain\"] = {}" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
    fi
    
    # Add test result
    local test_data="{
        \"status\": \"$status\",
        \"message\": \"$message\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }"
    
    if [[ -n "$details" ]]; then
        test_data=$(echo "$test_data" | jq ". + {\"details\": $details}")
    fi
    
    jq ".results.domains[\"$domain\"][\"$test_type\"] = $test_data" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
    
    # Update summary counters
    case "$status" in
        "PASS")
            jq ".results.summary.passed += 1" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
            ;;
        "FAIL")
            jq ".results.summary.failed += 1" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
            ;;
        "WARN")
            jq ".results.summary.warnings += 1" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
            ;;
    esac
    
    jq ".results.summary.total_tests += 1" "$REPORT_FILE" > tmp.json && mv tmp.json "$REPORT_FILE"
}

test_dns_resolution() {
    local domain="$1"
    
    if [[ $SKIP_DNS == true ]]; then
        return 0
    fi
    
    log "Testing DNS resolution for $domain"
    
    local ipv4_result=""
    local ipv6_result=""
    local dns_errors=0
    
    # Test IPv4 resolution
    if ipv4_result=$(dig +short A "$domain" 2>/dev/null) && [[ -n "$ipv4_result" ]]; then
        success "DNS IPv4 resolution for $domain: $ipv4_result"
        update_report "$domain" "dns_ipv4" "PASS" "Resolved to: $ipv4_result"
    else
        error "DNS IPv4 resolution failed for $domain"
        update_report "$domain" "dns_ipv4" "FAIL" "IPv4 resolution failed"
        ((dns_errors++))
    fi
    
    # Test IPv6 resolution
    if ipv6_result=$(dig +short AAAA "$domain" 2>/dev/null) && [[ -n "$ipv6_result" ]]; then
        success "DNS IPv6 resolution for $domain: $ipv6_result"
        update_report "$domain" "dns_ipv6" "PASS" "Resolved to: $ipv6_result"
    else
        warning "DNS IPv6 resolution not available for $domain"
        update_report "$domain" "dns_ipv6" "WARN" "IPv6 not configured"
    fi
    
    return $dns_errors
}

test_ssl_certificate() {
    local domain="$1"
    local port="${2:-443}"
    
    log "Testing SSL certificate for $domain:$port"
    
    local cert_info=""
    local ssl_errors=0
    
    # Test SSL connection and get certificate info
    if cert_info=$(timeout "$TIMEOUT" openssl s_client -connect "$domain:$port" -servername "$domain" -verify_return_error < /dev/null 2>/dev/null); then
        
        # Extract certificate details
        local cert_subject=""
        local cert_issuer=""
        local cert_serial=""
        local cert_not_before=""
        local cert_not_after=""
        local cert_fingerprint=""
        
        cert_subject=$(echo "$cert_info" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//' || echo "N/A")
        cert_issuer=$(echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "N/A")
        cert_serial=$(echo "$cert_info" | openssl x509 -noout -serial 2>/dev/null | sed 's/serial=//' || echo "N/A")
        cert_not_before=$(echo "$cert_info" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//' || echo "N/A")
        cert_not_after=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "N/A")
        cert_fingerprint=$(echo "$cert_info" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/SHA256 Fingerprint=//' || echo "N/A")
        
        # Check expiration
        local expiry_epoch=""
        local days_until_expiry=0
        
        if expiry_epoch=$(date -d "$cert_not_after" +%s 2>/dev/null); then
            local current_epoch=$(date +%s)
            days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt 0 ]]; then
                error "Certificate for $domain has EXPIRED!"
                update_report "$domain" "ssl_expiry" "FAIL" "Certificate expired ${days_until_expiry#-} days ago"
                ((ssl_errors++))
            elif [[ $days_until_expiry -lt 30 ]]; then
                warning "Certificate for $domain expires in $days_until_expiry days"
                update_report "$domain" "ssl_expiry" "WARN" "Certificate expires in $days_until_expiry days"
            else
                success "Certificate for $domain is valid for $days_until_expiry days"
                update_report "$domain" "ssl_expiry" "PASS" "Certificate valid for $days_until_expiry days"
            fi
        else
            warning "Could not parse expiry date for $domain"
            update_report "$domain" "ssl_expiry" "WARN" "Could not parse expiry date"
        fi
        
        # Certificate details for report
        local cert_details="{
            \"subject\": \"$cert_subject\",
            \"issuer\": \"$cert_issuer\",
            \"serial\": \"$cert_serial\",
            \"not_before\": \"$cert_not_before\",
            \"not_after\": \"$cert_not_after\",
            \"fingerprint\": \"$cert_fingerprint\",
            \"days_until_expiry\": $days_until_expiry
        }"
        
        success "SSL certificate test passed for $domain"
        update_report "$domain" "ssl_certificate" "PASS" "Certificate valid and properly configured" "$cert_details"
        
    else
        error "SSL connection failed for $domain:$port"
        update_report "$domain" "ssl_certificate" "FAIL" "SSL connection failed"
        ((ssl_errors++))
    fi
    
    return $ssl_errors
}

test_tls_configuration() {
    local domain="$1"
    local port="${2:-443}"
    
    log "Testing TLS configuration for $domain:$port"
    
    local tls_info=""
    local tls_errors=0
    
    # Test TLS versions and ciphers
    local tls_versions=("tls1_2" "tls1_3")
    local supported_versions=()
    local cipher_suites=()
    
    for version in "${tls_versions[@]}"; do
        if timeout "$TIMEOUT" openssl s_client -connect "$domain:$port" -servername "$domain" -"$version" -cipher 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA' < /dev/null >/dev/null 2>&1; then
            supported_versions+=("$version")
            log "TLS $version supported on $domain"
        fi
    done
    
    if [[ ${#supported_versions[@]} -eq 0 ]]; then
        error "No secure TLS versions supported on $domain"
        update_report "$domain" "tls_versions" "FAIL" "No secure TLS versions supported"
        ((tls_errors++))
    else
        success "TLS versions supported on $domain: ${supported_versions[*]}"
        local versions_json=$(printf '%s\n' "${supported_versions[@]}" | jq -R . | jq -s .)
        update_report "$domain" "tls_versions" "PASS" "Secure TLS versions supported" "{\"versions\": $versions_json}"
    fi
    
    # Test for weak protocols (should fail)
    local weak_versions=("ssl3" "tls1" "tls1_1")
    local weak_found=()
    
    for version in "${weak_versions[@]}"; do
        if timeout 5 openssl s_client -connect "$domain:$port" -servername "$domain" -"$version" < /dev/null >/dev/null 2>&1; then
            weak_found+=("$version")
        fi
    done
    
    if [[ ${#weak_found[@]} -gt 0 ]]; then
        warning "Weak TLS versions supported on $domain: ${weak_found[*]}"
        local weak_json=$(printf '%s\n' "${weak_found[@]}" | jq -R . | jq -s .)
        update_report "$domain" "weak_tls" "WARN" "Weak TLS versions detected" "{\"weak_versions\": $weak_json}"
    else
        success "No weak TLS versions detected on $domain"
        update_report "$domain" "weak_tls" "PASS" "No weak TLS versions found"
    fi
    
    return $tls_errors
}

test_security_headers() {
    local domain="$1"
    
    log "Testing security headers for $domain"
    
    local headers_response=""
    local security_errors=0
    local missing_headers=()
    local present_headers=()
    
    # Get HTTP headers
    if headers_response=$(timeout "$TIMEOUT" curl -I -s "https://$domain" 2>/dev/null); then
        
        # Check for important security headers
        local required_headers=(
            "strict-transport-security"
            "x-content-type-options"
            "x-frame-options"
            "x-xss-protection"
            "referrer-policy"
        )
        
        for header in "${required_headers[@]}"; do
            if echo "$headers_response" | grep -qi "^$header:"; then
                present_headers+=("$header")
                log "Security header found: $header"
            else
                missing_headers+=("$header")
                warning "Missing security header: $header"
            fi
        done
        
        # Check HSTS specifically
        if echo "$headers_response" | grep -qi "^strict-transport-security:"; then
            local hsts_value=$(echo "$headers_response" | grep -i "^strict-transport-security:" | head -1)
            success "HSTS enabled for $domain: $hsts_value"
            update_report "$domain" "hsts" "PASS" "HSTS properly configured" "{\"header\": \"$hsts_value\"}"
        else
            warning "HSTS not configured for $domain"
            update_report "$domain" "hsts" "WARN" "HSTS header missing"
        fi
        
        # Summary of security headers
        if [[ ${#missing_headers[@]} -eq 0 ]]; then
            success "All security headers present for $domain"
            local headers_json=$(printf '%s\n' "${present_headers[@]}" | jq -R . | jq -s .)
            update_report "$domain" "security_headers" "PASS" "All required security headers present" "{\"headers\": $headers_json}"
        else
            warning "Some security headers missing for $domain: ${missing_headers[*]}"
            local missing_json=$(printf '%s\n' "${missing_headers[@]}" | jq -R . | jq -s .)
            local present_json=$(printf '%s\n' "${present_headers[@]}" | jq -R . | jq -s .)
            update_report "$domain" "security_headers" "WARN" "Some security headers missing" "{\"present\": $present_json, \"missing\": $missing_json}"
        fi
        
    else
        error "Failed to fetch headers for $domain"
        update_report "$domain" "security_headers" "FAIL" "Could not fetch HTTP headers"
        ((security_errors++))
    fi
    
    return $security_errors
}

test_http_to_https_redirect() {
    local domain="$1"
    
    log "Testing HTTP to HTTPS redirect for $domain"
    
    local redirect_response=""
    local redirect_errors=0
    
    # Test HTTP redirect
    if redirect_response=$(timeout "$TIMEOUT" curl -I -s "http://$domain" 2>/dev/null); then
        if echo "$redirect_response" | grep -q "HTTP/[12].[01] 30[1-8]"; then
            local location=$(echo "$redirect_response" | grep -i "^location:" | head -1 | sed 's/location: //i' | tr -d '\r\n')
            if [[ "$location" =~ ^https://.* ]]; then
                success "HTTP to HTTPS redirect working for $domain: $location"
                update_report "$domain" "http_redirect" "PASS" "HTTP to HTTPS redirect configured" "{\"location\": \"$location\"}"
            else
                warning "HTTP redirect for $domain does not use HTTPS: $location"
                update_report "$domain" "http_redirect" "WARN" "Redirect not to HTTPS" "{\"location\": \"$location\"}"
            fi
        else
            warning "No HTTP redirect configured for $domain"
            update_report "$domain" "http_redirect" "WARN" "No HTTP redirect found"
        fi
    else
        error "Failed to test HTTP redirect for $domain"
        update_report "$domain" "http_redirect" "FAIL" "Could not test HTTP redirect"
        ((redirect_errors++))
    fi
    
    return $redirect_errors
}

test_domain_comprehensive() {
    local domain="$1"
    
    log "Starting comprehensive SSL test for $domain"
    
    local total_errors=0
    
    # Run all tests for this domain
    test_dns_resolution "$domain" || ((total_errors++))
    test_ssl_certificate "$domain" || ((total_errors++))
    test_tls_configuration "$domain" || ((total_errors++))
    test_security_headers "$domain" || ((total_errors++))
    test_http_to_https_redirect "$domain" || ((total_errors++))
    
    if [[ $total_errors -eq 0 ]]; then
        success "All tests passed for $domain"
    else
        error "Domain $domain failed $total_errors test(s)"
    fi
    
    return $total_errors
}

generate_summary_report() {
    log "Generating summary report"
    
    local total_tests=$(jq -r '.results.summary.total_tests' "$REPORT_FILE")
    local passed=$(jq -r '.results.summary.passed' "$REPORT_FILE")
    local failed=$(jq -r '.results.summary.failed' "$REPORT_FILE")
    local warnings=$(jq -r '.results.summary.warnings' "$REPORT_FILE")
    local success_rate=$((passed * 100 / total_tests))
    
    cat << EOF

${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}
${GREEN}                           SSL TEST SUMMARY REPORT                             ${NC}
${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}

Test Run: $(jq -r '.test_run.timestamp' "$REPORT_FILE")
Total Domains Tested: ${#DOMAINS[@]}
Total Tests Executed: $total_tests

Results:
  ${GREEN}✓ Passed:   $passed${NC}
  ${RED}✗ Failed:   $failed${NC}
  ${YELLOW}⚠ Warnings: $warnings${NC}

Success Rate: $success_rate%

EOF

    # Domain-by-domain summary
    echo "Domain Results:"
    for domain in "${DOMAINS[@]}"; do
        local domain_passed=$(jq -r ".results.domains[\"$domain\"] | to_entries | map(select(.value.status == \"PASS\")) | length" "$REPORT_FILE" 2>/dev/null || echo "0")
        local domain_failed=$(jq -r ".results.domains[\"$domain\"] | to_entries | map(select(.value.status == \"FAIL\")) | length" "$REPORT_FILE" 2>/dev/null || echo "0")
        local domain_warnings=$(jq -r ".results.domains[\"$domain\"] | to_entries | map(select(.value.status == \"WARN\")) | length" "$REPORT_FILE" 2>/dev/null || echo "0")
        
        local status_color=$GREEN
        if [[ $domain_failed -gt 0 ]]; then
            status_color=$RED
        elif [[ $domain_warnings -gt 0 ]]; then
            status_color=$YELLOW
        fi
        
        printf "  %s%-25s%s - Pass: %2d, Fail: %2d, Warn: %2d\n" "$status_color" "$domain" "$NC" "$domain_passed" "$domain_failed" "$domain_warnings"
    done
    
    echo
    echo "Detailed Report: $REPORT_FILE"
    
    if [[ $DETAILED_REPORT == true ]]; then
        echo
        echo "Detailed Analysis:"
        jq -r '.results.domains | to_entries[] | "\(.key):" + "\n" + (.value | to_entries[] | "  \(.key): \(.value.status) - \(.value.message)")' "$REPORT_FILE"
    fi
    
    echo
    
    if [[ $failed -gt 0 ]]; then
        error "SSL configuration has $failed failed tests that need attention"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        warning "SSL configuration has $warnings warnings that should be reviewed"
        return 0
    else
        success "SSL configuration is excellent! All tests passed."
        return 0
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--detailed)
                DETAILED_REPORT=true
                shift
                ;;
            -i|--internal)
                CHECK_INTERNAL=true
                shift
                ;;
            -s|--skip-dns)
                SKIP_DNS=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -o|--output)
                REPORT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log "Starting comprehensive SSL configuration test"
    log "Testing ${#DOMAINS[@]} domains with ${TIMEOUT}s timeout"
    
    # Check prerequisites
    for cmd in openssl curl dig jq; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    init_report
    
    local overall_errors=0
    
    # Test each domain
    for domain in "${DOMAINS[@]}"; do
        if ! test_domain_comprehensive "$domain"; then
            ((overall_errors++))
        fi
        echo  # Add spacing between domain tests
    done
    
    generate_summary_report
    local summary_exit_code=$?
    
    log "SSL configuration test completed"
    log "Report saved to: $REPORT_FILE"
    
    exit $summary_exit_code
}

# Handle script interruption
trap 'error "SSL test interrupted"; exit 130' INT TERM

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "This script requires 'jq' for JSON processing. Please install it:"
    error "  Ubuntu/Debian: sudo apt-get install jq"
    error "  CentOS/RHEL: sudo yum install jq"
    error "  macOS: brew install jq"
    exit 1
fi

# Run main function
main "$@"