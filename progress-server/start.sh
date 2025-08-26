#!/bin/bash

# Vault Progress Server Startup Script
set -e

echo "🚀 Starting Vault Progress Server..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if progress files exist
VAULT_DIR="/Users/mlautenschlager/cloudya/vault"
if [ ! -f "$VAULT_DIR/progress.json" ]; then
    echo "⚠️  Warning: progress.json not found at $VAULT_DIR/progress.json"
fi

if [ ! -f "$VAULT_DIR/progress.html" ]; then
    echo "⚠️  Warning: progress.html not found at $VAULT_DIR/progress.html"
fi

# Stop any existing container
echo "🧹 Cleaning up existing containers..."
docker-compose down --remove-orphans 2>/dev/null || true

# Build and start the container
echo "🏗️  Building nginx container..."
docker-compose build --no-cache

echo "▶️  Starting progress server..."
docker-compose up -d

# Wait for container to be healthy
echo "⏳ Waiting for server to be ready..."
sleep 3

# Check if container is running
if docker-compose ps | grep -q "Up"; then
    echo "✅ Progress server is running successfully!"
    echo ""
    echo "📊 Access your progress dashboard:"
    echo "   • Progress Dashboard: http://localhost:8080/progress.html"
    echo "   • Progress JSON API:  http://localhost:8080/progress.json"
    echo "   • Server Status:      docker-compose ps"
    echo ""
    echo "🛑 To stop the server:"
    echo "   ./stop.sh"
    echo ""
    
    # Test the endpoints
    echo "🔍 Testing endpoints..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/progress.json | grep -q "200"; then
        echo "✅ JSON endpoint is responding"
    else
        echo "⚠️  JSON endpoint test failed"
    fi
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/progress.html | grep -q "200"; then
        echo "✅ HTML endpoint is responding"
    else
        echo "⚠️  HTML endpoint test failed"
    fi
    
else
    echo "❌ Failed to start progress server"
    echo "📋 Container logs:"
    docker-compose logs
    exit 1
fi