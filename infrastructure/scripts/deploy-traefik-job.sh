#!/bin/bash
# Idempotent script to deploy Traefik job to Nomad
# Can be run multiple times safely
set -euo pipefail

# Configuration variables - can be overridden by environment
ENVIRONMENT="${ENVIRONMENT:-production}"
NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-default}"
NOMAD_REGION="${NOMAD_REGION:-global}"
TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.2.3}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DEPLOY="${FORCE_DEPLOY:-false}"
JOB_FILE="${JOB_FILE:-}"
ACME_EMAIL="${ACME_EMAIL:-admin@cloudya.net}"
DOMAIN_NAME="${DOMAIN_NAME:-cloudya.net}"
DASHBOARD_AUTH="${DASHBOARD_AUTH:-}"
LETS_ENCRYPT_STAGING="${LETS_ENCRYPT_STAGING:-false}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JOBS_DIR="${PROJECT_ROOT}/nomad/traefik"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/traefik-deploy.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/traefik-deploy.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/traefik-deploy.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/traefik-deploy.log"
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Traefik job to Nomad cluster"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (develop|staging|production) [default: production]"
    echo "  -n, --namespace NS        Nomad namespace [default: default]"
    echo "  -r, --region REGION       Nomad region [default: global]"
    echo "  -v, --version VERSION     Traefik version [default: v3.2.3]"
    echo "  -f, --file FILE          Custom job file path"
    echo "  --email EMAIL            ACME email for Let's Encrypt [default: admin@cloudya.net]"
    echo "  --domain DOMAIN          Primary domain name [default: cloudya.net]"
    echo "  --auth AUTH              Dashboard auth (user:hashedpass)"
    echo "  --staging                Use Let's Encrypt staging environment"
    echo "  -d, --dry-run            Show what would be deployed without executing"
    echo "  --force                  Force deployment even if job is running"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment production"
    echo "  $0 --environment staging --staging --dry-run"
    echo "  $0 --email admin@example.com --domain example.com"
    echo "  $0 --auth 'admin:$2y$10$...' --force"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -n|--namespace)
                NOMAD_NAMESPACE="$2"
                shift 2
                ;;
            -r|--region)
                NOMAD_REGION="$2"
                shift 2
                ;;
            -v|--version)
                TRAEFIK_VERSION="$2"
                shift 2
                ;;
            -f|--file)
                JOB_FILE="$2"
                shift 2
                ;;
            --email)
                ACME_EMAIL="$2"
                shift 2
                ;;
            --domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --auth)
                DASHBOARD_AUTH="$2"
                shift 2
                ;;
            --staging)
                LETS_ENCRYPT_STAGING=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        develop|staging|production)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid environments: develop, staging, production"
            exit 1
            ;;
    esac
}

