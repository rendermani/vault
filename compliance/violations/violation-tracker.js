#!/usr/bin/env node

/**
 * Violation Tracker - Records and manages compliance violations
 */

const fs = require('fs').promises;
const path = require('path');

class ViolationTracker {
  constructor() {
    this.violationsFile = path.join(__dirname, 'violations.json');
    this.violations = [];
    this.init();
  }

  async init() {
    try {
      const data = await fs.readFile(this.violationsFile, 'utf8');
      this.violations = JSON.parse(data);
    } catch (error) {
      // File doesn't exist yet, start with empty array
      this.violations = [];
    }
  }

  async recordViolation(violation) {
    const timestamp = new Date().toISOString();
    const violationRecord = {
      id: `VIOLATION_${Date.now()}`,
      timestamp,
      rule: violation.rule,
      severity: violation.severity,
      description: violation.description,
      details: violation.details || {},
      user: violation.user || 'system',
      source: violation.source || 'automated',
      resolved: false,
      resolution: null
    };

    this.violations.push(violationRecord);
    await this.saveViolations();

    // Log immediately
    console.error(`🚨 COMPLIANCE VIOLATION RECORDED:`);
    console.error(`   ID: ${violationRecord.id}`);
    console.error(`   Rule: ${violationRecord.rule}`);
    console.error(`   Severity: ${violationRecord.severity}`);
    console.error(`   Time: ${violationRecord.timestamp}`);

    return violationRecord;
  }

  async resolveViolation(violationId, resolution) {
    const violation = this.violations.find(v => v.id === violationId);
    if (!violation) {
      throw new Error(`Violation ${violationId} not found`);
    }

    violation.resolved = true;
    violation.resolution = {
      timestamp: new Date().toISOString(),
      action: resolution.action,
      notes: resolution.notes,
      resolvedBy: resolution.resolvedBy
    };

    await this.saveViolations();
    return violation;
  }

  async getViolations(filters = {}) {
    let filtered = [...this.violations];

    if (filters.severity) {
      filtered = filtered.filter(v => v.severity === filters.severity);
    }

    if (filters.resolved !== undefined) {
      filtered = filtered.filter(v => v.resolved === filters.resolved);
    }

    if (filters.rule) {
      filtered = filtered.filter(v => v.rule === filters.rule);
    }

    if (filters.since) {
      const since = new Date(filters.since);
      filtered = filtered.filter(v => new Date(v.timestamp) >= since);
    }

    return filtered;
  }

  async getViolationStats() {
    const total = this.violations.length;
    const resolved = this.violations.filter(v => v.resolved).length;
    const unresolved = total - resolved;

    const bySeverity = {
      CRITICAL: this.violations.filter(v => v.severity === 'CRITICAL').length,
      HIGH: this.violations.filter(v => v.severity === 'HIGH').length,
      MEDIUM: this.violations.filter(v => v.severity === 'MEDIUM').length,
      LOW: this.violations.filter(v => v.severity === 'LOW').length
    };

    return {
      total,
      resolved,
      unresolved,
      bySeverity,
      complianceScore: total === 0 ? 100 : Math.round((resolved / total) * 100)
    };
  }

  async saveViolations() {
    await fs.writeFile(this.violationsFile, JSON.stringify(this.violations, null, 2));
  }

  async generateViolationReport() {
    const stats = await this.getViolationStats();
    const recentViolations = await this.getViolations({ 
      since: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString() 
    });

    return {
      summary: stats,
      recentViolations,
      unresolvedViolations: await this.getViolations({ resolved: false }),
      trends: this.calculateTrends()
    };
  }

  calculateTrends() {
    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const last24h = this.violations.filter(v => new Date(v.timestamp) >= oneDayAgo).length;
    const lastWeek = this.violations.filter(v => new Date(v.timestamp) >= oneWeekAgo).length;

    return {
      last24Hours: last24h,
      lastWeek: lastWeek,
      averagePerDay: lastWeek / 7,
      trend: last24h > (lastWeek / 7) ? 'INCREASING' : 'DECREASING'
    };
  }
}

module.exports = ViolationTracker;

// CLI interface
if (require.main === module) {
  const tracker = new ViolationTracker();
  
  const command = process.argv[2];
  const args = process.argv.slice(3);

  switch (command) {
    case 'record':
      // node violation-tracker.js record RULE_NAME SEVERITY "Description"
      const [rule, severity, description] = args;
      tracker.recordViolation({ rule, severity, description })
        .then(violation => console.log('Violation recorded:', violation.id))
        .catch(console.error);
      break;

    case 'list':
      tracker.getViolations()
        .then(violations => console.log(JSON.stringify(violations, null, 2)))
        .catch(console.error);
      break;

    case 'stats':
      tracker.getViolationStats()
        .then(stats => console.log(JSON.stringify(stats, null, 2)))
        .catch(console.error);
      break;

    case 'report':
      tracker.generateViolationReport()
        .then(report => console.log(JSON.stringify(report, null, 2)))
        .catch(console.error);
      break;

    default:
      console.log('Usage: node violation-tracker.js [record|list|stats|report] [args...]');
  }
}