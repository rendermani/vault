# AppRole Authentication Configuration for Nomad-Vault Integration

## Overview

AppRole is a secure authentication method that allows Nomad servers and workloads to authenticate to Vault using role-based credentials. This guide provides the complete configuration for implementing AppRole authentication in the Nomad-Vault integration.

## AppRole Concepts

### Components

1. **Role ID**: A public identifier for the AppRole (equivalent to username)
2. **Secret ID**: A secret credential bound to the Role ID (equivalent to password)
3. **Token**: Vault token issued after successful AppRole authentication
4. **Bind Restrictions**: Security constraints on who can use the AppRole

### Security Model

- **Role ID**: Can be stored in configuration files (less sensitive)
- **Secret ID**: Must be protected like a password
- **Time-bound**: Both Secret IDs and tokens have configurable TTLs
- **Usage limits**: Secret IDs can be limited to N uses

---

## Phase 2: AppRole Setup for Nomad Servers

### Step 1: Enable AppRole Authentication

```bash
#!/bin/bash
# Enable AppRole auth method in Vault

export VAULT_TOKEN=$ROOT_TOKEN  # Use root token for initial setup

log_info "Enabling AppRole authentication method..."

# Enable AppRole auth method
vault auth enable approle

# Verify enablement
vault auth list | grep approle || {
    log_error "Failed to enable AppRole auth method"
    exit 1
}

log_success "AppRole authentication method enabled"
```

### Step 2: Create AppRole for Nomad Servers

```bash
#!/bin/bash
# Create AppRole specifically for Nomad servers

log_info "Creating AppRole for Nomad servers..."

# Create AppRole with appropriate policies and restrictions
vault write auth/approle/role/nomad-servers \
    token_policies="nomad-server-bootstrap" \
    token_ttl="1h" \
    token_max_ttl="24h" \
    secret_id_ttl="720h" \
    secret_id_num_uses=0 \
    bind_secret_id=true \
    secret_id_bound_cidrs="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
    token_bound_cidrs="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
    token_no_default_policy=true \
    token_type="service"

# Verify role creation
vault read auth/approle/role/nomad-servers || {
    log_error "Failed to create AppRole for Nomad servers"
    exit 1
}

log_success "AppRole created for Nomad servers"
```

### Step 3: Generate and Securely Store Credentials

```bash
#!/bin/bash
# Generate and store AppRole credentials securely

log_info "Generating AppRole credentials..."

# Get Role ID (less sensitive, can be in config)
NOMAD_ROLE_ID=$(vault read -field=role_id auth/approle/role/nomad-servers/role-id)

# Generate Secret ID (highly sensitive, must be protected)
SECRET_ID_RESPONSE=$(vault write -format=json auth/approle/role/nomad-servers/secret-id)
NOMAD_SECRET_ID=$(echo "$SECRET_ID_RESPONSE" | jq -r '.data.secret_id')
SECRET_ID_ACCESSOR=$(echo "$SECRET_ID_RESPONSE" | jq -r '.data.secret_id_accessor')

# Store credentials securely
mkdir -p /etc/nomad.d/vault-auth
chmod 700 /etc/nomad.d/vault-auth

# Store Role ID (can be in main config)
echo "NOMAD_VAULT_ROLE_ID=\"$NOMAD_ROLE_ID\"" > /etc/nomad.d/vault-auth/role-id
chmod 644 /etc/nomad.d/vault-auth/role-id

# Store Secret ID (highly protected)
echo "NOMAD_VAULT_SECRET_ID=\"$NOMAD_SECRET_ID\"" > /etc/nomad.d/vault-auth/secret-id
chmod 600 /etc/nomad.d/vault-auth/secret-id
chown nomad:nomad /etc/nomad.d/vault-auth/secret-id

# Store accessor for management/rotation
echo "SECRET_ID_ACCESSOR=\"$SECRET_ID_ACCESSOR\"" > /etc/nomad.d/vault-auth/secret-id-accessor
chmod 600 /etc/nomad.d/vault-auth/secret-id-accessor

log_success "AppRole credentials generated and stored securely"
log_info "Role ID: $NOMAD_ROLE_ID"
log_info "Secret ID Accessor: $SECRET_ID_ACCESSOR"
```

### Step 4: Configure Nomad Server for AppRole