# Setup directories
setup_directories() {
    mkdir -p "$LOGS_DIR"
    mkdir -p "${PROJECT_ROOT}/tmp"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Nomad CLI is available
    if ! command -v nomad &> /dev/null; then
        log_error "Nomad CLI not found. Please install Nomad."
        exit 1
    fi
    
    # Check Nomad connection
    if ! nomad node status &> /dev/null; then
        log_error "Cannot connect to Nomad cluster. Is Nomad agent running?"
        log_error "Make sure NOMAD_ADDR is set correctly or Nomad agent is accessible"
        exit 1
    fi
    
    # Validate email format
    if [[ ! "$ACME_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: $ACME_EMAIL"
        exit 1
    fi
    
    # Check if htpasswd is available for dashboard auth generation
    if [[ -z "$DASHBOARD_AUTH" ]] && command -v htpasswd &> /dev/null; then
        log_info "htpasswd is available for generating dashboard authentication"
    fi
    
    log_success "Prerequisites check passed"
}

# Generate dashboard authentication if not provided
generate_dashboard_auth() {
    if [[ -n "$DASHBOARD_AUTH" ]]; then
        log_info "Using provided dashboard authentication"
        return 0
    fi
    
    log_info "Generating dashboard authentication..."
    
    if command -v htpasswd &> /dev/null; then
        local password
        password=$(openssl rand -base64 12)
        DASHBOARD_AUTH="admin:$(htpasswd -nbB admin "$password" | cut -d: -f2)"
        
        log_warning "Generated dashboard credentials:"
        log_warning "  Username: admin"
        log_warning "  Password: $password"
        log_warning "  Save these credentials securely!"
    else
        # Fallback to bcrypt hash of 'admin123'
        DASHBOARD_AUTH="admin:\$2y\$10\$9L.K4cPdl8rwLgiYBNO9H.7L9X9RNzycQP7gFPNsuAcLqsXoLyoO2"
        log_warning "Using default dashboard credentials (change immediately!):"
        log_warning "  Username: admin"
        log_warning "  Password: admin123"
    fi
}

# Determine job file path
determine_job_file() {
    if [[ -n "$JOB_FILE" ]]; then
        if [[ ! -f "$JOB_FILE" ]]; then
            log_error "Custom job file not found: $JOB_FILE"
            exit 1
        fi
        log_info "Using custom job file: $JOB_FILE"
    else
        # Look for environment-specific job file first
        local env_job_file="${JOBS_DIR}/traefik-${ENVIRONMENT}.nomad"
        if [[ -f "$env_job_file" ]]; then
            JOB_FILE="$env_job_file"
        else
            JOB_FILE="${JOBS_DIR}/traefik.nomad"
        fi
        
        if [[ ! -f "$JOB_FILE" ]]; then
            log_error "Default job file not found: $JOB_FILE"
            log_error "Available job files:"
            find "$JOBS_DIR" -name "*.nomad" | sort || echo "No job files found in $JOBS_DIR"
            exit 1
        fi
        log_info "Using job file: $JOB_FILE"
    fi
}

# Get current job status
get_job_status() {
    local job_name="traefik"
    local job_status
    
    if nomad job status "$job_name" &> /dev/null; then
        job_status=$(nomad job status -short "$job_name" | grep "Status" | awk '{print $3}' || echo "unknown")
        echo "$job_status"
    else
        echo "not_found"
    fi
}

# Check if deployment should proceed
should_deploy() {
    local current_status
    current_status=$(get_job_status)
    
    log_info "Current job status: $current_status"
    
    case "$current_status" in
        "not_found")
            log_info "Job not found, proceeding with deployment"
            return 0
            ;;
        "running")
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                log_warning "Job is running but force deployment requested"
                return 0
            else
                log_warning "Job is already running. Use --force to redeploy"
                return 1
            fi
            ;;
        "pending"|"dead"|"failed")
            log_info "Job is in $current_status state, proceeding with deployment"
            return 0
            ;;
        *)
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                log_info "Forcing deployment despite status: $current_status"
                return 0
            else
                log_warning "Job status is $current_status. Use --force to override"
                return 1
            fi
            ;;
    esac
}

