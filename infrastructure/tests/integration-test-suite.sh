#!/bin/bash

# Comprehensive Infrastructure Integration Test Suite
# Tests all components and their integrations across the stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-develop}"
TEST_RESULTS_DIR="$INFRA_DIR/test-results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TEST_LIST=()

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    FAILED_TEST_LIST+=("$1")
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_test "Running: $test_name"
    ((TOTAL_TESTS++))
    
    if $test_function; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name"
        return 1
    fi
}

# Vault Tests
test_vault_health() {
    curl -sf "http://localhost:8200/v1/sys/health" > /dev/null 2>&1
}

test_vault_sealed_status() {
    local sealed_status=$(curl -s "http://localhost:8200/v1/sys/seal-status" | jq -r '.sealed')
    [[ "$sealed_status" == "false" ]]
}

test_vault_secret_engines() {
    vault secrets list | grep -q "secret/"
    vault secrets list | grep -q "nomad-secrets/"
    vault secrets list | grep -q "traefik-secrets/"
}

test_vault_policies() {
    vault policy list | grep -q "nomad-policy"
    vault policy list | grep -q "traefik-policy"
}

test_vault_secret_operations() {
    # Test write and read operations
    local test_secret="test-$(date +%s)"
    vault kv put secret/test-data value="$test_secret"
    local retrieved=$(vault kv get -field=value secret/test-data)
    [[ "$retrieved" == "$test_secret" ]]
    vault kv delete secret/test-data
}

test_vault_auth_methods() {
    vault auth list | grep -q "token/"
    # Add other auth methods based on configuration
}

# Nomad Tests
test_nomad_health() {
    curl -sf "http://localhost:4646/v1/status/leader" > /dev/null 2>&1
}

test_nomad_leader_election() {
    local leader=$(curl -s "http://localhost:4646/v1/status/leader")
    [[ -n "$leader" ]]
}

test_nomad_nodes() {
    local node_count=$(nomad node status -json | jq '. | length')
    [[ "$node_count" -gt 0 ]]
}

test_nomad_vault_integration() {
    # Check if Nomad can communicate with Vault
    nomad server members | grep -q "alive"
    
    # Test token creation via Vault
    local test_token=$(vault write -field=token auth/token/create policies=nomad-policy)
    [[ -n "$test_token" ]]
}

test_nomad_job_lifecycle() {
    # Create a simple test job
    cat > /tmp/test-job.nomad <<EOF
job "test-job" {
  datacenters = ["dc1"]
  type = "batch"
  
  group "test-group" {
    task "test-task" {
      driver = "raw_exec"
      config {
        command = "echo"
        args = ["Hello World"]
      }
      resources {
        cpu = 100
        memory = 64
      }
    }
  }
}
EOF
    
    # Run job and verify completion
    nomad job run /tmp/test-job.nomad
    sleep 5
    local job_status=$(nomad job status test-job | grep "Status" | awk '{print $3}')
    nomad job stop test-job
    rm /tmp/test-job.nomad
    
    [[ "$job_status" == "dead" ]] # Batch job should be dead after completion
}

test_nomad_acl_system() {
    if nomad acl token list > /dev/null 2>&1; then
        return 0  # ACLs are working
    else
        return 1  # ACLs not properly configured
    fi
}

# Traefik Tests
test_traefik_health() {
    curl -sf "http://localhost:8080/ping" > /dev/null 2>&1
}

test_traefik_api_access() {
    local response=$(curl -s "http://localhost:8080/api/version")
    echo "$response" | jq -r '.Version' | grep -q "^[0-9]"
}

test_traefik_dashboard() {
    # Check if dashboard is accessible (depending on environment)
    if [[ "$ENVIRONMENT" != "production" ]]; then
        curl -sf "http://localhost:8080/dashboard/" > /dev/null 2>&1
    else
        # Dashboard should be disabled in production
        ! curl -sf "http://localhost:8080/dashboard/" > /dev/null 2>&1
    fi
}

test_traefik_vault_integration() {
    # Test if Traefik can read secrets from Vault
    local dashboard_creds=$(vault kv get -json traefik-secrets/dashboard)
    echo "$dashboard_creds" | jq -r '.data.data.username' | grep -q "admin"
}

test_traefik_service_discovery() {
    # Check if Traefik can discover services via Nomad
    local services=$(curl -s "http://localhost:8080/api/http/services")
    echo "$services" | jq '. | length' | grep -q -v "^0$"
}

test_traefik_routing() {
    # Test basic routing functionality
    # This would need a test service deployed via Nomad
    log_skip "Routing test requires deployed services"
    return 0
}

