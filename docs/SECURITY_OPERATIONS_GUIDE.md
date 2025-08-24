# 🛡️ Vault Security Operations Guide

## 🔐 Security Overview

### Security Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT APPLICATIONS                   │
├─────────────────────────────────────────────────────────┤
│                      LOAD BALANCER                       │
│                    (TLS Termination)                     │
├─────────────────────────────────────────────────────────┤
│                     VAULT CLUSTER                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Node 1    │  │   Node 2    │  │   Node 3    │     │
│  │ (Primary)   │  │ (Standby)   │  │ (Standby)   │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
├─────────────────────────────────────────────────────────┤
│                   STORAGE BACKEND                        │
│                  (Encrypted at Rest)                     │
├─────────────────────────────────────────────────────────┤
│                   AUDIT LOGGING                          │
│              (All Operations Logged)                     │
└─────────────────────────────────────────────────────────┘
```

### Security Principles
1. **Zero Trust**: Never trust, always verify
2. **Principle of Least Privilege**: Minimum necessary access
3. **Defense in Depth**: Multiple security layers
4. **Audit Everything**: Complete audit trail
5. **Encrypt Everything**: Data in transit and at rest

## 🔑 Key Rotation Procedures

### Root Token Rotation (Quarterly)

#### Preparation Phase
```bash
#!/bin/bash
# Root token rotation preparation

echo "🔄 ROOT TOKEN ROTATION - PREPARATION"
echo "==================================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
CURRENT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)

if [ -z "$CURRENT_TOKEN" ]; then
    echo "❌ Current root token not found"
    exit 1
fi

# 1. Verify current token works
export VAULT_TOKEN="$CURRENT_TOKEN"
if ! vault auth -method=token token="$CURRENT_TOKEN" >/dev/null 2>&1; then
    echo "❌ Current root token is invalid"
    exit 1
fi
echo "✅ Current root token verified"

# 2. Create backup
echo "Creating backup before rotation..."
/vault/scripts/continuous-backup.sh

# 3. Verify backup
LATEST_BACKUP=$(ls -t /backups/vault/ | head -1)
echo "✅ Backup created: $LATEST_BACKUP"

# 4. Log rotation start
echo "$(date): Root token rotation started" >> /var/log/vault-security.log

echo "Preparation completed. Ready for rotation."
```

#### Rotation Execution
```bash
#!/bin/bash
# Execute root token rotation

echo "🔄 ROOT TOKEN ROTATION - EXECUTION"
echo "=================================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
CURRENT_TOKEN=$(cat /root/.vault/root-token)
export VAULT_TOKEN="$CURRENT_TOKEN"

# 1. Generate new root token
echo "Generating new root token..."
NEW_ROOT_TOKEN=$(vault write -field=token auth/token/create \
    policies=root \
    ttl=0 \
    renewable=false \
    display_name="root-token-$(date +%Y%m%d)")

if [ -z "$NEW_ROOT_TOKEN" ]; then
    echo "❌ Failed to generate new root token"
    exit 1
fi

echo "✅ New root token generated"

# 2. Test new token
export VAULT_TOKEN="$NEW_ROOT_TOKEN"
if vault auth -method=token token="$NEW_ROOT_TOKEN" >/dev/null 2>&1; then
    echo "✅ New root token validated"
else
    echo "❌ New root token validation failed"
    # Revoke the bad token
    export VAULT_TOKEN="$CURRENT_TOKEN"
    vault token revoke "$NEW_ROOT_TOKEN"
    exit 1
fi

# 3. Store new token securely
echo "Storing new root token..."
/vault/security/secure-token-manager.sh rotate root-token "$NEW_ROOT_TOKEN" "Rotated on $(date)"

# 4. Update root token file
echo "$NEW_ROOT_TOKEN" | sudo tee /root/.vault/root-token > /dev/null
sudo chmod 600 /root/.vault/root-token

# 5. Revoke old token
export VAULT_TOKEN="$NEW_ROOT_TOKEN"
vault token revoke "$CURRENT_TOKEN"

echo "✅ Old root token revoked"

# 6. Log completion
echo "$(date): Root token rotation completed successfully" >> /var/log/vault-security.log