# Prepare host volumes
prepare_host_volumes() {
    log_info "Preparing host volumes for Traefik..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would prepare host volumes"
        return 0
    fi
    
    local setup_script="${PROJECT_ROOT}/tmp/setup-traefik-volumes-$(date +%s).sh"
    
    cat > "$setup_script" <<'EOF'
#!/bin/bash
set -e

echo "Setting up Traefik host volumes..."

# Create volume directories
mkdir -p /opt/nomad/volumes/traefik-certs
mkdir -p /opt/nomad/volumes/traefik-config/dynamic

# Set secure permissions
chmod 700 /opt/nomad/volumes/traefik-certs
chmod 755 /opt/nomad/volumes/traefik-config
chmod 755 /opt/nomad/volumes/traefik-config/dynamic

# Initialize ACME storage if it doesn't exist
if [ ! -f /opt/nomad/volumes/traefik-certs/acme.json ]; then
    echo '{}' > /opt/nomad/volumes/traefik-certs/acme.json
    chmod 600 /opt/nomad/volumes/traefik-certs/acme.json
    echo "Created new ACME storage file"
else
    echo "ACME storage already exists, fixing permissions"
    chmod 600 /opt/nomad/volumes/traefik-certs/acme.json
fi

# Create initial dynamic config if it doesn't exist
if [ ! -f /opt/nomad/volumes/traefik-config/dynamic/routes.yml ]; then
    cat > /opt/nomad/volumes/traefik-config/dynamic/routes.yml <<EOL
http:
  routers: {}
  services: {}
  middlewares: {}
tls:
  stores: {}
EOL
    echo "Created initial dynamic configuration"
fi

echo "Volume setup complete"
ls -la /opt/nomad/volumes/traefik-*
EOF
    
    chmod +x "$setup_script"
    
    # Execute setup script
    if sudo bash "$setup_script"; then
        log_success "Host volumes prepared successfully"
    else
        log_error "Failed to prepare host volumes"
        exit 1
    fi
    
    rm -f "$setup_script"
}

# Create dynamic configuration template
create_dynamic_config() {
    log_info "Creating dynamic configuration template..."
    
    local temp_config="${PROJECT_ROOT}/tmp/traefik-dynamic-config-$(date +%s).yml"
    
    # Set ACME server based on staging flag
    local acme_server
    if [[ "$LETS_ENCRYPT_STAGING" == "true" ]]; then
        acme_server="https://acme-staging-v02.api.letsencrypt.org/directory"
        log_warning "Using Let's Encrypt STAGING environment"
    else
        acme_server="https://acme-v02.api.letsencrypt.org/directory"
        log_info "Using Let's Encrypt PRODUCTION environment"
    fi
    
    cat > "$temp_config" <<EOF
http:
  routers:
    dashboard:
      rule: "Host(\`traefik.${DOMAIN_NAME}\`)"
      service: api@internal
      middlewares:
        - auth-dashboard
        - security-headers
      tls:
        certResolver: letsencrypt
    
    vault:
      rule: "Host(\`vault.${DOMAIN_NAME}\`)"
      service: vault-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
    
    nomad:
      rule: "Host(\`nomad.${DOMAIN_NAME}\`)"
      service: nomad-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

  services:
    vault-service:
      loadBalancer:
        servers:
          - url: "http://localhost:8200"
    
    nomad-service:
      loadBalancer:
        servers:
          - url: "http://localhost:4646"

  middlewares:
    auth-dashboard:
      basicAuth:
        users:
          - "${DASHBOARD_AUTH}"
    
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        customRequestHeaders:
          X-Forwarded-Proto: "https"

tls:
  stores:
    default:
      defaultGeneratedCert:
        resolver: letsencrypt
        domain:
          main: "${DOMAIN_NAME}"
          sans:
            - "*.${DOMAIN_NAME}"
EOF
    
    # Store template for later use
    echo "$temp_config"
}

# Validate job file
validate_job() {
    log_info "Validating job file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate: $JOB_FILE"
        return 0
    fi
    
    # Create temporary job file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/traefik-${ENVIRONMENT}-$(date +%s).nomad"
    
    # Export environment variables for substitution
    export ENVIRONMENT TRAEFIK_VERSION ACME_EMAIL DOMAIN_NAME DASHBOARD_AUTH
    export LETS_ENCRYPT_SERVER
    if [[ "$LETS_ENCRYPT_STAGING" == "true" ]]; then
        LETS_ENCRYPT_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    else
        LETS_ENCRYPT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
    fi
    
    # Substitute variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    if ! nomad job validate "$temp_job"; then
        log_error "Job validation failed for $JOB_FILE"
        log_error "Check the temporary file for issues: $temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Job validation passed"
}

