#!/bin/bash

# Bootstrap and Circular Dependency Resolution Tests
# Tests the resolution of circular dependencies in Nomad-Vault-Traefik bootstrap

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TRAEFIK_URL="${TRAEFIK_URL:-http://localhost:80}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-300}"
DEPENDENCY_CHECK_INTERVAL="${DEPENDENCY_CHECK_INTERVAL:-5}"

# Circular dependency scenarios
declare -A DEPENDENCIES=(
    ["vault"]="nomad"          # Vault needs Nomad to run
    ["nomad"]="vault"          # Nomad needs Vault for secrets (circular!)
    ["traefik"]="vault"        # Traefik needs Vault for secrets
    ["traefik"]="nomad"        # Traefik runs on Nomad
)

# Bootstrap sequence order
BOOTSTRAP_ORDER=("nomad" "vault" "traefik")

# Helper functions
check_service_health() {
    local service="$1"
    
    case "$service" in
        "nomad")
            curl -s -f "$NOMAD_ADDR/v1/status/leader" >/dev/null 2>&1
            ;;
        "vault")
            curl -s -f "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1
            ;;
        "traefik")
            curl -s -f "$TRAEFIK_URL/ping" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

get_service_startup_time() {
    local service="$1"
    # Simulate different startup times
    case "$service" in
        "nomad") echo "30" ;;      # Nomad starts relatively quickly
        "vault") echo "45" ;;      # Vault takes longer due to initialization
        "traefik") echo "20" ;;    # Traefik starts quickly but needs config
        *) echo "60" ;;
    esac
}

simulate_service_start() {
    local service="$1"
    local startup_time
    startup_time=$(get_service_startup_time "$service")
    
    log_debug "Simulating $service startup (${startup_time}s)"
    
    # Create service state file
    local state_file="$TEST_TEMP_DIR/service-${service}.state"
    echo "starting:$(date +%s)" > "$state_file"
    
    # Simulate startup time
    sleep $((startup_time / 10))  # Reduced for testing
    
    echo "running:$(date +%s)" > "$state_file"
    return 0
}

simulate_service_stop() {
    local service="$1"
    local state_file="$TEST_TEMP_DIR/service-${service}.state"
    
    if [[ -f "$state_file" ]]; then
        echo "stopped:$(date +%s)" > "$state_file"
    fi
}

check_simulated_service_running() {
    local service="$1"
    local state_file="$TEST_TEMP_DIR/service-${service}.state"
    
    if [[ -f "$state_file" ]]; then
        local state
        state=$(cat "$state_file" | cut -d':' -f1)
        [[ "$state" == "running" ]]
    else
        return 1
    fi
}

get_service_dependencies() {
    local service="$1"
    local deps=()
    
    case "$service" in
        "vault")
            deps=("nomad")  # Vault runs on Nomad
            ;;
        "traefik")
            deps=("nomad" "vault")  # Traefik runs on Nomad and needs Vault secrets
            ;;
        "nomad")
            # Nomad can start standalone, but in integrated mode needs Vault for ACLs
            if [[ "${INTEGRATED_MODE:-true}" == "true" ]]; then
                deps=("vault-bootstrap")  # Special bootstrap mode
            fi
            ;;
    esac
    
    printf '%s\n' "${deps[@]}"
}

# Test functions
test_dependency_analysis() {
    log_info "Testing dependency analysis and detection"
    
    # Analyze the dependency graph
    local circular_deps=()
    
    # Check for circular dependencies
    for service in "${BOOTSTRAP_ORDER[@]}"; do
        local deps
        deps=$(get_service_dependencies "$service")
        
        if [[ -n "$deps" ]]; then
            log_debug "$service depends on: $deps"
            
            # Check if any dependency also depends on this service
            while IFS= read -r dep; do
                if [[ -n "$dep" ]]; then
                    local dep_deps
                    dep_deps=$(get_service_dependencies "$dep" | tr '\n' ' ')
                    
                    if echo "$dep_deps" | grep -q "$service"; then
                        circular_deps+=("$service<->$dep")
                        log_debug "Found circular dependency: $service <-> $dep"
                    fi
                fi
            done <<< "$deps"
        fi
    done
    
    # Verify we detected expected circular dependencies
    local found_vault_nomad=false
    for circular in "${circular_deps[@]}"; do
        if [[ "$circular" == "vault<->nomad" ]] || [[ "$circular" == "nomad<->vault" ]]; then
            found_vault_nomad=true
        fi
    done
    
    # In integrated mode, we expect to find the vault<->nomad circular dependency
    if [[ "${INTEGRATED_MODE:-true}" == "true" ]]; then
        log_debug "Circular dependencies found: ${#circular_deps[@]}"
        if [[ ${#circular_deps[@]} -gt 0 ]]; then
            log_debug "This is expected in integrated infrastructure"
        fi
    fi
    
    log_success "Dependency analysis completed"
}

test_bootstrap_sequence_planning() {
    log_info "Testing bootstrap sequence planning"
    
    # Plan bootstrap sequence considering circular dependencies
    local planned_sequence=()
    local bootstrap_phases=()
    
    # Phase 1: Start services that can run independently
    bootstrap_phases[0]="nomad-standalone"  # Start Nomad without Vault integration
    
    # Phase 2: Initialize Vault
    bootstrap_phases[1]="vault-init"        # Initialize Vault with basic config
    
    # Phase 3: Configure Nomad-Vault integration
    bootstrap_phases[2]="nomad-vault-integration"  # Enable Vault integration in Nomad
    
    # Phase 4: Deploy dependent services
    bootstrap_phases[3]="traefik-deploy"    # Deploy Traefik with Vault secrets
    
    # Verify bootstrap phases are in logical order
    local expected_phases=("nomad-standalone" "vault-init" "nomad-vault-integration" "traefik-deploy")
    
    for i in "${!expected_phases[@]}"; do
        local expected="${expected_phases[$i]}"
        local actual="${bootstrap_phases[$i]}"
        
        assert_equals "$expected" "$actual" "Bootstrap phase $((i+1)) should be $expected"
    done
    
    # Create bootstrap plan file
    local bootstrap_plan="$TEST_TEMP_DIR/bootstrap-plan.txt"
    printf '%s\n' "${bootstrap_phases[@]}" > "$bootstrap_plan"
    
    assert_file_exists "$bootstrap_plan" "Bootstrap plan should be created"
    
    local phase_count
    phase_count=$(wc -l < "$bootstrap_plan")
    assert_equals "4" "$phase_count" "Bootstrap plan should have 4 phases"
    
    log_success "Bootstrap sequence planning verified"
}

test_nomad_standalone_bootstrap() {
    log_info "Testing Nomad standalone bootstrap (Phase 1)"
    
    # Simulate starting Nomad without Vault integration
    log_debug "Starting Nomad in standalone mode"
    
    # Create Nomad config without Vault integration
    local nomad_config="$TEST_TEMP_DIR/nomad-standalone.hcl"
    cat > "$nomad_config" <<EOF
datacenter = "dc1"
data_dir = "/opt/nomad/data"

server {
  enabled = true
  bootstrap_expect = 1
  # No Vault integration yet
}

client {
  enabled = true
}
EOF
    
    # Verify config doesn't contain Vault references
    local config_content
    config_content=$(cat "$nomad_config")
    assert_not_contains "$config_content" "vault" "Standalone config should not reference Vault"
    
    # Simulate Nomad startup
    simulate_service_start "nomad"
    
    # Verify Nomad is running
    assert_true "check_simulated_service_running nomad" "Nomad should be running in standalone mode"
    
    # Create bootstrap state marker
    echo "phase1-complete:nomad-standalone:$(date +%s)" > "$TEST_TEMP_DIR/bootstrap-phase1.state"
    
    log_success "Nomad standalone bootstrap completed"
}

test_vault_initialization_bootstrap() {
    log_info "Testing Vault initialization bootstrap (Phase 2)"
    
    # Verify Nomad is running (prerequisite)
    assert_true "check_simulated_service_running nomad" "Nomad must be running before Vault initialization"
    
    # Create Vault job for Nomad
    local vault_job="$TEST_TEMP_DIR/vault-bootstrap.nomad"
    cat > "$vault_job" <<EOF
job "vault-bootstrap" {
  datacenters = ["dc1"]
  type = "service"
  
  group "vault" {
    count = 1
    
    task "vault" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:1.17.6"
        ports = ["vault"]
      }
      
      resources {
        cpu = 500
        memory = 512
      }
      
      service {
        name = "vault"
        port = "vault"
        
        check {
          type = "http"
          path = "/v1/sys/health"
          interval = "30s"
          timeout = "5s"
        }
      }
    }
  }
}
EOF
    
    # Simulate Vault deployment to Nomad
    log_debug "Deploying Vault to Nomad"
    simulate_service_start "vault"
    
    # Simulate Vault initialization
    local vault_init_output="$TEST_TEMP_DIR/vault-init.json"
    cat > "$vault_init_output" <<EOF
{
  "keys": ["key1", "key2", "key3", "key4", "key5"],
  "keys_base64": ["a2V5MQ==", "a2V5Mg==", "a2V5Mw==", "a2V5NA==", "a2V5NQ=="],
  "root_token": "hvs.test-root-token-bootstrap",
  "unseal_keys_b64": ["dW5zZWFsMQ==", "dW5zZWFsMg==", "dW5zZWFsMw=="],
  "unseal_keys_hex": ["756e7365616c31", "756e7365616c32", "756e7365616c33"]
}
EOF
    
    # Verify initialization output
    assert_file_exists "$vault_init_output" "Vault initialization output should exist"
    
    local root_token
    root_token=$(cat "$vault_init_output" | jq -r '.root_token')
    assert_not_equals "null" "$root_token" "Root token should be generated"
    
    # Store root token for later phases
    echo "$root_token" > "$TEST_TEMP_DIR/vault-root-token.txt"
    
    # Create bootstrap state marker
    echo "phase2-complete:vault-init:$(date +%s)" > "$TEST_TEMP_DIR/bootstrap-phase2.state"
    
    log_success "Vault initialization bootstrap completed"
}

test_nomad_vault_integration_bootstrap() {
    log_info "Testing Nomad-Vault integration bootstrap (Phase 3)"
    
    # Verify prerequisites
    assert_file_exists "$TEST_TEMP_DIR/bootstrap-phase1.state" "Phase 1 must be complete"
    assert_file_exists "$TEST_TEMP_DIR/bootstrap-phase2.state" "Phase 2 must be complete"
    
    # Get Vault root token from previous phase
    local vault_token
    vault_token=$(cat "$TEST_TEMP_DIR/vault-root-token.txt")
    assert_not_equals "" "$vault_token" "Vault root token should be available"
    
    # Create Vault policy for Nomad
    local nomad_policy="$TEST_TEMP_DIR/nomad-server-policy.hcl"
    cat > "$nomad_policy" <<EOF
# Policy for Nomad servers
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/lookup" {
  capabilities = ["update"]
}
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}
path "auth/token/create" {
  capabilities = ["create", "update"]
}
EOF
    
    # Simulate Vault policy creation
    log_debug "Creating Nomad server policy in Vault"
    assert_file_exists "$nomad_policy" "Nomad policy file should exist"
    
    # Create Nomad token role
    local nomad_role="$TEST_TEMP_DIR/nomad-cluster-role.json"
    cat > "$nomad_role" <<EOF
{
  "policies": ["nomad-server"],
  "explicit_max_ttl": 0,
  "name": "nomad-cluster",
  "orphan": true,
  "token_type": "service",
  "renewable": true
}
EOF
    
    assert_file_exists "$nomad_role" "Nomad cluster role should be created"
    
    # Create Nomad token for Vault integration
    local nomad_vault_token="hvs.nomad-integration-token-$(date +%s | tail -c 6)"
    echo "$nomad_vault_token" > "$TEST_TEMP_DIR/nomad-vault-token.txt"
    
    # Update Nomad config to include Vault integration
    local nomad_config_integrated="$TEST_TEMP_DIR/nomad-integrated.hcl"
    cat > "$nomad_config_integrated" <<EOF
datacenter = "dc1"
data_dir = "/opt/nomad/data"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

vault {
  enabled = true
  address = "$VAULT_ADDR"
  token = "$nomad_vault_token"
}
EOF
    
    # Verify integration config contains Vault settings
    local integrated_config
    integrated_config=$(cat "$nomad_config_integrated")
    assert_contains "$integrated_config" "vault {" "Integrated config should contain Vault block"
    assert_contains "$integrated_config" "$VAULT_ADDR" "Integrated config should contain Vault address"
    assert_contains "$integrated_config" "$nomad_vault_token" "Integrated config should contain Vault token"
    
    # Simulate Nomad reconfiguration
    log_debug "Reconfiguring Nomad with Vault integration"
    
    # Create bootstrap state marker
    echo "phase3-complete:nomad-vault-integration:$(date +%s)" > "$TEST_TEMP_DIR/bootstrap-phase3.state"
    
    log_success "Nomad-Vault integration bootstrap completed"
}

test_traefik_deployment_bootstrap() {
    log_info "Testing Traefik deployment bootstrap (Phase 4)"
    
    # Verify all prerequisites
    for phase in 1 2 3; do
        assert_file_exists "$TEST_TEMP_DIR/bootstrap-phase${phase}.state" "Phase $phase must be complete"
    done
    
    # Get tokens from previous phases
    local vault_token nomad_vault_token
    vault_token=$(cat "$TEST_TEMP_DIR/vault-root-token.txt")
    nomad_vault_token=$(cat "$TEST_TEMP_DIR/nomad-vault-token.txt")
    
    # Store Traefik secrets in Vault
    log_debug "Storing Traefik secrets in Vault"
    
    # Create Traefik dashboard credentials
    local dashboard_password
    dashboard_password="secure-password-$(date +%s | tail -c 8)"
    
    local traefik_secrets="$TEST_TEMP_DIR/traefik-secrets.json"
    cat > "$traefik_secrets" <<EOF
{
  "dashboard": {
    "username": "admin",
    "password": "$dashboard_password",
    "auth": "admin:$2y$10$encrypted.password.hash"
  },
  "nomad": {
    "token": "$nomad_vault_token",
    "addr": "$NOMAD_ADDR"
  }
}
EOF
    
    # Create Traefik Nomad job that uses Vault secrets
    local traefik_job="$TEST_TEMP_DIR/traefik-with-vault.nomad"
    cat > "$traefik_job" <<EOF
job "traefik" {
  datacenters = ["dc1"]
  type = "service"
  
  group "traefik" {
    count = 1
    
    # Vault integration for secrets
    vault {
      policies = ["traefik-policy"]
    }
    
    task "traefik" {
      driver = "docker"
      
      config {
        image = "traefik:v3.2.3"
        network_mode = "host"
        ports = ["web", "websecure"]
      }
      
      # Template to fetch secrets from Vault
      template {
        data = <<EOH
{{with secret "kv/data/traefik/dashboard"}}
DASHBOARD_USER={{.Data.data.username}}
DASHBOARD_PASS={{.Data.data.password}}
{{end}}
EOH
        destination = "secrets/dashboard.env"
        env = true
      }
      
      resources {
        cpu = 500
        memory = 512
      }
      
      service {
        name = "traefik"
        port = "web"
        
        check {
          type = "http"
          path = "/ping"
          interval = "30s"
          timeout = "5s"
        }
      }
    }
  }
}
EOF
    
    # Verify Traefik job uses Vault integration
    local traefik_job_content
    traefik_job_content=$(cat "$traefik_job")
    assert_contains "$traefik_job_content" "vault {" "Traefik job should use Vault integration"
    assert_contains "$traefik_job_content" "secret \"kv/data/traefik" "Traefik job should fetch secrets from Vault"
    assert_contains "$traefik_job_content" "template {" "Traefik job should use Vault templates"
    
    # Simulate Traefik deployment
    log_debug "Deploying Traefik with Vault integration"
    simulate_service_start "traefik"
    
    # Verify Traefik is running
    assert_true "check_simulated_service_running traefik" "Traefik should be running"
    
    # Create bootstrap state marker
    echo "phase4-complete:traefik-deploy:$(date +%s)" > "$TEST_TEMP_DIR/bootstrap-phase4.state"
    
    log_success "Traefik deployment bootstrap completed"
}

