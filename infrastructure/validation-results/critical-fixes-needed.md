# Critical Infrastructure Issues - Fix Required Before Deployment

## 🔴 HIGH PRIORITY - Must Fix Before Production

### 1. Nomad Job Configuration Errors

**File**: `/nomad/jobs/develop/vault.nomad`
```hcl
# ERROR: Auto Promote requires a Canary count greater than zero
update {
  auto_promote = true  # This requires canary > 0
  canary = 0          # This should be > 0
}
```
**Fix**: Set `canary = 1` or disable `auto_promote`

**File**: `/nomad/jobs/production/vault.nomad`
```hcl  
# ERROR: Duplicate check "service: vault-production check"
service {
  name = "vault-production"
  check {
    name = "vault-production"  # This name appears twice
  }
  check {
    name = "vault-production"  # DUPLICATE - causes error
  }
}
```
**Fix**: Rename second check or remove duplicate

## 🟡 MEDIUM PRIORITY - Fix for CI/CD

### 2. GitHub Workflow Syntax Errors

**Multiple files have syntax errors**:
- Missing `:` characters (line ~93-98 in several workflows)
- Malformed YAML structure

**Example from `/repositories/nomad/.github/workflows/deploy-traefik.yml`**:
```yaml
# Line 93: syntax error: could not find expected ':'
```

**Fix**: Review and repair YAML syntax in all workflow files

## 🟢 LOW PRIORITY - Cosmetic/Best Practice

### 3. YAML Formatting Issues
- Missing `---` document start markers
- Trailing whitespace throughout files  
- Missing newlines at end of files
- Line length violations (>80 chars)

### 4. Shell Script Warnings
- Variable assignment in command substitution (SC2155)
- Unquoted variable expansions (SC2086)
- Several other shellcheck warnings

## Environment Variables Missing

### Docker Compose Files Need:
- `MYSQL_ROOT_PASSWORD`
- `OWNCLOUD_DB_PASSWORD` 
- `OWNCLOUD_ADMIN_PASSWORD`
- `OWNCLOUD_DOMAIN`
- `NETWORK_NAME`
- `VAULT_TOKEN`

These should be provided by environment setup scripts.

## Files Requiring Immediate Attention:

1. `/nomad/jobs/develop/vault.nomad` - Fix canary config
2. `/nomad/jobs/production/vault.nomad` - Remove duplicate check  
3. `/nomad/traefik/traefik.nomad` - Fix canary config
4. `/traefik/traefik.nomad` - Fix canary config
5. All GitHub workflow files - Fix syntax errors

## Validation Commands to Re-run After Fixes:

```bash
# Test Nomad jobs
nomad job validate nomad/jobs/develop/vault.nomad
nomad job validate nomad/jobs/production/vault.nomad  
nomad job validate nomad/traefik/traefik.nomad

# Test GitHub workflows
yamllint .github/workflows/*.yml

# Test Docker compose with env vars set
docker compose -f docker-compose-owncloud.yml config
```