# Plan deployment
plan_deployment() {
    log_info "Planning deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would plan deployment of: $JOB_FILE"
        return 0
    fi
    
    # Create temporary job file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/traefik-${ENVIRONMENT}-plan-$(date +%s).nomad"
    
    # Export environment variables for substitution
    export ENVIRONMENT TRAEFIK_VERSION ACME_EMAIL DOMAIN_NAME DASHBOARD_AUTH
    export LETS_ENCRYPT_SERVER
    if [[ "$LETS_ENCRYPT_STAGING" == "true" ]]; then
        LETS_ENCRYPT_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    else
        LETS_ENCRYPT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
    fi
    
    # Substitute variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    log_info "Planning with namespace: $NOMAD_NAMESPACE, region: $NOMAD_REGION"
    
    if ! nomad job plan -namespace="$NOMAD_NAMESPACE" -region="$NOMAD_REGION" "$temp_job"; then
        log_error "Deployment planning failed"
        rm -f "$temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Deployment planning completed"
}

# Deploy Traefik job
deploy_traefik() {
    log_info "Deploying Traefik to $ENVIRONMENT environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy: $JOB_FILE"
        return 0
    fi
    
    # Create temporary job file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/traefik-${ENVIRONMENT}-deploy-$(date +%s).nomad"
    
    # Export environment variables for substitution
    export ENVIRONMENT TRAEFIK_VERSION ACME_EMAIL DOMAIN_NAME DASHBOARD_AUTH
    export LETS_ENCRYPT_SERVER
    if [[ "$LETS_ENCRYPT_STAGING" == "true" ]]; then
        LETS_ENCRYPT_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    else
        LETS_ENCRYPT_SERVER="https://acme-v02.api.letsencrypt.org/directory"
    fi
    
    # Substitute variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    log_info "Deploying with namespace: $NOMAD_NAMESPACE, region: $NOMAD_REGION"
    
    if ! nomad job run -namespace="$NOMAD_NAMESPACE" -region="$NOMAD_REGION" "$temp_job"; then
        log_error "Deployment failed"
        rm -f "$temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Traefik deployed successfully"
}

# Wait for deployment to be healthy
wait_for_healthy() {
    local job_name="traefik"
    local timeout=300  # 5 minutes
    local interval=15
    local elapsed=0
    
    log_info "Waiting for deployment to be healthy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for deployment to be healthy"
        return 0
    fi
    
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep "Status" | awk '{print $3}' || echo "unknown")
        
        if [ "$status" = "running" ]; then
            # Check if all allocations are healthy
            local healthy_allocs failed_allocs
            healthy_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep -c "running" || echo "0")
            failed_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep -c "failed" || echo "0")
            
            if [ "$healthy_allocs" -gt 0 ] && [ "$failed_allocs" -eq 0 ]; then
                log_success "Deployment is healthy ($healthy_allocs running allocations)"
                return 0
            fi
            
            log_info "Deployment status: $status ($healthy_allocs running, $failed_allocs failed)"
        else
            log_info "Deployment status: $status (waiting... ${elapsed}s/${timeout}s)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Deployment did not become healthy within $timeout seconds"
    
    # Show detailed status for troubleshooting
    log_info "Current job status:"
    nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" || true
    
    exit 1
}

