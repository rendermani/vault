# Vault Infrastructure Integration Package

A comprehensive integration package for connecting applications to HashiCorp Vault infrastructure, including Vault, Consul, Nomad, and Prometheus.

## 🚀 Features

- **Multi-language SDKs**: Python and JavaScript/Node.js libraries
- **Complete CI/CD Integration**: GitHub Actions, GitLab CI, and Jenkins pipelines
- **Example Applications**: Production-ready Flask and Express.js examples
- **Comprehensive Testing**: Integration test suite with security and performance validation
- **Helper Utilities**: CLI tools for setup, deployment, and management
- **Best Practices**: Security, monitoring, and deployment guidelines

## 📁 Package Structure

```
integrations/
├── python/                          # Python SDK
│   ├── vault_integration_sdk.py     # Main SDK module
│   ├── requirements.txt             # Dependencies
│   └── setup.py                     # Package setup
├── javascript/                      # JavaScript SDK
│   ├── vault-integration-sdk.js     # Main SDK module
│   └── package.json                 # Dependencies
├── ci-cd/                          # CI/CD Pipeline Templates
│   ├── github-actions/             # GitHub Actions workflows
│   ├── gitlab-ci/                  # GitLab CI pipeline
│   └── jenkins/                    # Jenkins pipeline
├── examples/                       # Example Applications
│   ├── python-flask-app/           # Flask example
│   └── javascript-express-app/     # Express.js example
├── tests/                          # Test Suites
│   └── integration_test_suite.py   # Comprehensive integration tests
├── utils/                          # Helper Utilities
│   └── vault-cli-helper.py         # CLI helper tool
└── docs/                           # Documentation
    ├── integration-guide.md        # Complete integration guide
    └── deployment-workflows.md     # Deployment documentation
```

## 🚀 Quick Start

### 1. Choose Your SDK

#### Python
```bash
cd integrations/python
pip install -r requirements.txt
pip install -e .
```

#### JavaScript/Node.js
```bash
cd integrations/javascript
npm install
```

### 2. Set Environment Variables

```bash
# Vault
export VAULT_ADDR=https://vault.your-domain.com:8200
export VAULT_TOKEN=your-vault-token

# Consul
export CONSUL_HTTP_ADDR=https://consul.your-domain.com:8500
export CONSUL_HTTP_TOKEN=your-consul-token

# Nomad
export NOMAD_ADDR=https://nomad.your-domain.com:4646
export NOMAD_TOKEN=your-nomad-token

# Prometheus
export PROMETHEUS_URL=https://prometheus.your-domain.com:9090
```

### 3. Basic Usage

#### Python
```python
from vault_integration_sdk import VaultInfrastructureSDK

# Initialize SDK
sdk = VaultInfrastructureSDK()

# Retrieve secrets
secrets = sdk.vault.get_secret("applications/my-app/production")

# Register service
service_config = {
    'name': 'my-app',
    'port': 8080,
    'health_check_url': 'http://localhost:8080/health'
}
sdk.consul.register_service(service_config)

# Deploy job
job_spec = {...}  # Your Nomad job specification
result = sdk.nomad.submit_job(job_spec)
```

#### JavaScript
```javascript
const { VaultInfrastructureSDK } = require('vault-infrastructure-sdk');

// Initialize SDK
const sdk = new VaultInfrastructureSDK();

// Retrieve secrets
const secrets = await sdk.vault.getSecret('applications/my-app/production');

// Register service
const serviceConfig = {
    name: 'my-app',
    port: 8080,
    health_check_url: 'http://localhost:8080/health'
};
await sdk.consul.registerService(serviceConfig);

// Deploy job
const jobSpec = {...};  // Your Nomad job specification
const result = await sdk.nomad.submitJob(jobSpec);
```

## 📊 Infrastructure Health Check

Both SDKs provide comprehensive health checking:

```python
# Python
health_status = await sdk.health_check_all()
print(f"Infrastructure status: {health_status}")
```

```javascript
// JavaScript
const healthStatus = await sdk.healthCheckAll();
console.log(`Infrastructure status: ${JSON.stringify(healthStatus)}`);
```

## 🔄 CI/CD Integration

### GitHub Actions

Use the provided workflow templates:

```yaml
# .github/workflows/deploy.yml
name: Deploy with Vault Integration
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
```

### GitLab CI

```yaml
# .gitlab-ci.yml
include:
  - 'integrations/ci-cd/gitlab-ci/vault-integration-pipeline.yml'

variables:
  APP_NAME: "my-application"
```

### Jenkins

```groovy
// Jenkinsfile
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

## 🧪 Testing

Run the comprehensive integration test suite:

```bash
cd integrations/tests
python integration_test_suite.py --config ../config.json --output results.json
```

The test suite validates:
- Infrastructure component health
- Vault secrets management
- Consul service discovery
- Nomad job deployment
- Prometheus metrics collection
- End-to-end workflows
- Security features
- Performance characteristics

## 🛠️ CLI Helper Tool

Use the CLI helper for common operations:

```bash
cd integrations/utils

# Setup application secrets and policies
python vault-cli-helper.py setup-app my-app --environments production staging

# Check infrastructure health
python vault-cli-helper.py health-check

# Rotate application secrets
python vault-cli-helper.py rotate-secrets my-app production

# Pre-deployment verification
python vault-cli-helper.py deploy-check my-app production --image-tag v1.2.3
```

## 📱 Example Applications

### Flask Application (Python)
```bash
cd examples/python-flask-app
pip install -r requirements.txt
export VAULT_ADDR=https://your-vault-url:8200
export VAULT_TOKEN=your-token
python app.py
```

### Express Application (JavaScript)
```bash
cd examples/javascript-express-app
npm install
export VAULT_ADDR=https://your-vault-url:8200
export VAULT_TOKEN=your-token
npm start
```

Both examples demonstrate:
- Vault secrets integration
- Consul service registration
- Prometheus metrics export
- JWT authentication
- Database connection management
- Graceful shutdown handling

## 🔐 Security Features

### AppRole Authentication
```python
# Python
sdk.vault.authenticate_approle(role_id, secret_id)
```

```javascript
// JavaScript
await sdk.vault.authenticateAppRole(roleId, secretId);
```

### Dynamic Database Secrets
```python
# Python
db_credentials = sdk.vault.get_database_credentials("app-db-role")
```

```javascript
// JavaScript
const dbCredentials = await sdk.vault.getDatabaseCredentials('app-db-role');
```

### Automatic Token Renewal
```python
# Python
sdk.vault.setup_auto_renewal(interval_ms=300000)  # 5 minutes
```

```javascript
// JavaScript
sdk.vault.setupAutoRenewal(300000);  // 5 minutes
```

## 📈 Monitoring Integration

### Custom Metrics
```python
# Python
from prometheus_client import Counter, Histogram

request_count = Counter('http_requests_total', 'Total requests')
request_duration = Histogram('http_request_duration_seconds', 'Request duration')
```

```javascript
// JavaScript
const promClient = require('prom-client');

const requestCount = new promClient.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests'
});
```

### Metrics Push to Prometheus
```python
# Python
sdk.prometheus.push_metric(
    job_name="my-app",
    metric_name="custom_metric",
    metric_value=42.0,
    labels={"environment": "production"}
)
```

```javascript
// JavaScript - handled by Prometheus client libraries
```

## 🏗️ Deployment Strategies

The integration supports multiple deployment strategies:

1. **Rolling Updates**: Gradual replacement with health checks
2. **Blue-Green**: Zero-downtime deployments with traffic switching
3. **Canary**: Risk-controlled deployments with monitoring

See [deployment-workflows.md](docs/deployment-workflows.md) for detailed guides.

## 📚 Documentation

- **[Integration Guide](docs/integration-guide.md)**: Comprehensive usage documentation
- **[Deployment Workflows](docs/deployment-workflows.md)**: Deployment strategies and procedures
- **[API Reference](docs/integration-guide.md#api-reference)**: Complete API documentation

## 🛠️ Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

### Testing

```bash
# Python SDK tests
cd integrations/python
pytest tests/ -v

# JavaScript SDK tests
cd integrations/javascript
npm test

# Integration tests
cd integrations/tests
python integration_test_suite.py
```

### Code Quality

```bash
# Python
black integrations/python/
flake8 integrations/python/

# JavaScript
cd integrations/javascript
npm run lint
npm run format
```

## 📋 Requirements

### Infrastructure Requirements

- HashiCorp Vault 1.12+
- Consul 1.15+
- Nomad 1.6+
- Prometheus 2.40+

### SDK Requirements

#### Python
- Python 3.8+
- hvac 1.2+
- python-consul 1.1+
- requests 2.31+
- prometheus-client 0.17+

#### JavaScript
- Node.js 16+
- axios 1.5+
- winston 3.10+

## 🐛 Troubleshooting

### Common Issues

1. **Vault Authentication Failures**
   ```bash
   vault token lookup
   vault policy read my-app-policy
   ```

2. **Consul Service Registration Issues**
   ```bash
   consul members
   consul catalog services
   ```

3. **Nomad Job Failures**
   ```bash
   nomad job status my-job
   nomad alloc logs <allocation-id>
   ```

### Debug Mode

Enable debug logging:

```bash
export VAULT_LOG_LEVEL=debug
export CONSUL_LOG_LEVEL=debug
export NOMAD_LOG_LEVEL=debug
```

## 📞 Support

- **Documentation**: Check the `docs/` directory
- **Examples**: Review the `examples/` directory
- **Issues**: Use the project issue tracker
- **Testing**: Run the integration test suite

## 📄 License

MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- HashiCorp for the excellent infrastructure tools
- The open-source community for inspiration and libraries
- Contributors and maintainers of this integration package

---

**Ready to integrate?** Start with the [Integration Guide](docs/integration-guide.md) or jump into the [example applications](examples/) to see the SDKs in action!