# Integration Tests
test_vault_nomad_secret_injection() {
    # Test that Nomad jobs can retrieve secrets from Vault
    cat > /tmp/vault-integration-job.nomad <<EOF
job "vault-integration-test" {
  datacenters = ["dc1"]
  type = "batch"
  
  group "vault-test" {
    task "secret-reader" {
      driver = "raw_exec"
      
      vault {
        policies = ["nomad-policy"]
      }
      
      template {
        data = <<EOH
{{with secret "secret/test-integration"}}
TEST_SECRET={{.Data.data.value}}
{{end}}
EOH
        destination = "secrets/test.env"
        env = true
      }
      
      config {
        command = "sh"
        args = ["-c", "echo $TEST_SECRET | grep -q 'integration-test-value'"]
      }
      
      resources {
        cpu = 100
        memory = 64
      }
    }
  }
}
EOF
    
    # Setup test secret in Vault
    vault kv put secret/test-integration value="integration-test-value"
    
    # Run the job
    nomad job run /tmp/vault-integration-job.nomad
    sleep 10
    
    # Check job completion
    local job_status=$(nomad job status vault-integration-test | grep "Status" | awk '{print $3}')
    
    # Cleanup
    nomad job stop vault-integration-test
    vault kv delete secret/test-integration
    rm /tmp/vault-integration-job.nomad
    
    [[ "$job_status" == "dead" ]]
}