# Test Traefik connectivity
test_traefik() {
    log_info "Testing Traefik connectivity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test Traefik connectivity"
        return 0
    fi
    
    local timeout=120
    local interval=5
    local elapsed=0
    
    # Test HTTP endpoint
    while [ $elapsed -lt $timeout ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ping | grep -q "200"; then
            log_success "Traefik HTTP endpoint is responding"
            break
        fi
        
        log_info "Waiting for Traefik HTTP endpoint... (${elapsed}s/${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_warning "Traefik HTTP endpoint did not respond within $timeout seconds"
    fi
    
    # Test HTTPS endpoint (may fail initially due to certificate provisioning)
    log_info "Testing HTTPS endpoint (certificates may still be provisioning)..."
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:443/ping | grep -q "200"; then
        log_success "Traefik HTTPS endpoint is responding"
    else
        log_warning "Traefik HTTPS endpoint not yet ready (normal during initial certificate provisioning)"
    fi
}

# Post-deployment verification
verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify deployment"
        return 0
    fi
    
    local job_name="traefik"
    
    # Check job status
    if ! nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" &> /dev/null; then
        log_error "Job $job_name not found in namespace $NOMAD_NAMESPACE"
        return 1
    fi
    
    log_success "Job is deployed and running"
    
    # Check file volumes
    if [ -d "/opt/nomad/volumes/traefik-certs" ] && [ -f "/opt/nomad/volumes/traefik-certs/acme.json" ]; then
        log_success "Certificate storage is properly configured"
    else
        log_warning "Certificate storage may not be properly configured"
    fi
    
    # Show service information
    log_info "Traefik service information:"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Version: $TRAEFIK_VERSION"
    log_info "  Domain: $DOMAIN_NAME"
    log_info "  ACME Email: $ACME_EMAIL"
    log_info "  Let's Encrypt: $([ "$LETS_ENCRYPT_STAGING" == "true" ] && echo "STAGING" || echo "PRODUCTION")"
    log_info "  Dashboard: https://traefik.${DOMAIN_NAME}"
    log_info "  Namespace: $NOMAD_NAMESPACE"
    log_info "  Region: $NOMAD_REGION"
    
    log_success "Deployment verification completed"
}

