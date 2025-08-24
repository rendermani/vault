# Vault Security Remediation Checklist

## 🔴 CRITICAL - Fix Immediately (Production Blocking)

- [ ] **Enable TLS Encryption**
  - [ ] Generate TLS certificates
  - [ ] Update vault.hcl: `tls_disable = false`
  - [ ] Configure tls_cert_file and tls_key_file
  - [ ] Test TLS connectivity

- [ ] **Secure Root Token Management**
  - [ ] Remove plaintext token files from filesystem
  - [ ] Implement response wrapping for initial tokens
  - [ ] Create break-glass emergency access procedure
  - [ ] Document token rotation process

- [ ] **Enable Audit Logging**
  - [ ] Add audit stanza to vault.hcl
  - [ ] Configure log rotation
  - [ ] Set up log monitoring
  - [ ] Test audit log generation

## 🟠 MAJOR - Fix Within 1 Week

- [ ] **Network Security**
  - [ ] Restrict listener to specific interfaces
  - [ ] Configure firewall rules
  - [ ] Remove 0.0.0.0 binding
  - [ ] Implement network segmentation

- [ ] **Service Account Security**
  - [ ] Ensure Vault runs as vault user (not root)
  - [ ] Verify systemd hardening settings
  - [ ] Test service restart functionality

- [ ] **CI/CD Security**
  - [ ] Move secrets to GitHub Secrets
  - [ ] Implement OIDC authentication
  - [ ] Remove plaintext credential storage in workflows
  - [ ] Add secret scanning to pipeline

## 🟡 MINOR - Fix Within 2 Weeks

- [ ] **Memory Security**
  - [ ] Set `disable_mlock = false`
  - [ ] Verify memory locking capability
  - [ ] Test with constrained environments

- [ ] **Policy Refinement**  
  - [ ] Refine admin policy with specific paths
  - [ ] Review all policy grants
  - [ ] Implement policy versioning

- [ ] **Token Management**
  - [ ] Reduce long-lived token TTLs
  - [ ] Implement automated rotation
  - [ ] Add token usage monitoring

## ✅ Verification Steps

After implementing fixes, verify:

1. **TLS Test**: `curl -k https://cloudya.net:8200/v1/sys/health`
2. **Audit Test**: Check audit.log for entry after API call
3. **Network Test**: Verify restricted access works
4. **Service Test**: Restart Vault service as vault user
5. **Policy Test**: Verify admin policy restrictions work

## Emergency Contacts

- Security Team: [Contact Info]
- Operations Team: [Contact Info]  
- Management: [Contact Info]

## Sign-off

- [ ] Security Review Complete: ________________ Date: __________
- [ ] Operations Approval: __________________ Date: __________
- [ ] Management Approval: _________________ Date: __________

**Production Deployment Approved**: ⚠️ **PENDING CRITICAL FIXES**