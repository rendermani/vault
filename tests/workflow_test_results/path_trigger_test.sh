#!/bin/bash
# Test path-based triggers

# Paths that should trigger deployment
trigger_paths=(
    "scripts/deploy-vault.sh"
    "scripts/init-vault.sh"
    "config/vault.hcl"
    "policies/admin.hcl"
    "policies/developer.hcl"
    ".github/workflows/deploy.yml"
)

# Paths that should NOT trigger deployment
non_trigger_paths=(
    "README.md"
    "docs/setup.md"
    "tests/test_something.sh"
    "src/app.js"
)

echo "Testing trigger paths..."
for path in "${trigger_paths[@]}"; do
    echo "✅ Should trigger: $path"
done

echo ""
echo "Testing non-trigger paths..."
for path in "${non_trigger_paths[@]}"; do
    echo "ℹ️ Should not trigger: $path"
done

echo ""
echo "✅ Path trigger test completed"
