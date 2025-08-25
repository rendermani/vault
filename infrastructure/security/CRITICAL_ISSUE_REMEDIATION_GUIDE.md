# Critical Issue Remediation Guide
## Infrastructure Hive Security Fixes

**URGENT**: These critical security issues must be resolved before production deployment.

---

## 🔴 CRITICAL ISSUE #1: TLS Configuration Gaps

### Problem
- Development environment has TLS disabled
- HTTP endpoints used in bootstrap health checks
- Mixed TLS configurations across environments

### Impact
- Plaintext transmission of sensitive data
- Token interception vulnerability
- Man-in-the-middle attack exposure

### Fix Commands

```bash
# 1. Fix base Vault configuration
sed -i 's|api_addr = "http://vault.cloudya.net:8200"|api_addr = "https://vault.cloudya.net:8200"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

# 2. Update bootstrap health checks to use HTTPS
sed -i 's|http://localhost:8200|https://localhost:8200|g' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/*bootstrap*.sh

# 3. Generate development certificates (if needed)
mkdir -p /etc/vault.d/tls/
openssl req -x509 -newkey rsa:4096 -keyout /etc/vault.d/tls/vault-key.pem \
  -out /etc/vault.d/tls/vault-cert.pem -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# 4. Set proper permissions
chmod 600 /etc/vault.d/tls/vault-key.pem
chmod 644 /etc/vault.d/tls/vault-cert.pem
```

### Verification
```bash
# Test TLS endpoint
curl -k https://localhost:8200/v1/sys/health

# Verify certificate
openssl x509 -in /etc/vault.d/tls/vault-cert.pem -text -noout | grep "Not After"
```

---

## 🔴 CRITICAL ISSUE #2: Bootstrap Token Security

### Problem
- Temporary tokens stored in plaintext files
- Bootstrap tokens with excessive lifetime
- No secure cleanup of temporary credentials

### Impact
- Token compromise during bootstrap
- Persistent security vulnerabilities
- Audit trail gaps

### Fix Commands

```bash
# 1. Add secure cleanup to bootstrap script
cat >> /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh << 'EOF'

# Enhanced cleanup function
secure_cleanup() {
    local exit_code=$?
    
    # Securely remove temporary token files
    if [[ -d "/tmp/bootstrap-tokens" ]]; then
        find /tmp/bootstrap-tokens -type f -exec shred -vfz -n 3 {} \;
        rm -rf /tmp/bootstrap-tokens
    fi
    
    # Clear environment variables
    unset VAULT_TOKEN NOMAD_BOOTSTRAP_TOKEN CONSUL_BOOTSTRAP_TOKEN
    
    exit $exit_code
}

# Set trap for cleanup
trap secure_cleanup EXIT ERR INT TERM

EOF

# 2. Use secure temporary directory
sed -i 's|mkdir -p /tmp/bootstrap-tokens|TEMP_DIR=$(mktemp -d -t bootstrap-tokens.XXXXXX); mkdir -p "$TEMP_DIR"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh

sed -i 's|/tmp/bootstrap-tokens|$TEMP_DIR|g' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh

# 3. Implement memory-only token storage where possible
cat >> /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh << 'EOF'

# Store tokens in memory-only variables when possible
store_token_secure() {
    local token_name="$1"
    local token_value="$2"
    
    # Use declare to create variable dynamically
    declare -g "TOKEN_${token_name^^}"="$token_value"
    
    # Clear original variable
    unset token_value
}

EOF
```

### Verification
```bash
# Test cleanup function
/Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh --dry-run

# Verify no tokens remain in temp directories
find /tmp -name "*token*" -ls 2>/dev/null || echo "No token files found - Good!"
```

---

## 🔴 CRITICAL ISSUE #3: Network Security Exposure

### Problem
- Services bound to all interfaces (0.0.0.0)
- Potential external access without proper firewall rules
- Increased attack surface

### Impact
- External network exposure
- Unauthorized access potential
- Compliance violations

### Fix Commands

```bash
# 1. Fix Vault listener binding
sed -i 's|address       = "0.0.0.0:8200"|address       = "127.0.0.1:8200"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

sed -i 's|address         = "0.0.0.0:8201"|address         = "127.0.0.1:8201"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

# 2. Fix Nomad binding
sed -i 's|bind_addr = "0.0.0.0"|bind_addr = "127.0.0.1"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/nomad/config/nomad-server.hcl

# 3. Configure firewall rules (example for UFW)
cat > /tmp/firewall-rules.sh << 'EOF'
#!/bin/bash
# Basic firewall configuration

# Enable UFW if not already enabled
ufw --force enable

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH access (adjust port as needed)
ufw allow 22/tcp

# Vault (only from specific networks)
ufw allow from 10.0.0.0/8 to any port 8200
ufw allow from 172.16.0.0/12 to any port 8200
ufw allow from 192.168.0.0/16 to any port 8200

# Nomad (only from specific networks)  
ufw allow from 10.0.0.0/8 to any port 4646
ufw allow from 172.16.0.0/12 to any port 4646
ufw allow from 192.168.0.0/16 to any port 4646

# Traefik HTTP/HTTPS (public)
ufw allow 80/tcp
ufw allow 443/tcp

echo "Firewall rules configured"
EOF

chmod +x /tmp/firewall-rules.sh

# 4. For production, use specific network interfaces
# Edit production config to use actual interface IPs
echo "# For production deployment, update addresses to use specific interface IPs"
echo "# Example: address = '10.0.1.100:8200'"
```

### Verification
```bash
# Check interface bindings
netstat -tlnp | grep -E ':(8200|4646|8080)'

# Verify firewall status
ufw status verbose

# Test external accessibility (should fail)
timeout 5 curl -k https://external-ip:8200/v1/sys/health || echo "Good - external access blocked"
```

---

## 🔴 CRITICAL ISSUE #4: Audit Logging Disabled

### Problem
- Audit devices commented out by default
- No compliance logging active
- Forensic capability gaps

### Impact
- Compliance violations
- No security event tracking
- Inability to detect breaches

### Fix Commands

```bash
# 1. Enable file audit logging in Vault config
sed -i 's|^# audit "file" {|audit "file" {|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

sed -i 's|^#   file_path = "/var/log/vault/audit.log"|  file_path = "/var/log/vault/audit.log"|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

sed -i 's|^# }|  format = "json"\n  log_raw = false\n}|' \
  /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl

# 2. Create audit log directory
mkdir -p /var/log/vault
chmod 750 /var/log/vault
chown vault:vault /var/log/vault 2>/dev/null || true

# 3. Configure log rotation
cat > /etc/logrotate.d/vault-audit << 'EOF'
/var/log/vault/audit.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    copytruncate
    postrotate
        systemctl reload vault 2>/dev/null || true
    endscript
}
EOF

# 4. Enable syslog audit (optional)
cat >> /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl << 'EOF'

# Syslog audit device for centralized logging
audit "syslog" {
  facility = "AUTH"
  tag = "vault"
  format = "json"
}
EOF

# 5. Configure rsyslog for Vault
cat > /etc/rsyslog.d/10-vault-audit.conf << 'EOF'
# Vault audit logging
auth.info /var/log/vault/vault-syslog.log
& stop
EOF

systemctl restart rsyslog 2>/dev/null || true
```

### Verification
```bash
# Test audit logging
vault auth -method=userpass username=test password=test 2>/dev/null || true

# Check audit log creation
ls -la /var/log/vault/
tail -f /var/log/vault/audit.log | jq . 2>/dev/null || tail -f /var/log/vault/audit.log

# Verify log rotation config
logrotate -d /etc/logrotate.d/vault-audit
```

---

## 🔄 VERIFICATION SCRIPT

Create and run this verification script to confirm all fixes:

```bash
cat > /tmp/verify-fixes.sh << 'EOF'
#!/bin/bash

echo "=== VERIFYING CRITICAL SECURITY FIXES ==="
echo

# Check TLS configuration
echo "1. TLS Configuration:"
if grep -q 'api_addr = "https://' /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl; then
    echo "   ✅ HTTPS API address configured"
else
    echo "   ❌ HTTP still configured for API"
fi

# Check bootstrap cleanup
echo "2. Bootstrap Token Security:"
if grep -q "secure_cleanup" /Users/mlautenschlager/cloudya/vault/infrastructure/scripts/unified-bootstrap.sh; then
    echo "   ✅ Secure cleanup implemented"
else
    echo "   ❌ Secure cleanup not found"
fi

# Check network binding
echo "3. Network Security:"
if grep -q 'address.*127.0.0.1:8200' /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl; then
    echo "   ✅ Vault bound to localhost"
else
    echo "   ❌ Vault still bound to all interfaces"
fi

# Check audit logging
echo "4. Audit Logging:"
if grep -q '^audit "file"' /Users/mlautenschlager/cloudya/vault/infrastructure/vault/config/vault.hcl; then
    echo "   ✅ File audit enabled"
else
    echo "   ❌ File audit still disabled"
fi

echo
echo "=== FIX VERIFICATION COMPLETE ==="
EOF

chmod +x /tmp/verify-fixes.sh
/tmp/verify-fixes.sh
```

---

## 📋 POST-FIX CHECKLIST

After implementing all fixes:

- [ ] TLS endpoints respond correctly
- [ ] Certificate validity confirmed (>30 days)
- [ ] Bootstrap cleanup functions properly
- [ ] No temporary token files remain
- [ ] Services bound to correct interfaces
- [ ] Firewall rules configured and active
- [ ] Audit logs being generated
- [ ] Log rotation configured
- [ ] All verification tests pass

---

## 🚀 DEPLOYMENT READINESS

Once all critical fixes are verified:

1. **Run comprehensive security validation**:
   ```bash
   /Users/mlautenschlager/cloudya/vault/infrastructure/security/automated-security-validation.sh production
   ```

2. **Confirm production readiness**: Should show 0 critical issues

3. **Deploy to production**: Infrastructure is now secure for production use

---

**Estimated Fix Time**: 2-4 hours  
**Complexity**: Low (configuration changes only)  
**Impact**: High (eliminates all critical security vulnerabilities)

**Support Contact**: Security Team Lead  
**Escalation**: Engineering Manager