```bash
#!/bin/bash
# Update Nomad configuration to use AppRole authentication

log_info "Configuring Nomad server for AppRole authentication..."

# Source the credentials
source /etc/nomad.d/vault-auth/role-id
source /etc/nomad.d/vault-auth/secret-id

# Create Nomad Vault configuration
cat > /etc/nomad.d/vault-approle.hcl <<EOF
vault {
  enabled = true
  address = "${VAULT_ADDR}"
  
  # AppRole authentication configuration
  auth_method = "approle"
  role_id     = "${NOMAD_VAULT_ROLE_ID}"
  secret_id   = "${NOMAD_VAULT_SECRET_ID}"
  
  # Token management
  create_from_role = "nomad-cluster"
  
  # Connection settings
  task_token_ttl    = "1h"
  ca_file          = "/etc/vault.d/tls/ca-cert.pem"
  cert_file        = "/etc/vault.d/tls/nomad-vault.pem"
  key_file         = "/etc/vault.d/tls/nomad-vault-key.pem"
  tls_server_name  = "vault.cloudya.net"
  
  # Retry configuration
  retry {
    attempts = 5
    backoff  = "250ms"
    max_backoff = "1m"
  }
}
EOF

chmod 640 /etc/nomad.d/vault-approle.hcl
chown nomad:nomad /etc/nomad.d/vault-approle.hcl

log_success "Nomad configured for AppRole authentication"
```

---

## AppRole for Individual Workloads

### Step 1: Create Workload-Specific AppRoles

```bash
#!/bin/bash
# Create AppRoles for individual applications

create_workload_approle() {
    local app_name="$1"
    local namespace="${2:-default}"
    local environment="${3:-develop}"
    
    log_info "Creating AppRole for workload: $app_name"
    
    # Create policy for the workload (if not exists)
    if ! vault policy read "${app_name}-policy" >/dev/null 2>&1; then
        vault policy write "${app_name}-policy" - <<EOF
# Application-specific secrets
path "kv/data/${namespace}/${app_name}/*" {
  capabilities = ["read"]
}

path "kv/metadata/${namespace}/${app_name}/*" {
  capabilities = ["read", "list"]
}

# Shared secrets for the namespace
path "kv/data/${namespace}/shared/*" {
  capabilities = ["read"]
}

# Database credentials
path "database/creds/${app_name}" {
  capabilities = ["read"]
}

# PKI certificates
path "pki_int/issue/${app_name}" {
  capabilities = ["update"]
  allowed_parameters = {
    "common_name" = ["${app_name}.service.consul"]
    "ttl" = ["24h"]
  }
}

# Self-token management
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
    fi
    
    # Create AppRole for the workload
    vault write auth/approle/role/${app_name} \
        token_policies="${app_name}-policy" \
        token_ttl="30m" \
        token_max_ttl="2h" \
        secret_id_ttl="168h" \
        secret_id_num_uses=100 \
        bind_secret_id=true \
        token_bound_cidrs="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
        token_type="service"
    
    # Generate credentials
    local role_id=$(vault read -field=role_id auth/approle/role/${app_name}/role-id)
    local secret_id=$(vault write -field=secret_id auth/approle/role/${app_name}/secret-id)
    
    # Store in Vault KV for retrieval by Nomad job
    vault kv put kv/nomad/approles/${app_name} \
        role_id="$role_id" \
        secret_id="$secret_id" \
        environment="$environment" \
        namespace="$namespace"
    
    log_success "AppRole created for workload: $app_name"
    log_info "Role ID: $role_id"
}

# Create AppRoles for common workloads
create_workload_approle "web-app" "default" "develop"
create_workload_approle "api-service" "default" "develop"
create_workload_approle "database-migration" "default" "develop"
create_workload_approle "monitoring-agent" "system" "develop"
```

### Step 2: Nomad Job Template with AppRole Authentication

