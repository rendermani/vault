#!/bin/bash

# Progress Watcher - File system monitor for deployment changes
# Watches for file changes and automatically updates progress

VAULT_DIR="/Users/mlautenschlager/cloudya/vault"

echo "🔍 Progress Watcher starting - monitoring file system changes..."

# Function to update progress based on file changes
handle_file_change() {
    local file="$1"
    local event="$2"
    
    case "$file" in
        */ansible-deployment.log)
            ./scripts/update-progress.sh "Ansible deployment log activity detected" "Ansible Bootstrap" 30
            ;;
        */terraform-deployment.log)
            ./scripts/update-progress.sh "Terraform deployment log activity detected" "Terraform Configuration" 45
            ;;
        */vault-deployment.log)
            ./scripts/update-progress.sh "Vault deployment activity detected" "Manual Initialization" 60
            ;;
        */traefik-deployment.log)
            ./scripts/update-progress.sh "Traefik deployment activity detected" "Deploy Traefik" 75
            ;;
        */ansible-complete.marker)
            ./scripts/update-progress.sh "Ansible bootstrap phase completed" "Terraform Configuration" 40
            ;;
        */terraform-complete.marker)
            ./scripts/update-progress.sh "Terraform configuration completed" "Enable Integration" 65
            ;;
        */vault-initialized.marker)
            ./scripts/update-progress.sh "Vault initialization completed" "Enable Integration" 70
            ;;
        */traefik-complete.marker)
            ./scripts/update-progress.sh "Traefik deployment completed - Infrastructure Ready!" "Deployment Complete" 100
            ;;
        *.nomad)
            ./scripts/update-progress.sh "Nomad job file updated: $(basename $file)"
            ;;
        *.hcl)
            if [[ "$file" == *vault* ]]; then
                ./scripts/update-progress.sh "Vault configuration updated: $(basename $file)"
            elif [[ "$file" == *nomad* ]]; then
                ./scripts/update-progress.sh "Nomad configuration updated: $(basename $file)"
            elif [[ "$file" == *consul* ]]; then
                ./scripts/update-progress.sh "Consul configuration updated: $(basename $file)"
            fi
            ;;
        *.yml|*.yaml)
            if [[ "$file" == *traefik* ]]; then
                ./scripts/update-progress.sh "Traefik configuration updated: $(basename $file)"
            elif [[ "$file" == *docker-compose* ]]; then
                ./scripts/update-progress.sh "Docker Compose configuration updated: $(basename $file)"
            fi
            ;;
    esac
}

# Check if fswatch is available (macOS)
if command -v fswatch >/dev/null 2>&1; then
    echo "Using fswatch for file monitoring..."
    fswatch -r "$VAULT_DIR" | while read file; do
        handle_file_change "$file" "modified"
    done
# Check if inotifywait is available (Linux)
elif command -v inotifywait >/dev/null 2>&1; then
    echo "Using inotifywait for file monitoring..."
    inotifywait -m -r -e create,modify,move "$VAULT_DIR" --format '%w%f %e' | while read file event; do
        handle_file_change "$file" "$event"
    done
else
    echo "⚠️  No file watching utility found (fswatch or inotifywait)"
    echo "Using polling method instead..."
    
    # Fallback to polling method
    declare -A file_timestamps
    
    while true; do
        # Check for new or modified files
        find "$VAULT_DIR" -name "*.log" -o -name "*.marker" -o -name "*.nomad" -o -name "*.hcl" -o -name "*.yml" -o -name "*.yaml" | while read file; do
            if [ -f "$file" ]; then
                current_timestamp=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
                last_timestamp=${file_timestamps[$file]:-0}
                
                if [ "$current_timestamp" != "$last_timestamp" ]; then
                    file_timestamps[$file]=$current_timestamp
                    handle_file_change "$file" "modified"
                fi
            fi
        done
        
        sleep 5  # Poll every 5 seconds
    done
fi