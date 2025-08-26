#!/bin/bash

# Consul DNS Testing Script
# Comprehensive testing of DNS resolution and service discovery
# Usage: ./test-consul-dns.sh [environment]

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-development}"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"
CONSUL_DNS_PORT="${CONSUL_DNS_PORT:-8600}"
LOG_FILE="/tmp/consul-dns-test-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    info "Running test: $test_name"
    
    if eval "$test_command" &>/dev/null; then
        success "$test_name: PASSED"
        ((TESTS_PASSED++))
        return 0
    else
        error "$test_name: FAILED"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Pre-requisites check
check_prerequisites() {
    log "=== Prerequisites Check ==="
    
    # Check if dig is available
    if ! command -v dig &> /dev/null; then
        error "dig command not found. Please install dnsutils (Ubuntu) or bind-tools (CentOS)"
        exit 1
    fi
    
    # Check if consul command is available
    if ! command -v consul &> /dev/null; then
        warning "consul command not found. Some tests may be limited"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl command not found. Please install curl"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Test Consul availability
test_consul_connectivity() {
    log "=== Consul Connectivity Tests ==="
    
    run_test "Consul HTTP API connectivity" \
        "curl -sf $CONSUL_HTTP_ADDR/v1/status/leader"
    
    run_test "Consul DNS port accessibility" \
        "nc -z 127.0.0.1 $CONSUL_DNS_PORT"
    
    if command -v consul &> /dev/null; then
        run_test "Consul cluster status" \
            "consul members"
    fi
}

# Test basic DNS resolution
test_basic_dns() {
    log "=== Basic DNS Resolution Tests ==="
    
    # Test 1: Consul service resolution
    run_test "Consul service DNS resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.service.consul +short"
    
    # Test 2: Node resolution
    run_test "Consul node DNS resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.node.consul +short"
    
    # Test 3: Datacenter resolution
    run_test "Consul datacenter resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.service.dc1.consul +short"
    
    # Test 4: SRV record resolution
    run_test "Consul SRV record resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT _consul._tcp.service.consul SRV +short"
}

# Test service discovery
test_service_discovery() {
    log "=== Service Discovery Tests ==="
    
    # Register a test service first
    register_test_service
    
    # Test service resolution
    run_test "Test service DNS resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT test-dns-service.service.consul +short"
    
    run_test "Test service SRV resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT _test-dns-service._tcp.service.consul SRV +short"
    
    # Test with tags
    run_test "Test service with tags resolution" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT test.test-dns-service.service.consul +short"
    
    # Clean up test service
    cleanup_test_service
}

# Register test service for testing
register_test_service() {
    info "Registering test service for DNS testing..."
    
    if command -v consul &> /dev/null; then
        consul services register - <<EOF
{
    "ID": "test-dns-service-1",
    "Name": "test-dns-service",
    "Tags": ["test", "dns"],
    "Port": 9999,
    "Address": "127.0.0.1",
    "Check": {
        "TCP": "127.0.0.1:9999",
        "Interval": "10s",
        "Timeout": "3s"
    }
}
EOF
    else
        # Fallback to HTTP API
        curl -X PUT "$CONSUL_HTTP_ADDR/v1/agent/service/register" \
            -H "Content-Type: application/json" \
            -d '{
                "ID": "test-dns-service-1",
                "Name": "test-dns-service",
                "Tags": ["test", "dns"],
                "Port": 9999,
                "Address": "127.0.0.1",
                "Check": {
                    "TCP": "127.0.0.1:9999",
                    "Interval": "10s",
                    "Timeout": "3s"
                }
            }' &>/dev/null
    fi
    
    # Wait for service registration to propagate
    sleep 3
}

# Clean up test service
cleanup_test_service() {
    info "Cleaning up test service..."
    
    if command -v consul &> /dev/null; then
        consul services deregister test-dns-service-1 &>/dev/null || true
    else
        curl -X PUT "$CONSUL_HTTP_ADDR/v1/agent/service/deregister/test-dns-service-1" &>/dev/null || true
    fi
}

# Test DNS forwarding integration
test_dns_forwarding() {
    log "=== DNS Forwarding Tests ==="
    
    # Test system DNS resolution of .consul domains
    run_test "System DNS resolution of .consul domain" \
        "dig consul.service.consul +short"
    
    # Test external DNS still works
    run_test "External DNS resolution" \
        "dig google.com +short"
    
    # Test mixed resolution
    run_test "Mixed DNS resolution" \
        "nslookup consul.service.consul"
}

# Test DNS caching and performance
test_dns_performance() {
    log "=== DNS Performance Tests ==="
    
    # Test response time
    info "Testing DNS response times..."
    local response_times=()
    
    for i in {1..5}; do
        local start_time=$(date +%s%3N)
        dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.service.consul +short &>/dev/null
        local end_time=$(date +%s%3N)
        local response_time=$((end_time - start_time))
        response_times+=("$response_time")
    done
    
    local avg_time=0
    for time in "${response_times[@]}"; do
        avg_time=$((avg_time + time))
    done
    avg_time=$((avg_time / 5))
    
    if [[ $avg_time -lt 100 ]]; then
        success "Average DNS response time: ${avg_time}ms (Good)"
    elif [[ $avg_time -lt 500 ]]; then
        warning "Average DNS response time: ${avg_time}ms (Acceptable)"
    else
        error "Average DNS response time: ${avg_time}ms (Slow)"
    fi
}

# Test DNS security features
test_dns_security() {
    log "=== DNS Security Tests ==="
    
    # Test DNSSEC if enabled
    run_test "DNS over TCP support" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.service.consul +tcp +short"
    
    # Test DNS query limits
    info "Testing DNS query handling..."
    
    # Test large response handling
    run_test "Large DNS response handling" \
        "dig @127.0.0.1 -p $CONSUL_DNS_PORT consul.service.consul ANY"
}

# Test health check integration
test_health_integration() {
    log "=== Health Check Integration Tests ==="
    
    # Create service with failing health check
    register_unhealthy_service
    
    # Test that unhealthy services are not returned in DNS
    if ! dig @127.0.0.1 -p $CONSUL_DNS_PORT unhealthy-test-service.service.consul +short | grep -q "127.0.0.1"; then
        success "Unhealthy services excluded from DNS responses"
    else
        warning "Unhealthy services included in DNS responses (check only_passing setting)"
    fi
    
    cleanup_unhealthy_service
}

# Register unhealthy test service
register_unhealthy_service() {
    info "Registering unhealthy test service..."
    
    if command -v consul &> /dev/null; then
        consul services register - <<EOF
{
    "ID": "unhealthy-test-service-1",
    "Name": "unhealthy-test-service",
    "Tags": ["test", "unhealthy"],
    "Port": 9998,
    "Address": "127.0.0.1",
    "Check": {
        "TCP": "127.0.0.1:1",
        "Interval": "10s",
        "Timeout": "3s"
    }
}
EOF
    fi
    
    sleep 5  # Wait for health check to fail
}

# Clean up unhealthy test service
cleanup_unhealthy_service() {
    if command -v consul &> /dev/null; then
        consul services deregister unhealthy-test-service-1 &>/dev/null || true
    fi
}

# Test service mesh DNS integration
test_service_mesh_dns() {
    log "=== Service Mesh DNS Tests ==="
    
    # Test Connect-enabled service resolution
    if curl -sf "$CONSUL_HTTP_ADDR/v1/connect/ca/roots" &>/dev/null; then
        success "Service mesh CA accessible via HTTP API"
        
        # Test mesh gateway resolution if configured
        run_test "Mesh gateway DNS resolution" \
            "dig @127.0.0.1 -p $CONSUL_DNS_PORT mesh-gateway.service.consul +short"
            
    else
        warning "Service mesh not enabled or not accessible"
    fi
}

# Generate test report
generate_report() {
    log "=== Test Report ==="
    log "Environment: $ENVIRONMENT"
    log "Total tests: $TESTS_TOTAL"
    log "Passed: $TESTS_PASSED"
    log "Failed: $TESTS_FAILED"
    log "Success rate: $(( (TESTS_PASSED * 100) / TESTS_TOTAL ))%"
    log "Log file: $LOG_FILE"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        success "All DNS tests passed!"
        return 0
    else
        error "$TESTS_FAILED tests failed. Check log for details."
        return 1
    fi
}

# Main function
main() {
    log "=== Starting Consul DNS Testing ==="
    log "Environment: $ENVIRONMENT"
    log "Consul HTTP Address: $CONSUL_HTTP_ADDR"
    log "Consul DNS Port: $CONSUL_DNS_PORT"
    
    # Run all test suites
    check_prerequisites
    test_consul_connectivity
    test_basic_dns
    test_service_discovery
    test_dns_forwarding
    test_dns_performance
    test_dns_security
    test_health_integration
    test_service_mesh_dns
    
    # Generate final report
    generate_report
}

# Cleanup function for script interruption
cleanup() {
    cleanup_test_service
    cleanup_unhealthy_service
    log "Test script interrupted. Cleaned up test services."
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"