#!/bin/bash

# Master script to start all progress monitoring components
# This is the main entry point for the Progress Documenter system

VAULT_DIR="/Users/mlautenschlager/cloudya/vault"
cd "$VAULT_DIR"

echo "🚀 Starting Progress Documenter System..."
echo "======================================"

# Create logs directory if it doesn't exist
mkdir -p logs

# Kill any existing monitoring processes
echo "Cleaning up any existing monitoring processes..."
pkill -f "progress-updater.py" 2>/dev/null || true
pkill -f "serve-dashboard.py" 2>/dev/null || true
pkill -f "progress-watcher.sh" 2>/dev/null || true

# Wait a moment for processes to terminate
sleep 2

# Start Python progress monitor
echo "🔄 Starting Python progress monitor..."
python3 scripts/progress-updater.py &
PYTHON_PID=$!
echo "Python monitor started (PID: $PYTHON_PID)"

# Start file system watcher
echo "👁️  Starting file system watcher..."
bash scripts/progress-watcher.sh &
WATCHER_PID=$!
echo "File watcher started (PID: $WATCHER_PID)"

# Find available port and start dashboard server
echo "🌐 Starting dashboard server..."
DASHBOARD_PORT=8081
python3 -c "
import socket
import sys
import threading
import http.server
import socketserver
from pathlib import Path

class ProgressHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory='/Users/mlautenschlager/cloudya/vault', **kwargs)
    
    def do_GET(self):
        if self.path == '/':
            self.path = '/scripts/progress-dashboard.html'
        elif self.path.startswith('/progress.json'):
            try:
                progress_file = Path('/Users/mlautenschlager/cloudya/vault/progress.json')
                if progress_file.exists():
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    with open(progress_file, 'r') as f:
                        self.wfile.write(f.read().encode())
                    return
            except:
                pass
        super().do_GET()
    
    def log_message(self, format, *args):
        pass

# Try different ports if needed
for port in range(8081, 8090):
    try:
        with socketserver.TCPServer(('', port), ProgressHandler) as httpd:
            print(f'Dashboard server started at http://localhost:{port}')
            httpd.serve_forever()
        break
    except OSError:
        continue
" &
DASHBOARD_PID=$!

# Update progress to indicate monitoring is active
sleep 1
./scripts/update-progress.sh "All monitoring components started successfully" "Research & Planning" 20

echo ""
echo "✅ Progress Documenter System Started!"
echo "======================================"
echo "📊 Dashboard: http://localhost:8081"
echo "📁 Progress file: $VAULT_DIR/progress.json"
echo "📝 Logs directory: $VAULT_DIR/logs/"
echo ""
echo "📊 Monitoring components:"
echo "  - Python Progress Monitor (PID: $PYTHON_PID)"
echo "  - File System Watcher (PID: $WATCHER_PID)"
echo "  - Dashboard Server (PID: $DASHBOARD_PID)"
echo ""
echo "🔄 Updates every 10 seconds"
echo "📱 Dashboard refreshes automatically"
echo ""
echo "To stop all monitoring:"
echo "  pkill -f progress-updater"
echo "  pkill -f progress-watcher" 
echo "  pkill -f serve-dashboard"
echo ""

# Keep track of PIDs
echo "$PYTHON_PID" > logs/progress-monitor.pid
echo "$WATCHER_PID" > logs/file-watcher.pid
echo "$DASHBOARD_PID" > logs/dashboard-server.pid

echo "🎯 Progress Documenter is now actively monitoring the deployment!"
echo "   All agent activities will be tracked automatically."