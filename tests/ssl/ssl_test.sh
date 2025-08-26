#!/bin/bash

# SSL Certificate Testing Script for traefik.cloudya.net
# Tests certificate validity, chain, and security configurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
DOMAIN="traefik.cloudya.net"
PORT="443"
TIMEOUT=10
LOG_FILE="tests/reports/ssl_test_report.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Initialize log file
echo "SSL Certificate Test Report - $(date)" > "$LOG_FILE"
echo "Domain: $DOMAIN" >> "$LOG_FILE"
echo "=============================================" >> "$LOG_FILE"

log_result() {
    local status="$1"
    local test_name="$2"
    local details="$3"
    
    echo "[$status] $test_name: $details" | tee -a "$LOG_FILE"
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ $test_name${NC}"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ $test_name${NC}"
    else
        echo -e "${YELLOW}⚠ $test_name${NC}"
    fi
}

test_ssl_connection() {
    echo "Testing SSL connection to $DOMAIN:$PORT..." | tee -a "$LOG_FILE"
    
    if timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" < /dev/null > /tmp/ssl_test.out 2>&1; then
        log_result "PASS" "SSL Connection" "Successfully connected to $DOMAIN:$PORT"
        return 0
    else
        log_result "FAIL" "SSL Connection" "Failed to connect to $DOMAIN:$PORT"
        return 1
    fi
}

test_certificate_validity() {
    echo "Testing certificate validity..." | tee -a "$LOG_FILE"
    
    # Get certificate information
    cert_info=$(echo | timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$cert_info" >> "$LOG_FILE"
        
        # Check expiration
        not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        exp_date=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null)
        current_date=$(date +%s)
        days_left=$(( (exp_date - current_date) / 86400 ))
        
        if [ $days_left -gt 30 ]; then
            log_result "PASS" "Certificate Expiration" "Certificate valid for $days_left days"
        elif [ $days_left -gt 0 ]; then
            log_result "WARN" "Certificate Expiration" "Certificate expires in $days_left days"
        else
            log_result "FAIL" "Certificate Expiration" "Certificate has expired"
        fi
    else
        log_result "FAIL" "Certificate Validity" "Unable to retrieve certificate information"
    fi
}

test_certificate_chain() {
    echo "Testing certificate chain..." | tee -a "$LOG_FILE"
    
    chain_result=$(echo | timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" -verify_return_error 2>&1)
    
    if echo "$chain_result" | grep -q "Verify return code: 0 (ok)"; then
        log_result "PASS" "Certificate Chain" "Certificate chain is valid"
    else
        verify_error=$(echo "$chain_result" | grep "Verify return code" | head -1)
        log_result "FAIL" "Certificate Chain" "$verify_error"
    fi
}

test_ssl_protocols() {
    echo "Testing SSL/TLS protocols..." | tee -a "$LOG_FILE"
    
    protocols=("ssl3" "tls1" "tls1_1" "tls1_2" "tls1_3")
    
    for protocol in "${protocols[@]}"; do
        if timeout $TIMEOUT openssl s_client -"$protocol" -connect "$DOMAIN:$PORT" -servername "$DOMAIN" < /dev/null > /dev/null 2>&1; then
            if [ "$protocol" = "ssl3" ] || [ "$protocol" = "tls1" ] || [ "$protocol" = "tls1_1" ]; then
                log_result "WARN" "Protocol $protocol" "Insecure protocol is supported"
            else
                log_result "PASS" "Protocol $protocol" "Secure protocol is supported"
            fi
        else
            if [ "$protocol" = "ssl3" ] || [ "$protocol" = "tls1" ] || [ "$protocol" = "tls1_1" ]; then
                log_result "PASS" "Protocol $protocol" "Insecure protocol is properly disabled"
            else
                log_result "FAIL" "Protocol $protocol" "Secure protocol is not supported"
            fi
        fi
    done
}

test_cipher_suites() {
    echo "Testing cipher suites..." | tee -a "$LOG_FILE"
    
    # Test for strong ciphers
    strong_cipher_result=$(echo | timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" -cipher 'ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS' 2>/dev/null)
    
    if echo "$strong_cipher_result" | grep -q "Cipher is"; then
        cipher=$(echo "$strong_cipher_result" | grep "Cipher is" | awk '{print $3}')
        log_result "PASS" "Strong Ciphers" "Using cipher: $cipher"
    else
        log_result "FAIL" "Strong Ciphers" "No strong ciphers supported"
    fi
    
    # Test for weak ciphers (should fail)
    weak_cipher_result=$(echo | timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" -cipher 'RC4:DES:3DES:MD5' 2>/dev/null)
    
    if echo "$weak_cipher_result" | grep -q "Cipher is"; then
        weak_cipher=$(echo "$weak_cipher_result" | grep "Cipher is" | awk '{print $3}')
        log_result "FAIL" "Weak Ciphers" "Weak cipher supported: $weak_cipher"
    else
        log_result "PASS" "Weak Ciphers" "Weak ciphers are properly disabled"
    fi
}

test_hsts() {
    echo "Testing HTTP Strict Transport Security..." | tee -a "$LOG_FILE"
    
    if command -v curl > /dev/null; then
        hsts_header=$(curl -sI "https://$DOMAIN" | grep -i "strict-transport-security" || true)
        
        if [ -n "$hsts_header" ]; then
            log_result "PASS" "HSTS Header" "$hsts_header"
        else
            log_result "WARN" "HSTS Header" "HSTS header not found"
        fi
    else
        log_result "WARN" "HSTS Header" "curl not available for HSTS testing"
    fi
}

test_ocsp_stapling() {
    echo "Testing OCSP stapling..." | tee -a "$LOG_FILE"
    
    ocsp_result=$(echo | timeout $TIMEOUT openssl s_client -connect "$DOMAIN:$PORT" -servername "$DOMAIN" -status 2>/dev/null)
    
    if echo "$ocsp_result" | grep -q "OCSP Response Status: successful"; then
        log_result "PASS" "OCSP Stapling" "OCSP stapling is enabled"
    else
        log_result "WARN" "OCSP Stapling" "OCSP stapling not detected"
    fi
}

# Main test execution
main() {
    echo "Starting SSL certificate tests for $DOMAIN"
    echo "========================================="
    
    # Run all tests
    test_ssl_connection
    test_certificate_validity
    test_certificate_chain
    test_ssl_protocols
    test_cipher_suites
    test_hsts
    test_ocsp_stapling
    
    echo "" | tee -a "$LOG_FILE"
    echo "SSL testing completed. Results saved to: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "=========================================" | tee -a "$LOG_FILE"
}

# Run main function
main "$@"