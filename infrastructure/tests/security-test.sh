#!/bin/bash

# Security Test Suite for Cloudya Vault Infrastructure
# Comprehensive security validation and penetration testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
VAULT_URL="https://vault.cloudya.net"
CONSUL_URL="https://consul.cloudya.net"
TRAEFIK_URL="https://traefik.cloudya.net"
SECURITY_RESULTS_FILE="/tmp/security_test_results.json"
SECURITY_LOG_FILE="/tmp/security_test.log"

# Initialize results
echo '{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","security_tests":{},"vulnerabilities":[],"recommendations":[],"summary":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}' > "$SECURITY_RESULTS_FILE"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$SECURITY_LOG_FILE"
}

security_pass() {
    echo -e "${GREEN}✓ SECURE: $1${NC}" | tee -a "$SECURITY_LOG_FILE"
    update_security_result "$2" "pass" "$1"
}

security_fail() {
    local severity="$3"
    echo -e "${RED}✗ $severity: $1${NC}" | tee -a "$SECURITY_LOG_FILE"
    update_security_result "$2" "fail" "$1" "$severity"
}

security_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}" | tee -a "$SECURITY_LOG_FILE"
    update_security_result "$2" "warning" "$1" "medium"
}

update_security_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local severity="${4:-info}"
    
    # Update JSON results
    jq --arg name "$test_name" --arg status "$status" --arg msg "$message" --arg sev "$severity" \
       '.security_tests[$name] = {"status": $status, "message": $msg, "severity": $sev, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
       "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE"
    
    # Update severity count
    if [ "$status" = "fail" ]; then
        case "$severity" in
            "critical") jq '.summary.critical += 1' "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE" ;;
            "high") jq '.summary.high += 1' "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE" ;;
            "medium") jq '.summary.medium += 1' "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE" ;;
            "low") jq '.summary.low += 1' "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE" ;;
        esac
    fi
}

add_recommendation() {
    local recommendation="$1"
    local priority="$2"
    
    jq --arg rec "$recommendation" --arg pri "$priority" \
       '.recommendations += [{"recommendation": $rec, "priority": $pri, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]' \
       "$SECURITY_RESULTS_FILE" > "${SECURITY_RESULTS_FILE}.tmp" && mv "${SECURITY_RESULTS_FILE}.tmp" "$SECURITY_RESULTS_FILE"
}

test_certificate_security() {
    local service_name="$1"
    local hostname="$2"
    local test_name="cert_security_${service_name}"
    
    log "Testing certificate security for $service_name"
    
    # Test certificate chain
    local cert_chain=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" -verify_return_error 2>&1 || echo "")
    
    if echo "$cert_chain" | grep -q "Verification: OK"; then
        security_pass "Certificate chain verification passed for $service_name" "$test_name"
    else
        security_fail "Certificate chain verification failed for $service_name" "$test_name" "high"
    fi
    
    # Test for weak cipher suites
    local weak_ciphers=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" -cipher 'RC4:DES:3DES:MD5' 2>/dev/null | grep -c "Cipher    :" || echo "0")
    
    if [ "$weak_ciphers" -eq 0 ]; then
        security_pass "No weak cipher suites detected for $service_name" "weak_ciphers_$service_name"
    else
        security_fail "Weak cipher suites detected for $service_name" "weak_ciphers_$service_name" "medium"
    fi
    
    # Test certificate expiration
    local cert_expiry=$(echo | openssl s_client -servername "$hostname" -connect "$hostname:443" 2>/dev/null | openssl x509 -noout -checkend 2592000 2>/dev/null && echo "valid" || echo "expiring")
    
    if [ "$cert_expiry" = "valid" ]; then
        security_pass "Certificate not expiring within 30 days for $service_name" "cert_expiry_$service_name"
    else
        security_fail "Certificate expiring within 30 days for $service_name" "cert_expiry_$service_name" "high"
    fi
}

