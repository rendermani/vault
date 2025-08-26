#!/usr/bin/env python3
"""
Progress Documenter - Advanced Python Monitor
Provides more sophisticated progress tracking and JSON manipulation
"""

import json
import time
import os
import subprocess
import threading
import signal
import sys
from datetime import datetime, timezone
from pathlib import Path
import logging

class ProgressDocumenter:
    def __init__(self):
        self.vault_dir = Path("/Users/mlautenschlager/cloudya/vault")
        self.progress_file = self.vault_dir / "progress.json"
        self.log_file = self.vault_dir / "logs" / "progress-documenter.log"
        self.running = True
        self.last_activities = []
        
        # Ensure logs directory exists
        self.vault_dir.joinpath("logs").mkdir(exist_ok=True)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def load_current_progress(self):
        """Load current progress from JSON file"""
        try:
            with open(self.progress_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.logger.error(f"Error loading progress file: {e}")
            return self.get_default_progress()
    
    def get_default_progress(self):
        """Return default progress structure"""
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "overall_progress": 10,
            "status": "Active - Full Enterprise Team Deployment",
            "current_phase": "Research & Planning",
            "agents": {"total": 35, "active": 30, "completed": 0},
            "phases": [],
            "services": [],
            "active_agents": [],
            "recent_activities": []
        }
    
    def calculate_phase_progress(self, phase_name):
        """Calculate progress for a specific phase based on indicators"""
        indicators = {
            "Research & Planning": [
                (self.vault_dir / "src" / "ansible").exists(),
                (self.vault_dir / "src" / "terraform").exists(), 
                len(list(self.vault_dir.glob("**/*.nomad"))) > 0,
                (self.vault_dir / "coordination").exists()
            ],
            "Ansible Bootstrap": [
                (self.vault_dir / "logs" / "ansible-deployment.log").exists(),
                self.is_service_running("consul"),
                self.is_service_running("nomad"),
                (self.vault_dir / "logs" / "ansible-complete.marker").exists()
            ],
            "Terraform Configuration": [
                (self.vault_dir / "logs" / "terraform-deployment.log").exists(),
                self.is_service_running("vault"),
                (self.vault_dir / "logs" / "vault-initialized.marker").exists(),
                (self.vault_dir / "logs" / "terraform-complete.marker").exists()
            ],
            "Deploy Traefik": [
                (self.vault_dir / "logs" / "traefik-deployment.log").exists(),
                self.is_service_running("traefik"),
                self.check_url_accessible("https://traefik.cloudya.net"),
                (self.vault_dir / "logs" / "traefik-complete.marker").exists()
            ]
        }
        
        phase_indicators = indicators.get(phase_name, [])
        if not phase_indicators:
            return 0
            
        completed = sum(1 for indicator in phase_indicators if indicator)
        return int((completed / len(phase_indicators)) * 100)
    
    def is_service_running(self, service_name):
        """Check if a service is running"""
        try:
            result = subprocess.run(
                ["pgrep", "-f", service_name], 
                capture_output=True, 
                text=True
            )
            return result.returncode == 0
        except:
            return False
    
    def check_url_accessible(self, url):
        """Check if URL is accessible (simplified)"""
        try:
            result = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.stdout.strip() in ["200", "301", "302"]
        except:
            return False
    
    def get_service_status(self, service_name):
        """Get status of a specific service"""
        if self.is_service_running(service_name):
            return "online"
        elif (self.vault_dir / "logs" / f"{service_name}-deployment.log").exists():
            return "starting"
        else:
            return "offline"
    
    def detect_new_activities(self):
        """Detect new activities by monitoring log files and processes"""
        activities = []
        
        # Check for new log files
        log_patterns = {
            "ansible-deployment.log": "Ansible bootstrap started",
            "terraform-deployment.log": "Terraform configuration started", 
            "vault-deployment.log": "Vault deployment initiated",
            "traefik-deployment.log": "Traefik deployment started",
            "consul-deployment.log": "Consul service deployment started",
            "nomad-deployment.log": "Nomad service deployment started"
        }
        
        for log_file, message in log_patterns.items():
            log_path = self.vault_dir / "logs" / log_file
            if log_path.exists() and message not in self.last_activities:
                activities.append(message)
                self.last_activities.append(message)
        
        # Check for service status changes
        services = ["consul", "nomad", "vault", "traefik"]
        for service in services:
            if self.is_service_running(service):
                message = f"{service.capitalize()} service is now running"
                if message not in self.last_activities:
                    activities.append(message)
                    self.last_activities.append(message)
        
        # Keep last activities list manageable
        self.last_activities = self.last_activities[-50:]
        
        return activities
    
    def update_progress_file(self):
        """Update the progress.json file with current status"""
        try:
            current_progress = self.load_current_progress()
            
            # Update timestamp
            current_progress["timestamp"] = datetime.now(timezone.utc).isoformat()
            
            # Calculate overall progress
            phase_names = ["Research & Planning", "Ansible Bootstrap", "Terraform Configuration", "Deploy Traefik"]
            total_progress = sum(self.calculate_phase_progress(name) for name in phase_names)
            current_progress["overall_progress"] = min(int(total_progress / len(phase_names)), 100)
            
            # Update current phase
            for phase_name in phase_names:
                phase_progress = self.calculate_phase_progress(phase_name)
                if phase_progress < 100:
                    current_progress["current_phase"] = phase_name
                    break
            else:
                current_progress["current_phase"] = "Deployment Complete"
            
            # Update services
            services = ["Consul", "Nomad", "Vault", "Traefik"]
            service_configs = []
            for service in services:
                service_configs.append({
                    "name": service,
                    "url": f"https://{service.lower()}.cloudya.net",
                    "status": self.get_service_status(service.lower()),
                    "ssl": self.check_url_accessible(f"https://{service.lower()}.cloudya.net")
                })
            current_progress["services"] = service_configs
            
            # Update agents count
            active_count = 30  # Base count
            if (self.vault_dir / "logs" / "ansible-deployment.log").exists():
                active_count += 5
            if (self.vault_dir / "logs" / "terraform-deployment.log").exists():
                active_count += 5
                
            completed_count = 0
            if (self.vault_dir / "logs" / "ansible-complete.marker").exists():
                completed_count += 5
            if (self.vault_dir / "logs" / "terraform-complete.marker").exists():
                completed_count += 5
                
            current_progress["agents"]["active"] = active_count
            current_progress["agents"]["completed"] = completed_count
            
            # Add new activities
            new_activities = self.detect_new_activities()
            current_time = datetime.now().strftime("%H:%M:%S")
            
            recent_activities = current_progress.get("recent_activities", [])
            for activity in new_activities:
                recent_activities.insert(0, {
                    "time": current_time,
                    "message": activity
                })
            
            # Keep only last 15 activities
            current_progress["recent_activities"] = recent_activities[:15]
            
            # Write updated progress
            with open(self.progress_file, 'w') as f:
                json.dump(current_progress, f, indent=2)
                
            self.logger.info("Progress file updated successfully")
            
        except Exception as e:
            self.logger.error(f"Error updating progress file: {e}")
    
    def monitor_loop(self):
        """Main monitoring loop"""
        self.logger.info("Progress Documenter started - continuous monitoring active")
        
        while self.running:
            try:
                self.update_progress_file()
                time.sleep(10)  # Update every 10 seconds
            except KeyboardInterrupt:
                break
            except Exception as e:
                self.logger.error(f"Error in monitoring loop: {e}")
                time.sleep(5)
        
        self.logger.info("Progress Documenter stopped")
    
    def stop(self):
        """Stop the monitoring"""
        self.running = False

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    print("\nReceived shutdown signal, stopping Progress Documenter...")
    documenter.stop()
    sys.exit(0)

if __name__ == "__main__":
    documenter = ProgressDocumenter()
    
    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        documenter.monitor_loop()
    except KeyboardInterrupt:
        documenter.stop()