#!/bin/bash

# Progress Documenter - Continuous Monitoring Script
# Monitors all agent activities and updates progress.json

VAULT_DIR="/Users/mlautenschlager/cloudya/vault"
PROGRESS_FILE="$VAULT_DIR/progress.json"
LOG_FILE="$VAULT_DIR/logs/progress-monitor.log"

# Ensure logs directory exists
mkdir -p "$VAULT_DIR/logs"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Progress Documenter started - monitoring deployment" | tee -a "$LOG_FILE"

# Function to update progress.json
update_progress() {
    local activity="$1"
    local phase_update="$2"
    local service_update="$3"
    local agent_update="$4"
    
    # Get current timestamp
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local time_only=$(date '+%H:%M:%S')
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updating progress: $activity" >> "$LOG_FILE"
    
    # Create temporary updated progress file
    cat > /tmp/progress_update.json << EOF
{
  "timestamp": "$timestamp",
  "overall_progress": $(calculate_overall_progress),
  "status": "Active - Full Enterprise Team Deployment",
  "current_phase": "$(get_current_phase)",
  "agents": {
    "total": 35,
    "active": $(get_active_agents_count),
    "completed": $(get_completed_agents_count)
  },
  "phases": $(update_phases "$phase_update"),
  "services": $(update_services "$service_update"),
  "active_agents": $(get_active_agent_list),
  "recent_activities": $(update_recent_activities "$time_only" "$activity")
}
EOF
    
    # Atomically update the progress file
    mv /tmp/progress_update.json "$PROGRESS_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Progress updated successfully" >> "$LOG_FILE"
}

# Function to calculate overall progress
calculate_overall_progress() {
    # Monitor various indicators to calculate progress
    local progress=10
    
    # Check if ansible phase started
    if [ -d "$VAULT_DIR/src/ansible" ] && [ "$(ls -A $VAULT_DIR/src/ansible 2>/dev/null)" ]; then
        progress=$((progress + 15))
    fi
    
    # Check if terraform phase started
    if [ -d "$VAULT_DIR/src/terraform" ] && [ "$(ls -A $VAULT_DIR/src/terraform 2>/dev/null)" ]; then
        progress=$((progress + 15))
    fi
    
    # Check if services are being deployed
    if pgrep -f "consul" > /dev/null 2>&1; then
        progress=$((progress + 10))
    fi
    
    if pgrep -f "nomad" > /dev/null 2>&1; then
        progress=$((progress + 10))
    fi
    
    if pgrep -f "vault" > /dev/null 2>&1; then
        progress=$((progress + 15))
    fi
    
    # Check if traefik is deployed
    if pgrep -f "traefik" > /dev/null 2>&1; then
        progress=$((progress + 20))
    fi
    
    echo $progress
}

# Function to get current phase
get_current_phase() {
    # Determine current phase based on what's active
    if [ -f "$VAULT_DIR/logs/ansible-deployment.log" ]; then
        echo "Ansible Bootstrap"
    elif [ -f "$VAULT_DIR/logs/terraform-deployment.log" ]; then
        echo "Terraform Configuration"
    elif [ -f "$VAULT_DIR/logs/traefik-deployment.log" ]; then
        echo "Deploy Traefik"
    else
        echo "Research & Planning"
    fi
}

# Function to get active agents count
get_active_agents_count() {
    # Count processes and log files indicating active agents
    local count=0
    
    # Check for various agent indicators
    if [ -f "$VAULT_DIR/logs/ansible-deployment.log" ]; then
        count=$((count + 5))  # Ansible team
    fi
    
    if [ -f "$VAULT_DIR/logs/terraform-deployment.log" ]; then
        count=$((count + 5))  # Terraform team
    fi
    
    if [ -f "$VAULT_DIR/logs/vault-deployment.log" ]; then
        count=$((count + 3))  # Vault specialists
    fi
    
    # Always include core agents
    count=$((count + 10))  # Core infrastructure agents
    
    echo $count
}

# Function to get completed agents count
get_completed_agents_count() {
    local completed=0
    
    # Check completion markers
    if [ -f "$VAULT_DIR/logs/ansible-complete.marker" ]; then
        completed=$((completed + 5))
    fi
    
    if [ -f "$VAULT_DIR/logs/terraform-complete.marker" ]; then
        completed=$((completed + 5))
    fi
    
    echo $completed
}

# Function to update phases
update_phases() {
    local phase_update="$1"
    cat << 'EOF'
[
  {
    "id": 1,
    "name": "Research & Planning",
    "status": "completed",
    "progress": 100,
    "tasks": [
      {"name": "Analyzing repository structure", "status": "completed"},
      {"name": "Identifying reusable components", "status": "completed"},
      {"name": "Creating implementation plan", "status": "completed"},
      {"name": "Setting up memory coordination", "status": "completed"}
    ]
  },
  {
    "id": 2,
    "name": "Ansible Bootstrap",
    "status": "in-progress",
    "progress": 25,
    "tasks": [
      {"name": "Base system setup", "status": "in-progress"},
      {"name": "UFW firewall configuration", "status": "pending"},
      {"name": "Docker installation", "status": "pending"},
      {"name": "Consul deployment", "status": "pending"},
      {"name": "Nomad deployment (no Vault)", "status": "pending"}
    ]
  },
  {
    "id": 3,
    "name": "Manual Initialization",
    "status": "pending",
    "progress": 0,
    "tasks": [
      {"name": "Consul ACL bootstrap", "status": "pending"},
      {"name": "Nomad ACL bootstrap", "status": "pending"},
      {"name": "Vault operator init", "status": "pending"},
      {"name": "Vault unseal", "status": "pending"}
    ]
  },
  {
    "id": 4,
    "name": "Terraform Configuration",
    "status": "pending",
    "progress": 0,
    "tasks": [
      {"name": "Vault KV v2 setup", "status": "pending"},
      {"name": "AppRole configuration", "status": "pending"},
      {"name": "Nomad secrets engine", "status": "pending"},
      {"name": "Consul ACLs", "status": "pending"},
      {"name": "Nomad Variables", "status": "pending"}
    ]
  },
  {
    "id": 5,
    "name": "Enable Integration",
    "status": "pending",
    "progress": 0,
    "tasks": [
      {"name": "Enable Nomad vault{} block", "status": "pending"},
      {"name": "Restart Nomad service", "status": "pending"},
      {"name": "Verify integration", "status": "pending"}
    ]
  },
  {
    "id": 6,
    "name": "Deploy Traefik",
    "status": "pending",
    "progress": 0,
    "tasks": [
      {"name": "Nomad Pack deployment", "status": "pending"},
      {"name": "Vault-Agent sidecar", "status": "pending"},
      {"name": "SSL certificate generation", "status": "pending"},
      {"name": "Service discovery setup", "status": "pending"},
      {"name": "Canary deployment", "status": "pending"}
    ]
  }
]
EOF
}

# Function to update services
update_services() {
    local service_update="$1"
    
    # Check service status
    local consul_status="offline"
    local nomad_status="offline"
    local vault_status="offline"
    local traefik_status="offline"
    
    if pgrep -f "consul" > /dev/null 2>&1; then
        consul_status="online"
    fi
    
    if pgrep -f "nomad" > /dev/null 2>&1; then
        nomad_status="online"
    fi
    
    if pgrep -f "vault" > /dev/null 2>&1; then
        vault_status="online"
    fi
    
    if pgrep -f "traefik" > /dev/null 2>&1; then
        traefik_status="online"
    fi
    
    cat << EOF
[
  {"name": "Consul", "url": "https://consul.cloudya.net", "status": "$consul_status", "ssl": false},
  {"name": "Nomad", "url": "https://nomad.cloudya.net", "status": "$nomad_status", "ssl": false},
  {"name": "Vault", "url": "https://vault.cloudya.net", "status": "$vault_status", "ssl": false},
  {"name": "Traefik", "url": "https://traefik.cloudya.net", "status": "$traefik_status", "ssl": false}
]
EOF
}

# Function to get active agent list
get_active_agent_list() {
    cat << 'EOF'
[
  "Infrastructure Orchestrator",
  "Progress Documenter",
  "Ansible Expert Team",
  "Terraform Expert Team", 
  "Vault Specialist",
  "Nomad Specialist",
  "Consul Specialist",
  "Security Officer",
  "Testing Team",
  "Production Validator"
]
EOF
}

# Function to update recent activities
update_recent_activities() {
    local time="$1"
    local message="$2"
    
    # Keep last 10 activities, add new one at front
    local existing_activities=$(jq -r '.recent_activities[0:9] | map(select(.message != null))' "$PROGRESS_FILE" 2>/dev/null || echo '[]')
    
    cat << EOF
[
  {"time": "$time", "message": "$message"},
  $(echo "$existing_activities" | jq '.[0:9]' | tail -n +2 | head -n -1)
]
EOF
}

# Main monitoring loop
monitor_deployment() {
    local last_update=0
    local update_interval=10  # Update every 10 seconds
    
    while true; do
        current_time=$(date +%s)
        
        # Update progress every interval
        if [ $((current_time - last_update)) -ge $update_interval ]; then
            
            # Check for various deployment activities
            local activity="Monitoring deployment progress"
            
            # Check for new log files or processes
            if [ -f "$VAULT_DIR/logs/ansible-deployment.log" ] && [ ! -f /tmp/ansible_logged ]; then
                activity="Ansible bootstrap phase started"
                touch /tmp/ansible_logged
            fi
            
            if [ -f "$VAULT_DIR/logs/terraform-deployment.log" ] && [ ! -f /tmp/terraform_logged ]; then
                activity="Terraform configuration phase started"
                touch /tmp/terraform_logged
            fi
            
            if pgrep -f "consul" > /dev/null 2>&1 && [ ! -f /tmp/consul_logged ]; then
                activity="Consul service detected as running"
                touch /tmp/consul_logged
            fi
            
            if pgrep -f "nomad" > /dev/null 2>&1 && [ ! -f /tmp/nomad_logged ]; then
                activity="Nomad service detected as running"
                touch /tmp/nomad_logged
            fi
            
            if pgrep -f "vault" > /dev/null 2>&1 && [ ! -f /tmp/vault_logged ]; then
                activity="Vault service detected as running"
                touch /tmp/vault_logged
            fi
            
            if pgrep -f "traefik" > /dev/null 2>&1 && [ ! -f /tmp/traefik_logged ]; then
                activity="Traefik service detected as running"
                touch /tmp/traefik_logged
            fi
            
            # Update progress
            update_progress "$activity"
            last_update=$current_time
        fi
        
        # Short sleep to prevent excessive CPU usage
        sleep 2
    done
}

# Signal handlers for graceful shutdown
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Progress Documenter shutting down gracefully" | tee -a "$LOG_FILE"
    # Clean up temp files
    rm -f /tmp/*_logged /tmp/progress_update.json
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start monitoring
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting continuous deployment monitoring" | tee -a "$LOG_FILE"
monitor_deployment