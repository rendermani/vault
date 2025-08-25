#!/bin/bash

# Nomad Cluster Formation Integration Tests
# Tests Nomad cluster initialization, node joining, and leader election

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
NOMAD_CLIENT_PORT="${NOMAD_CLIENT_PORT:-4647}"
NOMAD_SERF_PORT="${NOMAD_SERF_PORT:-4648}"
NOMAD_DATA_DIR="${NOMAD_DATA_DIR:-/opt/nomad/data}"
NOMAD_CONFIG_DIR="${NOMAD_CONFIG_DIR:-/etc/nomad.d}"

# Test helper functions
get_nomad_status() {
    nomad status 2>/dev/null || echo "ERROR"
}

get_nomad_leader() {
    nomad status -json 2>/dev/null | jq -r '.Leader // "none"' 2>/dev/null || echo "none"
}

get_nomad_nodes() {
    nomad node status -json 2>/dev/null | jq -r '.[].Name' 2>/dev/null || echo ""
}

get_nomad_node_count() {
    nomad node status -json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0"
}

check_nomad_connectivity() {
    curl -s -f "$NOMAD_ADDR/v1/status/leader" >/dev/null 2>&1
}

# Test functions
test_nomad_installation() {
    log_info "Testing Nomad installation"
    
    # Check if nomad binary exists
    assert_command_success "command -v nomad" "Nomad binary not found"
    
    # Check version
    local version
    version=$(nomad version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "unknown")
    assert_not_equals "unknown" "$version" "Could not determine Nomad version"
    
    log_success "Nomad installation verified - version: $version"
}

test_nomad_configuration() {
    log_info "Testing Nomad configuration"
    
    # Check configuration directory exists
    assert_dir_exists "$NOMAD_CONFIG_DIR" "Nomad config directory missing"
    
    # Check for main configuration file
    local config_files=("nomad.hcl" "server.hcl" "client.hcl")
    local found_config=false
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$NOMAD_CONFIG_DIR/$config_file" ]]; then
            found_config=true
            log_debug "Found config file: $config_file"
            
            # Validate configuration syntax
            assert_command_success "nomad config validate $NOMAD_CONFIG_DIR/$config_file" \
                "Configuration validation failed for $config_file"
        fi
    done
    
    assert_true "$found_config" "No Nomad configuration files found"
    
    log_success "Nomad configuration validated"
}

test_nomad_service_status() {
    log_info "Testing Nomad service status"
    
    # Check if Nomad service exists
    assert_command_success "systemctl list-units --all | grep -q nomad" \
        "Nomad service not found"
    
    # Check if Nomad is running
    assert_service_running "nomad" "Nomad service is not running"
    
    # Check service enabled status
    if systemctl is-enabled nomad >/dev/null 2>&1; then
        log_debug "Nomad service is enabled for startup"
    else
        log_warning "Nomad service is not enabled for startup"
    fi
    
    log_success "Nomad service status verified"
}

test_nomad_connectivity() {
    log_info "Testing Nomad API connectivity"
    
    # Wait for Nomad to be ready
    wait_for_http_endpoint "$NOMAD_ADDR/v1/status/leader" 200 60
    
    # Test API endpoints
    assert_http_status "$NOMAD_ADDR/v1/status/leader" 200 "Leader endpoint not responding"
    assert_http_status "$NOMAD_ADDR/v1/nodes" 200 "Nodes endpoint not responding"
    assert_http_status "$NOMAD_ADDR/v1/status/peers" 200 "Peers endpoint not responding"
    
    log_success "Nomad API connectivity verified"
}

test_nomad_cluster_formation() {
    log_info "Testing Nomad cluster formation"
    
    # Check if cluster has a leader
    local leader
    leader=$(get_nomad_leader)
    assert_not_equals "none" "$leader" "No cluster leader found"
    
    log_debug "Cluster leader: $leader"
    
    # Verify leader is accessible
    assert_command_success "curl -s -f $NOMAD_ADDR/v1/status/leader" \
        "Cannot connect to cluster leader"
    
    log_success "Nomad cluster formation verified"
}

test_nomad_node_registration() {
    log_info "Testing Nomad node registration"
    
    # Get node count
    local node_count
    node_count=$(get_nomad_node_count)
    local node_count_int=$((node_count))
    
    assert_true "$((node_count_int >= 1))" "No nodes registered in cluster"
    
    log_debug "Registered nodes: $node_count"
    
    # Check node details
    local nodes
    nodes=$(get_nomad_nodes)
    
    if [[ -n "$nodes" ]]; then
        while IFS= read -r node; do
            if [[ -n "$node" ]]; then
                log_debug "Node registered: $node"
                
                # Check node status
                local node_status
                node_status=$(nomad node status "$node" -json 2>/dev/null | jq -r '.Status // "unknown"')
                assert_equals "ready" "$node_status" "Node $node is not ready (status: $node_status)"
            fi
        done <<< "$nodes"
    fi
    
    log_success "Nomad node registration verified"
}

test_nomad_datacenter_configuration() {
    log_info "Testing Nomad datacenter configuration"
    
    # Check datacenter configuration
    local datacenters
    datacenters=$(nomad status -json 2>/dev/null | jq -r '.Datacenters[]?' 2>/dev/null || echo "")
    
    assert_not_equals "" "$datacenters" "No datacenters configured"
    
    # Check for expected datacenter
    assert_contains "$datacenters" "dc1" "Default datacenter 'dc1' not found"
    
    log_debug "Configured datacenters: $(echo "$datacenters" | tr '\n' ' ')"
    log_success "Nomad datacenter configuration verified"
}