```hcl
# Example Nomad job using AppRole authentication
job "web-app" {
  datacenters = ["dc1"]
  type        = "service"
  
  group "web" {
    count = 2
    
    # Restart policy for AppRole token renewal
    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }
    
    task "app" {
      driver = "docker"
      
      # Vault configuration for this specific task
      vault {
        policies = ["web-app-policy"]
        
        # Use workload identity if available, fallback to AppRole
        change_mode = "restart"
        env         = true
      }
      
      # Template to retrieve AppRole credentials from Vault
      template {
        data = <<EOH
{{- with secret "kv/nomad/approles/web-app" -}}
VAULT_ROLE_ID="{{ .Data.role_id }}"
VAULT_SECRET_ID="{{ .Data.secret_id }}"
{{- end -}}
EOH
        destination = "local/vault-approle.env"
        env         = true
        change_mode = "restart"
      }
      
      # Application configuration with Vault integration
      template {
        data = <<EOH
{{- with secret "kv/data/default/web-app/config" -}}
DATABASE_URL="{{ .Data.data.database_url }}"
API_KEY="{{ .Data.data.api_key }}"
{{- end -}}

# Database credentials
{{- with secret "database/creds/web-app" -}}
DB_USERNAME="{{ .Data.username }}"
DB_PASSWORD="{{ .Data.password }}"
{{- end -}}
EOH
        destination = "local/app-config.env"
        env         = true
        change_mode = "restart"
      }
      
      config {
        image = "web-app:latest"
        ports = ["http"]
      }
      
      service {
        name = "web-app"
        port = "http"
        
        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
    
    network {
      port "http" {
        to = 8080
      }
    }
  }
}
```

---

## Secret ID Management and Rotation

### Automatic Secret ID Rotation Script

```bash
#!/bin/bash
# Automatic Secret ID rotation for AppRoles

rotate_secret_id() {
    local role_name="$1"
    local current_accessor="$2"
    
    log_info "Rotating Secret ID for AppRole: $role_name"
    
    # Generate new Secret ID
    new_secret_response=$(vault write -format=json auth/approle/role/${role_name}/secret-id)
    new_secret_id=$(echo "$new_secret_response" | jq -r '.data.secret_id')
    new_accessor=$(echo "$new_secret_response" | jq -r '.data.secret_id_accessor')
    
    if [[ -z "$new_secret_id" || "$new_secret_id" == "null" ]]; then
        log_error "Failed to generate new Secret ID for $role_name"
        return 1
    fi
    
    # Update storage (example for workload AppRoles)
    if vault kv get kv/nomad/approles/${role_name} >/dev/null 2>&1; then
        # Get current data
        current_data=$(vault kv get -format=json kv/nomad/approles/${role_name})
        role_id=$(echo "$current_data" | jq -r '.data.data.role_id')
        environment=$(echo "$current_data" | jq -r '.data.data.environment')
        namespace=$(echo "$current_data" | jq -r '.data.data.namespace')
        
        # Update with new Secret ID
        vault kv put kv/nomad/approles/${role_name} \
            role_id="$role_id" \
            secret_id="$new_secret_id" \
            environment="$environment" \
            namespace="$namespace" \
            rotated_at="$(date -Iseconds)" \
            accessor="$new_accessor"
    fi
    
    # For Nomad servers, update the file
    if [[ "$role_name" == "nomad-servers" ]]; then
        echo "NOMAD_VAULT_SECRET_ID=\"$new_secret_id\"" > /etc/nomad.d/vault-auth/secret-id
        echo "SECRET_ID_ACCESSOR=\"$new_accessor\"" > /etc/nomad.d/vault-auth/secret-id-accessor
        
        # Reload Nomad configuration
        systemctl reload nomad
    fi
    
    # Revoke old Secret ID (after grace period)
    sleep 60  # Allow time for new credentials to propagate
    if [[ -n "$current_accessor" && "$current_accessor" != "null" ]]; then
        vault write auth/approle/role/${role_name}/secret-id-accessor/destroy \
            secret_id_accessor="$current_accessor"
        log_info "Revoked old Secret ID accessor: $current_accessor"
    fi
    
    log_success "Secret ID rotated successfully for $role_name"
    log_info "New accessor: $new_accessor"
}

# Automated rotation schedule (run via cron)
rotate_all_secret_ids() {
    log_info "Starting automated Secret ID rotation..."
    
    # Get list of all AppRoles
    approles=$(vault list -format=json auth/approle/role | jq -r '.[]')
    
    while IFS= read -r role; do
        if [[ -n "$role" ]]; then
            # Get current accessor
            current_accessor=$(cat "/etc/nomad.d/vault-auth/secret-id-accessor" 2>/dev/null | cut -d'"' -f2)
            
            # Check if rotation is needed (based on age/usage)
            secret_info=$(vault read -format=json auth/approle/role/${role}/secret-id-accessor/lookup 2>/dev/null || echo '{}')
            creation_time=$(echo "$secret_info" | jq -r '.data.creation_time // 0')
            
            if [[ $creation_time -ne 0 ]]; then
                # Rotate if older than 30 days
                current_time=$(date +%s)
                creation_epoch=$(date -d "$creation_time" +%s 2>/dev/null || echo 0)
                age_days=$(( (current_time - creation_epoch) / 86400 ))
                
                if [[ $age_days -gt 30 ]]; then
                    rotate_secret_id "$role" "$current_accessor"
                else
                    log_info "Secret ID for $role is $age_days days old, no rotation needed"
                fi
            fi
        fi
    done <<< "$approles"
    
    log_success "Automated Secret ID rotation completed"
}
```

