#!/bin/bash
# Simulate directory creation from workflow

TEST_ROOT="/tmp/test_vault_dirs"
rm -rf "$TEST_ROOT"

# Simulate the workflow directory creation
mkdir -p "$TEST_ROOT/opt/vault/{bin,config,data,logs,tls}"

# Verify all directories were created
required_dirs=("bin" "config" "data" "logs" "tls")
for dir in "${required_dirs[@]}"; do
    if [ ! -d "$TEST_ROOT/opt/vault/$dir" ]; then
        echo "❌ Directory not created: /opt/vault/$dir"
        rm -rf "$TEST_ROOT"
        exit 1
    else
        echo "✅ Directory created: /opt/vault/$dir"
    fi
done

# Clean up
rm -rf "$TEST_ROOT"
echo "✅ Directory creation test successful"
