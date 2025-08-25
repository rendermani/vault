#!/bin/bash

# Deployment Test Suite for Cloudya Vault Infrastructure
# Tests all deployed services for proper functionality and security

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
VAULT_URL="https://vault.cloudya.net"
CONSUL_URL="https://consul.cloudya.net"
TRAEFIK_URL="https://traefik.cloudya.net"
TEST_RESULTS_FILE="/tmp/deployment_test_results.json"
LOG_FILE="/tmp/deployment_test.log"

# Initialize results
echo '{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","tests":{},"summary":{"total":0,"passed":0,"failed":0,"warnings":0}}' > "$TEST_RESULTS_FILE"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
    update_test_result "$2" "passed" "$1"
}

error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
    update_test_result "$2" "failed" "$1"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
    update_test_result "$2" "warning" "$1"
}

update_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    # Update JSON results
    jq --arg name "$test_name" --arg status "$status" --arg msg "$message" \
       '.tests[$name] = {"status": $status, "message": $msg, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
       "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE"
    
    # Update summary
    case "$status" in
        "passed") jq '.summary.passed += 1 | .summary.total += 1' "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE" ;;
        "failed") jq '.summary.failed += 1 | .summary.total += 1' "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE" ;;
        "warning") jq '.summary.warnings += 1 | .summary.total += 1' "$TEST_RESULTS_FILE" > "${TEST_RESULTS_FILE}.tmp" && mv "${TEST_RESULTS_FILE}.tmp" "$TEST_RESULTS_FILE" ;;
    esac
}

test_https_connectivity() {
    local service_name="$1"
    local url="$2"
    local test_name="https_${service_name}"
    
    log "Testing HTTPS connectivity to $service_name ($url)"
    
    # Test basic connectivity with SSL verification
    if curl -s --fail --connect-timeout 10 --max-time 30 --head "$url" > /dev/null 2>&1; then
        success "HTTPS connectivity to $service_name working" "$test_name"
        return 0
    else
        error "HTTPS connectivity to $service_name failed" "$test_name"
        return 1
    fi
}

test_ssl_certificate() {
    local service_name="$1"
    local hostname="$2"
    local test_name="ssl_${service_name}"
    
    log "Testing SSL certificate for $service_name"
    
    # Get certificate info
    local cert_info=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" 2>/dev/null | openssl x509 -noout -text 2>/dev/null || echo "")
    
    if [ -n "$cert_info" ]; then
        # Check if it's not a default/self-signed certificate
        if echo "$cert_info" | grep -q "Let's Encrypt\|DigiCert\|Cloudflare\|Amazon\|Google"; then
            success "Valid SSL certificate for $service_name" "$test_name"
        elif echo "$cert_info" | grep -q "CN=$hostname"; then
            warning "SSL certificate for $service_name appears valid but issuer unknown" "$test_name"
        else
            error "SSL certificate for $service_name may be default/invalid" "$test_name"
        fi
        
        # Check expiration
        local expiry=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep "notAfter" | cut -d= -f2)
        if [ -n "$expiry" ]; then
            log "Certificate expires: $expiry"
        fi
    else
        error "Could not retrieve SSL certificate for $service_name" "$test_name"
    fi
}

test_security_headers() {
    local service_name="$1"
    local url="$2"
    local test_name="security_${service_name}"
    
    log "Testing security headers for $service_name"
    
    local headers=$(curl -s -I "$url" 2>/dev/null || echo "")
    local score=0
    local max_score=5
    
    if echo "$headers" | grep -qi "strict-transport-security"; then
        score=$((score + 1))
    fi
    
    if echo "$headers" | grep -qi "x-frame-options"; then
        score=$((score + 1))
    fi
    
    if echo "$headers" | grep -qi "x-content-type-options"; then
        score=$((score + 1))
    fi
    
    if echo "$headers" | grep -qi "x-xss-protection"; then
        score=$((score + 1))
    fi
    
    if echo "$headers" | grep -qi "content-security-policy"; then
        score=$((score + 1))
    fi
    
    if [ "$score" -ge 3 ]; then
        success "Good security headers for $service_name ($score/$max_score)" "$test_name"
    elif [ "$score" -ge 1 ]; then
        warning "Some security headers missing for $service_name ($score/$max_score)" "$test_name"
    else
        error "No security headers found for $service_name" "$test_name"
    fi
}

test_vault_status() {
    local test_name="vault_status"
    
    log "Testing Vault initialization and seal status"
    
    # Test Vault API
    local vault_status=$(curl -s "$VAULT_URL/v1/sys/health" 2>/dev/null || echo "")
    
    if [ -n "$vault_status" ]; then
        if echo "$vault_status" | jq -e '.initialized == true' >/dev/null 2>&1; then
            if echo "$vault_status" | jq -e '.sealed == false' >/dev/null 2>&1; then
                success "Vault is initialized and unsealed" "$test_name"
            else
                error "Vault is initialized but sealed" "$test_name"
            fi
        else
            error "Vault is not initialized" "$test_name"
        fi
    else
        error "Could not retrieve Vault status" "$test_name"
    fi
}

