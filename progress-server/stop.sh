#!/bin/bash

# Vault Progress Server Stop Script
set -e

echo "🛑 Stopping Vault Progress Server..."

# Stop and remove containers
docker-compose down --remove-orphans

# Optional: Remove the image (uncomment if desired)
# docker-compose down --rmi all --remove-orphans

echo "✅ Progress server stopped successfully!"
echo ""
echo "🚀 To start again: ./start.sh"