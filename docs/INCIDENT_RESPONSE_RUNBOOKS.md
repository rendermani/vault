# Incident Response Runbooks for HashiCorp Stack Monitoring

## Overview

This document provides comprehensive incident response runbooks for common monitoring scenarios in the HashiCorp stack. Each runbook includes symptoms, diagnosis steps, immediate actions, and resolution procedures.

## Alert Severity Levels

- **Critical (P0)**: Service unavailable or severe security incident - immediate response required
- **Warning (P1)**: Service degraded or potential issue - response within 15 minutes
- **Info (P2)**: Informational alert or minor issue - response within 1 hour

## Vault Incident Runbooks

### VaultSealed - CRITICAL

**Alert**: Vault instance is sealed
**Severity**: Critical (P0)
**Response Time**: Immediate

#### Symptoms
- Vault UI shows "Vault is sealed" message
- API returns 503 Service Unavailable
- Applications cannot authenticate with Vault
- Nomad jobs fail to retrieve secrets

#### Immediate Actions (First 5 minutes)
1. **Verify the alert**:
   ```bash
   vault status
   curl -s https://vault.cloudya.net/v1/sys/health
   ```

2. **Check Vault logs**:
   ```bash
   tail -f /var/log/vault/vault.log
   # Look for seal reasons: storage errors, memory issues, crashes
   ```

3. **Determine seal cause**:
   ```bash
   # Check system resources
   df -h  # Disk space
   free -h  # Memory
   systemctl status vault  # Service status
   ```

#### Investigation Steps
1. **Check storage backend health**:
   ```bash
   # For Raft storage
   vault operator raft list-peers
   vault operator raft autopilot get-config
   ```

2. **Review system events**:
   ```bash
   journalctl -u vault -n 100
   dmesg | grep -i vault
   ```

3. **Verify network connectivity**:
   ```bash
   # Test cluster communication
   nc -zv vault-node-1 8201
   nc -zv vault-node-2 8201
   nc -zv vault-node-3 8201
   ```

#### Resolution Steps
1. **Standard unseal process**:
   ```bash
   # Gather required number of unseal keys
   vault operator unseal [key1]
   vault operator unseal [key2]
   vault operator unseal [key3]
   ```

2. **If unseal fails**:
   ```bash
   # Check seal status
   vault operator unseal -status
   
   # Verify unseal keys
   # Contact key holders for additional keys
   ```

3. **For storage issues**:
   ```bash
   # Check disk space and fix if needed
   # Restart vault service if storage is recovered
   systemctl restart vault
   ```

4. **For cluster issues**:
   ```bash
   # Force new leader election if needed
   vault operator step-down
   
   # Rejoin cluster node if necessary
   vault operator raft join https://vault-node-1:8200
   ```

#### Post-Incident Actions
- Document root cause
- Update monitoring thresholds if needed
- Review backup procedures
- Conduct post-mortem meeting

---

### VaultHighLatency - WARNING

**Alert**: High request latency in Vault
**Severity**: Warning (P1)
**Response Time**: 15 minutes

#### Symptoms
- API response times > 1 second
- Application timeouts
- Dashboard shows elevated latency metrics

#### Investigation Steps
1. **Check current performance**:
   ```bash
   # Monitor active requests
   curl -s https://vault.cloudya.net/v1/sys/metrics | grep vault_core_handle_request
   
   # Check storage performance
   curl -s https://vault.cloudya.net/v1/sys/metrics | grep vault_barrier_get
   ```

2. **Identify bottlenecks**:
   ```bash
   # System resources
   top -p $(pgrep vault)
   iostat -x 1 5
   
   # Network latency
   ping vault.cloudya.net
   ```

#### Resolution Steps
1. **Resource optimization**:
   ```bash
   # Increase Vault memory if needed
   # Scale horizontally if possible
   # Optimize storage configuration
   ```

2. **Client-side improvements**:
   ```bash
   # Implement connection pooling
   # Add client-side caching
   # Use batch operations where possible
   ```

---

## Nomad Incident Runbooks

### NomadServerDown - CRITICAL

**Alert**: Nomad server is unreachable
**Severity**: Critical (P0)
**Response Time**: Immediate

#### Symptoms
- Nomad UI inaccessible
- Job scheduling failures
- Client nodes disconnecting

#### Immediate Actions
1. **Verify server status**:
   ```bash
   nomad server members
   nomad operator autopilot get-config
   systemctl status nomad
   ```

2. **Check logs**:
   ```bash
   tail -f /opt/nomad/logs/nomad.log
   journalctl -u nomad -n 50
   ```

#### Investigation Steps
1. **Cluster health assessment**:
   ```bash
   nomad operator raft list-peers
   nomad status
   ```

2. **Resource verification**:
   ```bash
   df -h /opt/nomad
   netstat -tulpn | grep :4646
   ```

#### Resolution Steps
1. **Service recovery**:
   ```bash
   # Restart service
   systemctl restart nomad
   
   # Rejoin cluster if needed
   nomad operator raft remove-peer [failed-node]
   ```

2. **Cluster rebuild** (if majority lost):
   ```bash
   # Bootstrap new cluster with peers.json
   nomad operator raft restore backup.snapshot
   ```

---

### NomadHighJobFailureRate - WARNING

**Alert**: High job failure rate
**Severity**: Warning (P1)
**Response Time**: 15 minutes

#### Investigation Steps
1. **Identify failing jobs**:
   ```bash
   nomad status
   nomad alloc status -short
   ```

2. **Analyze failure patterns**:
   ```bash
   # Check allocation failures
   nomad alloc logs [alloc-id]
   nomad alloc status [alloc-id]
   ```

#### Resolution Steps
1. **Resource issues**:
   ```bash
   # Scale cluster if resource constrained
   nomad node eligibility -enable [node-id]
   ```

2. **Job configuration fixes**:
   ```bash
   # Update resource requirements
   # Fix image or configuration issues
   nomad job run updated-job.nomad
   ```

---

## Consul Incident Runbooks

### ConsulNoLeader - CRITICAL

**Alert**: Consul cluster has no leader
**Severity**: Critical (P0)
**Response Time**: Immediate

#### Symptoms
- Service discovery failures
- KV store unavailable
- Connect proxy issues

#### Immediate Actions
1. **Check cluster status**:
   ```bash
   consul members
   consul operator raft list-peers
   ```

2. **Verify quorum**:
   ```bash
   # Ensure majority of servers are alive
   consul operator raft configuration
   ```

#### Resolution Steps
1. **Restart problematic nodes**:
   ```bash
   systemctl restart consul
   ```

2. **Force leader election**:
   ```bash
   consul operator raft remove-peer [failed-peer]
   ```

3. **Restore from backup** (last resort):
   ```bash
   consul snapshot restore backup.snap
   ```

---

### ConsulConnectCertExpired - CRITICAL

**Alert**: Consul Connect certificate expired
**Severity**: Critical (P0)
**Response Time**: Immediate

#### Symptoms
- Service mesh communication failures
- TLS handshake errors
- Connect proxy errors

#### Resolution Steps
1. **Rotate CA certificates**:
   ```bash
   consul connect ca set-config -config-file new-ca-config.json
   ```

2. **Restart Connect proxies**:
   ```bash
   # Restart all Connect sidecars
   nomad job restart connect-proxy-job
   ```

---

## Infrastructure Incident Runbooks

### HighMemoryUsage - WARNING

**Alert**: High memory usage on monitoring components
**Severity**: Warning (P1)
**Response Time**: 15 minutes

#### Investigation Steps
1. **Identify memory consumers**:
   ```bash
   docker stats --no-stream
   ps aux --sort=-%mem | head -10
   ```

2. **Check for memory leaks**:
   ```bash
   # Monitor memory growth over time
   watch -n 5 'free -h'
   ```

#### Resolution Steps
1. **Immediate relief**:
   ```bash
   # Restart high-memory containers
   docker restart prometheus grafana
   
   # Clear caches
   echo 3 > /proc/sys/vm/drop_caches
   ```

2. **Long-term fixes**:
   ```bash
   # Optimize Prometheus retention
   # Configure memory limits in docker-compose
   # Scale horizontally if needed
   ```

---

### MonitoringDataLoss - CRITICAL

**Alert**: Monitoring data loss detected
**Severity**: Critical (P0)
**Response Time**: Immediate

#### Investigation Steps
1. **Assess data loss scope**:
   ```bash
   # Check Prometheus data
   curl -s http://localhost:9090/api/v1/query?query=up
   
   # Check Loki logs
   curl -s http://localhost:3100/loki/api/v1/labels
   ```

2. **Verify backup status**:
   ```bash
   # Check latest backups
   ls -la /opt/cloudya-data/monitoring/backups/
   ```

#### Resolution Steps
1. **Restore from backup**:
   ```bash
   # Stop monitoring services
   docker-compose -f docker-compose.monitoring.yml down
   
   # Restore data
   tar -xzf backup-YYYYMMDD.tar.gz -C /opt/cloudya-data/monitoring/
   
   # Restart services
   docker-compose -f docker-compose.monitoring.yml up -d
   ```

2. **Implement data recovery**:
   ```bash
   # Use federation for historical data recovery
   # Reconfigure retention policies
   ```

---

## General Incident Response Procedures

### Incident Triage Process

1. **Initial Assessment (0-2 minutes)**:
   - Confirm alert validity
   - Assess impact and affected services
   - Determine severity level
   - Notify appropriate team members

2. **Investigation Phase (2-15 minutes)**:
   - Gather diagnostic information
   - Identify root cause
   - Document findings in incident ticket

3. **Resolution Phase (15+ minutes)**:
   - Implement fix or workaround
   - Verify resolution
   - Monitor for recurrence

4. **Post-Incident (24-48 hours)**:
   - Conduct post-mortem
   - Update documentation
   - Implement preventive measures

### Communication Templates

#### Critical Incident Notification
```
INCIDENT: [Brief Description]
STATUS: INVESTIGATING/MITIGATING/RESOLVED
IMPACT: [Affected Services/Users]
ETA: [Expected Resolution Time]
UPDATES: [Communication Channel]

Details:
- Time Started: [Timestamp]
- Services Affected: [List]
- Current Status: [Description]
- Next Update: [Time]
```

#### Resolution Notification
```
RESOLVED: [Brief Description]
DURATION: [Total Incident Time]
CAUSE: [Root Cause Summary]
RESOLUTION: [Actions Taken]

Post-Mortem: [Meeting Details/Document Link]
```

### Escalation Matrix

| Severity | Primary Contact | Secondary Contact | Manager Notification |
|----------|----------------|-------------------|---------------------|
| Critical | On-call Engineer | Platform Team Lead | Immediate |
| Warning | Platform Team | Security Team (if security-related) | Within 1 hour |
| Info | Platform Team | - | Daily summary |

### Useful Commands Reference

#### Vault Commands
```bash
# Status and health
vault status
vault operator unseal -status
vault auth list
vault secrets list

# Metrics and performance
curl -s $VAULT_ADDR/v1/sys/metrics?format=prometheus
vault operator raft list-peers
vault operator raft autopilot get-config
```

#### Nomad Commands
```bash
# Cluster status
nomad server members
nomad node status
nomad operator autopilot get-config

# Job management
nomad status
nomad alloc status
nomad logs -f [alloc-id]
```

#### Consul Commands
```bash
# Cluster health
consul members
consul operator raft list-peers
consul catalog services

# Connect and service mesh
consul connect proxy-config [service-name]
consul intention list
```

#### Monitoring Commands
```bash
# Prometheus queries
curl "http://localhost:9090/api/v1/query?query=up"
curl "http://localhost:9090/api/v1/rules"

# Grafana API
curl -u admin:password http://localhost:3000/api/health
curl -u admin:password http://localhost:3000/api/datasources

# Loki queries
curl "http://localhost:3100/loki/api/v1/query?query={job=\"vault\"}"
curl "http://localhost:3100/ready"
```

## Contact Information

- **Platform Team**: platform-team@cloudya.net
- **Security Team**: security-team@cloudya.net  
- **On-Call Rotation**: [PagerDuty/Slack Channel]
- **Escalation Manager**: engineering-manager@cloudya.net

## Additional Resources

- [HashiCorp Documentation](https://www.hashicorp.com/documentation)
- [Monitoring Architecture Guide](./MONITORING_ARCHITECTURE.md)
- [OTEL Integration Guide](./OTEL_INTEGRATION_GUIDE.md)
- [Disaster Recovery Procedures](./disaster-recovery.md)

---

*This runbook should be regularly updated based on incident learnings and infrastructure changes.*