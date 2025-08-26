#!/usr/bin/env bash
# Traefik Nomad Pack Validation and Testing Script
# Comprehensive validation of pack structure and configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_NAME="traefik"

# Color coding
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Track validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

error() {
    log_error "$*"
    ((VALIDATION_ERRORS++))
}

warn() {
    log_warn "$*"  
    ((VALIDATION_WARNINGS++))
}

# Validate pack structure
validate_pack_structure() {
    log_info "Validating pack structure..."
    
    local required_files=(
        "metadata.hcl"
        "variables.hcl"
        "templates/traefik.nomad.tpl"
        "README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            error "Required file missing: $file"
        else
            log_success "Found: $file"
        fi
    done
    
    # Check for optional but recommended files
    local optional_files=(
        "deploy.sh"
        "values/production.hcl"
        "values/staging.hcl"
        "values/development.hcl"
        "templates/vault-policy.hcl.tpl"
        "templates/vault-agent.hcl.tpl"
    )
    
    for file in "${optional_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            warn "Optional file missing: $file"
        else
            log_success "Found: $file"
        fi
    done
}

# Validate metadata.hcl syntax
validate_metadata() {
    log_info "Validating metadata.hcl..."
    
    local metadata_file="$SCRIPT_DIR/metadata.hcl"
    
    # Check for required blocks
    if ! grep -q "^app {" "$metadata_file"; then
        error "metadata.hcl missing 'app' block"
    fi
    
    if ! grep -q "^pack {" "$metadata_file"; then
        error "metadata.hcl missing 'pack' block"
    fi
    
    # Validate pack name
    if ! grep -q 'name.*=.*"traefik"' "$metadata_file"; then
        error "Pack name should be 'traefik'"
    fi
    
    # Check version format
    if ! grep -q 'version.*=.*"[0-9]\+\.[0-9]\+\.[0-9]\+"' "$metadata_file"; then
        warn "Version should follow semantic versioning (x.y.z)"
    fi
    
    log_success "Metadata validation completed"
}

# Validate variables.hcl syntax and completeness
validate_variables() {
    log_info "Validating variables.hcl..."
    
    local vars_file="$SCRIPT_DIR/variables.hcl"
    
    # Required variables for production deployment
    local required_vars=(
        "traefik_version"
        "vault_integration"
        "acme_enabled"
        "consul_integration"
        "count"
        "resources"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "variable \"$var\"" "$vars_file"; then
            error "Required variable missing: $var"
        else
            log_success "Found variable: $var"
        fi
    done
    
    # Check for validation blocks where appropriate
    if ! grep -A5 'variable "log_level"' "$vars_file" | grep -q "validation {"; then
        warn "log_level variable should include validation block"
    fi
    
    if ! grep -A5 'variable "environment"' "$vars_file" | grep -q "validation {"; then
        warn "environment variable should include validation block"
    fi
    
    log_success "Variables validation completed"
}

# Validate template syntax
validate_template_syntax() {
    log_info "Validating template syntax..."
    
    local template_file="$SCRIPT_DIR/templates/traefik.nomad.tpl"
    
    # Check for proper template syntax
    if ! grep -q "job \"traefik\"" "$template_file"; then
        error "Template should define job 'traefik'"
    fi
    
    # Check for template variable usage
    if ! grep -q "\[\[.*traefik\." "$template_file"; then
        error "Template should use traefik namespace variables"
    fi
    
    # Check for required job sections
    local required_sections=(
        "group \"traefik\""
        "task \"traefik\""
        "driver = \"docker\""
        "network {"
        "service {"
    )
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "$section" "$template_file"; then
            error "Template missing required section: $section"
        fi
    done
    
    # Check for Vault integration blocks
    if grep -q "vault_agent_enabled" "$template_file"; then
        if ! grep -q "task \"vault-agent\"" "$template_file"; then
            error "vault_agent_enabled is used but vault-agent task not found"
        fi
    fi
    
    log_success "Template syntax validation completed"
}

# Test pack rendering
test_pack_rendering() {
    log_info "Testing pack rendering..."
    
    cd "$SCRIPT_DIR"
    
    # Test with different environments
    local environments=("development" "staging" "production")
    
    for env in "${environments[@]}"; do
        log_info "Testing $env environment..."
        
        local values_file="values/$env.hcl"
        local render_cmd="nomad-pack render ."
        
        if [[ -f "$values_file" ]]; then
            render_cmd+=" -f $values_file"
        fi
        
        if ! $render_cmd > "/tmp/traefik-${env}.nomad" 2>/dev/null; then
            error "Pack rendering failed for $env environment"
        else
            log_success "Pack renders successfully for $env"
            
            # Validate generated Nomad job
            if command -v nomad &> /dev/null; then
                if ! nomad job validate "/tmp/traefik-${env}.nomad" &>/dev/null; then
                    error "Generated Nomad job invalid for $env"
                else
                    log_success "Generated Nomad job valid for $env"
                fi
            else
                warn "nomad CLI not available - skipping job validation"
            fi
        fi
        
        # Clean up
        rm -f "/tmp/traefik-${env}.nomad"
    done
}

# Validate Vault integration
validate_vault_integration() {
    log_info "Validating Vault integration..."
    
    local policy_file="$SCRIPT_DIR/templates/vault-policy.hcl.tpl"
    local agent_config="$SCRIPT_DIR/templates/vault-agent.hcl.tpl"
    
    if [[ -f "$policy_file" ]]; then
        # Check for required policy paths
        local required_paths=(
            "kv/data/cloudflare"
            "kv/data/traefik/dashboard"
            "auth/token/renew-self"
        )
        
        for path in "${required_paths[@]}"; do
            if ! grep -q "\"$path\"" "$policy_file"; then
                error "Vault policy missing required path: $path"
            fi
        done
        
        log_success "Vault policy validation completed"
    else
        warn "Vault policy template not found"
    fi
    
    if [[ -f "$agent_config" ]]; then
        # Check for required Vault Agent sections
        if ! grep -q "auto_auth {" "$agent_config"; then
            error "Vault Agent config missing auto_auth block"
        fi
        
        if ! grep -q "template {" "$agent_config"; then
            error "Vault Agent config missing template blocks"
        fi
        
        log_success "Vault Agent config validation completed"
    else
        warn "Vault Agent config template not found"
    fi
}

# Validate security configuration
validate_security_config() {
    log_info "Validating security configuration..."
    
    local template_file="$SCRIPT_DIR/templates/traefik.nomad.tpl"
    local vars_file="$SCRIPT_DIR/variables.hcl"
    
    # Check for security headers
    if ! grep -q "secure-headers" "$template_file"; then
        error "Security headers middleware not configured"
    fi
    
    # Check for rate limiting
    if ! grep -q "rate-limit" "$template_file"; then
        error "Rate limiting middleware not configured"
    fi
    
    # Check TLS configuration
    if ! grep -q "tls_options" "$vars_file"; then
        error "TLS options not configured"
    fi
    
    # Check for strong TLS settings
    if ! grep -q "VersionTLS12" "$vars_file"; then
        error "Minimum TLS version should be 1.2"
    fi
    
    # Check for dashboard auth in production
    local prod_values="$SCRIPT_DIR/values/production.hcl"
    if [[ -f "$prod_values" ]]; then
        if ! grep -q "dashboard_auth.*=.*true" "$prod_values"; then
            error "Dashboard authentication should be enabled in production"
        fi
        
        if grep -q "api_insecure.*=.*true" "$prod_values"; then
            error "Insecure API should not be enabled in production"
        fi
    fi
    
    log_success "Security configuration validation completed"
}

# Test deployment script
validate_deployment_script() {
    log_info "Validating deployment script..."
    
    local deploy_script="$SCRIPT_DIR/deploy.sh"
    
    if [[ -f "$deploy_script" ]]; then
        # Check if script is executable
        if [[ ! -x "$deploy_script" ]]; then
            error "Deploy script is not executable"
        fi
        
        # Check for required functions
        local required_functions=(
            "verify_prerequisites"
            "setup_vault_secrets"
            "validate_pack"
            "deploy_pack"
        )
        
        for func in "${required_functions[@]}"; do
            if ! grep -q "^$func()" "$deploy_script"; then
                error "Deploy script missing function: $func"
            fi
        done
        
        # Test script syntax
        if ! bash -n "$deploy_script"; then
            error "Deploy script has syntax errors"
        else
            log_success "Deploy script syntax is valid"
        fi
        
        log_success "Deploy script validation completed"
    else
        warn "Deploy script not found"
    fi
}

# Check documentation
validate_documentation() {
    log_info "Validating documentation..."
    
    local readme="$SCRIPT_DIR/README.md"
    
    if [[ -f "$readme" ]]; then
        # Check for required sections
        local required_sections=(
            "# Traefik Nomad Pack"
            "## Features"
            "## Quick Start"
            "## Configuration"
            "## Security"
        )
        
        for section in "${required_sections[@]}"; do
            if ! grep -q "$section" "$readme"; then
                warn "README missing section: $section"
            fi
        done
        
        # Check for deployment instructions
        if ! grep -q "deploy.sh" "$readme"; then
            warn "README should include deployment instructions"
        fi
        
        log_success "Documentation validation completed"
    else
        error "README.md not found"
    fi
}

# Run comprehensive validation
run_validation() {
    log_info "Starting comprehensive pack validation..."
    
    validate_pack_structure
    validate_metadata
    validate_variables
    validate_template_syntax
    test_pack_rendering
    validate_vault_integration
    validate_security_config
    validate_deployment_script
    validate_documentation
    
    # Summary
    echo
    log_info "=== Validation Summary ==="
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "✅ No errors found!"
    else
        log_error "❌ $VALIDATION_ERRORS errors found"
    fi
    
    if [[ $VALIDATION_WARNINGS -eq 0 ]]; then
        log_success "✅ No warnings"
    else
        log_warn "⚠️  $VALIDATION_WARNINGS warnings found"
    fi
    
    echo
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "Pack is ready for deployment! 🚀"
        return 0
    else
        log_error "Please fix errors before deployment"
        return 1
    fi
}

# Main execution
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help"
        echo "  --structure    Validate pack structure only"
        echo "  --syntax       Validate syntax only"  
        echo "  --render       Test rendering only"
        echo "  --security     Validate security config only"
        exit 0
        ;;
    "--structure")
        validate_pack_structure
        ;;
    "--syntax")
        validate_metadata
        validate_variables
        validate_template_syntax
        ;;
    "--render")
        test_pack_rendering
        ;;
    "--security")
        validate_security_config
        ;;
    *)
        run_validation
        ;;
esac