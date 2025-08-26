# Consul Integration Documentation

## Overview

This document provides comprehensive integration guidance for Consul DNS and security features within the Cloudya Vault infrastructure.

## Quick Start Commands

### 1. Security Automation
```bash
# Generate gossip encryption key
./scripts/consul-security-automation.sh generate-key

# Bootstrap ACL system for staging
./scripts/consul-security-automation.sh bootstrap staging

# Full security setup for production
./scripts/consul-security-automation.sh full-setup production

# Security health check
./scripts/consul-security-automation.sh healthcheck production
```

### 2. DNS Configuration
```bash
# Set up DNS forwarding for development
./scripts/consul-dns-setup.sh development

# Configure DNS for production
./scripts/consul-dns-setup.sh production

# Test DNS functionality
./scripts/test-consul-dns.sh production
```

### 3. Service Mesh Operations
```bash
# Enable service mesh with Vault CA
consul connect ca set-config -config-file vault-ca-config.json

# Create service intentions
consul intention create -allow frontend backend
consul intention create -deny "*" "*"

# Register service with sidecar proxy
consul services register frontend-service.json
```

## Configuration Files Summary

### Environment-Specific Configurations
- `/infrastructure/config/consul.hcl` - Basic development configuration
- `/infrastructure/config/consul-staging.hcl` - Security-enabled staging
- `/infrastructure/config/consul-production.hcl` - Full production security

### Security Features by Environment

| Feature | Development | Staging | Production |
|---------|-------------|---------|------------|
| ACLs | Disabled | Enabled (Allow default) | Enabled (Deny default) |
| TLS | No | Optional | Required |
| Gossip Encryption | No | Yes | Yes |
| Audit Logging | No | Basic | Comprehensive |
| Service Mesh | Basic | Enabled | Vault-integrated |
| DNS Security | Basic | Moderate | High |

## Security Implementation Roadmap

### Phase 1: Foundation (Completed)
- ✅ Security assessment completed
- ✅ Configuration files created for all environments
- ✅ Automation scripts developed
- ✅ DNS integration documented

### Phase 2: Staging Deployment
1. Deploy staging configuration with ACLs enabled
2. Set up TLS certificates
3. Configure gossip encryption
4. Test DNS forwarding
5. Validate service mesh functionality

### Phase 3: Production Hardening
1. Integrate Vault as CA provider
2. Implement zero-trust service intentions
3. Deploy monitoring and alerting
4. Set up backup automation
5. Configure disaster recovery

## Integration Points

### 1. Vault Integration
```hcl
# Consul configuration for Vault storage
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
  token   = "{{ env \"CONSUL_VAULT_TOKEN\" }}"
}
```

### 2. Nomad Integration
```hcl
# Nomad client configuration
consul {
  address = "127.0.0.1:8500"
  token   = "{{ env \"CONSUL_NOMAD_TOKEN\" }}"
  auto_advertise = true
  server_service_name = "nomad"
  client_service_name = "nomad-client"
}
```

### 3. Traefik Integration
```yaml
# Traefik provider configuration
providers:
  consul:
    endpoints:
      - "127.0.0.1:8500"
    token: "{{ env \"CONSUL_TRAEFIK_TOKEN\" }}"
    watch: true
```

## DNS Configuration Examples

### System-level DNS Forwarding

#### Ubuntu/Debian (systemd-resolved)
```ini
# /etc/systemd/resolved.conf.d/consul.conf
[Resolve]
DNS=127.0.0.1:8600
Domains=~consul
DNSSEC=false
```

#### macOS Resolver
```
# /etc/resolver/consul
nameserver 127.0.0.1
port 8600
```

#### dnsmasq Configuration
```
# /etc/dnsmasq.d/10-consul
server=/consul/127.0.0.1#8600
address=/.consul/127.0.0.1
```

### Service Discovery Examples
```bash
# Basic service resolution
dig consul.service.consul

# Service with datacenter
dig vault.service.dc1.consul

# Service with tag
dig production.vault.service.consul

# SRV record for load balancing
dig _vault._tcp.service.consul SRV
```

## Security Best Practices

### 1. Token Management
- Use short-lived tokens (24-72 hours)
- Implement token rotation automation
- Store tokens securely (Vault recommended)
- Use service-specific tokens with minimal permissions

### 2. Network Security
- Bind Consul to specific interfaces (not 0.0.0.0)
- Use TLS for all communications in production
- Implement network segmentation
- Configure firewall rules for Consul ports

### 3. Certificate Management
- Use Vault as CA provider for production
- Implement automatic certificate rotation
- Monitor certificate expiration
- Use short certificate lifetimes (24-72 hours)

### 4. Access Control
- Enable ACLs with default deny policy
- Create service-specific policies
- Implement least-privilege access
- Regular access reviews and cleanup

## Monitoring and Alerting

### Key Metrics
```yaml
# Prometheus metrics to monitor
- consul_health_service_status
- consul_dns_query_time
- consul_connect_cert_expiry
- consul_raft_leader_status
- consul_serf_member_status
```

### Alert Examples
```yaml
# Critical alerts
- ConsulClusterDown
- ConsulDNSResolutionFailure  
- ConsulCertificateExpiring
- ConsulACLTokenExpired
- ConsulServiceMeshFailure
```

## Troubleshooting

### Common Issues

#### 1. DNS Resolution Failures
```bash
# Debug DNS issues
dig @127.0.0.1 -p 8600 consul.service.consul
consul catalog services
consul catalog service consul
```

#### 2. ACL Permission Errors
```bash
# Check token permissions
consul acl token read -self
consul acl policy list
consul acl token list
```

#### 3. Service Mesh Issues
```bash
# Debug Connect issues
consul connect ca roots
consul connect proxy-config <service-id>
consul intention list
```

#### 4. Certificate Problems
```bash
# Certificate debugging
consul connect ca get-config
consul connect ca roots
openssl x509 -in cert.pem -text -noout
```

## Testing and Validation

### Automated Testing
```bash
# Run comprehensive DNS tests
./scripts/test-consul-dns.sh production

# Security validation
./scripts/consul-security-automation.sh healthcheck production

# Service mesh testing
consul connect proxy -service frontend -upstream backend:8080
```

### Manual Verification Checklist
- [ ] Consul cluster formation
- [ ] ACL system functioning
- [ ] DNS resolution working
- [ ] Service discovery operational
- [ ] TLS certificates valid
- [ ] Gossip encryption active
- [ ] Service mesh connected
- [ ] Monitoring data flowing

## Support and Documentation

### Internal Resources
- Security assessment: `/docs/consul-security-assessment.md`
- Service mesh guide: `/docs/consul-service-mesh-guide.md`
- Automation scripts: `/scripts/consul-*`
- Configuration templates: `/infrastructure/config/consul-*`

### External Resources
- [Consul Documentation](https://developer.hashicorp.com/consul)
- [Consul Security Model](https://developer.hashicorp.com/consul/docs/security)
- [Consul DNS Interface](https://developer.hashicorp.com/consul/docs/discovery/dns)
- [Consul Service Mesh](https://developer.hashicorp.com/consul/docs/connect)

## Migration Path

### From Development to Production
1. Review current configuration against production requirements
2. Plan ACL implementation and token distribution
3. Set up TLS certificates and gossip encryption
4. Configure DNS forwarding at system level
5. Implement monitoring and alerting
6. Test disaster recovery procedures
7. Deploy gradually with rollback plan

This documentation provides the foundation for secure, scalable Consul deployment supporting your infrastructure's DNS and service discovery needs.