test_consul_status() {
    local test_name="consul_status"
    
    log "Testing Consul status and leader election"
    
    # Test Consul API
    local consul_leader=$(curl -s "$CONSUL_URL/v1/status/leader" 2>/dev/null || echo "")
    
    if [ -n "$consul_leader" ] && [ "$consul_leader" != '""' ]; then
        success "Consul has elected leader: $consul_leader" "$test_name"
        
        # Test service catalog
        local services=$(curl -s "$CONSUL_URL/v1/catalog/services" 2>/dev/null || echo "")
        if echo "$services" | jq -e '. | length > 0' >/dev/null 2>&1; then
            success "Consul service catalog is populated" "consul_services"
        else
            warning "Consul service catalog appears empty" "consul_services"
        fi
    else
        error "Consul has no leader or is not accessible" "$test_name"
    fi
}

test_traefik_dashboard() {
    local test_name="traefik_dashboard"
    
    log "Testing Traefik dashboard accessibility"
    
    # Test if dashboard is accessible (should require auth)
    local traefik_response=$(curl -s -w "%{http_code}" -o /dev/null "$TRAEFIK_URL/dashboard/" 2>/dev/null || echo "000")
    
    if [ "$traefik_response" = "401" ] || [ "$traefik_response" = "403" ]; then
        success "Traefik dashboard properly protected with authentication" "$test_name"
    elif [ "$traefik_response" = "200" ]; then
        warning "Traefik dashboard accessible without authentication" "$test_name"
    else
        error "Traefik dashboard not responding (HTTP $traefik_response)" "$test_name"
    fi
    
    # Test API endpoint
    local api_response=$(curl -s -w "%{http_code}" -o /dev/null "$TRAEFIK_URL/api/overview" 2>/dev/null || echo "000")
    if [ "$api_response" = "401" ] || [ "$api_response" = "403" ]; then
        success "Traefik API properly protected" "traefik_api"
    elif [ "$api_response" = "200" ]; then
        warning "Traefik API accessible without authentication" "traefik_api"
    else
        error "Traefik API not responding (HTTP $api_response)" "traefik_api"
    fi
}

test_service_discovery() {
    local test_name="service_discovery"
    
    log "Testing service discovery integration"
    
    # Check if Traefik can discover services from Consul
    local traefik_services=$(curl -s "$TRAEFIK_URL/api/http/services" 2>/dev/null || echo "")
    
    if [ -n "$traefik_services" ]; then
        local service_count=$(echo "$traefik_services" | jq '. | length' 2>/dev/null || echo "0")
        if [ "$service_count" -gt 0 ]; then
            success "Service discovery working - $service_count services discovered" "$test_name"
        else
            warning "Service discovery configured but no services found" "$test_name"
        fi
    else
        error "Could not retrieve service discovery information" "$test_name"
    fi
}

test_tls_configuration() {
    local service_name="$1"
    local hostname="$2"
    local test_name="tls_${service_name}"
    
    log "Testing TLS configuration for $service_name"
    
    # Test TLS version and cipher suites
    local tls_info=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" 2>/dev/null | grep -E "Protocol|Cipher" || echo "")
    
    if echo "$tls_info" | grep -q "TLSv1.2\|TLSv1.3"; then
        success "Modern TLS protocol in use for $service_name" "$test_name"
    else
        error "Outdated TLS protocol for $service_name" "$test_name"
    fi
}

generate_report() {
    log "Generating comprehensive test report"
    
    # Read results and generate summary
    local results=$(cat "$TEST_RESULTS_FILE")
    local total=$(echo "$results" | jq '.summary.total')
    local passed=$(echo "$results" | jq '.summary.passed')
    local failed=$(echo "$results" | jq '.summary.failed')
    local warnings=$(echo "$results" | jq '.summary.warnings')
    
    echo
    echo "========================================="
    echo "       DEPLOYMENT TEST SUMMARY"
    echo "========================================="
    echo "Total Tests:    $total"
    echo "Passed:         $passed"
    echo "Failed:         $failed"
    echo "Warnings:       $warnings"
    echo
    
    if [ "$failed" -eq 0 ]; then
        if [ "$warnings" -eq 0 ]; then
            echo -e "${GREEN}🎉 ALL TESTS PASSED! Deployment is fully operational.${NC}"
        else
            echo -e "${YELLOW}✅ All critical tests passed with $warnings warnings.${NC}"
        fi
    else
        echo -e "${RED}❌ $failed tests failed. Please review and fix issues.${NC}"
    fi
    
    echo
    echo "Detailed results saved to: $TEST_RESULTS_FILE"
    echo "Test log saved to: $LOG_FILE"
    echo
}

# Main execution
main() {
    log "Starting Cloudya Vault Infrastructure Deployment Tests"
    log "========================================================"
    
    # Clean up previous results
    rm -f "$LOG_FILE"
    
    # Test HTTPS connectivity
    test_https_connectivity "vault" "$VAULT_URL"
    test_https_connectivity "consul" "$CONSUL_URL"
    test_https_connectivity "traefik" "$TRAEFIK_URL"
    
    # Test SSL certificates
    test_ssl_certificate "vault" "vault.cloudya.net"
    test_ssl_certificate "consul" "consul.cloudya.net"
    test_ssl_certificate "traefik" "traefik.cloudya.net"
    
    # Test security headers
    test_security_headers "vault" "$VAULT_URL"
    test_security_headers "consul" "$CONSUL_URL"
    test_security_headers "traefik" "$TRAEFIK_URL"
    
    # Test TLS configuration
    test_tls_configuration "vault" "vault.cloudya.net"
    test_tls_configuration "consul" "consul.cloudya.net"
    test_tls_configuration "traefik" "traefik.cloudya.net"
    
    # Test service-specific functionality
    test_vault_status
    test_consul_status
    test_traefik_dashboard
    test_service_discovery
    
    # Generate final report
    generate_report
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi