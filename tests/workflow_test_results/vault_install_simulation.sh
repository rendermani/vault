#!/bin/bash
# Simulate empty server Vault installation logic

VAULT_VERSION="1.17.3"
VAULT_DIR="/tmp/test_vault_install"

# Clean up any existing test directory
rm -rf "$VAULT_DIR"
mkdir -p "$VAULT_DIR/bin"

# Simulate the workflow logic
cd /tmp

# Check if vault binary exists (should not exist on empty server)
if [ ! -f "$VAULT_DIR/bin/vault" ]; then
    echo "✅ Vault binary not found - proceeding with installation"
    
    # Simulate download (we'll just create a dummy file)
    echo "Downloading Vault ${VAULT_VERSION}..."
    touch "vault_${VAULT_VERSION}_linux_amd64.zip"
    
    # Simulate unzip and move
    echo "Installing Vault binary..."
    echo "#!/bin/bash" > vault
    echo "echo 'Vault v$VAULT_VERSION'" >> vault
    chmod +x vault
    
    mv vault "$VAULT_DIR/bin/"
    echo "✅ Vault binary installed to $VAULT_DIR/bin/"
    
    # Check binary is executable
    if [ -x "$VAULT_DIR/bin/vault" ]; then
        echo "✅ Vault binary is executable"
    else
        echo "❌ Vault binary is not executable"
        exit 1
    fi
    
    # Clean up
    rm -f "vault_${VAULT_VERSION}_linux_amd64.zip"
    rm -rf "$VAULT_DIR"
    
    echo "✅ Empty server installation simulation successful"
else
    echo "❌ Vault binary already exists (not an empty server scenario)"
    exit 1
fi