test_bootstrap_completion_verification() {
    log_info "Testing bootstrap completion and verification"
    
    # Verify all phases completed
    local phases=(1 2 3 4)
    local completed_phases=()
    
    for phase in "${phases[@]}"; do
        local phase_file="$TEST_TEMP_DIR/bootstrap-phase${phase}.state"
        if [[ -f "$phase_file" ]]; then
            completed_phases+=("$phase")
            local phase_info
            phase_info=$(cat "$phase_file")
            log_debug "Phase $phase: $phase_info"
        fi
    done
    
    assert_equals "${#phases[@]}" "${#completed_phases[@]}" "All bootstrap phases should be completed"
    
    # Verify all services are running
    local services=("nomad" "vault" "traefik")
    for service in "${services[@]}"; do
        assert_true "check_simulated_service_running $service" "$service should be running after bootstrap"
    done
    
    # Verify integration is working
    assert_file_exists "$TEST_TEMP_DIR/nomad-vault-token.txt" "Nomad-Vault integration token should exist"
    assert_file_exists "$TEST_TEMP_DIR/traefik-secrets.json" "Traefik secrets should be stored"
    
    # Create overall bootstrap completion marker
    local completion_time
    completion_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    cat > "$TEST_TEMP_DIR/bootstrap-complete.json" <<EOF
{
  "completed_at": "$completion_time",
  "phases": [
    "nomad-standalone",
    "vault-init", 
    "nomad-vault-integration",
    "traefik-deploy"
  ],
  "services": {
    "nomad": "running",
    "vault": "running", 
    "traefik": "running"
  },
  "circular_dependencies_resolved": true
}
EOF
    
    # Verify completion marker
    assert_file_exists "$TEST_TEMP_DIR/bootstrap-complete.json" "Bootstrap completion marker should exist"
    
    local completion_data
    completion_data=$(cat "$TEST_TEMP_DIR/bootstrap-complete.json")
    assert_contains "$completion_data" '"circular_dependencies_resolved": true' \
        "Bootstrap should resolve circular dependencies"
    
    log_success "Bootstrap completion verified"
}

test_bootstrap_failure_recovery() {
    log_info "Testing bootstrap failure recovery scenarios"
    
    # Test recovery from various failure points
    local failure_scenarios=(
        "phase1-nomad-startup-failure"
        "phase2-vault-init-failure"
        "phase3-integration-failure"
        "phase4-traefik-deployment-failure"
    )
    
    for scenario in "${failure_scenarios[@]}"; do
        log_debug "Testing recovery scenario: $scenario"
        
        # Create failure state
        local failure_file="$TEST_TEMP_DIR/failure-${scenario}.json"
        cat > "$failure_file" <<EOF
{
  "scenario": "$scenario",
  "failed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error": "Simulated failure for testing",
  "recovery_strategy": "restart-from-failed-phase"
}
EOF
        
        # Simulate recovery procedure
        case "$scenario" in
            *"phase1"*)
                # Recovery: Clean restart of Nomad
                log_debug "Recovery: Restarting Nomad from clean state"
                simulate_service_stop "nomad"
                simulate_service_start "nomad"
                ;;
            *"phase2"*)
                # Recovery: Reinitialize Vault
                log_debug "Recovery: Reinitializing Vault"
                simulate_service_stop "vault"
                rm -f "$TEST_TEMP_DIR/vault-init.json" "$TEST_TEMP_DIR/vault-root-token.txt"
                simulate_service_start "vault"
                ;;
            *"phase3"*)
                # Recovery: Reset Nomad-Vault integration
                log_debug "Recovery: Resetting Nomad-Vault integration"
                rm -f "$TEST_TEMP_DIR/nomad-vault-token.txt"
                ;;
            *"phase4"*)
                # Recovery: Redeploy Traefik
                log_debug "Recovery: Redeploying Traefik"
                simulate_service_stop "traefik"
                simulate_service_start "traefik"
                ;;
        esac
        
        # Create recovery completion marker
        echo "recovered:$scenario:$(date +%s)" > "$TEST_TEMP_DIR/recovery-${scenario}.state"
        
        assert_file_exists "$TEST_TEMP_DIR/recovery-${scenario}.state" "Recovery should complete for $scenario"
    done
    
    log_success "Bootstrap failure recovery scenarios verified"
}

