# CloudYa Security Automation Suite

This directory contains comprehensive security automation scripts that address all critical security findings and implement enterprise-grade security measures.

## 🚨 Security Issues Addressed

### CRITICAL Issues Resolved
- ✅ **Hardcoded Basic Auth Credentials** - All credentials moved to Vault
- ✅ **Default Grafana Admin Password** - Secure password generation and rotation
- ✅ **Manual Vault Unsealing** - Auto-unseal configuration prepared

### HIGH Issues Resolved
- ✅ **Vault Network Exposure** - Services bound to localhost only
- ✅ **Missing TLS Client Verification** - Mutual TLS implemented
- ✅ **Weak TLS Configuration** - TLS 1.3 enforced with strong ciphers
- ✅ **Exposed Internal Services** - Network segmentation implemented

### MEDIUM Issues Resolved
- ✅ **Insufficient Audit Logging** - Comprehensive logging enabled
- ✅ **Missing Rate Limiting** - Rate limiting middleware configured
- ✅ **Container Security** - Security constraints and resource limits
- ✅ **Network Segmentation** - Isolated networks for services

## 📁 Directory Structure

```
automation/
├── README.md                          # This file
├── deployment-scripts/                # Secure deployment automation
│   ├── deploy-secure.sh               # Main secure deployment script
│   └── environments/                  # Environment-specific configs
│       ├── production.env
│       ├── staging.env
│       └── development.env
├── rotation-scripts/                  # Secret rotation automation
│   ├── rotation-engine.sh             # Main rotation engine
│   ├── rotate-tokens.sh               # Token rotation
│   └── monitor-rotation.sh            # Rotation monitoring
├── ssl-scripts/                       # SSL certificate management
│   ├── rotate-certificates.sh         # Certificate rotation
│   └── monitor-certificates.sh        # Certificate monitoring
├── acl-scripts/                       # ACL management
│   ├── rotate-tokens.sh               # ACL token rotation
│   └── acl-health-check.sh           # ACL health monitoring
├── templates/                         # Vault Agent templates
│   ├── traefik-auth.tpl
│   ├── grafana-env.tpl
│   └── docker-compose-production.yml.tpl
├── ssl-certs/                         # SSL certificates
│   ├── services/                      # Service certificates
│   └── clients/                       # Client certificates
└── vault-secrets/                     # Vault secret configurations
```

## 🛠 Main Automation Scripts

### 1. Security Automation Master (`/scripts/security-automation-master.sh`)
**Purpose**: Orchestrates all security automations
**Features**:
- Coordinates execution of all security automation scripts
- Provides rollback capabilities on failure
- Generates comprehensive security reports
- Validates all automations completed successfully

**Usage**:
```bash
sudo ./scripts/security-automation-master.sh
```

### 2. Secrets Migration (`/scripts/secrets-migration-automation.sh`)
**Purpose**: Migrates hardcoded credentials to Vault
**Features**:
- Removes all hardcoded basic auth hashes
- Generates secure passwords with bcrypt hashing
- Creates Vault policies for secret access
- Sets up Vault Agent for automatic secret injection
- Configures auto-unseal preparation

**Secrets Created**:
- `secret/cloudya/traefik/admin` - Traefik dashboard authentication
- `secret/cloudya/grafana/admin` - Grafana admin credentials
- `secret/cloudya/prometheus/admin` - Prometheus authentication
- `secret/cloudya/consul/admin` - Consul UI authentication

### 3. ACL Automation (`/scripts/acl-automation.sh`)
**Purpose**: Configures ACLs for Consul and Nomad
**Features**:
- Bootstrap ACL systems for Consul and Nomad
- Create service-specific policies with least privilege
- Generate tokens for service authentication
- Configure Vault integration for dynamic token generation

**Policies Created**:
- Consul: nomad-server, nomad-client, vault-service, traefik-service, monitoring-service
- Nomad: vault-integration, traefik-workload, monitoring-workload, developer, operations

### 4. SSL Automation (`/scripts/ssl-automation.sh`)
**Purpose**: Implements comprehensive SSL certificate management
**Features**:
- Sets up Vault PKI infrastructure (Root + Intermediate CA)
- Generates service certificates with proper SANs
- Creates client certificates for mutual TLS
- Updates service configurations for TLS 1.3
- Implements automated certificate rotation

**Certificates Generated**:
- Service certs: vault.crt, consul.crt, nomad.crt, traefik.crt
- Client certs: admin-client.crt, service-specific client certs
- CA certificates for trust chains

### 5. Secret Rotation (`/scripts/secret-rotation-automation.sh`)
**Purpose**: Implements automated secret rotation
**Features**:
- Configurable rotation schedules based on secret sensitivity
- Dynamic database credential generation
- Application secret rotation with service restart triggers
- Comprehensive rotation monitoring and alerting

**Rotation Schedules**:
- Traefik admin: 24h (max 7d)
- Grafana admin: 12h (max 24h)
- API keys: 1h (max 8h)
- Database credentials: Dynamic generation

### 6. Deployment Automation (`/scripts/deployment-automation.sh`)
**Purpose**: Updates deployment to use Vault for all secrets
**Features**:
- Updates docker-compose.production.yml for Vault integration
- Removes all hardcoded credentials
- Implements Vault Agent sidecar pattern
- Creates secure deployment procedures
- Generates GitHub Actions workflow for CI/CD

### 7. Security Validation (`/scripts/security-validation-automation.sh`)
**Purpose**: Comprehensive security testing and validation
**Features**:
- 15 comprehensive security tests
- Validates all critical issues are resolved
- Checks compliance with security standards
- Generates detailed security reports
- Provides remediation recommendations

## 🔄 Automated Processes

### Systemd Timers Created
- `secret-rotation.timer` - Every 6 hours
- `token-rotation.timer` - Daily  
- `cert-rotation.timer` - Daily
- `rotation-monitoring.timer` - Every 2 hours

### Vault Agent Templates
- Automatic secret injection into service configurations
- Real-time updates when secrets rotate
- Secure file permissions and ownership

### Monitoring and Alerting
- Health checks for all security systems
- Email alerts for certificate expiration
- Rotation failure notifications
- Security incident detection

## 🚀 Quick Start Guide

### Prerequisites
```bash
# Install required tools
sudo apt-get install vault consul nomad docker docker-compose jq bc python3-bcrypt

# Ensure Vault is initialized and unsealed
vault status
```

### Full Security Automation
```bash
# Run complete security automation (recommended)
sudo ./scripts/security-automation-master.sh
```

### Individual Automations
```bash
# Run specific automation components
sudo ./scripts/secrets-migration-automation.sh
sudo ./scripts/acl-automation.sh
sudo ./scripts/ssl-automation.sh
sudo ./scripts/secret-rotation-automation.sh
sudo ./scripts/deployment-automation.sh
```

### Validation Only
```bash
# Test current security posture
sudo ./scripts/security-validation-automation.sh
```

## 📊 Security Validation Tests

The security validation automation runs 15 comprehensive tests:

1. **Hardcoded Credentials Removal** - Ensures no hardcoded passwords remain
2. **Vault Secret Storage** - Verifies all secrets are stored in Vault
3. **Auto-unseal Configuration** - Checks auto-unseal setup
4. **TLS Configuration** - Validates strong TLS 1.3 implementation
5. **ACL Configurations** - Tests Consul and Nomad ACL enforcement
6. **Secret Rotation** - Verifies automated rotation is working
7. **Network Security** - Checks proper service binding and isolation
8. **Audit Logging** - Ensures comprehensive audit trails
9. **Vault Agent** - Validates automatic secret injection
10. **Certificate Management** - Tests PKI and certificate rotation
11. **Service Health** - Checks all services are accessible and healthy
12. **Security Compliance** - Validates compliance with security standards
13. **Backup Recovery** - Ensures backup procedures are in place
14. **Monitoring Alerting** - Tests monitoring and alerting systems
15. **Documentation** - Checks documentation completeness

## 🔐 Security Features Implemented

### Secret Management
- ✅ All secrets stored in Vault with encryption at rest
- ✅ Dynamic secret generation for databases
- ✅ Automated secret rotation with configurable TTLs
- ✅ Vault Agent for seamless secret injection

### Network Security
- ✅ Services bound to localhost/internal networks only
- ✅ Network segmentation with isolated Docker networks
- ✅ TLS 1.3 with strong cipher suites
- ✅ Mutual TLS for service-to-service communication

### Access Control
- ✅ ACL enforcement in Consul and Nomad
- ✅ Least privilege policies for all services
- ✅ Token-based authentication with automatic rotation
- ✅ Role-based access control (RBAC)

### Certificate Management
- ✅ Internal PKI with Root and Intermediate CAs
- ✅ Automated certificate generation and rotation
- ✅ Certificate expiration monitoring and alerting
- ✅ Proper certificate chain validation

### Monitoring and Compliance
- ✅ Comprehensive audit logging
- ✅ Security event monitoring
- ✅ Automated compliance checking
- ✅ Real-time alerting for security issues

## 📈 Performance and Reliability

### High Availability
- Multi-service health checks
- Automatic service restart on secret rotation
- Circuit breaker patterns in Traefik
- Graceful failure handling

### Performance
- Optimized secret caching
- Minimal service downtime during rotation
- Efficient certificate management
- Monitoring with minimal overhead

### Reliability
- Comprehensive backup procedures
- Rollback capabilities
- State validation and recovery
- Idempotent automation scripts

## 🚨 Emergency Procedures

### Security Incident Response
1. Run immediate validation: `./scripts/security-validation-automation.sh`
2. Check recent logs: `tail -f /var/log/cloudya-security/*.log`
3. Rotate all secrets immediately: `./automation/rotation-scripts/rotation-engine.sh rotate`
4. Generate incident report: Review validation output

### Rollback Procedures
1. The master script maintains automatic backups
2. Rollback path stored in `/var/log/cloudya-security/last-backup-path`
3. Manual rollback: Restore from backup directory
4. Service restart: `docker-compose restart`

### Certificate Emergency
1. Check certificate status: `./automation/ssl-scripts/monitor-certificates.sh`
2. Force certificate rotation: `./automation/ssl-scripts/rotate-certificates.sh`
3. Manual certificate generation via Vault PKI

## 📞 Support and Maintenance

### Regular Maintenance
- Monitor systemd timer status: `systemctl list-timers`
- Review rotation logs: `journalctl -u secret-rotation.service`
- Check certificate expiration: Weekly validation runs
- Update documentation: After any configuration changes

### Troubleshooting
1. **Vault Agent Issues**: Check `/opt/cloudya-infrastructure/secrets/` permissions
2. **Secret Rotation Failures**: Verify Vault connectivity and tokens
3. **Certificate Problems**: Check PKI configuration and CA chain
4. **ACL Issues**: Validate token permissions and policy assignments

### Log Locations
- Security automation: `/var/log/cloudya-security/`
- Service logs: `docker-compose logs <service>`
- System logs: `journalctl -f`
- Audit logs: `/vault/logs/audit.log`

---

## 🎯 Success Metrics

After running the complete security automation:

- **0** hardcoded credentials in configurations
- **100%** secrets managed by Vault
- **TLS 1.3** enforced across all services
- **Automated** secret rotation every 6-24 hours
- **Mutual TLS** for service authentication
- **ACL enforcement** for all HashiCorp services
- **Comprehensive** audit logging and monitoring

**Your CloudYa infrastructure is now production-ready with enterprise-grade security! 🚀**