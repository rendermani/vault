# HashiCorp Vault Security Audit Report

**Date**: 2025-08-24  
**Auditor**: Security Auditor Agent  
**Vault Version**: 1.17.3  
**Deployment Target**: cloudya.net  

## Executive Summary

This comprehensive security audit evaluates the HashiCorp Vault deployment configuration, policies, scripts, and procedures. The assessment covers security posture, compliance status, vulnerability analysis, and best practices adherence.

**Overall Security Rating**: ⚠️ MODERATE RISK  
**Critical Issues Found**: 3  
**Major Issues Found**: 4  
**Minor Issues Found**: 6  
**Compliance Status**: PARTIAL

---

## 🔴 Critical Security Issues

### 1. TLS Disabled in Production
**File**: `/config/vault.hcl`, `/scripts/deploy-vault.sh`, `.github/workflows/deploy.yml`  
**Risk Level**: CRITICAL  
**Issue**: TLS is explicitly disabled (`tls_disable = true`) for all network communications.

```hcl
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true  # CRITICAL VULNERABILITY
}
```

**Impact**:
- All API communications transmitted in plaintext
- Sensitive data (tokens, secrets) vulnerable to interception
- Root tokens, unseal keys transmitted without encryption
- Man-in-the-middle attacks possible

**Remediation**:
```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
  tls_min_version = "tls12"
}
```

### 2. Plaintext Root Token Storage
**File**: `/scripts/deploy-vault.sh` (lines 211, 234)  
**Risk Level**: CRITICAL  
**Issue**: Root tokens stored in plaintext files on filesystem.

```bash
echo "$ROOT_TOKEN" > /root/.vault/root-token  # CRITICAL
export VAULT_TOKEN=$(cat /root/.vault/root-token)
```

**Impact**:
- Persistent root access vulnerability
- Token compromise enables full Vault takeover
- Violates principle of least privilege
- No token rotation mechanism

**Remediation**:
- Implement secure token wrapping
- Use short-lived tokens only
- Implement automatic token rotation
- Use HSM or external key management

### 3. Insecure Secret Management in CI/CD
**File**: `.github/workflows/deploy.yml`  
**Risk Level**: CRITICAL  
**Issue**: Unseal keys and init data stored on production servers without proper protection.

```yaml
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /opt/vault/init.json  # STORED ON SERVER
```

**Impact**:
- Unseal keys accessible to attackers with server access
- Single point of failure for entire Vault cluster
- No key escrow or secure distribution mechanism

---

## 🟠 Major Security Issues

### 4. Excessive Admin Privileges
**File**: `/policies/admin.hcl`  
**Risk Level**: MAJOR  
**Issue**: Admin policy grants blanket access to all paths.

```hcl
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
```

**Remediation**: Implement granular admin policies with specific path restrictions.

### 5. Missing Audit Logging
**Risk Level**: MAJOR  
**Issue**: No audit logging configuration found in any Vault configuration files.

**Impact**:
- No security event logging
- Compliance violations (SOX, PCI-DSS, GDPR)
- Inability to detect unauthorized access
- No forensic capabilities

**Remediation**:
```hcl
audit "file" {
  file_path = "/opt/vault/logs/audit.log"
}
```

### 6. Weak Systemd Security
**File**: `.github/workflows/deploy.yml` (lines 99-100)  
**Risk Level**: MAJOR  
**Issue**: Vault service runs as root user instead of dedicated service account.

```yaml
User=root
Group=root
```

**Impact**: Privilege escalation if Vault is compromised.

**Remediation**: Use dedicated vault user as shown in `/scripts/deploy-vault.sh`.

### 7. Network Exposure
**File**: `/config/vault.hcl`  
**Risk Level**: MAJOR  
**Issue**: Vault bound to all interfaces (`0.0.0.0:8200`) without network restrictions.

```hcl
listener "tcp" {
  address = "0.0.0.0:8200"  # Exposed to all networks
}
```

---

## 🟡 Minor Security Issues

### 8. Memory Lock Disabled
**File**: `/config/vault.hcl`  
**Issue**: `disable_mlock = true` allows memory to be swapped to disk.
**Risk**: Secrets could be written to swap files.

### 9. Plaintext Credential Files
**Files**: Multiple scripts create plaintext credential files:
- `/root/traefik-vault-approle.txt`
- `/opt/vault/${SERVICE}-approle.txt`
- `/root/traefik-vault-token.txt`

### 10. Missing Input Validation
**Files**: Various scripts lack input sanitization and validation.

### 11. Hardcoded Paths
**Issue**: Many hardcoded paths reduce deployment flexibility.

### 12. Telemetry Configuration
**File**: `/config/vault.hcl`  
**Issue**: Prometheus retention time very short (30s), may lose metrics.

### 13. Weak Token TTLs
**Files**: `/policies/ci-cd.hcl`, `/scripts/setup-traefik-integration.sh`  
**Issue**: Some tokens have long TTLs (720h) without proper rotation.

---

## ✅ Security Strengths

### 1. Systemd Hardening (deploy-vault.sh)
```ini
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
```

### 2. File Permissions
- Proper use of `chmod 600` for sensitive files
- Dedicated vault user and group
- Secure directory permissions (700)

### 3. Policy Segregation
- Well-defined RBAC policies for different roles
- Principle of least privilege in developer/operations policies
- Good separation between admin, developer, operations, and CI/CD roles

### 4. AppRole Authentication
- Proper implementation of AppRole for service authentication
- Reasonable token TTLs and renewal policies
- Secret ID management

### 5. Backup Procedures
- Automated Raft snapshot backups
- Policy and configuration backups
- Timestamped backup directories

---

## Compliance Assessment

### CIS Benchmark Compliance: ⚠️ PARTIAL (4/10)

| Control | Status | Notes |
|---------|---------|--------|
| Enable TLS | ❌ FAIL | TLS explicitly disabled |
| Audit Logging | ❌ FAIL | No audit configuration |
| Root Token Management | ❌ FAIL | Plaintext storage |
| Network Security | ❌ FAIL | Exposed to all interfaces |
| File Permissions | ✅ PASS | Proper chmod/chown usage |
| Service Account | ✅ PASS | Dedicated vault user |
| Systemd Hardening | ✅ PASS | Good systemd security |
| Policy Management | ✅ PASS | RBAC implemented |
| Authentication | ⚠️ PARTIAL | AppRole good, token management weak |
| Storage Security | ⚠️ PARTIAL | Raft encrypted at rest, mlock disabled |

### Regulatory Compliance

- **SOX**: ❌ Fails audit requirements
- **PCI-DSS**: ❌ Fails encryption in transit requirements  
- **GDPR**: ❌ Lacks audit trail for data access
- **HIPAA**: ❌ Insufficient access logging

---

## Vulnerability Summary

### High Priority (Fix Immediately)
1. **Enable TLS encryption** for all communications
2. **Implement secure root token management** with wrapping/rotation
3. **Configure audit logging** for compliance and monitoring
4. **Restrict network access** to specific interfaces/networks

### Medium Priority (Fix Soon)
1. Enable memory locking (`disable_mlock = false`)
2. Implement proper CI/CD secret management
3. Add input validation to all scripts
4. Configure network security groups/firewalls

### Low Priority (Improvement)
1. Implement automated credential rotation
2. Add monitoring and alerting
3. Document security procedures
4. Regular security testing

---

## Recommendations

### Immediate Actions (1-3 Days)

1. **Enable TLS**:
   ```bash
   # Generate certificates
   vault write pki/root/generate/internal \
     common_name="vault-ca" \
     ttl=87600h
   
   # Update vault.hcl
   tls_disable = false
   tls_cert_file = "/opt/vault/tls/vault.crt"
   tls_key_file = "/opt/vault/tls/vault.key"
   ```

2. **Enable Audit Logging**:
   ```hcl
   audit "file" {
     file_path = "/opt/vault/logs/audit.log"
     log_raw = false
     format = "json"
   }
   ```

3. **Implement Network Security**:
   ```hcl
   listener "tcp" {
     address = "127.0.0.1:8200"  # Restrict to localhost
     # or specific interface
   }
   ```

### Short Term (1-2 Weeks)

1. **Root Token Security**:
   - Implement response wrapping for initial tokens
   - Create break-glass procedures for emergency access
   - Implement token rotation automation

2. **CI/CD Security**:
   - Use GitHub Secrets for sensitive data
   - Implement OIDC authentication for GitHub Actions
   - Remove plaintext credential storage

3. **Monitoring**:
   - Set up log monitoring with SIEM
   - Configure alerting for security events
   - Implement metrics dashboards

### Long Term (1-3 Months)

1. **High Availability**:
   - Implement Vault cluster with multiple nodes
   - Configure auto-unsealing with cloud HSM
   - Implement disaster recovery procedures

2. **Advanced Security**:
   - Implement MFA for admin access
   - Set up certificate-based authentication
   - Regular penetration testing

3. **Compliance**:
   - Document all security procedures
   - Implement regular security reviews
   - Create incident response procedures

---

## Security Test Results

### Authentication Tests
- ✅ AppRole authentication functional
- ✅ Token renewal working
- ❌ TLS certificate validation (N/A - disabled)
- ⚠️ Root token rotation (not implemented)

### Authorization Tests  
- ✅ Policy enforcement working
- ✅ Path-based access control functional
- ✅ RBAC implementation correct
- ❌ Admin policy too permissive

### Network Security Tests
- ❌ TLS encryption (disabled)
- ❌ Certificate validation (N/A)
- ⚠️ Network exposure (all interfaces)
- ✅ Port configuration correct

### Storage Security Tests
- ✅ Raft storage properly configured
- ❌ Memory locking disabled
- ✅ File permissions secure
- ⚠️ Backup encryption (needs verification)

---

## Conclusion

The HashiCorp Vault deployment shows good foundational security practices including proper RBAC policies, systemd hardening, and file permissions. However, **critical security vulnerabilities exist** that require immediate attention, particularly the disabled TLS encryption and insecure root token management.

**Priority Actions**:
1. Enable TLS encryption immediately
2. Implement secure token management
3. Configure audit logging
4. Restrict network access

The deployment is **NOT READY for production use** in its current state due to the critical security issues identified. With the recommended fixes implemented, this would become a secure, compliant Vault deployment suitable for production workloads.

**Risk Rating**: ⚠️ MODERATE TO HIGH RISK  
**Recommendation**: DEFER PRODUCTION DEPLOYMENT until critical issues resolved

---

*Report Generated: 2025-08-24*  
*Next Audit Due: After remediation implementation*