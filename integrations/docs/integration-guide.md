# Vault Infrastructure Integration Guide

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [SDK Documentation](#sdk-documentation)
- [CI/CD Integration](#cicd-integration)
- [Example Applications](#example-applications)
- [Testing](#testing)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

## Overview

This integration guide provides comprehensive documentation for connecting applications to the Vault infrastructure, including:

- **HashiCorp Vault**: Secrets management and encryption
- **Consul**: Service discovery and configuration management
- **Nomad**: Container orchestration and job scheduling
- **Prometheus**: Metrics collection and monitoring

### Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │    │      CI/CD      │    │   Monitoring    │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   Your App  │ │    │ │GitHub Actions│ │    │ │ Prometheus  │ │
│ │             │ │    │ │  GitLab CI   │ │    │ │   Grafana   │ │
│ │   SDK       │ │    │ │   Jenkins    │ │    │ │  Alerting   │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
    ┌────────────────────────────┼────────────────────────────┐
    │               Vault Infrastructure                       │
    │                                                          │
    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
    │  │    Vault    │  │   Consul    │  │    Nomad    │      │
    │  │             │  │             │  │             │      │
    │  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │      │
    │  │  │Secrets│  │  │  │Service│  │  │  │ Jobs  │  │      │
    │  │  │Policies│ │  │  │Mesh   │  │  │  │Scaling│  │      │
    │  │  │Auth   │  │  │  │KV     │  │  │  │Health │  │      │
    │  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │      │
    │  └─────────────┘  └─────────────┘  └─────────────┘      │
    └──────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Installation

#### Python SDK
```bash
# Install from PyPI (when published)
pip install vault-infrastructure-sdk

# Or install from source
cd integrations/python
pip install -r requirements.txt
pip install -e .
```

#### JavaScript SDK
```bash
# Install from npm (when published)
npm install vault-infrastructure-sdk

# Or install from source
cd integrations/javascript
npm install
```

### 2. Basic Configuration

#### Environment Variables
```bash
# Vault Configuration
export VAULT_ADDR=https://vault.your-domain.com:8200
export VAULT_TOKEN=your-vault-token
# Or for AppRole authentication:
export VAULT_ROLE_ID=your-role-id
export VAULT_SECRET_ID=your-secret-id

# Consul Configuration
export CONSUL_HTTP_ADDR=https://consul.your-domain.com:8500
export CONSUL_HTTP_TOKEN=your-consul-token

# Nomad Configuration
export NOMAD_ADDR=https://nomad.your-domain.com:4646
export NOMAD_TOKEN=your-nomad-token

# Prometheus Configuration
export PROMETHEUS_URL=https://prometheus.your-domain.com:9090
```

#### Configuration File (Optional)
```json
{
  "vault": {
    "host": "vault.your-domain.com",
    "port": 8200,
    "protocol": "https",
    "token": "your-vault-token",
    "verify_ssl": true
  },
  "consul": {
    "host": "consul.your-domain.com",
    "port": 8500,
    "protocol": "https",
    "token": "your-consul-token"
  },
  "nomad": {
    "host": "nomad.your-domain.com",
    "port": 4646,
    "protocol": "https",
    "token": "your-nomad-token"
  },
  "prometheus": {
    "host": "prometheus.your-domain.com",
    "port": 9090,
    "protocol": "https"
  }
}
```

### 3. Basic Usage

#### Python Example
```python
from vault_integration_sdk import VaultInfrastructureSDK

# Initialize SDK
sdk = VaultInfrastructureSDK()

# Retrieve application secrets
secrets = sdk.vault.get_secret("applications/my-app/production")
database_url = secrets["database_url"]
api_key = secrets["api_key"]

# Register service with Consul
service_config = {
    'name': 'my-app',
    'port': 8080,
    'health_check_url': 'http://localhost:8080/health'
}
sdk.consul.register_service(service_config)

# Deploy with Nomad
job_spec = create_nomad_job_template("my-app", "my-app:latest", 8080)
deployment_result = sdk.nomad.submit_job(job_spec)
```

#### JavaScript Example
```javascript
const { VaultInfrastructureSDK } = require('vault-infrastructure-sdk');

// Initialize SDK
const sdk = new VaultInfrastructureSDK();

// Retrieve application secrets
const secrets = await sdk.vault.getSecret('applications/my-app/production');
const databaseUrl = secrets.database_url;
const apiKey = secrets.api_key;

// Register service with Consul
const serviceConfig = {
    name: 'my-app',
    port: 8080,
    health_check_url: 'http://localhost:8080/health'
};
await sdk.consul.registerService(serviceConfig);

// Deploy with Nomad
const jobSpec = createNomadJobTemplate('my-app', 'my-app:latest', 8080);
const deploymentResult = await sdk.nomad.submitJob(jobSpec);
```

## SDK Documentation

### VaultInfrastructureSDK

The main SDK class that orchestrates all infrastructure services.

#### Initialization

```python
# Python
from vault_integration_sdk import VaultInfrastructureSDK

# From environment variables
sdk = VaultInfrastructureSDK()

# From configuration file
sdk = VaultInfrastructureSDK(config_file="config.json")

# From configuration dict
config = {...}
sdk = VaultInfrastructureSDK(config_dict=config)
```

```javascript
// JavaScript
const { VaultInfrastructureSDK } = require('vault-infrastructure-sdk');

// From environment variables
const sdk = new VaultInfrastructureSDK();

// From configuration file
const sdk = new VaultInfrastructureSDK('config.json');

// From configuration object
const config = {...};
const sdk = new VaultInfrastructureSDK(null, config);
```

#### Health Checks

```python
# Python
health_status = await sdk.health_check_all()
print(f"Overall status: {health_status}")
```

```javascript
// JavaScript
const healthStatus = await sdk.healthCheckAll();
console.log(`Overall status: ${JSON.stringify(healthStatus)}`);
```

### Vault Client

#### Authentication

```python
# Python - AppRole Authentication
sdk.vault.authenticate_approle(role_id, secret_id)

# Token Renewal
sdk.vault.renew_token()
```

```javascript
// JavaScript - AppRole Authentication
await sdk.vault.authenticateAppRole(roleId, secretId);

// Token Renewal
await sdk.vault.renewToken();
```

#### Secret Management

```python
# Python
# Write secret
sdk.vault.write_secret("path/to/secret", {"key": "value"})

# Read secret
secret_data = sdk.vault.get_secret("path/to/secret")

# Dynamic database credentials
db_creds = sdk.vault.get_database_credentials("my-app-role")
```

```javascript
// JavaScript
// Write secret
await sdk.vault.writeSecret('path/to/secret', {key: 'value'});

// Read secret
const secretData = await sdk.vault.getSecret('path/to/secret');

// Dynamic database credentials
const dbCreds = await sdk.vault.getDatabaseCredentials('my-app-role');
```

### Consul Client

#### Service Registration

```python
# Python
service_config = {
    'name': 'my-service',
    'port': 8080,
    'tags': ['web', 'api'],
    'health_check_url': 'http://localhost:8080/health'
}
sdk.consul.register_service(service_config)
```

```javascript
// JavaScript
const serviceConfig = {
    name: 'my-service',
    port: 8080,
    tags: ['web', 'api'],
    health_check_url: 'http://localhost:8080/health'
};
await sdk.consul.registerService(serviceConfig);
```

#### Service Discovery

```python
# Python
services = sdk.consul.discover_service("web-service")
for service in services:
    print(f"Found service at {service['address']}:{service['port']}")
```

```javascript
// JavaScript
const services = await sdk.consul.discoverService('web-service');
services.forEach(service => {
    console.log(`Found service at ${service.address}:${service.port}`);
});
```

#### Key-Value Store

```python
# Python
sdk.consul.set_kv_value("config/database", "postgresql://...")
database_config = sdk.consul.get_kv_value("config/database")
```

```javascript
// JavaScript
await sdk.consul.setKVValue('config/database', 'postgresql://...');
const databaseConfig = await sdk.consul.getKVValue('config/database');
```

### Nomad Client

#### Job Management

```python
# Python
# Submit job
job_spec = {...}
result = sdk.nomad.submit_job(job_spec)

# Check job status
status = sdk.nomad.get_job_status("my-job")

# Scale job
sdk.nomad.scale_job("my-job", "web-group", 5)

# Stop job
sdk.nomad.stop_job("my-job")
```

```javascript
// JavaScript
// Submit job
const jobSpec = {...};
const result = await sdk.nomad.submitJob(jobSpec);

// Check job status
const status = await sdk.nomad.getJobStatus('my-job');

// Scale job
await sdk.nomad.scaleJob('my-job', 'web-group', 5);

// Stop job
await sdk.nomad.stopJob('my-job');
```

### Prometheus Client

#### Metrics Queries

```python
# Python
# Instant query
result = sdk.prometheus.query_metric("up")

# Range query
result = sdk.prometheus.query_range(
    query="cpu_usage",
    start=start_time,
    end=end_time,
    step="5m"
)
```

```javascript
// JavaScript
// Instant query
const result = await sdk.prometheus.queryMetric('up');

// Range query
const result = await sdk.prometheus.queryRange({
    query: 'cpu_usage',
    start: startTime,
    end: endTime,
    step: '5m'
});
```

## CI/CD Integration

### GitHub Actions

The integration includes comprehensive GitHub Actions workflows:

1. **Main Integration Workflow** (`vault-integration-workflow.yml`)
   - Vault authentication and secret retrieval
   - Multi-stage testing (unit, integration, security)
   - Docker image building and pushing
   - Consul service registration
   - Nomad deployment
   - Monitoring setup with Prometheus/Grafana

2. **Secrets Synchronization Workflow** (`vault-secrets-sync.yml`)
   - Automated secret synchronization
   - Policy and AppRole management
   - Audit reporting

#### Usage Example

```yaml
# In your .github/workflows/deploy.yml
name: Deploy Application

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: ./.github/workflows/vault-integration-workflow.yml
    secrets:
      VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
      VAULT_ROLE_ID: ${{ secrets.VAULT_ROLE_ID }}
      VAULT_SECRET_ID: ${{ secrets.VAULT_SECRET_ID }}
      CONSUL_ADDR: ${{ secrets.CONSUL_ADDR }}
      NOMAD_ADDR: ${{ secrets.NOMAD_ADDR }}
```

### GitLab CI

The GitLab CI pipeline provides:

- JWT-based Vault authentication
- Parallel testing stages
- Multi-environment deployments
- Automatic rollback on failure

#### Usage Example

```yaml
# In your .gitlab-ci.yml
include:
  - 'integrations/ci-cd/gitlab-ci/vault-integration-pipeline.yml'

variables:
  APP_NAME: "my-application"
  VAULT_JWT_ROLE: $CI_PROJECT_PATH_SLUG
```

### Jenkins

The Jenkins pipeline offers:

- HashiCorp Vault plugin integration
- Parallel test execution
- Blue-green deployment support
- Comprehensive error handling

#### Usage Example

```groovy
// In your Jenkinsfile
@Library('vault-integration-lib@main') _
pipeline {
    agent any
    stages {
        stage('Deploy') {
            steps {
                script {
                    load 'integrations/ci-cd/jenkins/Jenkinsfile-vault-integration'
                }
            }
        }
    }
}
```

## Example Applications

The integration package includes complete example applications demonstrating best practices:

### Python Flask Application

Located in `examples/python-flask-app/`, this example demonstrates:

- Vault secrets retrieval and management
- Consul service registration
- Prometheus metrics export
- JWT authentication with Vault-managed secrets
- Database connection with dynamic secrets
- Graceful shutdown and error handling

#### Running the Example

```bash
cd examples/python-flask-app
pip install -r requirements.txt

# Set environment variables
export VAULT_ADDR=https://your-vault-url:8200
export VAULT_TOKEN=your-vault-token
export APP_NAME=flask-demo
export ENVIRONMENT=development

python app.py
```

### JavaScript Express Application

Located in `examples/javascript-express-app/`, this example demonstrates:

- Async/await Vault integration
- Service mesh integration with Consul
- Custom Prometheus metrics
- JWT authentication
- Database connection pooling
- OpenTelemetry tracing (ready)

#### Running the Example

```bash
cd examples/javascript-express-app
npm install

# Set environment variables
export VAULT_ADDR=https://your-vault-url:8200
export VAULT_TOKEN=your-vault-token
export APP_NAME=express-demo
export NODE_ENV=development

npm start
```

## Testing

### Integration Test Suite

The comprehensive integration test suite (`tests/integration_test_suite.py`) validates:

- Infrastructure component health
- Vault secrets management operations
- Consul service discovery
- Nomad job deployment
- Prometheus metrics collection
- End-to-end application workflows
- Security features and access controls
- Performance characteristics

#### Running the Tests

```bash
# Python tests
cd tests
python -m pytest integration_test_suite.py -v

# Or run standalone
python integration_test_suite.py --config config.json --output results.json
```

#### Test Categories

1. **Health Checks**: Verify all infrastructure components are accessible
2. **Vault Operations**: Test secret CRUD operations and authentication
3. **Consul Integration**: Test service registration and discovery
4. **Nomad Deployment**: Test job submission and management
5. **Prometheus Monitoring**: Test metrics collection and querying
6. **End-to-End Flow**: Test complete application deployment workflow
7. **Security Validation**: Test access controls and security features
8. **Performance Testing**: Validate response times and resource usage

## Best Practices

### Secret Management

1. **Use AppRole Authentication**
   ```python
   # Prefer AppRole over long-lived tokens
   sdk.vault.authenticate_approle(role_id, secret_id)
   ```

2. **Implement Secret Rotation**
   ```python
   # Regular secret rotation
   from datetime import datetime, timedelta
   
   def rotate_secrets_if_needed():
       last_rotation = get_last_rotation_time()
       if datetime.now() - last_rotation > timedelta(days=30):
           rotate_application_secrets()
   ```

3. **Use Dynamic Secrets**
   ```python
   # Dynamic database credentials
   db_creds = sdk.vault.get_database_credentials("app-db-role")
   connection = create_db_connection(db_creds)
   ```

### Service Discovery

1. **Health Check Implementation**
   ```python
   @app.route('/health')
   def health_check():
       return {
           'status': 'healthy',
           'timestamp': datetime.utcnow().isoformat(),
           'checks': {
               'database': check_database_health(),
               'vault': check_vault_health()
           }
       }
   ```

2. **Service Registration**
   ```python
   # Register with comprehensive metadata
   service_config = {
       'name': app_name,
       'port': port,
       'tags': [f'environment:{environment}', 'version:1.0.0'],
       'meta': {
           'version': '1.0.0',
           'environment': environment,
           'commit': git_commit_hash
       },
       'health_check_url': f'http://localhost:{port}/health'
   }
   ```

### Deployment

1. **Graceful Shutdown**
   ```python
   import signal
   import atexit
   
   def graceful_shutdown(signum, frame):
       logger.info("Initiating graceful shutdown...")
       # Deregister from Consul
       # Close database connections
       # Complete in-flight requests
       sys.exit(0)
   
   signal.signal(signal.SIGTERM, graceful_shutdown)
   ```

2. **Resource Management**
   ```python
   # Proper resource cleanup
   def cleanup_resources():
       if db_pool:
           db_pool.closeall()
       if consul_client:
           deregister_service()
   
   atexit.register(cleanup_resources)
   ```

### Monitoring

1. **Custom Metrics**
   ```python
   from prometheus_client import Counter, Histogram
   
   request_count = Counter('http_requests_total', 'Total requests')
   request_duration = Histogram('http_request_duration_seconds', 'Request duration')
   
   @request_duration.time()
   def handle_request():
       request_count.inc()
       # Handle request
   ```

2. **Structured Logging**
   ```python
   import structlog
   
   logger = structlog.get_logger()
   logger.info("Processing request", 
               user_id=user_id, 
               request_id=request_id,
               action="create_user")
   ```

## Troubleshooting

### Common Issues

#### Vault Authentication Failures

**Problem**: `permission denied` when accessing secrets

**Solution**:
```bash
# Check token status
vault token lookup

# Verify policy permissions
vault policy read my-app-policy

# Test AppRole authentication
vault write auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID
```

#### Consul Service Registration Issues

**Problem**: Service not appearing in Consul catalog

**Solution**:
```bash
# Check Consul agent status
consul members

# Verify service registration
curl -H "X-Consul-Token: $CONSUL_TOKEN" \
     http://consul:8500/v1/agent/services

# Check service health
consul catalog services -tags
```

#### Nomad Job Deployment Failures

**Problem**: Jobs failing to start

**Solution**:
```bash
# Check job status
nomad job status my-job

# View allocation logs
nomad alloc logs <allocation-id>

# Check node resources
nomad node status

# Validate job specification
nomad job validate job.nomad
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```python
# Python
import logging
logging.basicConfig(level=logging.DEBUG)

# Set SDK debug mode
sdk = VaultInfrastructureSDK()
# Enable debug logging in underlying clients
```

```javascript
// JavaScript
// Set debug environment variable
process.env.DEBUG = 'vault-sdk:*';

// Enable verbose logging
const sdk = new VaultInfrastructureSDK();
sdk.logger.level = 'debug';
```

### Support

For additional support:

1. Check the [deployment workflows guide](deployment-workflows.md)
2. Review example applications in the `examples/` directory
3. Run the integration test suite for environment validation
4. Check infrastructure logs for detailed error information

## API Reference

### Python SDK API

#### VaultInfrastructureSDK

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `__init__(config_file, config_dict)` | Initialize SDK | config file path or dict | SDK instance |
| `health_check_all()` | Check all services | None | Dict[str, bool] |
| `setup_application_secrets(app_name, secrets)` | Setup app secrets | app name, secrets dict | bool |
| `deploy_application(job_spec, secrets_path)` | Deploy with secrets | job spec, vault path | deployment result |

#### VaultClient

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `authenticate_approle(role_id, secret_id)` | AppRole auth | role ID, secret ID | auth response |
| `get_secret(path, mount_point)` | Get secret | vault path, mount point | secret data |
| `write_secret(path, data, mount_point)` | Write secret | vault path, data, mount | bool |
| `get_database_credentials(role)` | Dynamic DB creds | role name | credentials dict |
| `renew_token()` | Renew token | None | bool |

#### ConsulClient

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `register_service(config)` | Register service | service config | bool |
| `discover_service(name)` | Find services | service name | list of services |
| `get_kv_value(key)` | Get KV value | key | value string |
| `set_kv_value(key, value)` | Set KV value | key, value | bool |

#### NomadClient

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `submit_job(job_spec)` | Submit job | job specification | job result |
| `get_job_status(job_id)` | Get job status | job ID | status dict |
| `scale_job(job_id, group, count)` | Scale job group | job ID, group, count | scale result |
| `stop_job(job_id, purge)` | Stop job | job ID, purge flag | stop result |

#### PrometheusClient

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `query_metric(query, timestamp)` | Query metrics | PromQL query, timestamp | query result |
| `query_range(query, start, end, step)` | Range query | query, start, end, step | range result |
| `push_metric(job, name, value, labels)` | Push metric | job, metric name, value, labels | bool |

### JavaScript SDK API

The JavaScript SDK provides equivalent functionality with Promise-based async methods:

```javascript
// All methods return Promises
await sdk.vault.authenticateAppRole(roleId, secretId);
const secrets = await sdk.vault.getSecret(path);
const services = await sdk.consul.discoverService(name);
const result = await sdk.nomad.submitJob(jobSpec);
```

---

This integration guide provides comprehensive documentation for using the Vault Infrastructure Integration SDKs. For additional examples and advanced usage patterns, see the example applications and CI/CD templates included in this package.