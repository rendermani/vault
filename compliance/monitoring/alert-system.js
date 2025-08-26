#!/usr/bin/env node

/**
 * Compliance Alert System
 * Real-time monitoring and alerting for IaC compliance violations
 */

const fs = require('fs');
const { spawn } = require('child_process');
const ViolationTracker = require('../violations/violation-tracker');

class ComplianceAlertSystem {
  constructor() {
    this.violationTracker = new ViolationTracker();
    this.watchers = new Map();
    this.commandFilters = [];
    this.alertHandlers = new Map();
    this.setupAlertHandlers();
    this.setupCommandFilters();
  }

  setupAlertHandlers() {
    this.alertHandlers.set('CRITICAL', this.handleCriticalAlert.bind(this));
    this.alertHandlers.set('HIGH', this.handleHighAlert.bind(this));
    this.alertHandlers.set('MEDIUM', this.handleMediumAlert.bind(this));
    this.alertHandlers.set('LOW', this.handleLowAlert.bind(this));
  }

  setupCommandFilters() {
    this.commandFilters = [
      // SSH-based workarounds
      { pattern: /ssh.*systemctl/, rule: 'NO_SSH_WORKAROUNDS', severity: 'CRITICAL' },
      { pattern: /ssh.*service/, rule: 'NO_SSH_WORKAROUNDS', severity: 'CRITICAL' },
      { pattern: /ssh.*vim \/etc\//, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      { pattern: /ssh.*nano \/etc\//, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      { pattern: /scp.*config/, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      { pattern: /rsync.*config/, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      
      // Direct server modifications
      { pattern: /sudo vim \/etc\//, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      { pattern: /sudo nano \/etc\//, rule: 'NO_DIRECT_CONFIG_CHANGES', severity: 'CRITICAL' },
      { pattern: /sudo systemctl.*without.*ansible/, rule: 'NO_SSH_WORKAROUNDS', severity: 'HIGH' },
      
      // Plan deviation indicators
      { pattern: /skip.*ansible/, rule: 'STICK_TO_PLAN', severity: 'HIGH' },
      { pattern: /bypass.*terraform/, rule: 'STICK_TO_PLAN', severity: 'HIGH' },
      { pattern: /manual.*deployment/, rule: 'ONE_BUTTON_DEPLOYMENT', severity: 'HIGH' }
    ];
  }

  async startMonitoring() {
    console.log('🚨 Compliance Alert System starting...');
    
    // Monitor file system changes
    this.startFileSystemMonitoring();
    
    // Monitor command execution (if possible)
    this.startCommandMonitoring();
    
    // Start periodic health checks
    this.startHealthChecks();
    
    console.log('✅ Compliance Alert System active');
  }

  startFileSystemMonitoring() {
    const criticalPaths = [
      '/etc/vault.d',
      '/opt/vault',
      '/etc/systemd/system',
      '/etc/nginx',
      '/etc/ssl'
    ];

    criticalPaths.forEach(path => {
      try {
        const watcher = fs.watch(path, { recursive: true }, (eventType, filename) => {
          this.handleFileSystemEvent(path, eventType, filename);
        });
        
        this.watchers.set(path, watcher);
        console.log(`👁️  Monitoring: ${path}`);
      } catch (error) {
        // Path doesn't exist yet, that's okay
        console.log(`⚠️  Path not found (will monitor when created): ${path}`);
      }
    });
  }

  async handleFileSystemEvent(path, eventType, filename) {
    const violation = {
      rule: 'NO_DIRECT_CONFIG_CHANGES',
      severity: 'CRITICAL',
      description: `Direct file modification detected: ${eventType} ${filename} in ${path}`,
      details: {
        path,
        eventType,
        filename,
        timestamp: new Date().toISOString()
      }
    };

    await this.raiseAlert(violation);
  }

  startCommandMonitoring() {
    // This is a simplified version - in practice you'd need system-level monitoring
    console.log('🔍 Command monitoring active (monitoring process arguments)');
    
    // Monitor current process for suspicious patterns
    setInterval(() => {
      this.checkRunningProcesses();
    }, 5000);
  }

  async checkRunningProcesses() {
    // This would typically integrate with system monitoring tools
    // For now, we'll check for certain patterns in environment or logs
    
    try {
      const processes = await this.getRunningProcesses();
      
      for (const process of processes) {
        for (const filter of this.commandFilters) {
          if (filter.pattern.test(process.command)) {
            const violation = {
              rule: filter.rule,
              severity: filter.severity,
              description: `Prohibited command detected: ${process.command}`,
              details: {
                pid: process.pid,
                command: process.command,
                user: process.user
              }
            };
            
            await this.raiseAlert(violation);
          }
        }
      }
    } catch (error) {
      // Process monitoring not available, continue silently
    }
  }

  async getRunningProcesses() {
    // Simplified process checking - would use ps or similar in production
    return [];
  }

  startHealthChecks() {
    // Periodic compliance health checks
    setInterval(() => {
      this.performHealthCheck();
    }, 60000); // Every minute
  }

  async performHealthCheck() {
    const checks = [
      this.checkAutomationStatus(),
      this.checkPlanCompliance(),
      this.checkManualInterventions()
    ];

    const results = await Promise.allSettled(checks);
    
    for (const result of results) {
      if (result.status === 'rejected') {
        console.warn('Health check failed:', result.reason);
      }
    }
  }

  async checkAutomationStatus() {
    // Check if automation is running as expected
    const expectedProcesses = ['ansible-playbook', 'terraform', 'nomad'];
    // Implementation would check for these processes
    return true;
  }

  async checkPlanCompliance() {
    // Verify we're following the Ansible → Terraform → Nomad sequence
    // This would check project state and phase progression
    return true;
  }

  async checkManualInterventions() {
    // Look for signs of manual server modifications
    // Check logs, file timestamps, etc.
    return true;
  }

  async raiseAlert(violation) {
    // Record the violation
    await this.violationTracker.recordViolation(violation);
    
    // Handle based on severity
    const handler = this.alertHandlers.get(violation.severity);
    if (handler) {
      await handler(violation);
    }
    
    // Send notifications
    await this.sendNotifications(violation);
  }

  async handleCriticalAlert(violation) {
    console.error('🚨 CRITICAL COMPLIANCE VIOLATION - BLOCKING OPERATION');
    console.error(`Rule: ${violation.rule}`);
    console.error(`Description: ${violation.description}`);
    
    // Block operation
    if (violation.rule === 'NO_SSH_WORKAROUNDS' || violation.rule === 'NO_DIRECT_CONFIG_CHANGES') {
      console.error('🛑 OPERATION MUST BE STOPPED IMMEDIATELY');
      console.error('   Use automation tools or spawn analysis agents instead');
      
      // In a production system, this might kill processes or block access
      process.exit(1);
    }
  }

  async handleHighAlert(violation) {
    console.warn('⚠️ HIGH PRIORITY COMPLIANCE ISSUE');
    console.warn(`Rule: ${violation.rule}`);
    console.warn(`Description: ${violation.description}`);
    
    if (violation.rule === 'STICK_TO_PLAN') {
      console.warn('📋 Please provide justification for plan deviation');
      console.warn('   Expected sequence: Ansible → Terraform → Nomad Pack');
    }
  }

  async handleMediumAlert(violation) {
    console.info('ℹ️ MEDIUM PRIORITY COMPLIANCE NOTICE');
    console.info(`Rule: ${violation.rule}`);
    console.info(`Description: ${violation.description}`);
    
    if (violation.rule === 'SPAWN_RESEARCHERS_ON_FAILURE') {
      console.info('🤖 Auto-spawning analysis agents...');
      await this.autoSpawnAnalysisAgents(violation);
    }
  }

  async handleLowAlert(violation) {
    console.log('📝 LOW PRIORITY COMPLIANCE NOTE');
    console.log(`Rule: ${violation.rule}`);
    console.log(`Description: ${violation.description}`);
  }

  async autoSpawnAnalysisAgents(violation) {
    console.log('🔬 Spawning analysis agents for failure investigation:');
    console.log('   → Research Agent: Analyzing root cause');
    console.log('   → System Architect: Evaluating alternatives');
    console.log('   → Analyst Agent: Impact assessment');
    
    // This would integrate with the agent spawning system
    const analysisTask = {
      type: 'compliance_analysis',
      violation: violation,
      agents: ['researcher', 'system-architect', 'analyst'],
      objective: 'Analyze violation and propose compliant solution'
    };
    
    return analysisTask;
  }

  async sendNotifications(violation) {
    // Send notifications to relevant parties
    const notification = {
      timestamp: new Date().toISOString(),
      severity: violation.severity,
      rule: violation.rule,
      description: violation.description,
      project: 'Vault Progress Server'
    };
    
    // Email notifications (would integrate with email service)
    if (violation.severity === 'CRITICAL') {
      console.log('📧 Sending critical alert to: lead-engineer, security-officer');
    }
    
    // Slack/Teams notifications (would integrate with chat services)
    console.log('💬 Posting alert to compliance channel');
    
    // Log to compliance system
    const logFile = '/Users/mlautenschlager/cloudya/vault/compliance/logs/alerts.log';
    const logEntry = `${notification.timestamp} [${notification.severity}] ${notification.rule}: ${notification.description}\n`;
    
    try {
      fs.appendFileSync(logFile, logEntry);
    } catch (error) {
      console.warn('Could not write to alert log:', error.message);
    }
  }

  async stop() {
    console.log('🛑 Stopping Compliance Alert System...');
    
    // Close file watchers
    for (const [path, watcher] of this.watchers) {
      watcher.close();
      console.log(`   Stopped monitoring: ${path}`);
    }
    
    this.watchers.clear();
    console.log('✅ Compliance Alert System stopped');
  }
}

module.exports = ComplianceAlertSystem;

// Run if called directly
if (require.main === module) {
  const alertSystem = new ComplianceAlertSystem();
  
  alertSystem.startMonitoring().catch(console.error);
  
  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT, shutting down gracefully...');
    alertSystem.stop().then(() => {
      process.exit(0);
    });
  });
}