test_http_security_headers() {
    local service_name="$1"
    local url="$2"
    local test_name="headers_${service_name}"
    
    log "Testing HTTP security headers for $service_name"
    
    local headers=$(curl -s -I "$url" 2>/dev/null || echo "")
    local security_score=0
    
    # HSTS
    if echo "$headers" | grep -qi "strict-transport-security"; then
        local hsts_value=$(echo "$headers" | grep -i "strict-transport-security" | cut -d: -f2- | xargs)
        if echo "$hsts_value" | grep -q "max-age=[1-9][0-9]\{6,\}"; then
            security_pass "HSTS properly configured for $service_name" "hsts_$service_name"
            security_score=$((security_score + 2))
        else
            security_warning "HSTS configured but max-age too low for $service_name" "hsts_$service_name"
            security_score=$((security_score + 1))
        fi
    else
        security_fail "HSTS not configured for $service_name" "hsts_$service_name" "medium"
        add_recommendation "Configure Strict-Transport-Security header for $service_name" "medium"
    fi
    
    # X-Frame-Options
    if echo "$headers" | grep -qi "x-frame-options"; then
        security_pass "X-Frame-Options configured for $service_name" "xframe_$service_name"
        security_score=$((security_score + 1))
    else
        security_fail "X-Frame-Options not configured for $service_name" "xframe_$service_name" "low"
        add_recommendation "Configure X-Frame-Options header for $service_name" "low"
    fi
    
    # Content-Security-Policy
    if echo "$headers" | grep -qi "content-security-policy"; then
        security_pass "CSP configured for $service_name" "csp_$service_name"
        security_score=$((security_score + 2))
    else
        security_fail "Content-Security-Policy not configured for $service_name" "csp_$service_name" "medium"
        add_recommendation "Configure Content-Security-Policy header for $service_name" "medium"
    fi
    
    # X-Content-Type-Options
    if echo "$headers" | grep -qi "x-content-type-options.*nosniff"; then
        security_pass "X-Content-Type-Options configured for $service_name" "xcontent_$service_name"
        security_score=$((security_score + 1))
    else
        security_fail "X-Content-Type-Options not properly configured for $service_name" "xcontent_$service_name" "low"
    fi
    
    log "Security headers score for $service_name: $security_score/6"
}

test_vault_security() {
    local test_name="vault_security"
    
    log "Testing Vault-specific security configurations"
    
    # Test if Vault root token is disabled/revoked
    local vault_health=$(curl -s "$VAULT_URL/v1/sys/health" 2>/dev/null || echo "")
    
    if echo "$vault_health" | jq -e '.initialized == true and .sealed == false' >/dev/null 2>&1; then
        security_pass "Vault is properly initialized and unsealed" "vault_init"
        
        # Test if Vault UI is disabled in production
        local ui_response=$(curl -s -w "%{http_code}" -o /dev/null "$VAULT_URL/ui/" 2>/dev/null || echo "000")
        if [ "$ui_response" = "404" ]; then
            security_pass "Vault UI is disabled (production-ready)" "vault_ui"
        elif [ "$ui_response" = "200" ]; then
            security_warning "Vault UI is enabled (consider disabling in production)" "vault_ui"
            add_recommendation "Consider disabling Vault UI in production environment" "low"
        fi
        
        # Test if debug endpoints are disabled
        local debug_response=$(curl -s -w "%{http_code}" -o /dev/null "$VAULT_URL/v1/sys/pprof/profile" 2>/dev/null || echo "000")
        if [ "$debug_response" = "404" ] || [ "$debug_response" = "405" ]; then
            security_pass "Vault debug endpoints are disabled" "vault_debug"
        else
            security_fail "Vault debug endpoints may be enabled" "vault_debug" "medium"
        fi
    else
        security_fail "Vault is not properly initialized or is sealed" "vault_init" "critical"
    fi
}

