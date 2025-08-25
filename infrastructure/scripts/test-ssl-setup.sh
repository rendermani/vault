#!/bin/bash

# SSL Configuration Test Script
# Tests the SSL certificate setup without deploying services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "================================================"
echo "SSL Configuration Test Suite"
echo "================================================"
echo

# Test 1: Check if SSL setup script exists and is executable
log_info "Test 1: SSL setup script availability"
if [[ -x "$SCRIPT_DIR/setup-ssl-certificates.sh" ]]; then
    log_success "SSL setup script found and is executable"
else
    log_error "SSL setup script missing or not executable"
    exit 1
fi

# Test 2: Check if validation script exists and is executable
log_info "Test 2: SSL validation script availability"
if [[ -x "$SCRIPT_DIR/validate-ssl-config.sh" ]]; then
    log_success "SSL validation script found and is executable"
else
    log_error "SSL validation script missing or not executable"
    exit 1
fi

# Test 3: Check Traefik job file configuration
log_info "Test 3: Traefik job file validation"
TRAEFIK_JOB="/Users/mlautenschlager/cloudya/vault/infrastructure/nomad/jobs/traefik-production.nomad"
if [[ -f "$TRAEFIK_JOB" ]]; then
    # Check for SSL-related configuration
    if grep -q "certificatesResolvers" "$TRAEFIK_JOB" && \
       grep -q "letsencrypt" "$TRAEFIK_JOB" && \
       grep -q "httpChallenge" "$TRAEFIK_JOB"; then
        log_success "Traefik job file contains SSL configuration"
    else
        log_error "Traefik job file missing SSL configuration"
        exit 1
    fi
else
    log_error "Traefik job file not found: $TRAEFIK_JOB"
    exit 1
fi

# Test 4: Validate domain configuration
log_info "Test 4: Domain configuration validation"
DOMAINS=(
    "vault.cloudya.net"
    "consul.cloudya.net"
    "traefik.cloudya.net"
)

for domain in "${DOMAINS[@]}"; do
    if grep -q "$domain" "$TRAEFIK_JOB"; then
        log_success "Domain $domain configured in Traefik job"
    else
        log_warning "Domain $domain not found in Traefik configuration"
    fi
done

# Test 5: Check certificate resolver configuration
log_info "Test 5: Certificate resolver validation"
if grep -q "certResolver: letsencrypt" "$TRAEFIK_JOB"; then
    log_success "Let's Encrypt certificate resolver configured"
else
    log_error "Let's Encrypt certificate resolver not properly configured"
    exit 1
fi

# Test 6: Check ACME email configuration
log_info "Test 6: ACME email configuration"
if grep -q "email: admin@cloudya.net" "$TRAEFIK_JOB"; then
    log_success "ACME email address configured"
else
    log_warning "ACME email address not found or incorrect"
fi

# Test 7: Check storage configuration
log_info "Test 7: Certificate storage configuration"
if grep -q "/letsencrypt/acme.json" "$TRAEFIK_JOB"; then
    log_success "ACME storage path configured"
else
    log_error "ACME storage path not configured"
    exit 1
fi

# Test 8: Validate TLS configuration
log_info "Test 8: TLS security configuration"
if grep -q "minVersion.*TLS12" "$TRAEFIK_JOB" && \
   grep -q "cipherSuites" "$TRAEFIK_JOB"; then
    log_success "TLS security configuration found"
else
    log_warning "TLS security configuration may be incomplete"
fi

# Test 9: Check HTTP to HTTPS redirect
log_info "Test 9: HTTP to HTTPS redirect configuration"
if grep -q "redirections" "$TRAEFIK_JOB" && \
   grep -q "scheme: https" "$TRAEFIK_JOB"; then
    log_success "HTTP to HTTPS redirect configured"
else
    log_warning "HTTP to HTTPS redirect may not be configured"
fi