test_nomad_raft_peers() {
    log_info "Testing Nomad Raft peer configuration"
    
    # Get raft peers
    local peers
    peers=$(curl -s "$NOMAD_ADDR/v1/status/peers" 2>/dev/null || echo "[]")
    
    local peer_count
    peer_count=$(echo "$peers" | jq '. | length' 2>/dev/null || echo "0")
    
    assert_true "$((peer_count >= 1))" "No Raft peers found"
    
    log_debug "Raft peers: $(echo "$peers" | jq -c .)"
    log_success "Nomad Raft peer configuration verified"
}

test_nomad_ports() {
    log_info "Testing Nomad port accessibility"
    
    # Extract host from NOMAD_ADDR
    local nomad_host
    nomad_host=$(echo "$NOMAD_ADDR" | sed 's|http://||' | sed 's|https://||' | cut -d':' -f1)
    
    # Test main API port
    assert_port_open "$nomad_host" "4646" "Nomad API port not accessible"
    
    # Test client port (if running in mixed mode)
    if netstat -ln 2>/dev/null | grep -q ":$NOMAD_CLIENT_PORT "; then
        assert_port_open "$nomad_host" "$NOMAD_CLIENT_PORT" "Nomad client port not accessible"
    else
        log_debug "Nomad client port not bound (server-only mode)"
    fi
    
    # Test serf port
    if netstat -ln 2>/dev/null | grep -q ":$NOMAD_SERF_PORT "; then
        assert_port_open "$nomad_host" "$NOMAD_SERF_PORT" "Nomad serf port not accessible"
    else
        log_debug "Nomad serf port not bound"
    fi
    
    log_success "Nomad port accessibility verified"
}

test_nomad_data_directory() {
    log_info "Testing Nomad data directory"
    
    # Check data directory exists
    assert_dir_exists "$NOMAD_DATA_DIR" "Nomad data directory missing"
    
    # Check directory permissions
    local perms
    perms=$(stat -f "%Mp%Lp" "$NOMAD_DATA_DIR" 2>/dev/null || stat -c "%a" "$NOMAD_DATA_DIR" 2>/dev/null || echo "000")
    
    # Should be at least readable/writable by owner
    if [[ "$perms" =~ ^[67][0-7][0-7]$ ]] || [[ "$perms" =~ ^[67][0-7][0-7][0-7]$ ]]; then
        log_debug "Data directory permissions: $perms"
    else
        log_warning "Data directory permissions may be too restrictive: $perms"
    fi
    
    # Check for essential subdirectories
    local subdirs=("server" "client" "raft")
    for subdir in "${subdirs[@]}"; do
        if [[ -d "$NOMAD_DATA_DIR/$subdir" ]]; then
            log_debug "Found data subdirectory: $subdir"
        fi
    done
    
    log_success "Nomad data directory verified"
}

test_nomad_cluster_health() {
    log_info "Testing overall Nomad cluster health"
    
    # Comprehensive health check
    local health_checks=(
        "Leader election functional"
        "All nodes responsive"
        "Raft consensus working"
        "API endpoints accessible"
    )
    
    # Check leader stability
    local leader1 leader2
    leader1=$(get_nomad_leader)
    sleep 5
    leader2=$(get_nomad_leader)
    
    assert_equals "$leader1" "$leader2" "Leader election unstable"
    health_checks[0]="✓ Leader election stable"
    
    # Check all nodes are healthy
    local unhealthy_nodes
    unhealthy_nodes=$(nomad node status -json 2>/dev/null | \
        jq -r '.[] | select(.Status != "ready") | .Name' 2>/dev/null || echo "")
    
    assert_equals "" "$unhealthy_nodes" "Found unhealthy nodes: $unhealthy_nodes"
    health_checks[1]="✓ All nodes healthy"
    
    # Check Raft health
    local raft_error
    raft_error=$(nomad operator raft list-peers 2>&1 | grep -i error || echo "")
    
    assert_equals "" "$raft_error" "Raft consensus issues detected"
    health_checks[2]="✓ Raft consensus healthy"
    
    # Verify API responsiveness
    local api_response_time
    api_response_time=$(curl -w "%{time_total}" -o /dev/null -s "$NOMAD_ADDR/v1/status/leader" 2>/dev/null || echo "999")
    
    # Response time should be under 1 second
    assert_true "$(echo "$api_response_time < 1.0" | bc -l 2>/dev/null || echo 0)" \
        "API response time too slow: ${api_response_time}s"
    health_checks[3]="✓ API responsive (${api_response_time}s)"
    
    # Print health summary
    log_info "Cluster health summary:"
    for check in "${health_checks[@]}"; do
        log_info "  $check"
    done
    
    log_success "Nomad cluster health verification completed"
}

# Main test execution
main() {
    log_info "Starting Nomad Cluster Formation Tests"
    log_info "========================================"
    
    # Load test configuration
    load_test_config
    
    # Run tests in order
    run_test "Nomad Installation" "test_nomad_installation"
    run_test "Nomad Configuration" "test_nomad_configuration"
    run_test "Nomad Service Status" "test_nomad_service_status"
    run_test "Nomad Connectivity" "test_nomad_connectivity"
    run_test "Nomad Cluster Formation" "test_nomad_cluster_formation"
    run_test "Nomad Node Registration" "test_nomad_node_registration"
    run_test "Nomad Datacenter Config" "test_nomad_datacenter_configuration"
    run_test "Nomad Raft Peers" "test_nomad_raft_peers"
    run_test "Nomad Port Accessibility" "test_nomad_ports"
    run_test "Nomad Data Directory" "test_nomad_data_directory"
    run_test "Nomad Cluster Health" "test_nomad_cluster_health"
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi