# Pipeline QA Test Suite

This comprehensive test suite validates the two-phase bootstrap deployment pipeline for the Vault-Nomad infrastructure. It ensures that the circular dependency solution works correctly and the system can deploy reliably across all environments.

## Overview

The Pipeline QA Test Suite consists of six main test categories designed to validate every aspect of the two-phase bootstrap process:

1. **Phase 1 Tests** - Nomad bootstrap without Vault
2. **Phase 2 Tests** - Vault integration enablement  
3. **Environment Propagation Tests** - Variable consistency across stages
4. **Failure & Rollback Tests** - Error handling and recovery
5. **Idempotency Tests** - Safe repeated execution
6. **CI/CD Integration Tests** - Automation pipeline validation

## Quick Start

### Run All Tests
```bash
# Execute complete test suite
cd infrastructure/tests/pipeline-qa
./run-all-pipeline-tests.sh
```

### Run Individual Test Suites
```bash
# Phase 1: Nomad Bootstrap Tests
./phase1-nomad-bootstrap-test.sh

# Phase 2: Vault Integration Tests  
./phase2-vault-integration-test.sh

# Environment Variable Propagation Tests
./environment-propagation-test.sh

# Failure Scenarios and Rollback Tests
./failure-rollback-test.sh

# Idempotency Validation Tests
./idempotency-validation-test.sh

# CI/CD Integration Tests
./ci-cd-integration-test.sh
```

## Test Categories

### 1. Phase 1: Nomad Bootstrap Tests (`phase1-nomad-bootstrap-test.sh`)

**Purpose:** Validates that Nomad can start successfully without Vault dependency.

**Test Scenarios:**
- Configuration generation with `vault.enabled=false`
- Environment variable propagation for Phase 1
- Nomad service startup without Vault
- Simple job scheduling without Vault dependencies
- Phase 1 readiness indicators
- Verification of no Vault dependencies created

**Success Criteria:**
- Nomad configuration generates correctly with Vault disabled
- Nomad can start without Vault dependency
- Simple jobs can be scheduled and validated
- No active Vault configuration present

### 2. Phase 2: Vault Integration Tests (`phase2-vault-integration-test.sh`)

**Purpose:** Validates Vault integration and configuration reconfiguration.

**Test Scenarios:**
- Vault accessibility and health validation
- Nomad reconfiguration with Vault enabled
- Vault policy and token role creation
- Job scheduling with Vault templates
- Environment variable propagation for Phase 2
- Phase transition from Phase 1 to Phase 2
- Vault secret access from Nomad jobs

**Success Criteria:**
- Vault is accessible and healthy
- Nomad configuration transitions correctly to Vault-enabled
- Jobs with Vault templates validate and can be planned
- Phase transition works seamlessly

### 3. Environment Variable Propagation Tests (`environment-propagation-test.sh`)

**Purpose:** Ensures environment variables are correctly propagated through all deployment stages.

**Test Scenarios:**
- Environment file template validation
- Environment variable loading and validation
- Configuration generation with different environments
- Phase transition environment handling
- Script environment variable handling
- Environment consistency across components
- Environment variable validation

**Success Criteria:**
- All environment templates are valid and complete
- Variables load correctly across all environments (develop, staging, production)
- Configuration generation works consistently with environment variables
- Phase transitions handle environment changes properly

### 4. Failure Scenarios and Rollback Tests (`failure-rollback-test.sh`)

**Purpose:** Validates system handles failures gracefully and can rollback when needed.

**Test Scenarios:**
- Configuration backup and restore functionality
- Phase 1 failure scenarios (invalid environment, missing parameters, startup failures)
- Phase 2 failure scenarios (Vault unavailable, integration failures)
- Rollback mechanism testing
- Error recovery mechanisms
- State consistency during failures
- Network and connectivity failures

**Success Criteria:**
- Configuration backup and restore work correctly
- System handles various failure scenarios gracefully
- Rollback mechanisms are functional and can restore previous state
- State consistency is maintained during failures

### 5. Idempotency Validation Tests (`idempotency-validation-test.sh`)

**Purpose:** Ensures deployment operations can be run multiple times safely without negative side effects.

**Test Scenarios:**
- Configuration generation idempotency (multiple runs produce identical results)
- Script execution idempotency (safe to run multiple times)
- Environment variable handling idempotency
- State file operations idempotency
- Configuration validation idempotency
- Phase transition idempotency
- Resource cleanup idempotency

**Success Criteria:**
- Configuration generation produces identical results across multiple runs
- Scripts can be executed multiple times safely
- Environment variable handling is consistent
- All operations are idempotent and safe to repeat

### 6. CI/CD Integration Tests (`ci-cd-integration-test.sh`)

**Purpose:** Validates integration with continuous integration and deployment pipelines.

**Test Scenarios:**
- GitHub Actions workflow validation
- Environment-based deployment testing
- Secrets management in CI/CD
- Automated testing integration
- Deployment rollback in CI/CD
- Notification and reporting integration
- Multi-environment pipeline testing

**Success Criteria:**
- GitHub Actions workflows are properly configured
- Environment-based deployment works correctly
- Secrets management is secure and functional
- Automated testing integrates properly with CI/CD pipelines

## Test Results and Reporting

### Result Files

After running tests, you'll find results in the `results/` directory:

```
tests/pipeline-qa/results/
├── master-pipeline-test-YYYYMMDD_HHMMSS.log     # Complete execution log
├── pipeline-qa-summary-YYYYMMDD_HHMMSS.md       # Executive summary report
├── phase1-test-YYYYMMDD_HHMMSS.log              # Phase 1 detailed results
├── phase2-test-YYYYMMDD_HHMMSS.log              # Phase 2 detailed results
├── env-propagation-test-YYYYMMDD_HHMMSS.log     # Environment tests
├── failure-rollback-test-YYYYMMDD_HHMMSS.log    # Failure handling tests
├── idempotency-test-YYYYMMDD_HHMMSS.log         # Idempotency tests
└── ci-cd-integration-test-YYYYMMDD_HHMMSS.log   # CI/CD tests
```

### Understanding Results

**Test Status Indicators:**
- ✅ `PASS` - Test completed successfully
- ❌ `FAIL` - Test failed, requires attention
- ⚠️ `WARN` - Test passed with warnings
- ℹ️ `INFO` - Informational message

**Exit Codes:**
- `0` - All tests passed (may include warnings)
- `1` - One or more tests failed

## Prerequisites

### Required Software
- `bash` (4.0+)
- `nomad` (1.0+)
- `vault` (1.8+)
- `consul` (1.9+)
- `curl`
- `grep`, `sed`, `awk`

### Required Infrastructure
- Infrastructure scripts in `../../scripts/`
- Configuration templates in `../../config/`
- Environment configurations in `../../environments/`

### Permissions
- Read access to infrastructure configuration files
- Write access to `/tmp` for test artifacts
- Ability to execute validation commands

## Test Environment Setup

The test suite can run in different environments:

### Local Development
```bash
export ENVIRONMENT=develop
export CI=false
./run-all-pipeline-tests.sh
```

### CI/CD Environment
```bash
export ENVIRONMENT=staging
export CI=true
export GITHUB_ACTIONS=true
./run-all-pipeline-tests.sh
```

### Production Validation
```bash
export ENVIRONMENT=production
export VALIDATE_ONLY=true
./run-all-pipeline-tests.sh
```

## Troubleshooting

### Common Issues

#### Test Script Not Executable
```bash
chmod +x tests/pipeline-qa/*.sh
```

#### Missing Dependencies
```bash
# Install HashiCorp tools
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install nomad consul vault
```

#### Configuration Generation Fails
1. Ensure all required environment variables are set
2. Check that `config-templates.sh` exists and is sourced correctly
3. Validate environment template files exist

#### Tests Time Out
```bash
# Increase timeout in test scripts or set environment variable
export TEST_TIMEOUT=300  # 5 minutes
```

### Debug Mode
```bash
# Run with detailed debugging
export DEBUG=true
export VERBOSE=true
./run-all-pipeline-tests.sh
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Pipeline QA Tests

on:
  push:
    branches: [ main, develop ]
    paths: [ 'infrastructure/**' ]

jobs:
  pipeline-qa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install HashiCorp Tools
        run: |
          curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
          sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
          sudo apt-get update && sudo apt-get install nomad consul vault
      
      - name: Run Pipeline QA Tests
        run: |
          cd infrastructure/tests/pipeline-qa
          ./run-all-pipeline-tests.sh
      
      - name: Upload Test Results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: pipeline-qa-results
          path: infrastructure/tests/pipeline-qa/results/
```

## Best Practices

### Before Running Tests
1. Ensure infrastructure is in a clean state
2. Back up any existing configurations
3. Set appropriate environment variables
4. Review test logs from previous runs

### Interpreting Results
1. Always check the summary report first
2. Address all failures before proceeding
3. Review warnings and decide if they're acceptable
4. Validate that test coverage meets your requirements

### Maintenance
1. Update tests when infrastructure changes
2. Add new test scenarios for new features
3. Review and update expected results periodically
4. Keep test documentation current

## Contributing

### Adding New Tests
1. Create new test script following naming convention: `category-description-test.sh`
2. Follow existing logging and reporting patterns
3. Add test to `TESTS` array in `run-all-pipeline-tests.sh`
4. Update this README with test description

### Test Script Structure
```bash
#!/bin/bash
# Test Description
# Purpose and scope

set -euo pipefail

# Setup logging and cleanup functions
# Test functions (test_category_functionality)
# Main execution function
# Run main function
```

## Support

For issues with the Pipeline QA Test Suite:

1. Check the troubleshooting section above
2. Review test logs for specific error messages
3. Ensure all prerequisites are met
4. Validate infrastructure configuration files

---

**Pipeline QA Test Suite v1.0**  
*Comprehensive validation for two-phase bootstrap deployment pipeline*