# Infrastructure Test Suite

Comprehensive test suite for the Nomad-Vault-Traefik infrastructure deployment.

## Overview

This test suite validates the entire infrastructure stack including:

- **Integration Tests**: Nomad cluster formation, Vault deployment, and Traefik integration
- **Environment Tests**: Multi-environment deployment (develop, staging, production)  
- **Bootstrap Tests**: Circular dependency resolution and token lifecycle management
- **Secret Management Tests**: Secret rotation, versioning, and access control

## Test Structure

```
infrastructure/tests/
├── framework/               # Test framework and utilities
│   └── test_framework.sh   # Core testing functions and assertions
├── integration/             # Integration tests
│   ├── nomad_cluster_formation_test.sh
│   ├── vault_nomad_deployment_test.sh
│   └── traefik_vault_secret_integration_test.sh
├── environment/             # Multi-environment tests
│   └── multi_environment_deployment_test.sh
├── bootstrap/               # Bootstrap and dependency tests  
│   ├── token_lifecycle_test.sh
│   └── circular_dependency_test.sh
├── secrets/                 # Secret management tests
│   └── secret_management_rotation_test.sh
├── utils/                   # Test utilities and helpers
├── results/                 # Test execution results (generated)
├── run_all_tests.sh        # Master test runner
└── README.md               # This file
```

## Quick Start

### Prerequisites

Required tools:
- `bash` (version 4.0+)
- `curl` 
- `jq`
- `timeout`
- `bc`

Optional tools (some tests will be skipped if not available):
- `vault` - HashiCorp Vault CLI
- `nomad` - HashiCorp Nomad CLI  
- `docker` - Docker for container tests
- `openssl` - For certificate testing

### Running All Tests

```bash
# Run all tests sequentially (recommended)
./run_all_tests.sh

# Run tests in parallel (faster, but may have dependencies issues)
./run_all_tests.sh --parallel

# Run with custom timeout (default: 600s)
./run_all_tests.sh --timeout 900

# Run with debug output
./run_all_tests.sh --debug
```

### Running Individual Test Suites

```bash
# Integration tests
./integration/nomad_cluster_formation_test.sh
./integration/vault_nomad_deployment_test.sh
./integration/traefik_vault_secret_integration_test.sh

# Environment tests
./environment/multi_environment_deployment_test.sh

# Bootstrap tests
./bootstrap/token_lifecycle_test.sh
./bootstrap/circular_dependency_test.sh

# Secret management tests
./secrets/secret_management_rotation_test.sh
```

## Test Configuration

### Environment Variables

Key environment variables that affect test execution:

```bash
# Service endpoints
export VAULT_ADDR="http://localhost:8200"    # Vault API address
export NOMAD_ADDR="http://localhost:4646"    # Nomad API address  
export TRAEFIK_URL="http://localhost:80"     # Traefik endpoint

# Test configuration
export TEST_ENV="test"                        # Test environment name
export TEST_TIMEOUT="600"                    # Test timeout in seconds
export DEBUG="false"                         # Enable debug output

# Infrastructure configuration
export ENVIRONMENT="develop"                 # Target environment
export INTEGRATED_MODE="true"               # Enable integrated testing
```

### Configuration File

Create a `test_config.env` file for persistent configuration:

```bash
# Test configuration
TEST_ENV="staging"
VAULT_ADDR="http://vault.test.local:8200"
NOMAD_ADDR="http://nomad.test.local:4646"
TRAEFIK_URL="http://traefik.test.local"

# Test behavior
TEST_TIMEOUT="900"
DEBUG="true"
PARALLEL_EXECUTION="false"
```

## Test Categories

### 1. Integration Tests

Test the core integration between infrastructure components:

#### Nomad Cluster Formation (`nomad_cluster_formation_test.sh`)
- Nomad installation and configuration
- Cluster formation and leader election
- Node registration and health
- API connectivity and ports
- Data directory and storage

#### Vault-Nomad Deployment (`vault_nomad_deployment_test.sh`)
- Vault job deployment on Nomad
- Service registration and health checks
- Persistent storage configuration  
- Network connectivity and TLS
- Vault initialization and unsealing

#### Traefik-Vault Integration (`traefik_vault_secret_integration_test.sh`)
- Secret engine setup
- Vault policies for Traefik
- Dashboard authentication with Vault secrets
- TLS certificate management
- Secret rotation capabilities

### 2. Environment Tests

#### Multi-Environment Deployment (`multi_environment_deployment_test.sh`)
- Environment detection (develop, staging, production)
- Configuration templating per environment
- Security policies by environment
- Deployment promotion workflow
- Cross-environment communication
- Rollback procedures
- Environment-specific monitoring

### 3. Bootstrap Tests

#### Token Lifecycle (`token_lifecycle_test.sh`)
- Vault token creation and properties
- Token renewal and TTL management
- Token revocation (individual and hierarchical)
- Policy inheritance and capabilities
- Token metadata and tracking
- Nomad-Vault integration tokens
- Migration scenarios
- Emergency procedures

#### Circular Dependency Resolution (`circular_dependency_test.sh`)
- Dependency analysis and detection
- Bootstrap sequence planning
- 4-phase bootstrap process:
  1. Nomad standalone startup
  2. Vault initialization
  3. Nomad-Vault integration
  4. Traefik deployment with secrets
- Failure recovery scenarios
- Health monitoring

### 4. Secret Management Tests

#### Secret Management and Rotation (`secret_management_rotation_test.sh`)
- Secret engines setup (KV, PKI, Database)
- Basic CRUD operations
- Secret versioning and history
- Automated rotation for different secret types
- Access control and policies
- Certificate rotation (PKI)
- Database credential rotation
- Secret expiration and cleanup
- Backup and restore procedures
- Monitoring and alerting

## Test Framework

The test framework (`framework/test_framework.sh`) provides:

### Assertion Functions
- `assert_equals` / `assert_not_equals`
- `assert_contains` / `assert_not_contains`
- `assert_true` / `assert_false`
- `assert_file_exists` / `assert_dir_exists`
- `assert_command_success` / `assert_command_failure`
- `assert_http_status`
- `assert_service_running`
- `assert_port_open`

### Test Management
- `run_test` - Execute individual tests with timeout
- `run_test_with_retry` - Retry failed tests
- `skip_test` - Skip tests with reason
- `print_test_summary` - Display results summary

### Infrastructure Helpers
- `wait_for_service` - Wait for service to be ready
- `wait_for_http_endpoint` - Wait for HTTP endpoint
- `wait_for_port` - Wait for port to open
- `setup_test_environment` - Initialize test environment
- `cleanup_test_environment` - Clean up after tests

## Test Results

### Result Files

Test results are stored in `results/` directory:

```
results/
├── test_report.html                    # Comprehensive HTML report
├── test_summary.json                   # JSON summary of results
├── integration_nomad_cluster_result.txt    # Individual test results
├── integration_nomad_cluster_output.txt    # Test output logs
└── ...
```

### HTML Report

The HTML report (`test_report.html`) includes:
- Test execution summary with metrics
- Pass/fail status for each test suite
- Detailed output for failed tests
- Execution timing and environment info

### JSON Summary

The JSON summary (`test_summary.json`) provides:
```json
{
  "test_run": {
    "started_at": "2025-01-25T10:30:00Z",
    "completed_at": "2025-01-25T10:45:00Z", 
    "duration": "900s",
    "parallel_execution": false
  },
  "results": {
    "total_tests": 12,
    "passed": 10,
    "failed": 1,
    "skipped": 1,
    "success_rate": 83
  },
  "environment": {
    "test_env": "test",
    "vault_addr": "http://localhost:8200",
    "nomad_addr": "http://localhost:4646",
    "traefik_url": "http://localhost:80"
  }
}
```

## Troubleshooting

### Common Issues

#### Services Not Running
```bash
# Check if services are accessible
curl -f http://localhost:4646/v1/status/leader  # Nomad
curl -f http://localhost:8200/v1/sys/health     # Vault
curl -f http://localhost:80/ping                # Traefik
```

#### Permission Issues
```bash
# Ensure test scripts are executable
chmod +x infrastructure/tests/**/*.sh

# Check file permissions for test directories
ls -la infrastructure/tests/
```

#### Test Timeouts
```bash
# Increase timeout for slow environments
./run_all_tests.sh --timeout 1200

# Run individual slow tests
TEST_TIMEOUT=900 ./integration/vault_nomad_deployment_test.sh
```

#### Debug Output
```bash
# Enable debug mode for detailed logging
DEBUG=true ./run_all_tests.sh

# Check individual test logs
cat results/integration_nomad_cluster_output.txt
```

### Skipped Tests

Tests may be skipped for various reasons:
- Required services not accessible
- Missing prerequisites (vault CLI, nomad CLI, etc.)
- Environment not suitable for test
- Dependencies from previous tests not met

Check test output for skip reasons and ensure prerequisites are met.

### Test Dependencies

Some tests depend on others:
1. **Integration tests** must pass before others
2. **Vault** must be accessible for secret tests
3. **Nomad** must be running for deployment tests
4. **Bootstrap tests** simulate from clean state

Run tests in the provided order or use the master runner which handles dependencies.

## Contributing

### Adding New Tests

1. Create test file in appropriate category directory
2. Include the test framework: `source ../framework/test_framework.sh`
3. Implement test functions following naming convention: `test_feature_name()`
4. Use provided assertion functions
5. Add cleanup procedures
6. Update this README with new test description

### Test Standards

- Test functions should be atomic and independent
- Use descriptive test names and log messages
- Handle both success and failure cases
- Clean up resources after tests
- Mock external dependencies when possible
- Include both positive and negative test cases

### Example Test Template

```bash
#!/bin/bash
set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
TEST_CONFIG_VAR="${TEST_CONFIG_VAR:-default}"

# Test functions
test_feature_functionality() {
    log_info "Testing feature functionality"
    
    # Setup
    local test_data="test-value"
    
    # Execute
    local result=$(some_command "$test_data")
    
    # Assert
    assert_equals "expected" "$result" "Feature should return expected value"
    
    log_success "Feature functionality verified"
}

# Main execution
main() {
    log_info "Starting Feature Tests"
    
    load_test_config
    
    run_test "Feature Functionality" "test_feature_functionality"
    
    print_test_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## License

This test suite is part of the infrastructure project and follows the same license terms.