### Monitoring and Alerting

```bash
#!/bin/bash
# Monitor AppRole health and usage

monitor_approle_health() {
    log_info "Monitoring AppRole health..."
    
    # Check authentication failures
    auth_failures=$(vault read sys/internal/counters/auth/approle | grep -o 'failures.*[0-9]*' || echo "failures: 0")
    failure_count=$(echo "$auth_failures" | grep -o '[0-9]*$')
    
    if [[ $failure_count -gt 100 ]]; then
        alert_security_team "High AppRole authentication failures: $failure_count"
    fi
    
    # Check for expired Secret IDs
    expired_secrets=0
    approles=$(vault list -format=json auth/approle/role | jq -r '.[]')
    
    while IFS= read -r role; do
        if [[ -n "$role" ]]; then
            # List secret ID accessors
            accessors=$(vault list -format=json auth/approle/role/${role}/secret-id | jq -r '.[]' 2>/dev/null || echo "")
            
            while IFS= read -r accessor; do
                if [[ -n "$accessor" && "$accessor" != "null" ]]; then
                    # Check secret ID info
                    secret_info=$(vault read -format=json auth/approle/role/${role}/secret-id-accessor/lookup \
                        secret_id_accessor="$accessor" 2>/dev/null || echo '{}')
                    
                    ttl=$(echo "$secret_info" | jq -r '.data.secret_id_ttl // 0')
                    if [[ $ttl -eq 0 ]]; then
                        ((expired_secrets++))
                        log_warning "Expired Secret ID found for role $role: $accessor"
                    fi
                fi
            done <<< "$accessors"
        fi
    done <<< "$approles"
    
    if [[ $expired_secrets -gt 0 ]]; then
        alert_operations_team "Found $expired_secrets expired Secret IDs"
    fi
    
    log_success "AppRole health monitoring completed"
    log_info "Auth failures: $failure_count, Expired secrets: $expired_secrets"
}

# Alert functions
alert_security_team() {
    local message="$1"
    # Send to security team (Slack, email, PagerDuty, etc.)
    curl -X POST "$SECURITY_SLACK_WEBHOOK" -d "{\"text\":\"🔒 Security Alert: $message\"}"
    logger -t vault-security "SECURITY_ALERT: $message"
}

alert_operations_team() {
    local message="$1"
    # Send to operations team
    curl -X POST "$OPS_SLACK_WEBHOOK" -d "{\"text\":\"⚠️ Ops Alert: $message\"}"
    logger -t vault-ops "OPS_ALERT: $message"
}
```

---

## Security Best Practices

### AppRole Security Configuration

1. **Network Restrictions**: Always use `secret_id_bound_cidrs` and `token_bound_cidrs`
2. **TTL Management**: Set appropriate TTLs for tokens and Secret IDs
3. **Usage Limits**: Use `secret_id_num_uses` for high-security workloads
4. **Regular Rotation**: Implement automated Secret ID rotation
5. **Audit Logging**: Monitor all AppRole authentication events

### Production Hardening

