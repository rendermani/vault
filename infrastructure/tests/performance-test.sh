#!/bin/bash

# Performance Test Suite for Cloudya Vault Infrastructure
# Load testing and performance validation

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
PERF_RESULTS_FILE="/tmp/performance_test_results.json"
PERF_LOG_FILE="/tmp/performance_test.log"

# Performance thresholds (in milliseconds)
RESPONSE_TIME_THRESHOLD=2000
PAGE_LOAD_THRESHOLD=5000
API_RESPONSE_THRESHOLD=1000

# Initialize results
echo '{"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'","performance_tests":{},"metrics":{"response_times":[],"throughput":[],"availability":[]},"summary":{"avg_response_time":0,"max_response_time":0,"min_response_time":0,"total_requests":0,"failed_requests":0}}' > "$PERF_RESULTS_FILE"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$PERF_LOG_FILE"
}

perf_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}" | tee -a "$PERF_LOG_FILE"
    update_perf_result "$2" "pass" "$1"
}

perf_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}" | tee -a "$PERF_LOG_FILE"
    update_perf_result "$2" "fail" "$1"
}

perf_warning() {
    echo -e "${YELLOW}⚠ SLOW: $1${NC}" | tee -a "$PERF_LOG_FILE"
    update_perf_result "$2" "warning" "$1"
}

update_perf_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local response_time="${4:-0}"
    
    # Update JSON results
    jq --arg name "$test_name" --arg status "$status" --arg msg "$message" --argjson rt "$response_time" \
       '.performance_tests[$name] = {"status": $status, "message": $msg, "response_time": $rt, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
       "$PERF_RESULTS_FILE" > "${PERF_RESULTS_FILE}.tmp" && mv "${PERF_RESULTS_FILE}.tmp" "$PERF_RESULTS_FILE"
}

measure_response_time() {
    local url="$1"
    local method="${2:-GET}"
    local timeout="${3:-10}"
    
    # Use curl to measure response time
    local response_time=$(curl -s -w "%{time_total}" -o /dev/null --max-time "$timeout" --connect-timeout 5 "$url" 2>/dev/null || echo "timeout")
    
    if [ "$response_time" = "timeout" ]; then
        echo "timeout"
    else
        # Convert to milliseconds
        echo "$response_time * 1000" | bc -l | cut -d. -f1
    fi
}

test_response_times() {
    local service_name="$1"
    local url="$2"
    local test_name="response_time_${service_name}"
    
    log "Testing response times for $service_name"
    
    local total_time=0
    local successful_requests=0
    local failed_requests=0
    local min_time=999999
    local max_time=0
    
    # Perform 10 requests to get average
    for i in {1..10}; do
        local response_time=$(measure_response_time "$url")
        
        if [ "$response_time" = "timeout" ]; then
            failed_requests=$((failed_requests + 1))
            log "Request $i to $service_name: TIMEOUT"
        else
            successful_requests=$((successful_requests + 1))
            total_time=$((total_time + response_time))
            
            if [ "$response_time" -lt "$min_time" ]; then
                min_time="$response_time"
            fi
            
            if [ "$response_time" -gt "$max_time" ]; then
                max_time="$response_time"
            fi
            
            log "Request $i to $service_name: ${response_time}ms"
        fi
        
        sleep 0.1  # Small delay between requests
    done
    
    if [ "$successful_requests" -gt 0 ]; then
        local avg_time=$((total_time / successful_requests))
        
        # Update summary statistics
        jq --argjson avg "$avg_time" --argjson max "$max_time" --argjson min "$min_time" --argjson total "$successful_requests" --argjson failed "$failed_requests" \
           '.summary.avg_response_time = $avg | .summary.max_response_time = $max | .summary.min_response_time = $min | .summary.total_requests += $total | .summary.failed_requests += $failed' \
           "$PERF_RESULTS_FILE" > "${PERF_RESULTS_FILE}.tmp" && mv "${PERF_RESULTS_FILE}.tmp" "$PERF_RESULTS_FILE"
        
        if [ "$avg_time" -lt "$RESPONSE_TIME_THRESHOLD" ]; then
            perf_pass "Average response time for $service_name: ${avg_time}ms (threshold: ${RESPONSE_TIME_THRESHOLD}ms)" "$test_name" "$avg_time"
        elif [ "$avg_time" -lt $((RESPONSE_TIME_THRESHOLD * 2)) ]; then
            perf_warning "Average response time for $service_name: ${avg_time}ms (threshold: ${RESPONSE_TIME_THRESHOLD}ms)" "$test_name" "$avg_time"
        else
            perf_fail "Average response time for $service_name: ${avg_time}ms exceeds threshold (${RESPONSE_TIME_THRESHOLD}ms)" "$test_name" "$avg_time"
        fi
        
        log "  Min: ${min_time}ms, Max: ${max_time}ms, Avg: ${avg_time}ms, Success: $successful_requests/10, Failed: $failed_requests/10"
    else
        perf_fail "All requests to $service_name failed" "$test_name" "0"
    fi
}

test_concurrent_requests() {
    local service_name="$1"
    local url="$2"
    local concurrent_users="${3:-5}"
    local test_name="concurrent_${service_name}"
    
    log "Testing concurrent requests to $service_name with $concurrent_users concurrent users"
    
    # Create temporary file for concurrent test results
    local temp_results="/tmp/concurrent_test_$service_name.txt"
    rm -f "$temp_results"
    
    # Launch concurrent requests
    for i in $(seq 1 "$concurrent_users"); do
        {
            local response_time=$(measure_response_time "$url")
            echo "$response_time" >> "$temp_results"
        } &
    done
    
    # Wait for all requests to complete
    wait
    
    # Analyze results
    local successful_concurrent=0
    local failed_concurrent=0
    local total_concurrent_time=0
    
    if [ -f "$temp_results" ]; then
        while read -r time; do
            if [ "$time" = "timeout" ]; then
                failed_concurrent=$((failed_concurrent + 1))
            else
                successful_concurrent=$((successful_concurrent + 1))
                total_concurrent_time=$((total_concurrent_time + time))
            fi
        done < "$temp_results"
        
        rm -f "$temp_results"
    fi
    
    if [ "$successful_concurrent" -gt 0 ]; then
        local avg_concurrent_time=$((total_concurrent_time / successful_concurrent))
        local success_rate=$((successful_concurrent * 100 / concurrent_users))
        
        if [ "$success_rate" -ge 95 ] && [ "$avg_concurrent_time" -lt $((RESPONSE_TIME_THRESHOLD * 2)) ]; then
            perf_pass "Concurrent test for $service_name: ${success_rate}% success rate, ${avg_concurrent_time}ms avg response" "$test_name"
        elif [ "$success_rate" -ge 80 ]; then
            perf_warning "Concurrent test for $service_name: ${success_rate}% success rate, ${avg_concurrent_time}ms avg response" "$test_name"
        else
            perf_fail "Concurrent test for $service_name: ${success_rate}% success rate, ${avg_concurrent_time}ms avg response" "$test_name"
        fi
    else
        perf_fail "All concurrent requests to $service_name failed" "$test_name"
    fi
}

test_api_performance() {
    local service_name="$1"
    local api_url="$2"
    local test_name="api_perf_${service_name}"
    
    log "Testing API performance for $service_name"
    
    # Test different API endpoints if available
    local endpoints=()
    
    case "$service_name" in
        "vault")
            endpoints=("/v1/sys/health" "/v1/sys/seal-status")
            ;;
        "consul")
            endpoints=("/v1/status/leader" "/v1/catalog/services")
            ;;
        "traefik")
            endpoints=("/api/overview" "/ping")
            ;;
    esac
    
    local total_api_time=0
    local successful_api_requests=0
    
    for endpoint in "${endpoints[@]}"; do
        local full_url="$api_url$endpoint"
        local api_response_time=$(measure_response_time "$full_url")
        
        if [ "$api_response_time" != "timeout" ]; then
            successful_api_requests=$((successful_api_requests + 1))
            total_api_time=$((total_api_time + api_response_time))
            
            if [ "$api_response_time" -lt "$API_RESPONSE_THRESHOLD" ]; then
                log "  API endpoint $endpoint: ${api_response_time}ms (GOOD)"
            else
                log "  API endpoint $endpoint: ${api_response_time}ms (SLOW)"
            fi
        else
            log "  API endpoint $endpoint: TIMEOUT"
        fi
    done
    
    if [ "$successful_api_requests" -gt 0 ]; then
        local avg_api_time=$((total_api_time / successful_api_requests))
        
        if [ "$avg_api_time" -lt "$API_RESPONSE_THRESHOLD" ]; then
            perf_pass "API performance for $service_name: ${avg_api_time}ms average (threshold: ${API_RESPONSE_THRESHOLD}ms)" "$test_name"
        else
            perf_warning "API performance for $service_name: ${avg_api_time}ms average exceeds threshold (${API_RESPONSE_THRESHOLD}ms)" "$test_name"
        fi
    else
        perf_fail "All API requests to $service_name failed" "$test_name"
    fi
}

test_ssl_handshake_performance() {
    local service_name="$1"
    local hostname="$2"
    local test_name="ssl_handshake_${service_name}"
    
    log "Testing SSL handshake performance for $service_name"
    
    # Measure SSL handshake time
    local handshake_times=()
    local total_handshake_time=0
    local successful_handshakes=0
    
    for i in {1..5}; do
        local handshake_time=$(curl -s -w "%{time_connect}:%{time_appconnect}" -o /dev/null "https://$hostname" 2>/dev/null | cut -d: -f2)
        
        if [ -n "$handshake_time" ] && [ "$handshake_time" != "0.000000" ]; then
            local handshake_ms=$(echo "$handshake_time * 1000" | bc -l | cut -d. -f1)
            handshake_times+=("$handshake_ms")
            total_handshake_time=$((total_handshake_time + handshake_ms))
            successful_handshakes=$((successful_handshakes + 1))
            log "  SSL handshake $i: ${handshake_ms}ms"
        fi
        
        sleep 0.1
    done
    
    if [ "$successful_handshakes" -gt 0 ]; then
        local avg_handshake_time=$((total_handshake_time / successful_handshakes))
        
        if [ "$avg_handshake_time" -lt 500 ]; then
            perf_pass "SSL handshake for $service_name: ${avg_handshake_time}ms average (excellent)" "$test_name"
        elif [ "$avg_handshake_time" -lt 1000 ]; then
            perf_pass "SSL handshake for $service_name: ${avg_handshake_time}ms average (good)" "$test_name"
        elif [ "$avg_handshake_time" -lt 2000 ]; then
            perf_warning "SSL handshake for $service_name: ${avg_handshake_time}ms average (slow)" "$test_name"
        else
            perf_fail "SSL handshake for $service_name: ${avg_handshake_time}ms average (very slow)" "$test_name"
        fi
    else
        perf_fail "All SSL handshake attempts to $service_name failed" "$test_name"
    fi
}

test_availability() {
    local service_name="$1"
    local url="$2"
    local test_name="availability_${service_name}"
    
    log "Testing availability for $service_name over 60 seconds"
    
    local total_checks=60
    local successful_checks=0
    
    for i in $(seq 1 "$total_checks"); do
        local status_code=$(curl -s -w "%{http_code}" -o /dev/null --max-time 5 "$url" 2>/dev/null || echo "000")
        
        if [[ "$status_code" =~ ^[23] ]]; then
            successful_checks=$((successful_checks + 1))
        fi
        
        if [ $((i % 10)) -eq 0 ]; then
            log "  Availability check: $successful_checks/$i successful"
        fi
        
        sleep 1
    done
    
    local availability_percentage=$((successful_checks * 100 / total_checks))
    
    # Add to metrics
    jq --arg service "$service_name" --argjson avail "$availability_percentage" \
       '.metrics.availability += [{"service": $service, "percentage": $avail}]' \
       "$PERF_RESULTS_FILE" > "${PERF_RESULTS_FILE}.tmp" && mv "${PERF_RESULTS_FILE}.tmp" "$PERF_RESULTS_FILE"
    
    if [ "$availability_percentage" -ge 99 ]; then
        perf_pass "Availability for $service_name: ${availability_percentage}% (excellent)" "$test_name"
    elif [ "$availability_percentage" -ge 95 ]; then
        perf_pass "Availability for $service_name: ${availability_percentage}% (good)" "$test_name"
    elif [ "$availability_percentage" -ge 90 ]; then
        perf_warning "Availability for $service_name: ${availability_percentage}% (acceptable)" "$test_name"
    else
        perf_fail "Availability for $service_name: ${availability_percentage}% (poor)" "$test_name"
    fi
}

generate_performance_report() {
    log "Generating comprehensive performance report"
    
    # Read results and generate summary
    local results=$(cat "$PERF_RESULTS_FILE")
    local avg_response=$(echo "$results" | jq '.summary.avg_response_time')
    local max_response=$(echo "$results" | jq '.summary.max_response_time')
    local min_response=$(echo "$results" | jq '.summary.min_response_time')
    local total_requests=$(echo "$results" | jq '.summary.total_requests')
    local failed_requests=$(echo "$results" | jq '.summary.failed_requests')
    local success_rate=$(echo "scale=2; ($total_requests - $failed_requests) * 100 / $total_requests" | bc -l 2>/dev/null || echo "0")
    
    echo
    echo "========================================="
    echo "       PERFORMANCE TEST SUMMARY"
    echo "========================================="
    echo "Total Requests:     $total_requests"
    echo "Failed Requests:    $failed_requests"
    echo "Success Rate:       ${success_rate}%"
    echo "Average Response:   ${avg_response}ms"
    echo "Min Response:       ${min_response}ms"
    echo "Max Response:       ${max_response}ms"
    echo
    
    # Performance grade
    if [ "$avg_response" -lt 500 ] && [ "$(echo "$success_rate >= 99" | bc -l)" = "1" ]; then
        echo -e "${GREEN}🚀 EXCELLENT PERFORMANCE! All systems performing optimally.${NC}"
    elif [ "$avg_response" -lt 1000 ] && [ "$(echo "$success_rate >= 95" | bc -l)" = "1" ]; then
        echo -e "${GREEN}✅ Good performance with room for minor optimizations.${NC}"
    elif [ "$avg_response" -lt 2000 ] && [ "$(echo "$success_rate >= 90" | bc -l)" = "1" ]; then
        echo -e "${YELLOW}⚠️  Acceptable performance but optimization recommended.${NC}"
    else
        echo -e "${RED}🐌 Performance issues detected. Investigation and optimization required.${NC}"
    fi
    
    # Availability summary
    echo
    echo "Service Availability:"
    echo "$results" | jq -r '.metrics.availability[]? | "• " + .service + ": " + (.percentage|tostring) + "%"'
    
    echo
    echo "Detailed performance results saved to: $PERF_RESULTS_FILE"
    echo "Performance test log saved to: $PERF_LOG_FILE"
    echo
}

# Main execution
main() {
    log "Starting Cloudya Vault Infrastructure Performance Tests"
    log "======================================================="
    
    # Clean up previous results
    rm -f "$PERF_LOG_FILE"
    
    # Install bc for calculations if not available
    if ! command -v bc &> /dev/null; then
        log "Installing bc for calculations..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y bc
        elif command -v yum &> /dev/null; then
            sudo yum install -y bc
        elif command -v brew &> /dev/null; then
            brew install bc
        fi
    fi
    
    # Response time tests
    test_response_times "vault" "$VAULT_URL"
    test_response_times "consul" "$CONSUL_URL"
    test_response_times "traefik" "$TRAEFIK_URL"
    
    # SSL handshake performance
    test_ssl_handshake_performance "vault" "vault.cloudya.net"
    test_ssl_handshake_performance "consul" "consul.cloudya.net"
    test_ssl_handshake_performance "traefik" "traefik.cloudya.net"
    
    # API performance tests
    test_api_performance "vault" "$VAULT_URL"
    test_api_performance "consul" "$CONSUL_URL"
    test_api_performance "traefik" "$TRAEFIK_URL"
    
    # Concurrent request tests
    test_concurrent_requests "vault" "$VAULT_URL" 5
    test_concurrent_requests "consul" "$CONSUL_URL" 5
    test_concurrent_requests "traefik" "$TRAEFIK_URL" 5
    
    # Availability tests (run in parallel to save time)
    {
        test_availability "vault" "$VAULT_URL" &
        test_availability "consul" "$CONSUL_URL" &
        test_availability "traefik" "$TRAEFIK_URL" &
        wait
    }
    
    # Generate final performance report
    generate_performance_report
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi