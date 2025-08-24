# Vault Security Operations Runbook

## Table of Contents

1. [Security Overview](#security-overview)
2. [Emergency Procedures](#emergency-procedures)
3. [Security Monitoring](#security-monitoring)
4. [Incident Response](#incident-response)
5. [Compliance and Auditing](#compliance-and-auditing)
6. [Certificate Management](#certificate-management)
7. [Token Security](#token-security)
8. [Backup and Recovery](#backup-and-recovery)
9. [Security Best Practices](#security-best-practices)
10. [Troubleshooting](#troubleshooting)

## Security Overview

### Infrastructure Security Components

- **TLS Configuration**: End-to-end encryption with TLS 1.2+
- **Token Management**: Encrypted storage and secure distribution
- **Audit Logging**: Comprehensive audit trail with real-time monitoring
- **Emergency Access**: Break-glass procedures for critical situations
- **Security Monitoring**: 24/7 threat detection and alerting
- **Certificate Management**: Automated certificate lifecycle management

### Security Architecture

```
┌─────────────────────────────────────────┐
│              Load Balancer               │
│            (TLS Termination)            │
└─────────────────┬───────────────────────┘
                  │ HTTPS (TLS 1.2+)
┌─────────────────┼───────────────────────┐
│                 │                       │
│    Vault Cluster (HA)                   │
│  ┌─────────────┴─────────────┐          │
│  │     Vault Node 1          │          │
│  │   (Primary/Leader)        │          │
│  └─────────────┬─────────────┘          │
│                │                        │
│  ┌─────────────┴─────────────┐          │
│  │     Vault Node 2          │          │
│  │    (Standby/Follower)     │          │
│  └─────────────┬─────────────┘          │
│                │                        │
│  └─────────────┼─────────────────────────┘
                  │ Encrypted Raft
┌─────────────────┼───────────────────────┐
│                 │                       │
│        Storage Backend                  │
│      (Integrated Raft)                 │
│                                         │
└─────────────────────────────────────────┘
```

## Emergency Procedures

### 🚨 Break-Glass Access

#### When to Use Break-Glass
- All normal authentication methods are unavailable
- Critical system outage requiring immediate access
- Security incident requiring emergency response
- Loss of all administrative tokens

#### Break-Glass Unseal Procedure

```bash
# 1. Assess the situation
systemctl status vault
vault status

# 2. Initiate break-glass unseal
cd /Users/mlautenschlager/cloudya/vault/security
./emergency-access.sh break-glass-unseal

# 3. Follow prompts to enter emergency unseal keys
# (Keys must be obtained from emergency contacts)

# 4. Verify unsealing success
vault status

# 5. Generate temporary emergency token
./emergency-access.sh generate-emergency-token 2h
```

#### Root Token Recovery

```bash
# When root token is lost or compromised
./emergency-access.sh recover-root-token

# Follow the interactive prompts to select recovery method:
# 1. Use existing emergency token
# 2. Use recovery keys (if configured)
# 3. Generate from existing valid token
# 4. Use DR operation token
```

#### Emergency Contacts

| Role | Contact | Method |
|------|---------|--------|
| Primary Admin | admin@cloudya.net | Email, SMS |
| Security Team | security@cloudya.net | Email, Slack |
| On-Call Engineer | +1-XXX-XXX-XXXX | Phone, PagerDuty |
| Emergency Key Holder 1 | holder1@cloudya.net | Encrypted Email |
| Emergency Key Holder 2 | holder2@cloudya.net | Encrypted Email |

### Emergency Escalation Matrix

```
Severity 1 (Critical): System Down / Security Breach
├── Immediate: Notify all emergency contacts
├── 15 min: Engage incident response team
├── 30 min: Update stakeholders
└── 1 hour: Escalate to executive team

Severity 2 (High): Degraded Performance / Failed Component
├── 15 min: Notify primary admin
├── 30 min: Engage on-call engineer
└── 2 hours: Update stakeholders

Severity 3 (Medium): Warning Conditions
├── 1 hour: Log incident
└── 4 hours: Notify during business hours

Severity 4 (Low): Information / Scheduled Maintenance
└── Next business day: Document and plan
```

## Security Monitoring

### Real-Time Monitoring Components

1. **Health Monitoring**
   - Vault service availability
   - API response times
   - Resource utilization (CPU, memory, disk)

2. **Security Event Detection**
   - Failed authentication attempts
   - Unusual token usage patterns
   - Policy and configuration changes
   - Certificate expiration warnings

3. **Audit Log Analysis**
   - Real-time log parsing
   - Pattern recognition
   - Anomaly detection
   - Compliance validation

### Monitoring Dashboard

```bash
# Start continuous monitoring
./security-monitor.sh start

# Generate monitoring reports
./security-monitor.sh report daily
./security-monitor.sh report weekly
./security-monitor.sh report monthly

# Run specific checks
./security-monitor.sh health
./security-monitor.sh auth
./security-monitor.sh performance
```

### Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Failed Auth/min | >10 | >20 |
| Token Creation/min | >20 | >50 |
| Root Token Usage | Any | N/A |
| API Response Time | >1000ms | >5000ms |
| CPU Usage | >80% | >90% |
| Memory Usage | >80% | >90% |
| Disk Usage | >85% | >95% |
| Certificate Expiry | <30 days | <7 days |

## Incident Response

### Incident Classification

#### Security Incidents
- **Data Breach**: Unauthorized access to sensitive data
- **Token Compromise**: Compromised authentication tokens
- **Unauthorized Access**: Successful unauthorized authentication
- **Policy Violations**: Unauthorized policy changes
- **Certificate Compromise**: TLS certificate security issues

#### Operational Incidents
- **Service Outage**: Vault unavailable or degraded
- **Performance Issues**: Slow response times
- **Storage Issues**: Disk space or corruption
- **Network Issues**: Connectivity problems

### Incident Response Process

#### 1. Detection and Analysis (0-15 minutes)
- **Automated Detection**: Security monitoring alerts
- **Manual Detection**: User reports, log analysis
- **Initial Assessment**: Severity classification
- **Evidence Collection**: Log snapshots, system state

```bash
# Capture system state for analysis
./security-monitor.sh cycle > incident-$(date +%Y%m%d-%H%M%S).log
./emergency-access.sh emergency-backup
```

#### 2. Containment (15-30 minutes)
- **Isolate Affected Systems**: Network segmentation
- **Revoke Compromised Credentials**: Token/certificate revocation
- **Enable Additional Logging**: Increase audit verbosity
- **Preserve Evidence**: System snapshots, memory dumps

```bash
# Revoke all tokens in case of compromise
./emergency-access.sh incident-response token_compromise

# Enable enhanced audit logging
./audit-logger.sh enable
```

#### 3. Eradication and Recovery (30 minutes - 4 hours)
- **Remove Threats**: Malware, unauthorized access
- **Patch Vulnerabilities**: System updates, configuration fixes
- **Restore Services**: From clean backups if needed
- **Validate Integrity**: System and data verification

```bash
# Emergency restore if needed
./emergency-access.sh emergency-restore /path/to/backup

# Validate system integrity
./security-monitor.sh health
vault status
```

#### 4. Post-Incident Activities (Ongoing)
- **Lessons Learned**: Document findings
- **Process Improvements**: Update procedures
- **Training Updates**: Staff education
- **Monitoring Enhancements**: Improve detection

### Incident Response Playbooks

#### Token Compromise Response
```bash
# 1. Immediate containment
./emergency-access.sh incident-response token_compromise

# 2. Generate emergency access token
./emergency-access.sh generate-emergency-token 4h incident_response

# 3. Audit recent token activity
./audit-logger.sh report daily

# 4. Rotate all service tokens
vault write -field=token auth/token/create policies=service-policy

# 5. Update applications with new tokens
# (Coordinate with development teams)

# 6. Document incident
echo "Token compromise incident at $(date)" >> /var/log/vault/incidents.log
```

#### Unauthorized Access Response
```bash
# 1. Identify affected accounts
grep "unauthorized" /var/log/vault/audit/vault-audit.log

# 2. Disable compromised authentication methods temporarily
vault auth disable userpass  # Example - adjust as needed

# 3. Enable enhanced monitoring
./security-monitor.sh start

# 4. Review and update policies
vault policy list
vault policy read suspicious-policy

# 5. Reset affected user credentials
vault write auth/userpass/users/username password=new-secure-password
```

## Compliance and Auditing

### Audit Requirements

#### SOC 2 Type II Compliance
- **Continuous Monitoring**: 24/7 security monitoring
- **Access Controls**: Role-based access with least privilege
- **Data Protection**: Encryption at rest and in transit
- **Incident Response**: Documented procedures and testing
- **Vendor Management**: Third-party security assessments

#### GDPR Compliance
- **Data Minimization**: Store only necessary data
- **Access Rights**: Subject access request procedures
- **Breach Notification**: 72-hour reporting requirements
- **Data Protection**: Technical and organizational measures
- **Privacy by Design**: Default privacy settings

#### HIPAA Compliance (if applicable)
- **Administrative Safeguards**: Security officer designation
- **Physical Safeguards**: Facility access controls
- **Technical Safeguards**: Access control and audit controls
- **Risk Assessment**: Annual security risk assessments

### Audit Log Management

```bash
# Enable comprehensive audit logging
./audit-logger.sh full-setup

# Generate compliance reports
./audit-logger.sh report daily
./audit-logger.sh report monthly

# Check log integrity
./audit-logger.sh check-integrity

# Archive old logs
./audit-logger.sh archive 90
```

### Compliance Checks

#### Daily Checks
- [ ] Vault service health
- [ ] Authentication success rates
- [ ] Failed login attempts
- [ ] Policy changes
- [ ] Certificate validity
- [ ] Backup integrity

#### Weekly Checks
- [ ] Security monitoring review
- [ ] Incident report analysis
- [ ] User access review
- [ ] System performance analysis
- [ ] Vulnerability scanning
- [ ] Configuration validation

#### Monthly Checks
- [ ] Comprehensive security assessment
- [ ] Access right reviews
- [ ] Policy effectiveness review
- [ ] Disaster recovery testing
- [ ] Compliance gap analysis
- [ ] Staff security training

## Certificate Management

### TLS Certificate Lifecycle

#### Certificate Generation
```bash
# Self-signed certificates (development)
./tls-cert-manager.sh self-signed

# Let's Encrypt certificates (production)
VAULT_DOMAIN=vault.cloudya.net LE_EMAIL=admin@cloudya.net \
./tls-cert-manager.sh letsencrypt
```

#### Certificate Monitoring
```bash
# Check certificate status
./tls-cert-manager.sh verify

# View certificate information
./tls-cert-manager.sh info

# Setup automatic renewal
./tls-cert-manager.sh letsencrypt  # Includes auto-renewal setup
```

#### Certificate Rotation
```bash
# Manual certificate rotation
./tls-cert-manager.sh rotate

# Emergency certificate replacement
cp new-cert.pem /etc/vault.d/tls/vault-cert.pem
cp new-key.pem /etc/vault.d/tls/vault-key.pem
systemctl reload vault
```

### Certificate Security Best Practices

1. **Key Length**: Minimum 2048-bit RSA or 256-bit ECDSA
2. **Cipher Suites**: Strong ciphers only (AES-GCM, ChaCha20-Poly1305)
3. **Protocol Version**: TLS 1.2 minimum, TLS 1.3 preferred
4. **Certificate Transparency**: Monitor CT logs for unauthorized certificates
5. **OCSP Stapling**: Enable for real-time revocation checking

## Token Security

### Token Management Best Practices

#### Secure Token Storage
```bash
# Initialize secure token storage
./secure-token-manager.sh init

# Store tokens securely
./secure-token-manager.sh store app-token "hvs.XXXXXX" "Application token"

# Retrieve tokens
TOKEN=$(./secure-token-manager.sh retrieve app-token)
```

#### Token Rotation
```bash
# Generate new token
NEW_TOKEN=$(vault write -field=token auth/token/create policies=app-policy)

# Rotate stored token
./secure-token-manager.sh rotate app-token "$NEW_TOKEN" "Rotated token"

# Distribute to applications
./secure-token-manager.sh distribute app-token app-server:/etc/app/token
```

#### Token Monitoring
```bash
# Monitor token usage
./secure-token-manager.sh monitor

# List stored tokens
./secure-token-manager.sh list

# Clean up expired tokens
./secure-token-manager.sh cleanup
```

### Token Security Policies

#### Development Tokens
- **TTL**: Maximum 8 hours
- **Renewable**: Yes
- **Policies**: Least privilege
- **Usage**: Single application/service
- **Rotation**: Daily

#### Production Tokens
- **TTL**: Maximum 30 days
- **Renewable**: Yes, with approval
- **Policies**: Strictly scoped
- **Usage**: Specific service only
- **Rotation**: Weekly

#### Emergency Tokens
- **TTL**: Maximum 2 hours
- **Renewable**: No
- **Policies**: Limited scope
- **Usage**: Break-glass only
- **Rotation**: After each use

## Backup and Recovery

### Backup Strategy

#### Automated Backups
- **Frequency**: Daily full backups, hourly incrementals
- **Retention**: 30 days local, 90 days remote
- **Encryption**: AES-256 encryption at rest
- **Verification**: Daily backup integrity checks
- **Testing**: Weekly restore testing

```bash
# Create emergency backup
./emergency-access.sh emergency-backup

# Schedule automated backups (cron)
0 2 * * * /usr/local/bin/vault-backup.sh daily
0 */6 * * * /usr/local/bin/vault-backup.sh incremental
```

#### Disaster Recovery Plan

##### RTO/RPO Targets
- **RTO (Recovery Time Objective)**: 4 hours
- **RPO (Recovery Point Objective)**: 1 hour
- **Data Loss Tolerance**: Maximum 1 hour
- **Service Availability**: 99.9% uptime

##### Recovery Procedures
```bash
# 1. Assess damage and determine recovery scope
./emergency-access.sh emergency-backup  # Backup current state

# 2. Stop affected services
systemctl stop vault

# 3. Restore from backup
./emergency-access.sh emergency-restore /path/to/backup

# 4. Verify system integrity
vault status
./security-monitor.sh health

# 5. Resume operations
systemctl start vault
./security-monitor.sh start
```

## Security Best Practices

### Infrastructure Security

#### Network Security
- **Network Segmentation**: Isolated Vault network
- **Firewall Rules**: Restrict access to required ports only
- **VPN Access**: Secure remote administration
- **DDoS Protection**: Rate limiting and traffic filtering
- **Intrusion Detection**: Network-based IDS/IPS

#### Host Security
- **OS Hardening**: Minimal installation, security patches
- **User Management**: No shared accounts, sudo access control
- **File Permissions**: Strict file and directory permissions
- **Log Monitoring**: Centralized log collection and analysis
- **Antivirus**: Real-time malware protection

#### Application Security
- **Code Reviews**: Security-focused code reviews
- **Vulnerability Scanning**: Regular application scanning
- **Dependency Management**: Keep dependencies updated
- **Input Validation**: Validate all user inputs
- **Error Handling**: Secure error messages

### Operational Security

#### Access Control
- **Principle of Least Privilege**: Minimum required permissions
- **Role-Based Access**: Predefined roles and responsibilities
- **Multi-Factor Authentication**: Required for all admin access
- **Regular Access Reviews**: Quarterly access audits
- **Session Management**: Automatic session timeouts

#### Change Management
- **Change Approval**: All changes require approval
- **Testing Requirements**: Changes tested in staging
- **Rollback Procedures**: Documented rollback plans
- **Change Documentation**: Maintain change logs
- **Emergency Changes**: Expedited approval process

#### Monitoring and Alerting
- **24/7 Monitoring**: Continuous security monitoring
- **Alert Tuning**: Reduce false positives
- **Escalation Procedures**: Clear escalation paths
- **Response Times**: Defined SLAs for response
- **Documentation**: Maintain runbooks and procedures

## Troubleshooting

### Common Issues and Solutions

#### Vault Sealed
**Symptoms**: API returns 503 Service Unavailable, sealed=true
**Causes**: Server restart, memory exhaustion, storage issues
**Resolution**:
```bash
# Check seal status
vault status

# Unseal with keys
vault operator unseal <key1>
vault operator unseal <key2>  
vault operator unseal <key3>

# If keys unavailable, use break-glass procedure
./emergency-access.sh break-glass-unseal
```

#### Authentication Failures
**Symptoms**: Login attempts fail, unusual auth patterns
**Causes**: Wrong credentials, expired tokens, policy issues
**Resolution**:
```bash
# Check audit logs
./audit-logger.sh report daily | grep auth

# Verify user policies
vault token lookup
vault policy read user-policy

# Reset user credentials if needed
vault write auth/userpass/users/username password=new-password
```

#### Certificate Issues
**Symptoms**: TLS handshake failures, browser warnings
**Causes**: Expired certificates, wrong domains, key mismatches
**Resolution**:
```bash
# Check certificate validity
./tls-cert-manager.sh verify

# View certificate details
./tls-cert-manager.sh info

# Renew certificate
./tls-cert-manager.sh letsencrypt
```

#### Performance Issues
**Symptoms**: Slow response times, high resource usage
**Causes**: High load, memory leaks, disk I/O issues
**Resolution**:
```bash
# Check performance metrics
./security-monitor.sh performance

# Monitor resource usage
top -p $(pgrep vault)
iostat -x 1

# Review Vault configuration
vault read sys/config/state
```

#### Storage Issues
**Symptoms**: Write failures, corruption errors, space issues
**Causes**: Disk full, permissions, hardware failures
**Resolution**:
```bash
# Check disk space
df -h /var/lib/vault

# Verify permissions
ls -la /var/lib/vault

# Check for corruption
vault operator raft list-peers
```

### Diagnostic Commands

#### System Health Check
```bash
# Comprehensive health check
./security-monitor.sh health
systemctl status vault
vault status
vault operator raft list-peers
```

#### Log Analysis
```bash
# View recent logs
journalctl -u vault -f
tail -f /var/log/vault/vault.log
tail -f /var/log/vault/audit/vault-audit.log
```

#### Performance Analysis
```bash
# Resource usage
top -p $(pgrep vault)
netstat -tulpn | grep vault
lsof -p $(pgrep vault)

# Vault metrics
curl -s http://localhost:8200/v1/sys/metrics
```

## Contact Information

### Emergency Contacts
- **Primary**: admin@cloudya.net
- **Security**: security@cloudya.net
- **On-Call**: +1-XXX-XXX-XXXX

### Escalation
- **Level 1**: Operations Team
- **Level 2**: Security Team
- **Level 3**: Engineering Management
- **Level 4**: Executive Team

### External Resources
- **HashiCorp Support**: [support.hashicorp.com](https://support.hashicorp.com)
- **Security Advisories**: [security@hashicorp.com](mailto:security@hashicorp.com)
- **Documentation**: [vaultproject.io](https://www.vaultproject.io)

---

*This runbook is a living document and should be updated regularly to reflect changes in infrastructure, procedures, and security requirements.*