test_end_to_end_workflow() {
    log_test "Running end-to-end workflow test"
    
    # 1. Store a secret in Vault
    local test_value="e2e-test-$(date +%s)"
    vault kv put secret/e2e-test workflow="complete" value="$test_value"
    
    # 2. Deploy a job via Nomad that uses the secret
    cat > /tmp/e2e-test-job.nomad <<EOF
job "e2e-workflow-test" {
  datacenters = ["dc1"]
  type = "service"
  
  group "web" {
    count = 1
    
    network {
      port "http" {
        to = 8080
      }
    }
    
    service {
      name = "e2e-test-service"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.e2e-test.rule=PathPrefix(\`/e2e-test\`)"
      ]
      
      check {
        type = "http"
        path = "/health"
        interval = "10s"
        timeout = "3s"
      }
    }
    
    task "web-server" {
      driver = "raw_exec"
      
      vault {
        policies = ["nomad-policy"]
      }
      
      template {
        data = <<EOH
{{with secret "secret/e2e-test"}}
SECRET_VALUE={{.Data.data.value}}
{{end}}
EOH
        destination = "secrets/app.env"
        env = true
      }
      
      config {
        command = "python3"
        args = ["-c", "
import http.server
import socketserver
import os

class TestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
        elif self.path == '/e2e-test':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            secret = os.environ.get('SECRET_VALUE', 'not-found')
            response = f'{{\"secret\": \"{secret}\", \"status\": \"success\"}}'
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(('', 8080), TestHandler) as httpd:
    httpd.serve_forever()
"]
      }
      
      resources {
        cpu = 200
        memory = 128
      }
    }
  }
}
EOF
    
    # Deploy the job
    nomad job run /tmp/e2e-test-job.nomad
    sleep 15  # Wait for deployment and service registration
    
    # 3. Test via Traefik routing
    local response=$(curl -s "http://localhost:80/e2e-test" || echo '{"secret": "failed"}')
    local secret_value=$(echo "$response" | jq -r '.secret')
    
    # Cleanup
    nomad job stop e2e-workflow-test
    vault kv delete secret/e2e-test
    rm /tmp/e2e-test-job.nomad
    
    [[ "$secret_value" == "$test_value" ]]
}

# Performance Tests
test_vault_performance() {
    log_test "Running Vault performance baseline"
    
    # Simple performance test - measure secret write/read operations
    local start_time=$(date +%s)
    for i in {1..100}; do
        vault kv put secret/perf-test-$i value="test-value-$i" > /dev/null 2>&1
    done
    local write_time=$(($(date +%s) - start_time))
    
    start_time=$(date +%s)
    for i in {1..100}; do
        vault kv get secret/perf-test-$i > /dev/null 2>&1
    done
    local read_time=$(($(date +%s) - start_time))
    
    # Cleanup
    for i in {1..100}; do
        vault kv delete secret/perf-test-$i > /dev/null 2>&1
    done
    
    echo "Vault Performance: 100 writes in ${write_time}s, 100 reads in ${read_time}s"
    
    # Basic performance thresholds (adjust based on requirements)
    [[ $write_time -lt 30 && $read_time -lt 15 ]]
}

test_nomad_performance() {
    log_test "Running Nomad performance baseline"
    
    # Test job scheduling performance
    local start_time=$(date +%s)
    
    # Submit multiple batch jobs
    for i in {1..10}; do
        cat > /tmp/perf-test-job-$i.nomad <<EOF
job "perf-test-$i" {
  datacenters = ["dc1"]
  type = "batch"
  
  group "test" {
    task "echo" {
      driver = "raw_exec"
      config {
        command = "echo"
        args = ["Performance test $i"]
      }
      resources {
        cpu = 50
        memory = 32
      }
    }
  }
}
EOF
        nomad job run /tmp/perf-test-job-$i.nomad > /dev/null 2>&1
    done
    
    # Wait for all jobs to complete
    local all_complete=false
    local timeout=60
    local elapsed=0
    
    while [[ $elapsed -lt $timeout && "$all_complete" == "false" ]]; do
        all_complete=true
        for i in {1..10}; do
            local status=$(nomad job status perf-test-$i | grep "Status" | awk '{print $3}')
            if [[ "$status" != "dead" ]]; then
                all_complete=false
                break
            fi
        done
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    local total_time=$(($(date +%s) - start_time))
    
    # Cleanup
    for i in {1..10}; do
        nomad job stop perf-test-$i > /dev/null 2>&1
        rm -f /tmp/perf-test-job-$i.nomad
    done
    
    echo "Nomad Performance: 10 batch jobs completed in ${total_time}s"
    
    # Performance threshold
    [[ $total_time -lt 30 ]]
}

# Security Tests
test_vault_security() {
    log_test "Running Vault security checks"
    
    # Test that root token is not permanently stored
    if [[ -z "${VAULT_TOKEN:-}" ]] || [[ "${VAULT_TOKEN:-}" == "root" ]]; then
        return 1  # Root token should not be in environment
    fi
    
    # Test that audit logging is enabled
    vault audit list | grep -q "file/"
    
    # Test that TLS is properly configured (if not dev mode)
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        vault status | grep -q "Cluster Address.*https"
    fi
}

test_nomad_security() {
    log_test "Running Nomad security checks"
    
    # Test that ACLs are enabled
    nomad acl bootstrap -check > /dev/null 2>&1
    
    # Test that TLS is configured (if not dev mode)
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        nomad status | grep -q "https://"
    fi
}

test_traefik_security() {
    log_test "Running Traefik security checks"
    
    # Test that dashboard is properly secured in non-dev environments
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        # Dashboard should require authentication or be disabled
        local dashboard_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/dashboard/")
        [[ "$dashboard_response" == "401" || "$dashboard_response" == "404" ]]
    fi
    
    # Test security headers (if configured)
    local headers=$(curl -sI "http://localhost:8080/ping")
    echo "$headers" | grep -q "X-Content-Type-Options"
}

# Main test execution
main() {
    echo "======================================"
    echo "Infrastructure Integration Test Suite"
    echo "Environment: $ENVIRONMENT"
    echo "======================================"
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Individual component tests
    echo -e "\n${BLUE}=== Vault Tests ===${NC}"
    run_test "Vault Health Check" test_vault_health
    run_test "Vault Seal Status" test_vault_sealed_status
    run_test "Vault Secret Engines" test_vault_secret_engines
    run_test "Vault Policies" test_vault_policies
    run_test "Vault Secret Operations" test_vault_secret_operations
    run_test "Vault Auth Methods" test_vault_auth_methods
    run_test "Vault Security" test_vault_security
    
    echo -e "\n${BLUE}=== Nomad Tests ===${NC}"
    run_test "Nomad Health Check" test_nomad_health
    run_test "Nomad Leader Election" test_nomad_leader_election
    run_test "Nomad Nodes" test_nomad_nodes
    run_test "Nomad Vault Integration" test_nomad_vault_integration
    run_test "Nomad Job Lifecycle" test_nomad_job_lifecycle
    run_test "Nomad ACL System" test_nomad_acl_system
    run_test "Nomad Security" test_nomad_security
    
    echo -e "\n${BLUE}=== Traefik Tests ===${NC}"
    run_test "Traefik Health Check" test_traefik_health
    run_test "Traefik API Access" test_traefik_api_access
    run_test "Traefik Dashboard" test_traefik_dashboard
    run_test "Traefik Vault Integration" test_traefik_vault_integration
    run_test "Traefik Service Discovery" test_traefik_service_discovery
    run_test "Traefik Security" test_traefik_security
    
    echo -e "\n${BLUE}=== Integration Tests ===${NC}"
    run_test "Vault-Nomad Secret Injection" test_vault_nomad_secret_injection
    run_test "End-to-End Workflow" test_end_to_end_workflow
    
    echo -e "\n${BLUE}=== Performance Tests ===${NC}"
    run_test "Vault Performance Baseline" test_vault_performance
    run_test "Nomad Performance Baseline" test_nomad_performance
    
    # Generate test report
    echo -e "\n======================================"
    echo "Test Results Summary"
    echo "======================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "\n${RED}Failed Tests:${NC}"
        for test in "${FAILED_TEST_LIST[@]}"; do
            echo "  - $test"
        done
        echo ""
        exit 1
    else
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Run the test suite
main "$@"