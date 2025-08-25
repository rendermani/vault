# Monitoring and Observability Blueprint
## 3-Group Architecture with Vault on Nomad

### Executive Summary

This blueprint provides comprehensive monitoring strategies for a 3-group Vault deployment on Nomad, focusing on infrastructure visibility, security monitoring, and operational excellence. The strategy combines modern observability tools with proven patterns for high-availability secret management at scale.

---

## 1. Infrastructure Monitoring

### 1.1 Nomad Cluster Health Metrics

**Core Metrics Collection:**
```yaml
# Nomad Agent Configuration
telemetry {
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics      = true
  collection_interval       = "1s"
  disable_hostname          = false
}
```

**Key Performance Indicators:**
- **Cluster Health**: `nomad.raft.leader.lastContact` - General indicator of Raft latency
- **Resource Utilization**: CPU, memory, disk, and network usage scaling linearly with cluster size
- **Scheduling Performance**: `nomad.worker.invoke_scheduler.<type>` - Monitor scheduling throughput
- **Job Execution**: Job summary and status metrics from leader server
- **Node Status**: Client node availability and resource allocation

**Monitoring Endpoints:**
- `/v1/metrics` - Prometheus formatted metrics
- `/v1/agent/health` - Node health status
- `/v1/status/leader` - Leader election status

### 1.2 Vault Performance and Audit Logs

**Performance Metrics:**
```hcl
# Vault Configuration
telemetry {
  prometheus_retention_time = "24h"
  disable_hostname          = false
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = false
  
  telemetry {
    unauthenticated_metrics_access = true
  }
}
```

**Critical Vault Metrics:**
- **Core Operations**: Latency for list, get, put, delete operations in storage
- **Authentication**: Login requests, token validation, ACL fetch times
- **Lease Management**: Token TTL distribution, lease creation/revocation rates
- **Storage Performance**: Disk utilization, storage backend latency
- **Request Patterns**: Requests per second, error rates, response times

**Audit Configuration:**
```hcl
audit "file" {
  file_path = "/vault/logs/audit.log"
  format    = "json"
}

audit "syslog" {
  facility = "AUTH"
  tag      = "vault"
  format   = "json"
}
```

### 1.3 Resource Utilization Tracking

**Bootstrap Phase Monitoring:**
- Initial cluster formation metrics
- Service registration latency
- First-leader election time
- Vault unsealing performance
- Initial policy application

**Ongoing Resource Metrics:**
- Memory usage per node (linear scaling with cluster size)
- Disk I/O patterns for storage backends
- Network bandwidth utilization
- CPU usage during peak authentication periods

---

## 2. Service Discovery Monitoring

### 2.1 Automatic Vault Endpoint Discovery

**Consul Integration:**
```hcl
# Nomad Job Configuration
service {
  name = "vault"
  tags = ["vault", "${NOMAD_DC}", "active"]
  port = "vault"
  
  check {
    name     = "vault-health"
    http     = "https://${NOMAD_ADDR_vault}/v1/sys/health"
    interval = "10s"
    timeout  = "5s"
  }
  
  meta {
    environment = "${NOMAD_META_env}"
    group       = "${NOMAD_GROUP_NAME}"
  }
}
```

**Service Discovery Metrics:**
- Service registration/deregistration events
- Health check success rates
- DNS query latency for service lookups
- Service catalog update frequency

### 2.2 Multi-Environment Monitoring

**Environment Segmentation:**
```yaml
# Prometheus Service Discovery
consul_sd_configs:
  - server: 'consul.service.consul:8500'
    services: ['vault']
    tags: ['active']
    
relabel_configs:
  - source_labels: [__meta_consul_service_metadata_environment]
    target_label: environment
  - source_labels: [__meta_consul_service_metadata_group]
    target_label: vault_group
```

**Health Check Patterns:**
- Multi-layer health validation (L4/L7)
- Environment-specific health thresholds
- Cross-environment connectivity monitoring
- Failover detection and recovery time

---

## 3. Security Monitoring

### 3.1 Vault Audit Log Analysis

**Audit Log Processing:**
```json
{
  "time": "2024-01-15T10:30:45.123Z",
  "type": "request",
  "auth": {
    "client_token": "hvs.CAESIJ...",
    "accessor": "hmac-sha256:...",
    "display_name": "approle",
    "policies": ["default", "app-policy"]
  },
  "request": {
    "operation": "read",
    "path": "secret/data/myapp/config",
    "remote_address": "10.0.1.45"
  }
}
```

**Security Event Detection:**
- Failed authentication attempts (threshold: >5 failures/minute)
- Unusual access patterns (location, time-based anomalies)
- High-privilege token usage monitoring
- Root token usage alerts
- Policy violation attempts

### 3.2 Token Usage Patterns

**Token Lifecycle Monitoring:**
```promql
# Token creation rate
rate(vault_token_creation_total[5m])

# Token TTL distribution
histogram_quantile(0.95, vault_token_ttl_seconds_bucket)

# Active token count
vault_token_count_by_policy
```

**Anomaly Detection Rules:**
- Unexpected long-lived tokens (TTL > 24 hours without business justification)
- High token creation rates (>100 tokens/minute)
- Cross-environment token usage
- Service account token sharing detection

### 3.3 Failed Authentication Tracking

**Authentication Metrics:**
- Failed login attempts by method (AppRole, LDAP, etc.)
- Geographic distribution of login attempts
- Time-based authentication patterns
- Brute force attack detection (>10 failures from single IP)

### 3.4 Compliance Reporting

**Audit Trail Requirements:**
- Complete request/response logging
- Long-term audit log retention (7+ years for compliance)
- Tamper-proof log storage
- Regular audit log integrity verification

---

## 4. Application Monitoring

### 4.1 Secret Fetch Performance

**Application-Level Metrics:**
```go
// Example Go metrics
var (
    secretFetchDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "vault_secret_fetch_duration_seconds",
            Help: "Time taken to fetch secrets from Vault",
        },
        []string{"secret_path", "environment"},
    )
    
    secretFetchErrors = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "vault_secret_fetch_errors_total",
            Help: "Total number of secret fetch errors",
        },
        []string{"error_type", "secret_path"},
    )
)
```

### 4.2 Database Connection Pooling

**Connection Pool Monitoring:**
```yaml
# Connection pool metrics to track
metrics:
  - name: "connection_pool_active"
    help: "Number of active database connections"
  - name: "connection_pool_idle"
    help: "Number of idle connections in pool"
  - name: "connection_pool_wait_time"
    help: "Time waiting for available connection"
  - name: "connection_pool_errors"
    help: "Connection pool error count"
```

**Database Secret Rotation:**
- Rotation success/failure rates
- Application restart requirements post-rotation
- Connection pool refresh latency
- Zero-downtime rotation validation

### 4.3 API Rate Limiting Metrics

**Rate Limiting Monitoring:**
```promql
# Rate limit violations
increase(vault_rate_limit_violations_total[5m])

# Request queue depth
vault_request_queue_depth

# Processing time by endpoint
histogram_quantile(0.95, vault_http_request_duration_seconds_bucket)
```

---

## 5. Alerting Strategy

### 5.1 Critical vs Warning Thresholds

**Critical Alerts (Page immediately):**
- Vault cluster unavailable (>50% nodes down)
- Vault seal status changes unexpectedly
- Authentication failure rate >20/minute from single source
- Root token usage detected
- Audit log write failures
- Storage backend connectivity loss

**Warning Alerts (Email/Slack):**
- High resource utilization (CPU >80%, Memory >85%)
- Elevated response times (>2x baseline)
- Certificate expiration within 30 days
- Failed health checks for non-critical services
- Token TTL anomalies

### 5.2 Environment-Specific Alerts

**Production Environment:**
```yaml
# Critical thresholds for production
vault_response_time_p95: 500ms
vault_error_rate: 0.1%
vault_availability: 99.95%
storage_utilization: 80%
```

**Development/Staging:**
```yaml
# Relaxed thresholds for non-production
vault_response_time_p95: 2000ms
vault_error_rate: 1%
vault_availability: 99%
storage_utilization: 90%
```

### 5.3 On-Call Rotation Integration

**Escalation Paths:**
1. **Immediate (0-5 minutes)**: Primary on-call engineer
2. **Secondary (5-15 minutes)**: Backup on-call engineer
3. **Management (15-30 minutes)**: Engineering manager
4. **Executive (30+ minutes)**: CTO/VP Engineering

### 5.4 Runbook Automation

**Automated Responses:**
- Vault node restart for transient failures
- Automatic failover to standby regions
- Secret rotation triggers on compromise detection
- Scaling actions based on load patterns

---

## 6. Monitoring Blueprint Implementation

### 6.1 Technology Stack

**Core Components:**
- **Metrics Collection**: Prometheus with Nomad/Vault exporters
- **Log Aggregation**: Loki for structured log collection
- **Visualization**: Grafana with pre-built dashboards
- **Alerting**: Prometheus AlertManager with PagerDuty integration
- **Security Analysis**: Datadog Cloud SIEM for audit log analysis

### 6.2 Dashboard Templates

**Nomad Cluster Dashboard:**
```yaml
Dashboard ID: 15764 (Official Grafana)
Panels:
  - Cluster Health Overview
  - Resource Utilization by Node
  - Job Execution Status
  - Scheduling Performance
  - Network and Storage I/O
```

**Vault Security Dashboard:**
```yaml
Dashboard ID: 12904 (Official Grafana)
Panels:
  - Authentication Success/Failure Rates
  - Token Usage Patterns
  - Audit Event Timeline
  - Policy Violation Attempts
  - Geographic Access Distribution
```

**Custom Application Dashboard:**
```yaml
Panels:
  - Secret Fetch Latency (P50, P95, P99)
  - Database Connection Pool Status
  - API Rate Limiting Status
  - Error Rate by Service
  - Business Metrics Integration
```

### 6.3 Metric Specifications

**Infrastructure Metrics:**
```promql
# Nomad cluster health
up{job="nomad"}
nomad_client_allocations_running
nomad_client_host_memory_total
nomad_raft_leader_lastcontact

# Vault performance
vault_core_handle_request_duration_seconds
vault_token_creation_total
vault_audit_log_request_failure_total
vault_storage_backend_operation_duration_seconds
```

**Security Metrics:**
```promql
# Authentication monitoring
increase(vault_auth_method_login_total[5m])
increase(vault_token_creation_total{auth_method="root"}[1h])
increase(vault_audit_log_request_failure_total[5m])

# Access pattern analysis
vault_policy_usage_total
vault_secret_kv_request_total
```

### 6.4 Compliance Requirements

**Audit Trail Specifications:**
- **Retention**: 7 years minimum for financial compliance
- **Integrity**: Cryptographic signing of audit logs
- **Accessibility**: Searchable within 24 hours
- **Format**: Structured JSON with standardized fields
- **Backup**: Replicated across multiple regions

**Reporting Automation:**
- Daily security summary reports
- Weekly access pattern analysis
- Monthly compliance attestation
- Quarterly security review preparation

---

## 7. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Deploy Prometheus and Grafana infrastructure
- Configure basic Nomad and Vault metrics collection
- Implement essential health checks
- Set up basic alerting for critical failures

### Phase 2: Security Monitoring (Weeks 3-4)
- Deploy audit log collection and analysis
- Configure security-specific dashboards
- Implement anomaly detection rules
- Set up compliance reporting framework

### Phase 3: Application Integration (Weeks 5-6)
- Integrate application-level metrics
- Deploy connection pool monitoring
- Configure secret rotation monitoring
- Implement business metrics correlation

### Phase 4: Optimization (Weeks 7-8)
- Fine-tune alerting thresholds
- Implement automated remediation
- Deploy advanced analytics
- Complete runbook automation

---

## 8. Success Metrics

### Operational Metrics:
- **MTTR**: Mean Time to Resolution < 15 minutes for critical issues
- **MTTD**: Mean Time to Detection < 2 minutes for security incidents
- **Uptime**: 99.95% availability SLA compliance
- **Performance**: <200ms P95 response time for secret retrieval

### Security Metrics:
- **Detection Rate**: >95% of security events detected within 5 minutes
- **False Positive Rate**: <5% for critical security alerts
- **Compliance**: 100% audit trail completeness
- **Response Time**: <1 hour for security incident response

This monitoring blueprint provides comprehensive coverage of the 3-group Vault architecture with specific focus areas including infrastructure health, security monitoring, compliance requirements, and operational excellence. The implementation follows industry best practices while providing specific, actionable guidance for deployment and management.