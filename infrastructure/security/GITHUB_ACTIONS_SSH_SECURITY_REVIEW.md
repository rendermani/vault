# GitHub Actions SSH Security Review
**Date**: 2025-08-25  
**Reviewer**: Claude Code - Security Review Agent  
**Scope**: SSH key handling, secrets management, and remote deployment security  

## Executive Summary

**Overall Security Rating**: ⚠️ **REQUIRES IMMEDIATE SECURITY IMPROVEMENTS**

**Critical Findings**:
- 🔴 **CRITICAL**: SSH host key verification bypassed in multiple workflows
- 🔴 **CRITICAL**: Multiple SSH private key secrets with unclear management
- 🟠 **MAJOR**: Inconsistent secret naming patterns
- 🟡 **MINOR**: Missing SSH connection timeout configurations

## 🔍 SSH Key Management Analysis

### SSH Private Key Secrets Identified

| Secret Name | Used In | Security Assessment |
|-------------|---------|-------------------|
| `DEPLOY_SSH_KEY` | Vault deployment workflows | ✅ **GOOD** - Proper key management with ssh-keyscan |
| `SSH_PRIVATE_KEY` | Traefik deployment workflows | ❌ **POOR** - Used with StrictHostKeyChecking=no |

### SSH Authentication Methods

**Positive Security Practices Found**:
- ✅ SSH keys stored as GitHub Secrets (not hardcoded)
- ✅ SSH keys have proper file permissions (600) when created
- ✅ Some workflows use `ssh-keyscan` for host key verification
- ✅ SSH keys are cleaned up after use in some workflows

**Security Vulnerabilities Found**:
- ❌ **CRITICAL**: Multiple workflows disable host key checking
- ❌ **CRITICAL**: Inconsistent SSH security practices across workflows
- ❌ No SSH connection timeouts configured

## 🚨 Critical Security Issues

### 1. Host Key Verification Bypass
**Risk Level**: CRITICAL  
**Impact**: Man-in-the-middle attacks, connection to malicious servers

**Vulnerable Code Found**:
```bash
# Multiple workflows contain this insecure pattern
scp -o StrictHostKeyChecking=no \
ssh -o StrictHostKeyChecking=no root@${SERVER_IP} << 'EOF'
```

**Locations**:
- `/repositories/traefik/.github/workflows/deploy.yml`
- `/nomad/traefik/.github/workflows/deploy.yml`  
- `/repositories/vault/traefik/.github/workflows/deploy.yml`
- `/repositories/nomad/traefik/.github/workflows/deploy.yml`
- `/traefik/.github/workflows/deploy.yml`

### 2. Secure vs Insecure SSH Implementations

**✅ SECURE IMPLEMENTATION** (in Vault workflows):
```yaml
- name: Set up SSH
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan -H ${{ env.DEPLOY_HOST }} >> ~/.ssh/known_hosts
```

**❌ INSECURE IMPLEMENTATION** (in Traefik workflows):
```bash
scp -o StrictHostKeyChecking=no \
ssh -o StrictHostKeyChecking=no root@${SERVER_IP} << 'EOF'
```

## 📋 Secrets Management Review

### Required GitHub Secrets

| Secret Name | Purpose | Security Status |
|-------------|---------|----------------|
| `DEPLOY_SSH_KEY` | SSH private key for root@cloudya.net | ✅ **SECURE** - Used with proper host verification |
| `SSH_PRIVATE_KEY` | SSH private key for deployments | ⚠️ **INSECURE** - Used without host verification |
| `VAULT_ADDR` | Vault server address | ✅ **GOOD** - Environment configuration |
| `VAULT_TOKEN` | Vault authentication token | ✅ **GOOD** - Proper token management |
| `NOMAD_ADDR` | Nomad server address | ✅ **GOOD** - Environment configuration |
| `NOMAD_TOKEN` | Nomad authentication token | ✅ **GOOD** - Proper token management |
| `SERVER_IP` | Target server IP address | ✅ **GOOD** - Environment configuration |
| `ACME_EMAIL` | Let's Encrypt email | ✅ **GOOD** - Certificate management |

## 🔧 Security Fixes Required

### IMMEDIATE FIXES (Critical Priority)

#### 1. Fix SSH Host Key Verification

**Replace all instances of**:
```bash
ssh -o StrictHostKeyChecking=no
scp -o StrictHostKeyChecking=no
```

**With secure implementation**:
```yaml
- name: Set up SSH with host verification
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan -H ${{ env.DEPLOY_HOST }} >> ~/.ssh/known_hosts
    
- name: Deploy with secure SSH
  run: |
    scp scripts/deploy.sh root@${{ env.DEPLOY_HOST }}:/tmp/
    ssh root@${{ env.DEPLOY_HOST }} "/tmp/deploy.sh"
```

#### 2. Standardize SSH Secret Names