# Generate post-deployment instructions
generate_instructions() {
    local instructions_file="${LOGS_DIR}/traefik-deployment-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).md"
    
    log_info "Generating post-deployment instructions..."
    
    cat > "$instructions_file" <<EOF
# Traefik Deployment Instructions - $ENVIRONMENT

**Generated:** $(date)  
**Environment:** $ENVIRONMENT  
**Version:** $TRAEFIK_VERSION  
**Domain:** $DOMAIN_NAME  
**ACME Email:** $ACME_EMAIL  
**Let's Encrypt:** $([ "$LETS_ENCRYPT_STAGING" == "true" ] && echo "STAGING" || echo "PRODUCTION")  
**Nomad Namespace:** $NOMAD_NAMESPACE  
**Nomad Region:** $NOMAD_REGION  

## Quick Status Check

\`\`\`bash
# Check job status
nomad job status -namespace=$NOMAD_NAMESPACE traefik

# Check Traefik endpoints
curl http://localhost:80/ping
curl -k https://localhost:443/ping

# Check certificate storage
sudo ls -la /opt/nomad/volumes/traefik-certs/
sudo cat /opt/nomad/volumes/traefik-certs/acme.json | jq
\`\`\`

## Access Points

- **Dashboard**: https://traefik.${DOMAIN_NAME}
- **Vault**: https://vault.${DOMAIN_NAME}
- **Nomad**: https://nomad.${DOMAIN_NAME}
- **HTTP**: http://localhost:80 (redirects to HTTPS)
- **HTTPS**: https://localhost:443
- **Metrics**: http://localhost:8082/metrics

## Dashboard Authentication

EOF
    
    if [[ -n "$DASHBOARD_AUTH" ]]; then
        if [[ "$DASHBOARD_AUTH" == *"admin123"* ]]; then
            cat >> "$instructions_file" <<EOF
⚠️ **CHANGE DEFAULT CREDENTIALS IMMEDIATELY**

Default credentials (CHANGE THESE):
- **Username**: admin
- **Password**: admin123

To generate new credentials:
\`\`\`bash
# Generate new password hash
htpasswd -nbB admin YOUR_NEW_PASSWORD

# Update the job file with the new hash
# Redeploy Traefik with --force flag
\`\`\`
EOF
        else
            cat >> "$instructions_file" <<EOF
Dashboard authentication is configured.  
See deployment logs for credentials if auto-generated.
EOF
        fi
    fi
    
    cat >> "$instructions_file" <<EOF

## Certificate Management

### Let's Encrypt Status
Current mode: $([ "$LETS_ENCRYPT_STAGING" == "true" ] && echo "**STAGING** (test certificates)" || echo "**PRODUCTION** (trusted certificates)")

### Certificate Files
- **ACME Storage**: /opt/nomad/volumes/traefik-certs/acme.json
- **Dynamic Config**: /opt/nomad/volumes/traefik-config/dynamic/

### Certificate Troubleshooting
\`\`\`bash
# Check ACME challenges
sudo tail -f /var/log/nomad/nomad.log | grep -i acme

# View certificate details
echo | openssl s_client -servername traefik.$DOMAIN_NAME -connect localhost:443 2>/dev/null | openssl x509 -noout -text

# Check certificate expiry
echo | openssl s_client -servername traefik.$DOMAIN_NAME -connect localhost:443 2>/dev/null | openssl x509 -noout -dates
\`\`\`

## Adding New Routes

To add new services to Traefik, update the dynamic configuration:

\`\`\`bash
# Edit dynamic configuration
sudo vim /opt/nomad/volumes/traefik-config/dynamic/routes.yml

# Traefik will automatically reload the configuration
\`\`\`

Example service addition:
\`\`\`yaml
http:
  routers:
    my-service:
      rule: "Host(\`myservice.$DOMAIN_NAME\`)"
      service: my-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
  
  services:
    my-service:
      loadBalancer:
        servers:
          - url: "http://localhost:8080"
\`\`\`

## Monitoring & Troubleshooting

### View Logs
\`\`\`bash
# Nomad job logs
nomad alloc logs -namespace=$NOMAD_NAMESPACE \$(nomad job allocs -namespace=$NOMAD_NAMESPACE traefik | grep running | head -1 | awk '{print \$1}')

# Follow logs
nomad alloc logs -namespace=$NOMAD_NAMESPACE -f \$(nomad job allocs -namespace=$NOMAD_NAMESPACE traefik | grep running | head -1 | awk '{print \$1}')
\`\`\`

### Common Issues

1. **Certificate provisioning failures**
   - Check DNS resolution for your domain
   - Verify port 80/443 are accessible from internet
   - Check ACME challenge logs
   - Ensure domain ownership

2. **Service not accessible**
   - Verify backend service is running
   - Check service discovery in Consul
   - Validate routing rules

3. **Dashboard not accessible**
   - Verify authentication credentials
   - Check DNS resolution for traefik.$DOMAIN_NAME
   - Ensure certificate is valid

### Health Checks
\`\`\`bash
# Traefik ping endpoint
curl http://localhost:80/ping

# Prometheus metrics
curl http://localhost:8082/metrics

# Service status
nomad job status -namespace=$NOMAD_NAMESPACE traefik
\`\`\`

## Security Considerations

$(if [ "$ENVIRONMENT" == "production" ]; then
    echo "### PRODUCTION SECURITY CHECKLIST"
    echo ""
    echo "- [ ] Default dashboard credentials changed"
    echo "- [ ] TLS certificates from trusted CA (not staging)"
    echo "- [ ] Security headers properly configured"
    echo "- [ ] Access logs enabled and monitored"
    echo "- [ ] Rate limiting configured (if needed)"
    echo "- [ ] Firewall rules properly configured"
    echo "- [ ] Regular certificate renewal tested"
    echo "- [ ] Backup and recovery procedures tested"
elif [ "$ENVIRONMENT" == "staging" ]; then
    echo "### STAGING SECURITY NOTES"
    echo ""
    echo "- [ ] Using staging Let's Encrypt certificates (not trusted)"
    echo "- [ ] Dashboard authentication configured"
    echo "- [ ] Testing certificate renewal process"
    echo "- [ ] Security headers validation"
else
    echo "### DEVELOPMENT NOTES"
    echo ""
    echo "- Using development configuration"
    echo "- May use self-signed or staging certificates"
    echo "- Security settings may be relaxed for development"
fi)

## Backup and Recovery

### Backup Important Files
\`\`\`bash
# Backup ACME certificates
sudo cp -r /opt/nomad/volumes/traefik-certs /backup/traefik-certs-\$(date +%Y%m%d)

# Backup dynamic configuration
sudo cp -r /opt/nomad/volumes/traefik-config /backup/traefik-config-\$(date +%Y%m%d)
\`\`\`

### Recovery
\`\`\`bash
# Restore certificates (if needed)
sudo cp -r /backup/traefik-certs-YYYYMMDD /opt/nomad/volumes/traefik-certs

# Restart Traefik
nomad job restart -namespace=$NOMAD_NAMESPACE traefik
\`\`\`

---
*Generated by Traefik deployment script*
EOF
    
    log_success "Instructions written to: $instructions_file"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "=== POST-DEPLOYMENT SUMMARY ==="
        cat "$instructions_file"
    fi
}

# Cleanup on failure
cleanup_on_failure() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warning "Deployment failed, checking if cleanup is needed..."
    
    local job_name="traefik"
    
    if nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" &> /dev/null; then
        local status
        status=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep "Status" | awk '{print $3}')
        
        if [[ "$status" == "failed" || "$status" == "dead" ]]; then
            log_info "Stopping failed job..."
            nomad job stop -namespace="$NOMAD_NAMESPACE" "$job_name" || true
        fi
    fi
    
    # Clean up temporary files
    rm -f "${PROJECT_ROOT}/tmp/traefik-${ENVIRONMENT}"-*.nomad
    rm -f "${PROJECT_ROOT}/tmp/traefik-dynamic-config"-*.yml
}

# Main deployment function
main() {
    log_info "=== Traefik Deployment Script ==="
    log_info "Environment: $ENVIRONMENT"
    log_info "Namespace: $NOMAD_NAMESPACE"
    log_info "Region: $NOMAD_REGION"
    log_info "Version: $TRAEFIK_VERSION"
    log_info "Domain: $DOMAIN_NAME"
    log_info "ACME Email: $ACME_EMAIL"
    log_info "Let's Encrypt: $([ "$LETS_ENCRYPT_STAGING" == "true" ] && echo "STAGING" || echo "PRODUCTION")"
    log_info "Dry Run: $DRY_RUN"
    log_info "Force Deploy: $FORCE_DEPLOY"
    
    # Setup error handling
    trap cleanup_on_failure ERR
    
    # Execute deployment steps
    setup_directories
    check_prerequisites
    validate_environment
    generate_dashboard_auth
    determine_job_file
    
    if ! should_deploy; then
        log_info "Skipping deployment based on current status"
        exit 0
    fi
    
    prepare_host_volumes
    validate_job
    plan_deployment
    deploy_traefik
    wait_for_healthy
    test_traefik
    verify_deployment
    generate_instructions
    
    # Remove error trap
    trap - ERR
    
    log_success "=== Traefik deployment completed successfully! ==="
    
    if [[ "$LETS_ENCRYPT_STAGING" == "true" ]]; then
        echo ""
        log_warning "🔒 STAGING CERTIFICATES DEPLOYED"
        log_warning "Remember to switch to production Let's Encrypt when ready:"
        log_warning "$0 --environment $ENVIRONMENT --force"
    fi
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        echo ""
        log_warning "🔐 PRODUCTION DEPLOYMENT COMPLETED"
        log_warning "CRITICAL NEXT STEPS:"
        log_warning "1. Change default dashboard credentials if using defaults"
        log_warning "2. Verify DNS points to this server"
        log_warning "3. Test certificate provisioning"
        log_warning "4. Configure monitoring and alerting"
        log_warning "5. Set up automated backups"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main "$@"