echo "Root token rotation completed successfully!"
echo "New token: $(echo $NEW_ROOT_TOKEN | head -c 8)***$(echo $NEW_ROOT_TOKEN | tail -c 5)"
```

### Unseal Key Rotation (Semi-Annually)

#### Unseal Key Rekey Process
```bash
#!/bin/bash
# Unseal key rotation (rekey process)

echo "🔐 UNSEAL KEY ROTATION - REKEY PROCESS"
echo "====================================="

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token)

# CRITICAL WARNING
echo "⚠️  CRITICAL WARNING ⚠️"
echo "This process will generate NEW unseal keys!"
echo "ALL current unseal keys will become invalid!"
echo "Ensure you have multiple administrators available!"
echo ""
read -p "Are you absolutely sure? Type 'REKEY' to continue: " -r

if [[ ! $REPLY == "REKEY" ]]; then
    echo "Rekey cancelled"
    exit 0
fi

# 1. Create comprehensive backup
echo "Creating pre-rekey backup..."
/vault/scripts/continuous-backup.sh

# 2. Initialize rekey operation
echo "Initializing rekey operation..."
REKEY_NONCE=$(vault operator rekey -init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json | jq -r '.nonce')

if [ -z "$REKEY_NONCE" ]; then
    echo "❌ Failed to initialize rekey"
    exit 1
fi

echo "✅ Rekey initialized with nonce: $REKEY_NONCE"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Gather 3 current unseal key holders"
echo "2. Each person provides their unseal key using:"
echo "   vault operator rekey -nonce=$REKEY_NONCE [their_key]"
echo "3. After 3 keys provided, new keys will be generated"
echo ""
echo "⚠️ Save the new keys immediately when generated!"

# Log the rekey initiation
echo "$(date): Unseal key rekey initiated with nonce $REKEY_NONCE" >> /var/log/vault-security.log
```

### TLS Certificate Rotation (Annually)

#### Certificate Renewal Process
```bash
#!/bin/bash
# TLS certificate rotation

echo "📜 TLS CERTIFICATE ROTATION"
echo "=========================="

CERT_FILE="/etc/vault.d/tls/vault-cert.pem"
KEY_FILE="/etc/vault.d/tls/vault-key.pem"
CA_FILE="/etc/vault.d/tls/ca-cert.pem"

# 1. Check current certificate
if [ -f "$CERT_FILE" ]; then
    echo "Current certificate information:"
    openssl x509 -in "$CERT_FILE" -noout -dates -subject -issuer
    
    # Check expiration
    EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -dates | grep notAfter | cut -d= -f2)
    DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))
    echo "Days until expiration: $DAYS_LEFT"
    
    if [ "$DAYS_LEFT" -gt 30 ]; then
        echo "⚠️ Certificate is still valid for $DAYS_LEFT days"
        read -p "Continue with rotation anyway? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Certificate rotation cancelled"
            exit 0
        fi
    fi
fi

# 2. Backup current certificates
echo "Backing up current certificates..."
BACKUP_DIR="/backups/certificates/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/vault.d/tls/* "$BACKUP_DIR/" 2>/dev/null || true
echo "✅ Certificates backed up to $BACKUP_DIR"

# 3. Generate new certificates (using existing CA or generate new)
echo "Generating new certificates..."
/vault/security/tls-cert-manager.sh renew

# 4. Validate new certificates
echo "Validating new certificates..."
if openssl verify -CAfile "$CA_FILE" "$CERT_FILE"; then
    echo "✅ Certificate validation successful"
else
    echo "❌ Certificate validation failed"
    # Restore from backup
    cp "$BACKUP_DIR"/* /etc/vault.d/tls/
    exit 1
fi

# 5. Test TLS connection
echo "Testing TLS connection..."
if openssl s_client -connect localhost:8200 -verify_return_error < /dev/null >/dev/null 2>&1; then
    echo "✅ TLS connection test successful"
else
    echo "❌ TLS connection test failed"
fi

# 6. Restart Vault to use new certificates
echo "Restarting Vault service..."
systemctl restart vault
sleep 10

# 7. Verify Vault is operational
if vault status >/dev/null 2>&1; then
    echo "✅ Vault is operational with new certificates"
else
    echo "❌ Vault is not operational - restoring backup"
    # Restore backup certificates
    cp "$BACKUP_DIR"/* /etc/vault.d/tls/
    systemctl restart vault
    exit 1
fi

echo "$(date): TLS certificates rotated successfully" >> /var/log/vault-security.log
echo "✅ TLS certificate rotation completed successfully"
```

## 🔒 Authentication Security

### AppRole Security Management

#### AppRole Rotation
```bash
#!/bin/bash
# AppRole credential rotation

echo "🎭 APPROLE CREDENTIAL ROTATION"
echo "============================"

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token)

ROLE_NAME="$1"
if [ -z "$ROLE_NAME" ]; then
    echo "Usage: $0 <role_name>"
    echo "Available roles:"
    vault list auth/approle/role
    exit 1
fi

# 1. Verify role exists
if ! vault read "auth/approle/role/$ROLE_NAME" >/dev/null 2>&1; then
    echo "❌ Role '$ROLE_NAME' does not exist"
    exit 1
fi

echo "Rotating credentials for role: $ROLE_NAME"

# 2. Get current role ID (this doesn't change)
ROLE_ID=$(vault read -field=role_id "auth/approle/role/$ROLE_NAME/role-id")
echo "Role ID: $ROLE_ID"

# 3. Generate new secret ID
NEW_SECRET_ID=$(vault write -field=secret_id \
    "auth/approle/role/$ROLE_NAME/secret-id")

if [ -z "$NEW_SECRET_ID" ]; then
    echo "❌ Failed to generate new secret ID"
    exit 1
fi

echo "✅ New secret ID generated"

# 4. Test authentication with new credentials
TEST_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$NEW_SECRET_ID")

if [ -n "$TEST_TOKEN" ]; then
    echo "✅ New credentials validated"
    # Revoke test token
    vault token revoke "$TEST_TOKEN"
else
    echo "❌ New credentials validation failed"
    exit 1
fi

# 5. Store new credentials securely
/vault/security/secure-token-manager.sh store \
    "$ROLE_NAME-role-id" "$ROLE_ID" "AppRole $ROLE_NAME role ID"
    
/vault/security/secure-token-manager.sh store \
    "$ROLE_NAME-secret-id" "$NEW_SECRET_ID" "AppRole $ROLE_NAME secret ID (rotated $(date))"

# 6. Log rotation
echo "$(date): AppRole $ROLE_NAME credentials rotated" >> /var/log/vault-security.log

echo "✅ AppRole credential rotation completed"
echo "Provide the new secret ID to the application team:"
echo "Secret ID: $(echo $NEW_SECRET_ID | head -c 8)***$(echo $NEW_SECRET_ID | tail -c 4)"
```

### User Account Security

#### Password Policy Enforcement
```bash
#!/bin/bash
# Password policy management

echo "🔐 PASSWORD POLICY MANAGEMENT"
echo "============================"

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token)

# 1. Create password policy
vault write sys/policies/password/strong-policy policy=-<<EOF
length = 12
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 1
}
rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
rule "charset" {
  charset = "!@#$%^&*"
  min-chars = 1
}
EOF

echo "✅ Password policy 'strong-policy' created"

# 2. Apply to userpass authentication
vault write auth/userpass/config password_policy=strong-policy

echo "✅ Password policy applied to userpass authentication"

# 3. Test password generation
echo ""
echo "Sample strong passwords:"
for i in {1..3}; do
    vault read -field=password sys/policies/password/strong-policy/generate
done

echo "$(date): Password policy updated" >> /var/log/vault-security.log
```

## 🔍 Security Monitoring

### Real-time Security Monitoring

#### Security Event Monitor
```bash
#!/bin/bash
# Real-time security event monitoring

echo "👁️ SECURITY EVENT MONITOR"
echo "========================"

AUDIT_LOG="/var/log/vault/audit.log"
SECURITY_LOG="/var/log/vault-security.log"

if [ ! -f "$AUDIT_LOG" ]; then
    echo "❌ Audit log not found: $AUDIT_LOG"
    exit 1
fi

# Monitor in real-time
tail -f "$AUDIT_LOG" | while read -r line; do
    # Parse audit event
    EVENT_TYPE=$(echo "$line" | jq -r '.type // "unknown"')
    REQUEST_PATH=$(echo "$line" | jq -r '.request.path // "unknown"')
    REMOTE_ADDR=$(echo "$line" | jq -r '.request.remote_address // "unknown"')
    ERROR=$(echo "$line" | jq -r '.error // null')
    
    # Check for security events
    ALERT=false
    ALERT_MSG=""
    
    # Failed authentication attempts
    if [[ "$ERROR" != "null" && "$REQUEST_PATH" =~ auth/ ]]; then
        ALERT=true
        ALERT_MSG="🚨 Failed authentication from $REMOTE_ADDR to $REQUEST_PATH"
    fi
    
    # Root token usage
    if [[ "$REQUEST_PATH" =~ ^sys/ && "$EVENT_TYPE" == "request" ]]; then
        ALERT=true
        ALERT_MSG="ℹ️ Root-level operation: $REQUEST_PATH from $REMOTE_ADDR"
    fi
    
    # New IP addresses
    if [[ "$REMOTE_ADDR" != "127.0.0.1" && "$REMOTE_ADDR" != "unknown" ]]; then
        # Check if this IP has been seen recently
        RECENT_IPS=$(tail -100 "$AUDIT_LOG" | jq -r '.request.remote_address' | sort | uniq)
        if ! echo "$RECENT_IPS" | grep -q "$REMOTE_ADDR"; then
            ALERT=true
            ALERT_MSG="👀 New client IP: $REMOTE_ADDR accessing $REQUEST_PATH"
        fi
    fi
    
    # Log and display alerts
    if [ "$ALERT" = true ]; then
        echo "$(date): $ALERT_MSG" | tee -a "$SECURITY_LOG"
    fi
done
```

#### Security Metrics Dashboard
```bash
#!/bin/bash
# Security metrics dashboard

echo "📊 SECURITY METRICS DASHBOARD"
echo "============================="

AUDIT_LOG="/var/log/vault/audit.log"

if [ ! -f "$AUDIT_LOG" ]; then
    echo "❌ Audit log not found"
    exit 1
fi

# Time ranges
HOUR_AGO=$(date -d '1 hour ago' +%s)
DAY_AGO=$(date -d '24 hours ago' +%s)
WEEK_AGO=$(date -d '7 days ago' +%s)

echo "📈 AUTHENTICATION METRICS (Last 24 Hours)"
echo "========================================"

# Failed authentication attempts
FAILED_AUTH=$(tail -10000 "$AUDIT_LOG" | \
    jq -r --arg day_ago "$DAY_AGO" \
    'select(.time | tonumber > ($day_ago | tonumber)) | select(.error != null and (.request.path | test("auth/"))) | .time' | \
    wc -l)

echo "Failed authentications: $FAILED_AUTH"

# Successful authentications
SUCCESS_AUTH=$(tail -10000 "$AUDIT_LOG" | \
    jq -r --arg day_ago "$DAY_AGO" \
    'select(.time | tonumber > ($day_ago | tonumber)) | select(.error == null and (.request.path | test("auth/"))) | .time' | \
    wc -l)

echo "Successful authentications: $SUCCESS_AUTH"

# Authentication success rate
if [ $((SUCCESS_AUTH + FAILED_AUTH)) -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; $SUCCESS_AUTH * 100 / ($SUCCESS_AUTH + $FAILED_AUTH)" | bc)
    echo "Authentication success rate: ${SUCCESS_RATE}%"
else
    echo "Authentication success rate: No data"
fi

echo ""
echo "🌍 CLIENT ANALYTICS (Last 24 Hours)"
echo "=================================="

# Unique client IPs
UNIQUE_IPS=$(tail -10000 "$AUDIT_LOG" | \
    jq -r --arg day_ago "$DAY_AGO" \
    'select(.time | tonumber > ($day_ago | tonumber)) | .request.remote_address // "unknown"' | \
    grep -v "127.0.0.1" | sort | uniq | wc -l)

echo "Unique client IPs: $UNIQUE_IPS"

# Top client IPs
echo ""
echo "Top 5 client IPs:"
tail -10000 "$AUDIT_LOG" | \
    jq -r --arg day_ago "$DAY_AGO" \
    'select(.time | tonumber > ($day_ago | tonumber)) | .request.remote_address // "unknown"' | \
    grep -v "127.0.0.1" | sort | uniq -c | sort -nr | head -5

echo ""
echo "🔐 ACCESS PATTERNS (Last 24 Hours)"
echo "================================="

# Most accessed paths
echo "Top 10 accessed paths:"
tail -10000 "$AUDIT_LOG" | \
    jq -r --arg day_ago "$DAY_AGO" \
    'select(.time | tonumber > ($day_ago | tonumber)) | .request.path // "unknown"' | \
    sort | uniq -c | sort -nr | head -10

echo ""
echo "Security metrics generated: $(date)"
```

### Vulnerability Scanning

#### Security Configuration Audit
```bash
#!/bin/bash
# Security configuration audit

echo "🔒 SECURITY CONFIGURATION AUDIT"
echo "==============================="

ISSUES_FOUND=0

# 1. File Permissions Audit
echo "1. File Permissions Audit:"
echo "========================="

# Check Vault configuration file
if [ -f "/etc/vault.d/vault.hcl" ]; then
    VAULT_CONFIG_PERMS=$(stat -c "%a" /etc/vault.d/vault.hcl)
    if [ "$VAULT_CONFIG_PERMS" -le 640 ]; then
        echo "✅ Vault config permissions: $VAULT_CONFIG_PERMS (secure)"
    else
        echo "❌ Vault config permissions: $VAULT_CONFIG_PERMS (too permissive)"
        ((ISSUES_FOUND++))
    fi
fi

# Check TLS certificate permissions
if [ -f "/etc/vault.d/tls/vault-key.pem" ]; then
    KEY_PERMS=$(stat -c "%a" /etc/vault.d/tls/vault-key.pem)
    if [ "$KEY_PERMS" -le 600 ]; then
        echo "✅ TLS key permissions: $KEY_PERMS (secure)"
    else
        echo "❌ TLS key permissions: $KEY_PERMS (too permissive)"
        ((ISSUES_FOUND++))
    fi
fi

# Check token file permissions
if [ -f "/root/.vault/root-token" ]; then
    TOKEN_PERMS=$(stat -c "%a" /root/.vault/root-token)
    if [ "$TOKEN_PERMS" -le 600 ]; then
        echo "✅ Root token permissions: $TOKEN_PERMS (secure)"
    else
        echo "❌ Root token permissions: $TOKEN_PERMS (too permissive)"
        ((ISSUES_FOUND++))
    fi
fi

echo ""

# 2. Network Security Audit
echo "2. Network Security Audit:"
echo "========================="

# Check if Vault is listening on all interfaces
VAULT_LISTENERS=$(netstat -tlnp | grep :8200 | awk '{print $4}')
if echo "$VAULT_LISTENERS" | grep -q "0.0.0.0:8200"; then
    echo "ℹ️ Vault listening on all interfaces (ensure firewall is configured)"
else
    echo "✅ Vault listening on specific interfaces"
fi

# Check TLS configuration
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
if [[ "$VAULT_ADDR" == https* ]]; then
    echo "✅ TLS enabled for Vault API"
    
    # Check TLS version
    TLS_VERSION=$(openssl s_client -connect localhost:8200 2>/dev/null | grep "Protocol" | awk '{print $3}')
    if [[ "$TLS_VERSION" =~ TLSv1\.[23] ]]; then
        echo "✅ TLS version: $TLS_VERSION (secure)"
    else
        echo "❌ TLS version: $TLS_VERSION (consider upgrading)"
        ((ISSUES_FOUND++))
    fi
else
    echo "❌ TLS not enabled for Vault API"
    ((ISSUES_FOUND++))
fi

echo ""

# 3. Vault Configuration Audit
echo "3. Vault Configuration Audit:"
echo "============================"

export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)

# Check if audit logging is enabled
if vault audit list >/dev/null 2>&1; then
    AUDIT_DEVICES=$(vault audit list -format=json | jq -r 'keys[]' | wc -l)
    if [ "$AUDIT_DEVICES" -gt 0 ]; then
        echo "✅ Audit logging enabled ($AUDIT_DEVICES devices)"
    else
        echo "❌ No audit devices enabled"
        ((ISSUES_FOUND++))
    fi
else
    echo "⚠️ Cannot check audit devices (token may be invalid)"
fi

# Check default lease TTL
if DEFAULT_TTL=$(vault read -field=default_lease_ttl sys/config/lease 2>/dev/null); then
    if [ "$DEFAULT_TTL" -le 86400 ]; then
        echo "✅ Default lease TTL: ${DEFAULT_TTL}s (reasonable)"
    else
        echo "⚠️ Default lease TTL: ${DEFAULT_TTL}s (consider reducing)"
    fi
fi

# Check if root token has TTL
if TOKEN_INFO=$(vault token lookup -format=json 2>/dev/null); then
    TTL=$(echo "$TOKEN_INFO" | jq -r '.data.ttl')
    if [ "$TTL" = "0" ]; then
        echo "⚠️ Root token has no expiration (consider using limited TTL tokens)"
    else
        echo "✅ Token TTL: ${TTL}s"
    fi
fi

echo ""

# 4. System Security Audit
echo "4. System Security Audit:"
echo "========================"

# Check if Vault user exists and is non-root
if id vault >/dev/null 2>&1; then
    VAULT_UID=$(id -u vault)
    if [ "$VAULT_UID" -ne 0 ]; then
        echo "✅ Vault running as non-root user (UID: $VAULT_UID)"
    else
        echo "❌ Vault running as root user"
        ((ISSUES_FOUND++))
    fi
else
    echo "⚠️ Vault user does not exist"
fi

# Check systemd security features
if systemctl show vault --property=PrivateTmp | grep -q "yes"; then
    echo "✅ Vault service has PrivateTmp enabled"
else
    echo "⚠️ Vault service does not have PrivateTmp enabled"
fi

# Summary
echo ""
echo "AUDIT SUMMARY"
echo "============="
if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo "✅ No critical security issues found"
else
    echo "❌ Found $ISSUES_FOUND security issues that should be addressed"
fi

echo ""
echo "Audit completed: $(date)"
echo "Report saved to: /var/log/vault-security-audit-$(date +%Y%m%d).log"

# Save detailed report
{
    echo "Vault Security Audit Report"
    echo "Generated: $(date)"
    echo "Issues Found: $ISSUES_FOUND"
    echo ""
    echo "Recommendations:"
    if [ "$ISSUES_FOUND" -gt 0 ]; then
        echo "- Review and fix all identified issues"
        echo "- Implement regular security audits"
        echo "- Consider external security assessment"
    else
        echo "- Maintain current security configuration"
        echo "- Continue regular monitoring"
    fi
} > "/var/log/vault-security-audit-$(date +%Y%m%d).log"

exit $ISSUES_FOUND
```

## 🚨 Incident Response

### Security Incident Response Plan

#### Incident Classification
```bash
#!/bin/bash
# Security incident classification and response

INCIDENT_TYPE="$1"
SEVERITY="$2"

echo "🚨 SECURITY INCIDENT RESPONSE"
echo "============================"
echo "Incident Type: $INCIDENT_TYPE"
echo "Severity: $SEVERITY"
echo "Timestamp: $(date)"

case "$INCIDENT_TYPE" in
    "unauthorized-access")
        echo ""
        echo "UNAUTHORIZED ACCESS RESPONSE:"
        echo "1. Identify compromised accounts/tokens"
        echo "2. Revoke compromised credentials immediately"
        echo "3. Review audit logs for extent of access"
        echo "4. Change all potentially affected passwords/tokens"
        echo "5. Implement additional monitoring"
        ;;
    "token-compromise")
        echo ""
        echo "TOKEN COMPROMISE RESPONSE:"
        echo "1. Revoke compromised token immediately:"
        echo "   vault token revoke [TOKEN_ID]"
        echo "2. Review all activities performed with token"
        echo "3. Rotate all related credentials"
        echo "4. Notify affected application owners"
        ;;
    "data-breach")
        echo ""
        echo "DATA BREACH RESPONSE:"
        echo "1. Immediately isolate affected systems"
        echo "2. Preserve evidence for investigation"
        echo "3. Assess scope and impact of breach"
        echo "4. Notify security team and management"
        echo "5. Consider external security assistance"
        echo "6. Prepare breach notifications as required"
        ;;
    "system-compromise")
        echo ""
        echo "SYSTEM COMPROMISE RESPONSE:"
        echo "1. Isolate compromised systems from network"
        echo "2. Preserve system state for forensics"
        echo "3. Rebuild systems from known-good backups"
        echo "4. Rotate ALL credentials and certificates"
        echo "5. Implement enhanced monitoring"
        ;;
esac

# Log incident
echo "$(date): Security incident $INCIDENT_TYPE (severity: $SEVERITY) reported" >> /var/log/vault-security-incidents.log
```

### Emergency Lockdown Procedures

#### Complete System Lockdown
```bash
#!/bin/bash
# Emergency system lockdown

echo "🔒 EMERGENCY SYSTEM LOCKDOWN"
echo "============================"
echo "WARNING: This will disable all Vault access!"
echo ""

read -p "Are you sure you want to proceed? Type 'LOCKDOWN' to confirm: " -r
if [[ ! $REPLY == "LOCKDOWN" ]]; then
    echo "Lockdown cancelled"
    exit 0
fi

export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)

# 1. Seal Vault immediately
echo "Sealing Vault..."
vault operator seal

# 2. Stop Vault service
echo "Stopping Vault service..."
systemctl stop vault

# 3. Block network access (if firewall is available)
if command -v ufw >/dev/null; then
    echo "Blocking Vault ports..."
    ufw deny 8200
    ufw deny 8201
fi

# 4. Log lockdown
echo "$(date): EMERGENCY LOCKDOWN ACTIVATED" >> /var/log/vault-security-incidents.log
echo "$(date): EMERGENCY LOCKDOWN ACTIVATED" | wall

echo ""
echo "🔒 SYSTEM LOCKED DOWN"
echo "===================="
echo "- Vault is sealed"
echo "- Service is stopped"  
echo "- Network access blocked"
echo ""
echo "To recover:"
echo "1. Investigate the security incident"
echo "2. Address the root cause"
echo "3. Follow unlock procedures"
echo "4. Re-enable network access"
echo "5. Start Vault service"
echo "6. Unseal Vault"
```

## 📋 Security Compliance

### Compliance Checklist Generator
```bash
#!/bin/bash
# Generate security compliance checklist

echo "📋 VAULT SECURITY COMPLIANCE CHECKLIST"
echo "======================================"

COMPLIANCE_DATE=$(date +%Y-%m-%d)
REPORT_FILE="/var/log/vault-compliance-$COMPLIANCE_DATE.json"

# Initialize JSON report
cat > "$REPORT_FILE" << 'EOF'
{
  "compliance_report": {
    "date": "",
    "vault_version": "",
    "checks": []
  }
}
EOF

# Update report metadata
jq --arg date "$COMPLIANCE_DATE" \
   --arg version "$(vault version 2>/dev/null | head -1 || echo 'unknown')" \
   '.compliance_report.date = $date | .compliance_report.vault_version = $version' \
   "$REPORT_FILE" > "${REPORT_FILE}.tmp" && mv "${REPORT_FILE}.tmp" "$REPORT_FILE"

add_check() {
    local name="$1"
    local status="$2"
    local details="$3"
    
    jq --arg name "$name" --arg status "$status" --arg details "$details" \
       '.compliance_report.checks += [{
         "check": $name,
         "status": $status,
         "details": $details,
         "timestamp": (now | todate)
       }]' "$REPORT_FILE" > "${REPORT_FILE}.tmp" && mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
}

echo "Running compliance checks..."

# Check 1: Encryption at Rest
if grep -q "seal" /etc/vault.d/vault.hcl 2>/dev/null; then
    add_check "Encryption at Rest" "PASS" "Vault configured with seal stanza"
    echo "✅ Encryption at Rest"
else
    add_check "Encryption at Rest" "REVIEW" "No seal configuration found"
    echo "⚠️ Encryption at Rest - requires review"
fi

# Check 2: TLS Configuration
export VAULT_ADDR=${VAULT_ADDR:-https://127.0.0.1:8200}
if [[ "$VAULT_ADDR" == https* ]]; then
    add_check "TLS Encryption" "PASS" "HTTPS enabled"
    echo "✅ TLS Encryption"
else
    add_check "TLS Encryption" "FAIL" "HTTP only - TLS not enabled"
    echo "❌ TLS Encryption"
fi

# Check 3: Audit Logging
export VAULT_TOKEN=$(cat /root/.vault/root-token 2>/dev/null)
if vault audit list >/dev/null 2>&1; then
    AUDIT_COUNT=$(vault audit list -format=json | jq -r 'keys | length')
    if [ "$AUDIT_COUNT" -gt 0 ]; then
        add_check "Audit Logging" "PASS" "$AUDIT_COUNT audit devices enabled"
        echo "✅ Audit Logging"
    else
        add_check "Audit Logging" "FAIL" "No audit devices enabled"
        echo "❌ Audit Logging"
    fi
else
    add_check "Audit Logging" "UNKNOWN" "Cannot verify - token invalid"
    echo "⚠️ Audit Logging - cannot verify"
fi

# Check 4: Access Controls
if vault policy list | grep -qv "^root$\|^default$"; then
    add_check "Access Controls" "PASS" "Custom policies configured"
    echo "✅ Access Controls"
else
    add_check "Access Controls" "REVIEW" "Only default policies found"
    echo "⚠️ Access Controls - requires review"
fi

# Check 5: Authentication Methods
if vault auth list | grep -qv "^token/"; then
    add_check "Authentication Methods" "PASS" "Non-token auth methods configured"
    echo "✅ Authentication Methods"
else
    add_check "Authentication Methods" "REVIEW" "Only token authentication enabled"
    echo "⚠️ Authentication Methods - requires review"
fi

# Check 6: Regular Backups
if [ -d "/backups/vault" ] && [ "$(ls -A /backups/vault 2>/dev/null)" ]; then
    BACKUP_COUNT=$(ls /backups/vault | wc -l)
    add_check "Backup Strategy" "PASS" "$BACKUP_COUNT backups found"
    echo "✅ Backup Strategy"
else
    add_check "Backup Strategy" "FAIL" "No backups found"
    echo "❌ Backup Strategy"
fi

# Generate summary
TOTAL_CHECKS=$(jq '.compliance_report.checks | length' "$REPORT_FILE")
PASS_COUNT=$(jq '.compliance_report.checks | map(select(.status == "PASS")) | length' "$REPORT_FILE")
FAIL_COUNT=$(jq '.compliance_report.checks | map(select(.status == "FAIL")) | length' "$REPORT_FILE")

echo ""
echo "COMPLIANCE SUMMARY"
echo "=================="
echo "Total checks: $TOTAL_CHECKS"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "Compliance rate: $(( PASS_COUNT * 100 / TOTAL_CHECKS ))%"
echo ""
echo "Full report saved to: $REPORT_FILE"

# Display JSON report
echo ""
echo "DETAILED REPORT:"
jq . "$REPORT_FILE"
```

---

## 📞 Security Team Contacts

### Emergency Security Response Team
- **Security Officer**: [Primary Contact]
- **Vault Administrator**: [Vault Expert]
- **Infrastructure Team**: [System Access]
- **Legal/Compliance**: [Breach Notifications]

### Escalation Procedures
1. **Level 1** (0-15 min): Vault Administrator
2. **Level 2** (15-30 min): Security Officer + Management
3. **Level 3** (30+ min): External security consultant

---

**🛡️ This security operations guide provides comprehensive procedures for maintaining Vault security in production environments.**

*Regular review and practice of these procedures is essential for maintaining security posture.*

---
*Last Updated: $(date)*
*Security Operations Guide Version: 1.0*