test_consul_security() {
    local test_name="consul_security"
    
    log "Testing Consul security configurations"
    
    # Test if Consul ACLs are enabled
    local acl_status=$(curl -s "$CONSUL_URL/v1/acl/bootstrap" 2>/dev/null || echo "")
    
    if echo "$acl_status" | jq -e '.AccessorID' >/dev/null 2>&1; then
        security_warning "Consul ACL bootstrap still available" "consul_acl"
        add_recommendation "Ensure Consul ACL system is properly configured and bootstrap disabled" "high"
    else
        # Check if ACLs are configured (bootstrap should be disabled after setup)
        local acl_check=$(curl -s -w "%{http_code}" -o /dev/null "$CONSUL_URL/v1/acl/policies" 2>/dev/null || echo "000")
        if [ "$acl_check" = "403" ]; then
            security_pass "Consul ACLs appear to be properly configured" "consul_acl"
        elif [ "$acl_check" = "200" ]; then
            security_warning "Consul ACL policies accessible without authentication" "consul_acl"
        fi
    fi
    
    # Test Consul UI access
    local ui_response=$(curl -s -w "%{http_code}" -o /dev/null "$CONSUL_URL/ui/" 2>/dev/null || echo "000")
    if [ "$ui_response" = "401" ] || [ "$ui_response" = "403" ]; then
        security_pass "Consul UI is properly protected" "consul_ui"
    elif [ "$ui_response" = "200" ]; then
        security_warning "Consul UI accessible without authentication" "consul_ui"
        add_recommendation "Secure Consul UI with authentication" "medium"
    fi
}

test_traefik_security() {
    local test_name="traefik_security"
    
    log "Testing Traefik security configurations"
    
    # Test API access
    local api_response=$(curl -s -w "%{http_code}" -o /dev/null "$TRAEFIK_URL/api/overview" 2>/dev/null || echo "000")
    if [ "$api_response" = "401" ] || [ "$api_response" = "403" ]; then
        security_pass "Traefik API is properly protected" "traefik_api_auth"
    elif [ "$api_response" = "200" ]; then
        security_fail "Traefik API accessible without authentication" "traefik_api_auth" "high"
        add_recommendation "Secure Traefik API with authentication" "high"
    fi
    
    # Test dashboard access
    local dashboard_response=$(curl -s -w "%{http_code}" -o /dev/null "$TRAEFIK_URL/dashboard/" 2>/dev/null || echo "000")
    if [ "$dashboard_response" = "401" ] || [ "$dashboard_response" = "403" ]; then
        security_pass "Traefik dashboard is properly protected" "traefik_dashboard_auth"
    elif [ "$dashboard_response" = "200" ]; then
        security_fail "Traefik dashboard accessible without authentication" "traefik_dashboard_auth" "high"
        add_recommendation "Secure Traefik dashboard with authentication" "high"
    fi
    
    # Test for debug endpoints
    local debug_response=$(curl -s -w "%{http_code}" -o /dev/null "$TRAEFIK_URL/debug/" 2>/dev/null || echo "000")
    if [ "$debug_response" = "404" ] || [ "$debug_response" = "405" ]; then
        security_pass "Traefik debug endpoints are disabled" "traefik_debug"
    else
        security_warning "Traefik debug endpoints may be accessible" "traefik_debug"
    fi
}

test_network_security() {
    local test_name="network_security"
    
    log "Testing network-level security"
    
    # Test for HTTP redirects
    for service in "vault.cloudya.net" "consul.cloudya.net" "traefik.cloudya.net"; do
        local http_response=$(curl -s -w "%{http_code}" -o /dev/null "http://$service" 2>/dev/null || echo "000")
        if [ "$http_response" = "301" ] || [ "$http_response" = "302" ] || [ "$http_response" = "308" ]; then
            security_pass "HTTP to HTTPS redirect working for $service" "http_redirect_$service"
        else
            security_fail "No HTTP to HTTPS redirect for $service (HTTP $http_response)" "http_redirect_$service" "medium"
            add_recommendation "Configure HTTP to HTTPS redirect for $service" "medium"
        fi
    done
    
    # Test for common vulnerability paths
    local vuln_paths=(
        "/.well-known/"
        "/admin"
        "/api/debug"
        "/.env"
        "/backup"
        "/config"
    )
    
    for service_url in "$VAULT_URL" "$CONSUL_URL" "$TRAEFIK_URL"; do
        for path in "${vuln_paths[@]}"; do
            local vuln_response=$(curl -s -w "%{http_code}" -o /dev/null "$service_url$path" 2>/dev/null || echo "000")
            if [ "$vuln_response" = "200" ]; then
                security_warning "Potential sensitive path accessible: $service_url$path" "vuln_path_$(basename "$service_url")_$(echo "$path" | tr '/' '_')"
            fi
        done
    done
}