```bash
#!/bin/bash
# Production hardening for AppRole authentication

harden_approle_production() {
    log_info "Applying production hardening for AppRole..."
    
    # Disable AppRole listing for non-admin users
    vault policy write approle-deny-list - <<EOF
path "auth/approle/role" {
  capabilities = ["deny"]
}

path "auth/approle/role/*" {
  capabilities = ["deny"]
}
EOF
    
    # Create tighter policies for production workloads
    vault write auth/approle/role/production-app \
        token_policies="production-app-policy" \
        token_ttl="15m" \
        token_max_ttl="1h" \
        token_num_uses=10 \
        secret_id_ttl="24h" \
        secret_id_num_uses=50 \
        bind_secret_id=true \
        secret_id_bound_cidrs="10.0.1.0/24" \
        token_bound_cidrs="10.0.1.0/24" \
        token_type="service" \
        token_no_default_policy=true
    
    # Enable MFA for AppRole management operations
    vault write sys/mfa/method/totp/admin_totp \
        issuer="Vault-AppRole" \
        period=30 \
        algorithm=SHA256 \
        digits=6
    
    # Create MFA policy for AppRole operations
    vault policy write approle-mfa-required - <<EOF
path "auth/approle/role/*/secret-id" {
  capabilities = ["update"]
  mfa_methods = ["admin_totp"]
}

path "auth/approle/role/*/secret-id-accessor/destroy" {
  capabilities = ["update"]
  mfa_methods = ["admin_totp"]
}
EOF
    
    log_success "Production hardening applied for AppRole"
}
```

---

## Troubleshooting Guide

### Common AppRole Issues

1. **Authentication Failures**
   ```bash
   # Check AppRole configuration
   vault read auth/approle/role/nomad-servers
   
   # Verify Secret ID is valid
   vault write auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"
   
   # Check audit logs for detailed error
   tail -f /var/log/vault/audit.log | grep approle
   ```

2. **Token Renewal Issues**
   ```bash
   # Check token TTL settings
   vault token lookup $TOKEN
   
   # Verify renewal capability
   vault token capabilities $TOKEN auth/token/renew-self
   ```

3. **Secret ID Exhaustion**
   ```bash
   # Check Secret ID usage
   vault read auth/approle/role/nomad-servers/secret-id-accessor/lookup \
     secret_id_accessor="$ACCESSOR"
   
   # Generate new Secret ID if needed
   vault write auth/approle/role/nomad-servers/secret-id
   ```

### Health Check Script

```bash
#!/bin/bash
# AppRole health check script

check_approle_health() {
    local role_name="$1"
    local role_id="$2"
    local secret_id="$3"
    
    log_info "Checking AppRole health for: $role_name"
    
    # Test authentication
    auth_response=$(vault write -format=json auth/approle/login \
        role_id="$role_id" \
        secret_id="$secret_id" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        token=$(echo "$auth_response" | jq -r '.auth.client_token')
        ttl=$(echo "$auth_response" | jq -r '.auth.lease_duration')
        
        log_success "AppRole authentication successful"
        log_info "Token TTL: ${ttl}s"
        
        # Test token renewal
        VAULT_TOKEN="$token" vault token renew >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            log_success "Token renewal successful"
        else
            log_warning "Token renewal failed"
        fi
        
        # Clean up test token
        vault token revoke "$token" >/dev/null 2>&1
    else
        log_error "AppRole authentication failed for $role_name"
        return 1
    fi
}

# Run health checks for all configured AppRoles
main() {
    # Check Nomad servers
    if [[ -f "/etc/nomad.d/vault-auth/role-id" && -f "/etc/nomad.d/vault-auth/secret-id" ]]; then
        source /etc/nomad.d/vault-auth/role-id
        source /etc/nomad.d/vault-auth/secret-id
        check_approle_health "nomad-servers" "$NOMAD_VAULT_ROLE_ID" "$NOMAD_VAULT_SECRET_ID"
    fi
    
    # Check workload AppRoles
    workload_approles=$(vault list -format=json auth/approle/role | jq -r '.[]' | grep -v nomad-servers)
    while IFS= read -r role; do
        if [[ -n "$role" ]]; then
            # Skip if no stored credentials
            if vault kv get kv/nomad/approles/${role} >/dev/null 2>&1; then
                log_info "Checking workload AppRole: $role"
                # Note: In practice, you'd get these from secure storage
                role_id=$(vault kv get -field=role_id kv/nomad/approles/${role})
                secret_id=$(vault kv get -field=secret_id kv/nomad/approles/${role})
                check_approle_health "$role" "$role_id" "$secret_id"
            fi
        fi
    done <<< "$workload_approles"
}

main "$@"
```

This comprehensive AppRole configuration provides secure, scalable authentication for the Nomad-Vault integration with proper credential management, rotation, monitoring, and troubleshooting capabilities.