**Current State**: Mixed usage of `DEPLOY_SSH_KEY` and `SSH_PRIVATE_KEY`  
**Fix**: Standardize on `DEPLOY_SSH_KEY` for all workflows

#### 3. Add SSH Connection Timeouts

```yaml
- name: Test SSH Connection with timeout
  run: |
    timeout 30 ssh -o ConnectTimeout=10 root@${{ env.DEPLOY_HOST }} "echo 'SSH connection successful'"
```

#### 4. Implement SSH Connection Hardening

```yaml
- name: Harden SSH connection
  run: |
    cat >> ~/.ssh/config << EOF
    Host ${{ env.DEPLOY_HOST }}
        User root
        IdentitiesOnly yes
        PasswordAuthentication no
        PubkeyAuthentication yes
        ConnectTimeout 10
        ServerAliveInterval 60
        ServerAliveCountMax 3
    EOF
```

### Updated Workflow Template

```yaml
- name: Setup Secure SSH
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    
    # Add host key verification
    ssh-keyscan -H ${{ env.DEPLOY_HOST }} >> ~/.ssh/known_hosts
    
    # Configure SSH client hardening
    cat >> ~/.ssh/config << EOF
    Host ${{ env.DEPLOY_HOST }}
        User root
        IdentitiesOnly yes
        PasswordAuthentication no
        PubkeyAuthentication yes
        ConnectTimeout 10
        ServerAliveInterval 60
        ServerAliveCountMax 3
    EOF

- name: Test SSH Connection
  run: |
    timeout 30 ssh root@${{ env.DEPLOY_HOST }} "echo 'SSH connection successful'"

- name: Deploy
  run: |
    scp scripts/deploy.sh root@${{ env.DEPLOY_HOST }}:/tmp/
    ssh root@${{ env.DEPLOY_HOST }} "/tmp/deploy.sh"

- name: Cleanup SSH
  if: always()
  run: |
    rm -f ~/.ssh/id_rsa
    rm -f ~/.ssh/config
```

## 🛡️ Additional Security Recommendations

### 1. SSH Key Rotation Policy
- Rotate SSH keys quarterly
- Use separate keys for different environments
- Implement key auditing

### 2. Network Security
- Use SSH tunneling for sensitive operations
- Implement IP whitelisting where possible
- Consider using bastion hosts for production

### 3. Monitoring and Alerting
- Monitor SSH connection attempts
- Alert on failed authentication
- Log all SSH sessions for audit

### 4. Backup Authentication
- Implement emergency access procedures
- Maintain offline key recovery methods
- Document key management procedures

## 📊 Security Compliance Assessment

| Requirement | Current Status | Target Status |
|-------------|---------------|---------------|
| **SSH Host Verification** | ❌ Disabled in most workflows | ✅ **MUST FIX** - Enable everywhere |
| **SSH Key Management** | ⚠️ Mixed approaches | ✅ **SHOULD FIX** - Standardize |
| **Connection Security** | ⚠️ Basic implementation | ✅ **SHOULD FIX** - Add hardening |
| **Secret Management** | ✅ Using GitHub Secrets | ✅ **GOOD** - Continue current practice |
| **Access Logging** | ⚠️ Limited | ✅ **SHOULD ADD** - Enhance monitoring |

## 🚀 Implementation Plan

### Phase 1: Critical Fixes (24 hours)
1. **Replace all `StrictHostKeyChecking=no` with proper host verification**
2. **Standardize SSH secret names across all workflows**
3. **Add SSH connection timeouts**

### Phase 2: Security Hardening (1 week)
1. **Implement SSH client hardening configurations**
2. **Add comprehensive SSH connection testing**
3. **Enhance error handling and cleanup**

### Phase 3: Monitoring Enhancement (2 weeks)
1. **Implement SSH session monitoring**
2. **Add security alerts for failed connections**
3. **Create SSH key rotation procedures**

## ✅ Verification Checklist

After implementing fixes:

- [ ] All workflows use `ssh-keyscan` for host verification
- [ ] No workflows use `StrictHostKeyChecking=no`
- [ ] SSH connections have appropriate timeouts
- [ ] SSH keys are properly cleaned up after use
- [ ] All workflows use standardized secret names
- [ ] SSH client configurations are hardened
- [ ] Connection testing is implemented before deployment
- [ ] Error handling and rollback procedures are in place

## 📝 Conclusion

The current SSH implementation has **critical security vulnerabilities** that must be addressed immediately. While some workflows demonstrate good security practices (particularly the Vault deployment), the majority bypass essential security controls.

**Priority Actions**:
1. **IMMEDIATELY** fix host key verification bypass
2. **URGENTLY** standardize SSH security practices
3. **SOON** implement additional hardening measures

**Risk Level**: After fixes are applied, the deployment security will be **SIGNIFICANTLY IMPROVED** and suitable for production use.

---
**Security Review Completed**: 2025-08-25  
**Next Review Recommended**: After critical fixes are implemented  
**Review Classification**: Internal Security Assessment