test_information_disclosure() {
    local test_name="info_disclosure"
    
    log "Testing for information disclosure vulnerabilities"
    
    for service_name in "vault" "consul" "traefik"; do
        local service_url=""
        case "$service_name" in
            "vault") service_url="$VAULT_URL" ;;
            "consul") service_url="$CONSUL_URL" ;;
            "traefik") service_url="$TRAEFIK_URL" ;;
        esac
        
        # Check server headers
        local server_header=$(curl -s -I "$service_url" 2>/dev/null | grep -i "server:" | cut -d: -f2- | xargs || echo "")
        if [ -n "$server_header" ]; then
            if echo "$server_header" | grep -qE "nginx/[0-9.]+|apache/[0-9.]+"; then
                security_warning "Server version disclosed for $service_name: $server_header" "server_version_$service_name"
                add_recommendation "Hide server version information for $service_name" "low"
            else
                security_pass "Server version information properly hidden for $service_name" "server_version_$service_name"
            fi
        fi
        
        # Check for powered-by headers
        local powered_by=$(curl -s -I "$service_url" 2>/dev/null | grep -i "x-powered-by:" | cut -d: -f2- | xargs || echo "")
        if [ -n "$powered_by" ]; then
            security_warning "X-Powered-By header disclosed for $service_name: $powered_by" "powered_by_$service_name"
            add_recommendation "Remove X-Powered-By header for $service_name" "low"
        else
            security_pass "No X-Powered-By header disclosed for $service_name" "powered_by_$service_name"
        fi
    done
}

generate_security_report() {
    log "Generating comprehensive security report"
    
    # Read results and generate summary
    local results=$(cat "$SECURITY_RESULTS_FILE")
    local critical=$(echo "$results" | jq '.summary.critical')
    local high=$(echo "$results" | jq '.summary.high')
    local medium=$(echo "$results" | jq '.summary.medium')
    local low=$(echo "$results" | jq '.summary.low')
    local recommendations_count=$(echo "$results" | jq '.recommendations | length')
    
    echo
    echo "========================================="
    echo "       SECURITY TEST SUMMARY"
    echo "========================================="
    echo "Critical Issues:    $critical"
    echo "High Issues:        $high"
    echo "Medium Issues:      $medium"
    echo "Low Issues:         $low"
    echo "Recommendations:    $recommendations_count"
    echo
    
    if [ "$critical" -eq 0 ] && [ "$high" -eq 0 ]; then
        if [ "$medium" -eq 0 ]; then
            echo -e "${GREEN}🔒 EXCELLENT SECURITY POSTURE! No critical, high, or medium severity issues found.${NC}"
        else
            echo -e "${YELLOW}🔐 Good security posture with $medium medium-severity items to address.${NC}"
        fi
    elif [ "$critical" -eq 0 ] && [ "$high" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Security review needed: $high high-severity issues require attention.${NC}"
    else
        echo -e "${RED}🚨 CRITICAL SECURITY ISSUES FOUND! Immediate action required.${NC}"
    fi
    
    # Display top recommendations
    if [ "$recommendations_count" -gt 0 ]; then
        echo
        echo "Top Security Recommendations:"
        echo "$results" | jq -r '.recommendations[] | "• " + .recommendation + " (" + .priority + " priority)"' | head -5
    fi
    
    echo
    echo "Detailed security results saved to: $SECURITY_RESULTS_FILE"
    echo "Security test log saved to: $SECURITY_LOG_FILE"
    echo
}

# Main execution
main() {
    log "Starting Cloudya Vault Infrastructure Security Tests"
    log "====================================================="
    
    # Clean up previous results
    rm -f "$SECURITY_LOG_FILE"
    
    # Certificate security tests
    test_certificate_security "vault" "vault.cloudya.net"
    test_certificate_security "consul" "consul.cloudya.net"
    test_certificate_security "traefik" "traefik.cloudya.net"
    
    # HTTP security headers
    test_http_security_headers "vault" "$VAULT_URL"
    test_http_security_headers "consul" "$CONSUL_URL"
    test_http_security_headers "traefik" "$TRAEFIK_URL"
    
    # Service-specific security tests
    test_vault_security
    test_consul_security
    test_traefik_security
    
    # Network security tests
    test_network_security
    
    # Information disclosure tests
    test_information_disclosure
    
    # Generate final security report
    generate_security_report
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi