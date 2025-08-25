#!/bin/bash

# SSH Security Fixes for GitHub Actions Workflows
# Applies critical security fixes to all deployment workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔒 Applying SSH Security Fixes to GitHub Actions Workflows"
echo "========================================================="

# Function to fix SSH security in workflow files
fix_ssh_security() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    echo "🔧 Fixing SSH security in: $(basename "$file")"
    
    # Create backup
    cp "$file" "$backup_file"
    echo "   📦 Backup created: $backup_file"
    
    # Fix 1: Replace StrictHostKeyChecking=no with secure implementation
    if grep -q "StrictHostKeyChecking=no" "$file"; then
        echo "   🚨 Found insecure SSH configuration - applying fix..."
        
        # Create temporary script for complex replacement
        cat > /tmp/ssh_fix.py << 'EOF'
import sys
import re

def fix_ssh_workflow(content):
    # Pattern to match insecure SSH/SCP commands
    insecure_patterns = [
        r'scp -o StrictHostKeyChecking=no',
        r'ssh -o StrictHostKeyChecking=no'
    ]
    
    for pattern in insecure_patterns:
        if re.search(pattern, content):
            print(f"   ⚠️  Found insecure pattern: {pattern}")
            # Replace with secure alternatives
            content = re.sub(
                r'scp -o StrictHostKeyChecking=no\s+',
                'scp ',
                content
            )
            content = re.sub(
                r'ssh -o StrictHostKeyChecking=no\s+',
                'ssh ',
                content
            )
    
    # Add secure SSH setup if not present
    if 'ssh-keyscan' not in content and 'SSH_PRIVATE_KEY' in content:
        # Find the SSH setup section and enhance it
        ssh_setup_pattern = r'(\s+- name: Set up SSH.*?\n(?:\s+.*\n)*?.*chmod 600.*?id_rsa)'
        
        secure_ssh_setup = '''      - name: Set up SSH with host verification
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ env.DEPLOY_HOST }} >> ~/.ssh/known_hosts
          
          # SSH client hardening
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
          timeout 30 ssh root@${{ env.DEPLOY_HOST }} "echo 'SSH connection successful'"'''
        
        content = re.sub(ssh_setup_pattern, secure_ssh_setup, content, flags=re.MULTILINE)
    
    return content

if __name__ == "__main__":
    file_path = sys.argv[1]
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    fixed_content = fix_ssh_workflow(content)
    
    with open(file_path, 'w') as f:
        f.write(fixed_content)
    
    print(f"   ✅ SSH security fixes applied to {file_path}")
EOF
        
        python3 /tmp/ssh_fix.py "$file"
        rm /tmp/ssh_fix.py
    else
        echo "   ✅ No insecure SSH patterns found"
    fi
    
    # Fix 2: Standardize secret names
    if grep -q "SSH_PRIVATE_KEY" "$file"; then
        echo "   🔧 Standardizing SSH secret name..."
        sed -i.tmp 's/SSH_PRIVATE_KEY/DEPLOY_SSH_KEY/g' "$file"
        rm "${file}.tmp"
        echo "   ✅ SSH secret name standardized to DEPLOY_SSH_KEY"
    fi
    
    # Fix 3: Add SSH cleanup
    if ! grep -q "Cleanup SSH" "$file"; then
        echo "   🧹 Adding SSH cleanup step..."
        # Add cleanup step before the last job step
        cat >> /tmp/cleanup_step << 'EOF'

      - name: Cleanup SSH and temp files
        if: always()
        run: |
          # Remove SSH key
          rm -f ~/.ssh/id_rsa ~/.ssh/config
          
          # Clean up remote temp files
          ssh root@${{ env.DEPLOY_HOST }} '
            rm -f /tmp/deploy-*.sh /tmp/*.hcl /tmp/*.nomad
          ' || true
EOF
        
        # Insert cleanup step before the end of the jobs section
        if grep -q "if: always()" "$file"; then
            echo "   ℹ️  Cleanup step already exists"
        else
            # This is a simplified approach - manual review recommended
            echo "   ⚠️  Manual addition of cleanup step recommended"
        fi
    fi
    
    echo "   ✅ Security fixes applied to $(basename "$file")"
    echo ""
}

# Find all GitHub Actions workflow files
echo "🔍 Scanning for GitHub Actions workflow files..."
WORKFLOW_FILES=($(find "$INFRA_DIR" -name "*.yml" -path "*/.github/workflows/*" -type f))

if [ ${#WORKFLOW_FILES[@]} -eq 0 ]; then
    echo "❌ No GitHub Actions workflow files found"
    exit 1
fi

echo "📝 Found ${#WORKFLOW_FILES[@]} workflow files:"
for file in "${WORKFLOW_FILES[@]}"; do
    echo "   - $(realpath --relative-to="$INFRA_DIR" "$file")"
done
echo ""

# Apply fixes to each workflow file
for workflow_file in "${WORKFLOW_FILES[@]}"; do
    if [[ -f "$workflow_file" ]]; then
        fix_ssh_security "$workflow_file"
    fi
done

echo "🔍 Scanning for deployment scripts with SSH usage..."
SCRIPT_FILES=($(find "$INFRA_DIR" -name "*.sh" -exec grep -l "ssh\|scp" {} \;))

echo "📝 Found ${#SCRIPT_FILES[@]} scripts with SSH usage:"
for script in "${SCRIPT_FILES[@]}"; do
    echo "   - $(realpath --relative-to="$INFRA_DIR" "$script")"
done
echo ""

# Check deployment scripts for SSH security issues
echo "🔍 Checking deployment scripts for SSH security..."
for script_file in "${SCRIPT_FILES[@]}"; do
    if [[ -f "$script_file" ]]; then
        echo "🔧 Checking: $(basename "$script_file")"
        
        if grep -q "StrictHostKeyChecking=no" "$script_file"; then
            echo "   ⚠️  WARNING: Found StrictHostKeyChecking=no in script"
            echo "   📝 Manual review and fix required for: $script_file"
        elif grep -q "ssh.*root@" "$script_file"; then
            echo "   ℹ️  Contains SSH to root - verify security practices"
        else
            echo "   ✅ No obvious SSH security issues detected"
        fi
        echo ""
    fi
done

# Generate security validation script
echo "📝 Creating SSH security validation script..."
cat > "$SCRIPT_DIR/validate-ssh-security.sh" << 'EOF'
#!/bin/bash

# SSH Security Validation Script
# Validates that all SSH security fixes have been properly applied

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔍 Validating SSH Security Fixes"
echo "================================"

VALIDATION_PASSED=true
ISSUES_FOUND=0

# Check for insecure SSH patterns
echo "1. Checking for insecure SSH patterns..."
if find "$INFRA_DIR" -name "*.yml" -exec grep -l "StrictHostKeyChecking=no" {} \; | head -1 > /dev/null; then
    echo "   ❌ FAIL: Found StrictHostKeyChecking=no in workflows"
    find "$INFRA_DIR" -name "*.yml" -exec grep -l "StrictHostKeyChecking=no" {} \;
    VALIDATION_PASSED=false
    ((ISSUES_FOUND++))
else
    echo "   ✅ PASS: No insecure SSH patterns found in workflows"
fi

# Check for ssh-keyscan usage
echo "2. Checking for proper host key verification..."
WORKFLOWS_WITH_SSH=$(find "$INFRA_DIR" -name "*.yml" -exec grep -l "secrets\..*SSH" {} \;)
if [ -n "$WORKFLOWS_WITH_SSH" ]; then
    WORKFLOWS_WITHOUT_KEYSCAN=""
    while IFS= read -r workflow; do
        if ! grep -q "ssh-keyscan" "$workflow"; then
            WORKFLOWS_WITHOUT_KEYSCAN="$WORKFLOWS_WITHOUT_KEYSCAN\n   - $workflow"
        fi
    done <<< "$WORKFLOWS_WITH_SSH"
    
    if [ -n "$WORKFLOWS_WITHOUT_KEYSCAN" ]; then
        echo "   ❌ FAIL: Workflows using SSH without host verification:"
        echo -e "$WORKFLOWS_WITHOUT_KEYSCAN"
        VALIDATION_PASSED=false
        ((ISSUES_FOUND++))
    else
        echo "   ✅ PASS: All SSH workflows use host verification"
    fi
else
    echo "   ℹ️  INFO: No SSH workflows found"
fi

# Check for secret name consistency
echo "3. Checking for consistent secret naming..."
if find "$INFRA_DIR" -name "*.yml" -exec grep -l "SSH_PRIVATE_KEY" {} \; | head -1 > /dev/null; then
    echo "   ⚠️  WARNING: Found inconsistent SSH secret names"
    echo "   📝 Consider standardizing on DEPLOY_SSH_KEY"
    ((ISSUES_FOUND++))
else
    echo "   ✅ PASS: SSH secret naming is consistent"
fi

# Check for cleanup steps
echo "4. Checking for SSH cleanup procedures..."
SSH_WORKFLOWS=$(find "$INFRA_DIR" -name "*.yml" -exec grep -l "secrets\..*SSH\|secrets\.DEPLOY_SSH_KEY" {} \;)
if [ -n "$SSH_WORKFLOWS" ]; then
    WORKFLOWS_WITHOUT_CLEANUP=""
    while IFS= read -r workflow; do
        if ! grep -q "rm.*id_rsa\|Cleanup.*SSH" "$workflow"; then
            WORKFLOWS_WITHOUT_CLEANUP="$WORKFLOWS_WITHOUT_CLEANUP\n   - $workflow"
        fi
    done <<< "$SSH_WORKFLOWS"
    
    if [ -n "$WORKFLOWS_WITHOUT_CLEANUP" ]; then
        echo "   ⚠️  WARNING: Workflows without SSH cleanup:"
        echo -e "$WORKFLOWS_WITHOUT_CLEANUP"
        echo "   📝 Consider adding SSH key cleanup steps"
    else
        echo "   ✅ PASS: All SSH workflows include cleanup"
    fi
fi

echo ""
echo "🏁 Validation Summary"
echo "===================="
if [ "$VALIDATION_PASSED" = true ] && [ $ISSUES_FOUND -eq 0 ]; then
    echo "✅ ALL CHECKS PASSED: SSH security is properly configured"
    exit 0
elif [ "$VALIDATION_PASSED" = true ]; then
    echo "⚠️  WARNINGS FOUND: SSH security is mostly correct but has minor issues"
    echo "Issues found: $ISSUES_FOUND"
    exit 1
else
    echo "❌ VALIDATION FAILED: Critical SSH security issues found"
    echo "Issues found: $ISSUES_FOUND"
    echo ""
    echo "Please fix the identified issues and run this script again."
    exit 2
fi
EOF

chmod +x "$SCRIPT_DIR/validate-ssh-security.sh"

echo "✅ SSH Security Fixes Applied Successfully!"
echo "=========================================="
echo ""
echo "📋 Summary of changes:"
echo "   - Applied security fixes to ${#WORKFLOW_FILES[@]} workflow files"
echo "   - Created SSH security validation script"
echo "   - Generated backup files for all modified workflows"
echo ""
echo "🔍 Next Steps:"
echo "   1. Review the modified workflow files"
echo "   2. Test the workflows in a development environment" 
echo "   3. Run the validation script: $SCRIPT_DIR/validate-ssh-security.sh"
echo "   4. Commit the changes to version control"
echo ""
echo "⚠️  Manual Review Required:"
echo "   - Some deployment scripts may still need manual fixes"
echo "   - Verify that all GitHub Secrets are properly configured"
echo "   - Test SSH connectivity after applying changes"
echo ""
echo "📁 Backup files created with timestamp: $(date +%Y%m%d-%H%M%S)"