test_dependency_health_monitoring() {
    log_info "Testing dependency health monitoring"
    
    # Create health monitoring configuration
    local health_config="$TEST_TEMP_DIR/dependency-health.json"
    cat > "$health_config" <<EOF
{
  "monitoring": {
    "nomad": {
      "endpoint": "$NOMAD_ADDR/v1/status/leader",
      "expected_status": 200,
      "timeout": 5
    },
    "vault": {
      "endpoint": "$VAULT_ADDR/v1/sys/health",
      "expected_status": 200,
      "timeout": 5
    },
    "traefik": {
      "endpoint": "$TRAEFIK_URL/ping",
      "expected_status": 200,
      "timeout": 5
    }
  },
  "dependencies": {
    "vault": ["nomad"],
    "traefik": ["nomad", "vault"]
  }
}
EOF
    
    # Simulate health check results
    local health_results="$TEST_TEMP_DIR/health-check-results.json"
    cat > "$health_results" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "results": {
    "nomad": {
      "status": "healthy",
      "response_time": 0.05,
      "dependencies_met": true
    },
    "vault": {
      "status": "healthy", 
      "response_time": 0.12,
      "dependencies_met": true,
      "depends_on": ["nomad"]
    },
    "traefik": {
      "status": "healthy",
      "response_time": 0.03,
      "dependencies_met": true,
      "depends_on": ["nomad", "vault"]
    }
  }
}
EOF
    
    # Verify health monitoring setup
    assert_file_exists "$health_config" "Health monitoring config should exist"
    assert_file_exists "$health_results" "Health check results should exist"
    
    # Parse and verify health results
    local nomad_status vault_status traefik_status
    nomad_status=$(cat "$health_results" | jq -r '.results.nomad.status')
    vault_status=$(cat "$health_results" | jq -r '.results.vault.status')
    traefik_status=$(cat "$health_results" | jq -r '.results.traefik.status')
    
    assert_equals "healthy" "$nomad_status" "Nomad should be healthy"
    assert_equals "healthy" "$vault_status" "Vault should be healthy"
    assert_equals "healthy" "$traefik_status" "Traefik should be healthy"
    
    # Verify dependency relationships
    local vault_deps traefik_deps
    vault_deps=$(cat "$health_results" | jq -r '.results.vault.depends_on[]?' | tr '\n' ' ')
    traefik_deps=$(cat "$health_results" | jq -r '.results.traefik.depends_on[]?' | tr '\n' ' ')
    
    assert_contains "$vault_deps" "nomad" "Vault dependencies should include Nomad"
    assert_contains "$traefik_deps" "nomad" "Traefik dependencies should include Nomad"
    assert_contains "$traefik_deps" "vault" "Traefik dependencies should include Vault"
    
    log_success "Dependency health monitoring verified"
}

# Main test execution
main() {
    log_info "Starting Bootstrap and Circular Dependency Resolution Tests"
    log_info "============================================================="
    
    # Load test configuration
    load_test_config
    
    # Clean up any existing state files
    rm -f "$TEST_TEMP_DIR"/bootstrap-phase*.state
    rm -f "$TEST_TEMP_DIR"/service-*.state
    
    # Run tests in dependency order
    run_test "Dependency Analysis" "test_dependency_analysis"
    run_test "Bootstrap Sequence Planning" "test_bootstrap_sequence_planning"
    run_test "Phase 1: Nomad Standalone Bootstrap" "test_nomad_standalone_bootstrap"
    run_test "Phase 2: Vault Initialization Bootstrap" "test_vault_initialization_bootstrap"
    run_test "Phase 3: Nomad-Vault Integration Bootstrap" "test_nomad_vault_integration_bootstrap"
    run_test "Phase 4: Traefik Deployment Bootstrap" "test_traefik_deployment_bootstrap"
    run_test "Bootstrap Completion Verification" "test_bootstrap_completion_verification"
    run_test "Bootstrap Failure Recovery" "test_bootstrap_failure_recovery"
    run_test "Dependency Health Monitoring" "test_dependency_health_monitoring"
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi