#!/usr/bin/env python3
"""
Simple HTTP server to serve the progress dashboard
Serves both the HTML dashboard and JSON progress data
"""

import http.server
import socketserver
import os
import json
from pathlib import Path
import threading
import time

class ProgressHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.vault_dir = Path("/Users/mlautenschlager/cloudya/vault")
        super().__init__(*args, directory=str(self.vault_dir), **kwargs)
    
    def do_GET(self):
        if self.path == '/':
            # Serve the dashboard HTML
            self.path = '/scripts/progress-dashboard.html'
        elif self.path.startswith('/progress.json'):
            # Serve the progress JSON with CORS headers
            try:
                progress_file = self.vault_dir / 'progress.json'
                if progress_file.exists():
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                    self.end_headers()
                    
                    with open(progress_file, 'r') as f:
                        self.wfile.write(f.read().encode())
                    return
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
                return
        
        # Default handling for other requests
        super().do_GET()
    
    def log_message(self, format, *args):
        # Suppress default logging to reduce noise
        pass

def start_server(port=8080):
    """Start the HTTP server"""
    try:
        with socketserver.TCPServer(("", port), ProgressHTTPRequestHandler) as httpd:
            print(f"Progress Dashboard server running at http://localhost:{port}")
            print("Access the dashboard at: http://localhost:8080")
            print("Press Ctrl+C to stop the server")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped")
    except Exception as e:
        print(f"Error starting server: {e}")

if __name__ == "__main__":
    start_server()