# Cloudya Vault Infrastructure - Test Suite

Comprehensive testing suite for the HashiCorp stack (Vault, Consul, Nomad, Traefik) with security, performance, and monitoring validation.

## 📋 Test Categories

### 🔐 SSL/TLS Tests
- **Location**: `tests/ssl/`
- **Command**: `npm run test:ssl`
- **Coverage**: Certificate validation, TLS protocols, cipher suites
- **Tools**: OpenSSL, custom shell scripts

### 🔗 Integration Tests
- **Location**: `tests/integration/`
- **Command**: `npm run test:integration`
- **Coverage**: 
  - Vault secret management
  - Nomad job deployment
  - Consul service discovery
  - Traefik routing and load balancing
- **Tools**: Jest, Node.js test frameworks

### 🛡️ Security Tests
- **Location**: `tests/security/`
- **Command**: `npm run test:security`
- **Coverage**:
  - Credential scanning (hardcoded secrets detection)
  - ACL enforcement validation
  - TLS/SSL security configuration
  - Vulnerability assessments
- **Tools**: Jest, security scanning utilities

### ⚡ Performance Tests
- **Location**: `tests/performance/`
- **Command**: `npm run test:performance`
- **Coverage**:
  - Response time benchmarks
  - Concurrent operation handling
  - Memory usage validation
  - Throughput measurements
- **Tools**: Jest, performance profiling

### 📊 Monitoring Tests
- **Location**: `tests/monitoring/`
- **Command**: `npm run test:monitoring`
- **Coverage**:
  - Prometheus metrics collection
  - Grafana dashboard validation
  - Alert rule configuration
  - Log aggregation verification
- **Tools**: Jest, monitoring API clients

### 🤖 Automation Script Tests
- **Location**: `tests/scripts/`
- **Command**: `npm run test:automation`
- **Coverage**:
  - Script functionality validation
  - Error handling verification
  - Dependency checking
  - Syntax analysis (ShellCheck)
- **Tools**: Bash, ShellCheck

## 🚀 Quick Start

### Prerequisites
```bash
# Install Node.js dependencies
npm install

# Install system dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y curl jq openssl shellcheck

# Install system dependencies (macOS)
brew install curl jq openssl shellcheck
```

### Run All Tests
```bash
# Run complete test suite
npm run test:all

# Run specific test categories
npm run test:ssl
npm run test:integration
npm run test:security
npm run test:performance
npm run test:monitoring
npm run test:automation

# Run with coverage
npm run test -- --coverage

# Watch mode for development
npm run test:watch
```

### CI/CD Integration
```bash
# Silent mode for CI pipelines
npm run test:ci

# Generate coverage reports
npm run coverage
```

## 📊 Test Reports

### Automatic Report Generation
After running tests, comprehensive reports are generated in `tests/reports/`:

- **HTML Report**: `comprehensive_test_report.html` - Interactive dashboard
- **JSON Report**: `comprehensive_test_report.json` - Machine-readable results
- **Coverage Reports**: `tests/reports/coverage/` - Code coverage analysis
- **Individual Reports**: Category-specific JSON/log files

### Generate Custom Reports
```bash
# Generate comprehensive report from existing results
node tests/generate_report.js

# View HTML report (opens in browser)
open tests/reports/comprehensive_test_report.html
```

## 🔧 Configuration

### Environment Variables
```bash
# Service endpoints
export VAULT_ADDR="http://localhost:8200"
export CONSUL_ADDR="http://localhost:8500"
export NOMAD_ADDR="http://localhost:4646"
export TRAEFIK_ADDR="http://localhost:8080"

# Test configuration
export SKIP_INTEGRATION="false"
export SKIP_PERFORMANCE="false"
export TEST_TIMEOUT="60000"
```

### Test Configuration File
Edit `tests/setup.js` to modify global test settings:
- Timeouts per test category
- Service endpoints
- Mock configurations
- Global utilities

## 📈 Performance Thresholds

| Service | Metric | Threshold |
|---------|---------|-----------|
| Vault | Secret Read | ≤ 100ms |
| Vault | Secret Write | ≤ 200ms |
| Consul | KV Read | ≤ 50ms |
| Consul | Service Discovery | ≤ 30ms |
| Nomad | Job Submission | ≤ 500ms |
| Traefik | Routing Latency | ≤ 10ms |
| Traefik | SSL Handshake | ≤ 50ms |

## 🔒 Security Test Coverage

### Credential Scanning
- Hardcoded passwords, API keys, tokens
- Private key detection
- Weak credential patterns
- Environment variable usage validation

### Access Control Lists (ACL)
- Vault policy validation
- Consul ACL rules
- Nomad namespace isolation
- Cross-service authentication

### TLS/SSL Security
- Certificate chain validation
- Protocol version enforcement
- Cipher suite strength
- Vulnerability protections (BEAST, CRIME, etc.)

## 📋 Test Structure

```
tests/
├── integration/          # Service integration tests
│   ├── vault_test.js
│   ├── consul_test.js
│   ├── nomad_test.js
│   └── traefik_test.js
├── security/             # Security validation tests
│   ├── credential_scan.js
│   ├── acl_test.js
│   └── tls_ssl_test.js
├── performance/          # Performance benchmarks
│   └── performance_test.js
├── monitoring/           # Monitoring validation
│   └── monitoring_test.js
├── scripts/              # Automation script tests
│   └── automation_test.sh
├── ssl/                  # SSL certificate tests
│   └── ssl_test.sh
├── reports/              # Generated test reports
├── package.json          # Node.js dependencies
├── setup.js             # Global test configuration
├── generate_report.js   # Report generator
└── README.md            # This file
```

## 🎯 Testing Best Practices

### Unit Tests
- Mock external dependencies
- Test edge cases and error conditions
- Validate input/output contracts
- Maintain fast execution times

### Integration Tests
- Test real component interactions
- Validate end-to-end workflows
- Check error handling and recovery
- Verify configuration compatibility

### Security Tests
- Never expose real credentials
- Use secure test data patterns
- Validate all access controls
- Test security configurations

### Performance Tests
- Establish baseline metrics
- Test under realistic loads
- Monitor resource consumption
- Validate scalability limits

## 🚨 Troubleshooting

### Common Issues

**Tests timing out**
```bash
# Increase timeout for specific test
jest --testTimeout=120000

# Or set environment variable
export TEST_TIMEOUT=120000
```

**Service connection errors**
```bash
# Check service availability
curl -f http://localhost:8200/v1/sys/health  # Vault
curl -f http://localhost:8500/v1/status/leader  # Consul
curl -f http://localhost:4646/v1/status/leader  # Nomad
curl -f http://localhost:8080/ping  # Traefik
```

**Permission denied on scripts**
```bash
# Make scripts executable
chmod +x tests/ssl/ssl_test.sh
chmod +x tests/scripts/automation_test.sh
```

**Missing dependencies**
```bash
# Check for required tools
which jq curl openssl docker shellcheck

# Install missing dependencies
npm install
```

### Debug Mode
```bash
# Enable verbose output
DEBUG=* npm test

# Run specific test with debug info
jest tests/integration/vault_test.js --verbose --no-cache
```

## 🤝 Contributing

### Adding New Tests
1. Create test file in appropriate category directory
2. Follow existing naming conventions (`*_test.js` or `*_test.sh`)
3. Use provided mocking patterns
4. Add test to package.json scripts if needed
5. Update documentation

### Test Standards
- All tests must be deterministic
- Mock external dependencies
- Include both positive and negative test cases
- Provide clear test descriptions and error messages
- Follow established timeout patterns

### Reporting Issues
- Include test output and logs
- Specify environment details
- Provide steps to reproduce
- Include relevant configuration

## 📞 Support

- **Documentation**: See individual test category README files
- **Issues**: GitHub Issues for bug reports and feature requests
- **Monitoring**: Check Grafana dashboards for infrastructure health
- **Logs**: Review test reports in `tests/reports/` directory

---

**Note**: This test suite is designed to validate a complete HashiCorp infrastructure stack. Ensure all services are properly configured and accessible before running tests.