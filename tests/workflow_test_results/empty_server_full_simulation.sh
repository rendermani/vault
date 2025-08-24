#!/bin/bash
# Complete empty server deployment simulation

set -e

VAULT_VERSION="1.17.3"
DEPLOY_HOST="cloudya.net"
DEPLOY_USER="root"
SIMULATION_ROOT="/tmp/empty_server_simulation"

echo "🚀 Starting empty server simulation..."

# Clean up previous simulation
rm -rf "$SIMULATION_ROOT"
mkdir -p "$SIMULATION_ROOT/opt/vault/{bin,config,data,logs,tls}"
mkdir -p "$SIMULATION_ROOT/etc/systemd/system"

cd "$SIMULATION_ROOT"

echo "📦 Step 1: Checking for existing Vault installation..."
if [ ! -f "$SIMULATION_ROOT/opt/vault/bin/vault" ]; then
    echo "✅ No existing Vault found (empty server confirmed)"
else
    echo "❌ Vault binary exists (not an empty server)"
    exit 1
fi

echo "⬇️ Step 2: Simulating Vault download and installation..."
# Simulate download
echo "Downloading Vault ${VAULT_VERSION}..."
echo "#!/bin/bash" > "$SIMULATION_ROOT/opt/vault/bin/vault"
echo "echo 'Vault v$VAULT_VERSION'" >> "$SIMULATION_ROOT/opt/vault/bin/vault"
chmod +x "$SIMULATION_ROOT/opt/vault/bin/vault"

# Simulate symlink creation
mkdir -p "$SIMULATION_ROOT/usr/local/bin"
ln -sf "$SIMULATION_ROOT/opt/vault/bin/vault" "$SIMULATION_ROOT/usr/local/bin/vault"

echo "✅ Vault binary installed and symlinked"

echo "📝 Step 3: Creating Vault configuration..."
cat > "$SIMULATION_ROOT/opt/vault/config/vault.hcl" << 'VAULTCFG'
ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://cloudya.net:8200"
cluster_addr = "http://cloudya.net:8201"
VAULTCFG

echo "✅ Vault configuration created"

echo "🔧 Step 4: Creating systemd service..."
cat > "$SIMULATION_ROOT/etc/systemd/system/vault.service" << 'SYSTEMD'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/opt/vault/config/vault.hcl

[Service]
Type=notify
EnvironmentFile=/opt/vault/vault.env
User=root
Group=root
ExecStart=/opt/vault/bin/vault server -config=/opt/vault/config/vault.hcl
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

echo "✅ Systemd service created"

echo "🌍 Step 5: Creating environment file..."
cat > "$SIMULATION_ROOT/opt/vault/vault.env" << 'ENVFILE'
VAULT_ADDR=http://127.0.0.1:8200
VAULT_API_ADDR=http://cloudya.net:8200
ENVFILE

echo "✅ Environment file created"

echo "✅ Step 6: Validating all components..."

# Validate binary
if [ -x "$SIMULATION_ROOT/opt/vault/bin/vault" ]; then
    echo "✅ Vault binary is executable"
else
    echo "❌ Vault binary is not executable"
    exit 1
fi

# Validate config
if [ -f "$SIMULATION_ROOT/opt/vault/config/vault.hcl" ] && [ -s "$SIMULATION_ROOT/opt/vault/config/vault.hcl" ]; then
    echo "✅ Vault configuration exists and is not empty"
else
    echo "❌ Vault configuration missing or empty"
    exit 1
fi

# Validate systemd service
if [ -f "$SIMULATION_ROOT/etc/systemd/system/vault.service" ]; then
    echo "✅ Systemd service file created"
else
    echo "❌ Systemd service file missing"
    exit 1
fi

# Validate environment file
if [ -f "$SIMULATION_ROOT/opt/vault/vault.env" ]; then
    echo "✅ Environment file created"
else
    echo "❌ Environment file missing"
    exit 1
fi

echo ""
echo "🎉 Empty server deployment simulation completed successfully!"
echo "📊 Summary:"
echo "   - Vault binary: ✅ Installed"
echo "   - Configuration: ✅ Created"
echo "   - Systemd service: ✅ Configured"
echo "   - Environment file: ✅ Created"
echo "   - Directory structure: ✅ Established"

# Clean up
cd /tmp
rm -rf "$SIMULATION_ROOT"
echo "🧹 Simulation environment cleaned up"