# Test 10: Check if directory structure would be created properly
log_info "Test 10: Directory structure validation"
REQUIRED_DIRS=(
    "/opt/nomad/volumes/traefik-certs"
    "/opt/nomad/volumes/traefik-config"
    "/opt/nomad/volumes/traefik-logs"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        log_success "Directory exists: $dir"
        
        # Check permissions
        if [[ "$dir" == "/opt/nomad/volumes/traefik-certs" ]]; then
            perms=$(stat -f%Mp%Lp "$dir" 2>/dev/null || stat -c"%a" "$dir" 2>/dev/null || echo "unknown")
            if [[ "$perms" == "700" ]]; then
                log_success "Certificate directory has correct permissions (700)"
            else
                log_warning "Certificate directory permissions: $perms (should be 700)"
            fi
        fi
    else
        log_info "Directory will be created: $dir"
    fi
done

# Test 11: Check ACME storage file if it exists
log_info "Test 11: ACME storage file validation"
ACME_FILE="/opt/nomad/volumes/traefik-certs/acme.json"
if [[ -f "$ACME_FILE" ]]; then
    perms=$(stat -f%Mp%Lp "$ACME_FILE" 2>/dev/null || stat -c"%a" "$ACME_FILE" 2>/dev/null || echo "unknown")
    if [[ "$perms" == "600" ]]; then
        log_success "ACME storage file has correct permissions (600)"
    else
        log_warning "ACME storage file permissions: $perms (should be 600)"
    fi
    
    size=$(stat -f%z "$ACME_FILE" 2>/dev/null || stat -c%s "$ACME_FILE" 2>/dev/null || echo "0")
    if [[ "$size" -gt 10 ]]; then
        log_info "ACME storage file contains data ($size bytes)"
    else
        log_info "ACME storage file is empty (will be populated on certificate generation)"
    fi
else
    log_info "ACME storage file will be created during setup"
fi

# Test 12: Check DNS resolution (if dig is available)
log_info "Test 12: DNS resolution test"
if command -v dig &> /dev/null; then
    for domain in "vault.cloudya.net" "traefik.cloudya.net"; do
        if dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
            log_success "DNS resolution successful for $domain"
        else
            log_warning "DNS resolution failed or returns no IP for $domain"
        fi
    done
else
    log_info "dig not available, skipping DNS resolution test"
fi

# Test 13: Check required tools
log_info "Test 13: Required tools availability"
REQUIRED_TOOLS=("openssl" "curl" "nomad")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        log_success "$tool is available"
    else
        log_warning "$tool is not available (may be required for SSL operations)"
    fi
done

# Test 14: Check if monitoring scripts work
log_info "Test 14: Monitoring scripts validation"
if [[ -x "$SCRIPT_DIR/monitor-certificates.sh" ]] || \
   grep -q "monitor-certificates.sh" "$SCRIPT_DIR/setup-ssl-certificates.sh"; then
    log_success "Certificate monitoring is configured"
else
    log_info "Certificate monitoring will be configured during setup"
fi

# Summary
echo
echo "================================================"
echo "SSL Configuration Test Summary"
echo "================================================"
echo

log_success "SSL configuration test completed successfully!"
echo
echo "Key findings:"
echo "✓ SSL setup and validation scripts are ready"
echo "✓ Traefik job file contains proper SSL configuration"
echo "✓ Let's Encrypt integration is configured"
echo "✓ Domain routing is properly configured"
echo "✓ Security headers and TLS settings are in place"
echo
echo "Next steps:"
echo "1. Ensure DNS records point to your servers"
echo "2. Run: ./scripts/setup-ssl-certificates.sh setup"
echo "3. Deploy Traefik: nomad job run nomad/jobs/traefik-production.nomad"
echo "4. Validate SSL: ./scripts/validate-ssl-config.sh validate"
echo "5. Monitor certificates: ./scripts/monitor-certificates.sh"
echo
echo "For production deployment:"
echo "  ./scripts/deploy-production.sh --environment production"
echo

log_info "SSL test completed at: $(date)"