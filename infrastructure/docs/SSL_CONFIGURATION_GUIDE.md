# SSL Certificate Configuration Guide

This document outlines the comprehensive SSL certificate setup for Cloudya infrastructure using Let's Encrypt and Traefik.

## Overview

The SSL certificate configuration provides:
- **Automatic SSL certificates** from Let's Encrypt for all `cloudya.net` domains
- **HTTP to HTTPS redirect** for all services
- **Certificate monitoring and renewal** automation
- **A+ SSL Labs rating** configuration
- **Persistent certificate storage** across deployments

## Configured Domains

The following domains are configured with automatic SSL certificates:

### Core Infrastructure
- `vault.cloudya.net` - HashiCorp Vault
- `consul.cloudya.net` - HashiCorp Consul  
- `traefik.cloudya.net` - Traefik Dashboard
- `nomad.cloudya.net` - Nomad UI

### Monitoring & Observability
- `metrics.cloudya.net` - Prometheus
- `grafana.cloudya.net` - Grafana Dashboard
- `logs.cloudya.net` - Loki Logs

### Storage & API
- `storage.cloudya.net` - MinIO Object Storage
- `api.cloudya.net` - Application API
- `app.cloudya.net` - Application Frontend
- `cloudya.net` - Main Domain

### Environment-Specific
- `*-staging.cloudya.net` - Staging environment services

## Certificate Configuration

### Let's Encrypt Setup

The configuration uses Let's Encrypt with:
- **HTTP-01 Challenge** for single domain certificates
- **DNS Challenge** (Cloudflare) for wildcard certificates (fallback)
- **Staging environment** for testing
- **Production environment** for live certificates

### ACME Configuration

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@cloudya.net
      storage: /letsencrypt/acme.json
      keyType: EC256
      caServer: "https://acme-v02.api.letsencrypt.org/directory"
      httpChallenge:
        entryPoint: web
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 60s
```

### Certificate Storage

Certificates are stored persistently in:
- **ACME Storage**: `/opt/nomad/volumes/traefik-certs/acme.json`
- **Certificate Files**: `/opt/nomad/volumes/traefik-certs/certs/`
- **Private Keys**: `/opt/nomad/volumes/traefik-certs/private/`
- **Logs**: `/opt/nomad/volumes/traefik-logs/`

## Security Configuration

### TLS Settings

```yaml
tls:
  options:
    modern:
      minVersion: "VersionTLS12"
      maxVersion: "VersionTLS13"
      cipherSuites:
        - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        - "TLS_AES_128_GCM_SHA256"
        - "TLS_AES_256_GCM_SHA384"
        - "TLS_CHACHA20_POLY1305_SHA256"
      sniStrict: true
      alpnProtocols:
        - "h2"
        - "http/1.1"
```

### Security Headers

```yaml
middlewares:
  security-headers:
    headers:
      frameDeny: true
      browserXssFilter: true
      contentTypeNosniff: true
      forceSTSHeader: true
      stsIncludeSubdomains: true
      stsPreload: true
      stsSeconds: 63072000
      customResponseHeaders:
        X-Frame-Options: "DENY"
        X-Content-Type-Options: "nosniff"
        X-XSS-Protection: "1; mode=block"
        Referrer-Policy: "strict-origin-when-cross-origin"
        Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline';"
```

## Automation Scripts

### Setup Script

```bash
# Run complete SSL setup
./scripts/setup-ssl-certificates.sh setup

# Check SSL status
./scripts/setup-ssl-certificates.sh status

# Monitor certificates
./scripts/setup-ssl-certificates.sh monitor

# Force renewal
./scripts/setup-ssl-certificates.sh renew
```

### Validation Script

```bash
# Validate all SSL configurations
./scripts/validate-ssl-config.sh validate

# Generate SSL report
./scripts/validate-ssl-config.sh report

# Check specific components
./scripts/validate-ssl-config.sh traefik
./scripts/validate-ssl-config.sh acme
```

## Certificate Monitoring

### Automated Monitoring

The system includes automated certificate monitoring:

- **Daily certificate checks** at 2 AM
- **Weekly renewal attempts** on Sundays at 3 AM
- **Alert thresholds** at 30 days before expiry
- **Log rotation** monthly cleanup

### Crontab Configuration

```bash
# Check certificates daily
0 2 * * * root /path/to/scripts/monitor-certificates.sh

# Attempt renewal weekly
0 3 * * 0 root /path/to/scripts/renew-certificates.sh

# Cleanup old logs monthly
0 4 1 * * root find /opt/nomad/volumes/traefik-logs -name "*.log" -mtime +30 -delete
```

## Certificate Lifecycle

### Initial Setup

1. **Domain DNS configuration** must point to your servers
2. **Traefik deployment** with updated configuration
3. **Certificate generation** on first HTTPS request
4. **Monitoring activation** via cron jobs

### Renewal Process

1. **Automatic renewal** occurs 30 days before expiry
2. **Certificate validation** ensures successful renewal
3. **Service restart** if required
4. **Notification** of renewal status

### Monitoring Alerts

- **Certificate expiration** warnings (30+ days)
- **Renewal failures** critical alerts
- **SSL grade degradation** notifications
- **Service availability** monitoring

## Troubleshooting

### Common Issues

#### Certificate Not Generated

```bash
# Check Traefik logs
nomad alloc logs -f <traefik-alloc-id>

# Verify DNS resolution
nslookup vault.cloudya.net

# Check HTTP challenge endpoint
curl -v http://vault.cloudya.net/.well-known/acme-challenge/
```

#### Certificate Renewal Failed

```bash
# Check ACME storage permissions
ls -la /opt/nomad/volumes/traefik-certs/acme.json

# Verify certificate expiry
openssl x509 -in /path/to/cert.crt -noout -dates

# Force renewal
FORCE_RENEWAL=true ./scripts/renew-certificates.sh
```

#### SSL Grade Issues

```bash
# Test SSL configuration
./scripts/validate-ssl-config.sh validate

# Check cipher suites
nmap --script ssl-enum-ciphers -p 443 vault.cloudya.net

# Verify HSTS headers
curl -I https://vault.cloudya.net
```

### Log Locations

- **Traefik logs**: `/opt/nomad/volumes/traefik-logs/traefik.log`
- **Access logs**: `/opt/nomad/volumes/traefik-logs/access.log`
- **Certificate monitor**: `/opt/nomad/volumes/traefik-logs/certificate-monitor.log`
- **Renewal logs**: `/opt/nomad/volumes/traefik-logs/cron-renewal.log`

## Best Practices

### Security

1. **Never commit** ACME storage files to version control
2. **Backup** certificate storage regularly
3. **Monitor** certificate expiration proactively
4. **Use staging** environment for testing changes
5. **Implement** proper access controls on certificate files

### Performance

1. **Enable HTTP/2** for better performance
2. **Use OCSP stapling** to reduce handshake time
3. **Optimize cipher suites** for your security requirements
4. **Monitor SSL handshake** performance metrics
5. **Cache certificates** appropriately

### Maintenance

1. **Test certificate renewal** process regularly
2. **Update certificate monitoring** alerts
3. **Review SSL configuration** quarterly
4. **Keep Traefik updated** for latest security fixes
5. **Document configuration changes** thoroughly

## Integration with Deployment

The SSL certificate configuration is automatically integrated into:

### Production Deployment

```bash
# Production deployment includes SSL setup
./scripts/deploy-production.sh --environment production

# Dry run with SSL validation
./scripts/deploy-production.sh --dry-run
```

### Environment-Specific Configuration

- **Development**: Self-signed certificates for local testing
- **Staging**: Let's Encrypt staging CA for testing
- **Production**: Let's Encrypt production CA for live certificates

## Monitoring Dashboard

Create monitoring dashboards for:

- **Certificate expiry dates**
- **SSL handshake performance**
- **Certificate renewal success rates**
- **SSL Labs grades**
- **HTTPS traffic metrics**

## Support and Maintenance

### Regular Tasks

- **Weekly**: Review certificate monitoring logs
- **Monthly**: Test certificate renewal process  
- **Quarterly**: Review SSL configuration and security
- **Annually**: Update certificate monitoring thresholds

### Emergency Procedures

1. **Certificate expiry**: Emergency renewal process
2. **CA compromise**: Certificate revocation and renewal
3. **Configuration issues**: Rollback and recovery procedures
4. **Service outages**: SSL-related incident response

## Contact Information

- **Security Team**: security@cloudya.net
- **Operations Team**: ops@cloudya.net
- **Emergency Contact**: emergency@cloudya.net

---

**Last Updated**: $(date +"%Y-%m-%d")  
**Configuration Version**: 2.0  
**Review Date**: $(date -d "+3 months" +"%Y-%m-%d")