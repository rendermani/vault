# Cloudya Infrastructure Deployment Architecture

## Overview

This document describes the comprehensive deployment architecture for the Cloudya infrastructure, designed for both local development and production deployment to `root@cloudya.net`.

## Architecture Decisions

### 1. Deployment Strategy

**Decision**: Hybrid approach with local testing and remote production deployment
**Rationale**: Enables safe development iteration while maintaining production security
**Alternatives Considered**: Direct production deployment, GitOps-only approach
**Trade-offs**: Increased complexity but improved reliability and safety

### 2. Infrastructure Components

**Core Stack**:
- **HashiCorp Vault**: Secret management and encryption
- **HashiCorp Nomad**: Workload orchestration  
- **HashiCorp Consul**: Service discovery and configuration
- **Traefik**: Reverse proxy and load balancer

**Supporting Services**:
- **PostgreSQL**: Primary database
- **Redis**: Caching and session storage
- **MinIO**: S3-compatible object storage
- **Prometheus**: Metrics collection
- **Grafana**: Monitoring dashboards
- **AlertManager**: Alert routing and handling

### 3. Network Architecture

```
Internet
    │
    ├─ Cloudflare (DNS/CDN) 
    │
    └─ Traefik (443/80)
        │
        ├─ vault.cloudya.net → Vault (8200)
        ├─ nomad.cloudya.net → Nomad (4646)
        ├─ grafana.cloudya.net → Grafana (3000)
        └─ app.cloudya.net → Applications
```

### 4. Security Model

**Principles**:
- Zero-trust networking
- Encryption in transit and at rest
- Principle of least privilege
- Defense in depth

**Implementation**:
- TLS everywhere with Let's Encrypt certificates
- Vault-managed secrets and rotation
- Firewall with minimal open ports
- SSH key-based authentication only
- Regular security scanning and updates

## Deployment Environments

### Local Development (docker-compose.local.yml)

**Purpose**: Safe development and testing environment
**Components**: All services in Docker containers with development-friendly configurations
**Network**: Isolated Docker network (172.20.0.0/16)
**Security**: Relaxed for development convenience
**Data**: Ephemeral volumes for easy reset

**Access URLs**:
- Traefik Dashboard: http://localhost:8080
- Vault UI: http://localhost:8200  
- Nomad UI: http://localhost:4646
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

### Production (root@cloudya.net)

**Purpose**: Production-ready deployment with high availability
**Components**: Services deployed via systemd and Docker with production hardening
**Network**: Host networking with firewall protection
**Security**: Full TLS, encrypted secrets, comprehensive monitoring
**Data**: Persistent storage with automated backups

**Access URLs**:
- Main site: https://cloudya.net
- Vault: https://vault.cloudya.net
- Nomad: https://nomad.cloudya.net  
- Grafana: https://grafana.cloudya.net
- Traefik: https://traefik.cloudya.net

## Directory Structure

```
/Users/mlautenschlager/cloudya/vault/infrastructure/
├── config/                          # Configuration templates
│   ├── production.env.template       # Production environment variables
│   └── local.env.template           # Local development variables
├── docs/                            # Documentation
│   └── DEPLOYMENT_ARCHITECTURE.md   # This document
├── monitoring/                      # Monitoring stack
│   ├── docker-compose.monitoring.yml # Monitoring services
│   ├── prometheus/config/           # Prometheus configuration
│   ├── grafana/provisioning/        # Grafana provisioning
│   └── alertmanager/config/         # Alert configuration
├── scripts/                         # Deployment automation
│   ├── remote-deploy.sh             # Remote deployment orchestrator
│   ├── provision-server.sh          # Server provisioning
│   └── backup-restore.sh            # Backup and recovery
├── docker-compose.local.yml         # Local development stack
└── Makefile                         # Build automation
```

### Production Server Structure

```
/opt/cloudya-infrastructure/         # Infrastructure code and config
├── config/                         # Configuration files
├── scripts/                        # Deployment and maintenance scripts
├── vault/                          # Vault configuration
├── nomad/                          # Nomad job definitions  
└── traefik/                        # Traefik configuration

/opt/cloudya-data/                   # Persistent data
├── vault/                          # Vault data and logs
├── nomad/                          # Nomad data and logs
├── traefik/                        # Traefik certificates
├── consul/                         # Consul data
└── monitoring/                     # Monitoring data

/var/log/cloudya/                   # Centralized logs
/var/backups/cloudya/               # Backup storage
```

## Deployment Process

### 1. Local Development Workflow

1. **Setup Local Environment**:
   ```bash
   cd infrastructure
   cp config/local.env.template local.env
   # Edit local.env as needed
   ```

2. **Start Local Stack**:
   ```bash
   docker-compose -f docker-compose.local.yml --env-file local.env up -d
   ```

3. **Development and Testing**:
   - Make changes to configurations
   - Test service integrations
   - Validate monitoring and logging

4. **Cleanup**:
   ```bash
   docker-compose -f docker-compose.local.yml down -v
   ```

### 2. Production Deployment Workflow

1. **Server Provisioning** (one-time):
   ```bash
   ./scripts/provision-server.sh root@cloudya.net --verbose
   ```

2. **Configuration Setup**:
   ```bash
   cp config/production.env.template production.env
   # Edit production.env with secure values
   # Generate encryption keys and passwords
   ```

3. **Remote Deployment**:
   ```bash
   ./scripts/remote-deploy.sh --components all --verbose
   ```

4. **Verification**:
   - Check service health endpoints
   - Verify SSL certificates
   - Test application functionality
   - Review monitoring dashboards

### 3. Backup and Recovery

1. **Create Backup**:
   ```bash
   ./scripts/backup-restore.sh backup --type full --verbose
   ```

2. **List Backups**:
   ```bash
   ./scripts/backup-restore.sh list
   ```

3. **Verify Backup**:
   ```bash
   ./scripts/backup-restore.sh verify backup-20241225-123456
   ```

4. **Restore** (if needed):
   ```bash
   ./scripts/backup-restore.sh restore backup-20241225-123456
   ```

## Security Considerations

### 1. Access Control

**SSH Access**:
- Key-based authentication only
- Fail2ban protection against brute force
- Limited to specific users/keys

**Service Access**:
- TLS-only communication
- HTTP redirects to HTTPS
- Strong cipher suites only

### 2. Secret Management

**Vault Integration**:
- All application secrets stored in Vault
- Automatic secret rotation where possible
- Encrypted backup of secrets

**Key Management**:
- Separate encryption keys for different purposes
- Secure key storage and rotation procedures
- Recovery key distribution and escrow

### 3. Network Security

**Firewall Configuration**:
- Minimal open ports (22, 80, 443)
- Application-specific ports only from localhost
- Regular security scanning

**TLS/SSL**:
- Let's Encrypt certificates with auto-renewal
- Strong cipher suites and protocols
- HSTS and security headers

## Monitoring and Alerting

### 1. Metrics Collection

**Infrastructure Metrics**:
- System resources (CPU, memory, disk)
- Network performance and availability
- Service health and performance

**Application Metrics**:
- Request rates and response times
- Error rates and success ratios
- Business-specific metrics

### 2. Log Aggregation

**Centralized Logging**:
- All services log to `/var/log/cloudya/`
- Structured JSON logging where possible
- Log rotation and retention policies

**Log Analysis**:
- Real-time log monitoring
- Error pattern detection
- Security event correlation

### 3. Alerting

**Alert Categories**:
- Critical: Service down, security breach
- Warning: High resource usage, errors
- Info: Deployments, maintenance events

**Notification Channels**:
- Email for critical alerts
- Webhooks for integration with external systems
- Dashboard indicators for status

## Disaster Recovery

### 1. Backup Strategy

**Backup Types**:
- Full: Complete system backup (weekly)
- Incremental: Changed data only (daily)
- Configuration: Critical config files (on change)

**Backup Storage**:
- Local encrypted storage
- Optional remote replication
- Geographic distribution for critical backups

### 2. Recovery Procedures

**Service Recovery**:
1. Stop affected services
2. Restore from backup
3. Verify data integrity
4. Restart services
5. Validate functionality

**Full System Recovery**:
1. Provision new server
2. Restore system configuration
3. Restore application data
4. Reconfigure DNS/networking
5. Validate full system functionality

### 3. RTO/RPO Targets

**Recovery Time Objective (RTO)**:
- Critical services: < 1 hour
- Non-critical services: < 4 hours
- Full system: < 8 hours

**Recovery Point Objective (RPO)**:
- Critical data: < 1 hour (incremental backups)
- Configuration: < 15 minutes (continuous backup)
- Monitoring data: < 24 hours (daily backups)

## Performance and Scaling

### 1. Current Configuration

**Single Server Setup**:
- Suitable for small to medium workloads
- Vertical scaling capability
- Cost-effective for initial deployment

**Resource Requirements**:
- Minimum: 4GB RAM, 2 CPU cores, 50GB disk
- Recommended: 8GB RAM, 4 CPU cores, 100GB disk
- Production: 16GB RAM, 8 CPU cores, 200GB SSD

### 2. Scaling Strategies

**Vertical Scaling**:
- Increase server resources
- Add more memory and CPU
- Use faster storage (SSD)

**Horizontal Scaling** (future):
- Multi-node Nomad cluster
- Vault HA with Consul backend
- Load balancer distribution

### 3. Performance Monitoring

**Key Metrics**:
- Response times < 500ms for web requests
- System load average < 2.0
- Memory usage < 80%
- Disk usage < 85%

**Performance Optimization**:
- Regular performance reviews
- Resource utilization analysis
- Bottleneck identification and resolution

## Maintenance Procedures

### 1. Regular Maintenance

**Daily**:
- Automated backup verification
- Security update installation
- Service health monitoring

**Weekly**:
- Full system backup
- Performance review
- Security scan results

**Monthly**:
- Certificate renewal check
- Backup restoration test
- Security configuration review

### 2. Update Procedures

**Security Updates**:
- Automatic installation for critical security patches
- Scheduled maintenance windows for major updates
- Rollback procedures for failed updates

**Application Updates**:
- Blue-green deployment strategy
- Canary releases for major changes
- Automated rollback on failure detection

### 3. Troubleshooting

**Common Issues**:
- Service startup failures
- Certificate expiration
- Disk space exhaustion
- Network connectivity problems

**Diagnostic Tools**:
- System logs analysis
- Service status monitoring
- Network connectivity tests
- Performance profiling

## Future Enhancements

### 1. Short Term (1-3 months)

**Infrastructure**:
- Implement automated testing pipeline
- Add more comprehensive monitoring
- Improve backup and recovery automation

**Security**:
- Implement vulnerability scanning
- Add intrusion detection system
- Enhance audit logging

### 2. Medium Term (3-6 months)

**Scalability**:
- Multi-node cluster setup
- Database replication
- CDN integration

**Reliability**:
- Chaos engineering implementation
- Automated failover procedures
- Enhanced disaster recovery testing

### 3. Long Term (6+ months)

**Advanced Features**:
- GitOps deployment pipeline
- Infrastructure as Code (Terraform)
- Multi-region deployment capability

**Optimization**:
- Advanced performance monitoring
- Predictive scaling
- Cost optimization strategies

## Conclusion

This architecture provides a robust, secure, and scalable foundation for the Cloudya infrastructure. The hybrid local/remote deployment approach enables safe development while maintaining production security and reliability.

The modular design allows for incremental improvements and scaling as requirements grow, while the comprehensive monitoring and backup strategies ensure system reliability and data protection.

Regular review and updates of this architecture documentation will ensure it remains current and continues to meet evolving requirements.