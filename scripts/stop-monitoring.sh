#!/bin/bash

# Stop all progress monitoring components

echo "🛑 Stopping Progress Documenter System..."

# Kill monitoring processes
echo "Stopping Python progress monitor..."
pkill -f "progress-updater.py" 2>/dev/null && echo "✅ Python monitor stopped" || echo "⚠️  Python monitor not running"

echo "Stopping file system watcher..."
pkill -f "progress-watcher.sh" 2>/dev/null && echo "✅ File watcher stopped" || echo "⚠️  File watcher not running"

echo "Stopping dashboard server..."
pkill -f "serve-dashboard.py" 2>/dev/null && echo "✅ Dashboard server stopped" || echo "⚠️  Dashboard server not running"

# Clean up PID files
rm -f logs/progress-monitor.pid logs/file-watcher.pid logs/dashboard-server.pid 2>/dev/null

# Final progress update
if [ -f "scripts/update-progress.sh" ]; then
    ./scripts/update-progress.sh "Progress monitoring system stopped"
fi

echo "🔚 Progress Documenter System stopped."