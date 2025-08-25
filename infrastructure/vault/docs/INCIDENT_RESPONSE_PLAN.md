# Vault Incident Response Plan

## Executive Summary

This document outlines the incident response procedures for HashiCorp Vault security incidents. It provides a structured approach to detect, contain, eradicate, recover from, and learn from security incidents affecting our Vault infrastructure.

## Incident Response Team

### Core Team Members

| Role | Primary | Secondary | Contact |
|------|---------|-----------|---------|
| **Incident Commander** | Security Manager | DevOps Lead | admin@cloudya.net |
| **Technical Lead** | Senior DevOps Engineer | Cloud Architect | tech@cloudya.net |
| **Security Analyst** | Security Engineer | InfoSec Analyst | security@cloudya.net |
| **Communications** | IT Manager | Operations Manager | comms@cloudya.net |
| **Legal/Compliance** | Legal Counsel | Compliance Officer | legal@cloudya.net |

### Extended Team (As Needed)

| Role | Contact | When to Engage |
|------|---------|----------------|
| **Development Team Lead** | dev@cloudya.net | Application-related incidents |
| **Network Operations** | netops@cloudya.net | Network-related incidents |
| **Database Administrator** | dba@cloudya.net | Data integrity issues |
| **External Forensics** | forensics@external.com | Major security breaches |
| **HashiCorp Support** | support.hashicorp.com | Product-specific issues |

## Incident Classification

### Severity Levels

#### **Severity 1 (Critical)**
- **Response Time**: Immediate (within 15 minutes)
- **Description**: 
  - Complete Vault service outage
  - Active security breach with data exfiltration
  - Compromised root tokens
  - Multiple system compromise
- **Examples**:
  - All Vault nodes down
  - Confirmed data theft
  - Ransomware attack
  - Nation-state actor involvement

#### **Severity 2 (High)**
- **Response Time**: Within 1 hour
- **Description**:
  - Partial service degradation
  - Suspected security breach
  - Compromised service tokens
  - Single system compromise
- **Examples**:
  - Primary Vault node failure
  - Suspicious authentication patterns
  - Certificate compromise
  - Malware detection

#### **Severity 3 (Medium)**
- **Response Time**: Within 4 hours
- **Description**:
  - Service warnings
  - Security policy violations
  - Performance degradation
  - Minor configuration issues
- **Examples**:
  - High error rates
  - Failed authentication spikes
  - Certificate expiration warnings
  - Audit log anomalies

#### **Severity 4 (Low)**
- **Response Time**: Next business day
- **Description**:
  - Informational alerts
  - Scheduled maintenance
  - Minor policy changes
  - Routine security events
- **Examples**:
  - Successful maintenance
  - Normal policy updates
  - Regular backup completion
  - Training exercises

### Incident Types

#### **Security Incidents**

##### **S1: Data Breach**
- **Definition**: Unauthorized access to sensitive data stored in Vault
- **Indicators**:
  - Unusual data access patterns
  - Large volume data exports
  - Access from suspicious IP addresses
  - Privilege escalation attempts
- **Immediate Actions**:
  1. Isolate affected systems
  2. Revoke suspicious tokens
  3. Enable enhanced logging
  4. Preserve evidence
  5. Notify legal/compliance team

##### **S2: Token Compromise**
- **Definition**: Unauthorized access or theft of Vault tokens
- **Indicators**:
  - Token usage from unexpected locations
  - Unusual API call patterns
  - Failed authentication followed by successful access
  - Token creation spikes
- **Immediate Actions**:
  1. Revoke compromised tokens
  2. Generate emergency tokens
  3. Review token policies
  4. Audit recent token activity
  5. Update affected applications

##### **S3: Unauthorized Access**
- **Definition**: Successful authentication by unauthorized parties
- **Indicators**:
  - Logins from suspicious IPs
  - Off-hours access attempts
  - Unusual user behavior patterns
  - Failed followed by successful logins
- **Immediate Actions**:
  1. Disable compromised accounts
  2. Force password resets
  3. Review access logs
  4. Implement additional MFA
  5. Contact affected users

##### **S4: Malware Infection**
- **Definition**: Detection of malicious software on Vault systems
- **Indicators**:
  - Antivirus alerts
  - Unusual network traffic
  - Unexpected processes
  - System performance degradation
- **Immediate Actions**:
  1. Isolate infected systems
  2. Run comprehensive scans
  3. Analyze malware samples
  4. Check for data exfiltration
  5. Clean or rebuild systems

#### **Operational Incidents**

##### **O1: Service Outage**
- **Definition**: Vault service unavailable or severely degraded
- **Indicators**:
  - HTTP 5xx errors
  - Connection timeouts
  - Health check failures
  - User reports of unavailability
- **Immediate Actions**:
  1. Check system status
  2. Review recent changes
  3. Attempt service restart
  4. Initiate failover if needed
  5. Communicate status to users

##### **O2: Performance Degradation**
- **Definition**: Vault responding slowly or with reduced capacity
- **Indicators**:
  - High response times
  - Increased error rates
  - Resource utilization alerts
  - User performance complaints
- **Immediate Actions**:
  1. Monitor resource usage
  2. Identify bottlenecks
  3. Scale resources if possible
  4. Optimize configurations
  5. Plan capacity upgrades

##### **O3: Storage Issues**
- **Definition**: Problems with Vault's storage backend
- **Indicators**:
  - Disk space alerts
  - I/O errors
  - Raft consensus failures
  - Data corruption warnings
- **Immediate Actions**:
  1. Check storage health
  2. Free up disk space
  3. Repair corrupted data
  4. Consider storage migration
  5. Implement additional monitoring

## Incident Response Process

### Phase 1: Preparation (Ongoing)

#### Pre-Incident Activities
- [ ] Maintain incident response procedures
- [ ] Train response team members
- [ ] Conduct regular drills and exercises
- [ ] Update emergency contact lists
- [ ] Maintain forensic tools and capabilities
- [ ] Review and update playbooks

#### Detection Capabilities
- [ ] 24/7 security monitoring
- [ ] Automated alerting systems
- [ ] Log analysis and correlation
- [ ] User behavior analytics
- [ ] Threat intelligence integration
- [ ] External threat monitoring

### Phase 2: Detection and Analysis (0-15 minutes)

#### Initial Detection
1. **Automated Alerts**
   ```bash
   # Security monitoring system detects anomaly
   ./security-monitor.sh start
   
   # Alert generated and sent to response team
   # Investigation begins immediately
   ```

2. **Manual Detection**
   ```bash
   # User reports issue or anomaly observed
   # Initial triage and classification
   # Escalate to appropriate severity level
   ```

#### Incident Declaration
1. **Assessment Criteria**
   - Scope of impact
   - Type of incident
   - Potential damage
   - Regulatory implications

2. **Declaration Process**
   ```bash
   # Incident Commander declares incident
   # Activate response team
   # Begin documentation
   # Notify stakeholders
   ```

#### Evidence Collection
```bash
# Capture system state immediately
./security-monitor.sh cycle > incident-$(date +%Y%m%d-%H%M%S).log

# Create emergency backup
./emergency-access.sh emergency-backup

# Preserve audit logs
cp /var/log/vault/audit/vault-audit.log /tmp/incident-audit-$(date +%Y%m%d-%H%M%S).log

# Capture network traffic (if configured)
tcpdump -i any -w /tmp/incident-traffic-$(date +%Y%m%d-%H%M%S).pcap
```

### Phase 3: Containment (15-30 minutes)

#### Short-term Containment
1. **Immediate Isolation**
   ```bash
   # Block suspicious IP addresses
   iptables -A INPUT -s <suspicious-ip> -j DROP
   
   # Revoke compromised tokens
   vault write auth/token/revoke-accessor accessor=<accessor-id>
   
   # Disable compromised accounts
   vault delete auth/userpass/users/<username>
   ```

2. **System Isolation**
   ```bash
   # Isolate affected systems from network
   # Maintain forensic access
   # Preserve system state
   ```

#### Long-term Containment
1. **Enhanced Monitoring**
   ```bash
   # Enable detailed audit logging
   vault audit enable -path="detailed" file file_path="/var/log/vault/incident-audit.log"
   
   # Increase monitoring frequency
   ./security-monitor.sh start
   ```

2. **Access Restrictions**
   ```bash
   # Implement additional authentication requirements
   # Restrict network access
   # Enable additional MFA where possible
   ```

### Phase 4: Eradication (30 minutes - 4 hours)

#### Threat Removal
1. **Remove Malicious Elements**
   ```bash
   # Remove malware
   # Delete unauthorized accounts
   # Remove malicious policies
   # Clean infected systems
   ```

2. **Vulnerability Patching**
   ```bash
   # Apply security patches
   # Update configurations
   # Strengthen access controls
   # Implement additional security measures
   ```

#### System Hardening
```bash
# Update all passwords and tokens
./secure-token-manager.sh rotate-all

# Update TLS certificates
./tls-cert-manager.sh rotate

# Review and update policies
vault policy list
vault policy read <policy-name>

# Implement additional security controls
```

### Phase 5: Recovery (1-8 hours)

#### Service Restoration
1. **Gradual Restoration**
   ```bash
   # Start with minimal services
   # Gradually restore functionality
   # Monitor for recurrence
   # Validate system integrity
   ```

2. **Verification Testing**
   ```bash
   # Comprehensive health checks
   ./security-monitor.sh health
   
   # Functionality testing
   vault status
   vault auth list
   vault policy list
   
   # Performance testing
   ./security-monitor.sh performance
   ```

#### Monitoring Enhancement
```bash
# Implement additional monitoring
./security-monitor.sh start

# Enhanced alerting
# Update detection rules
# Increase log retention
```

### Phase 6: Post-Incident Activities (Ongoing)

#### Lessons Learned
1. **Incident Review Meeting**
   - Timeline analysis
   - Response effectiveness
   - Process improvements
   - Tool enhancements

2. **Documentation Update**
   - Update procedures
   - Revise playbooks
   - Improve training materials
   - Share knowledge

#### Follow-up Actions
- [ ] Complete forensic analysis
- [ ] Legal/regulatory notifications
- [ ] Customer communications
- [ ] Insurance claims
- [ ] Vendor notifications
- [ ] Staff training updates

## Incident Response Playbooks

### Playbook 1: Token Compromise Response

#### Scenario
Detection of compromised Vault tokens through unusual usage patterns

#### Response Actions
```bash
# 1. Immediate Containment (0-5 minutes)
./emergency-access.sh incident-response token_compromise

# 2. Evidence Collection (5-15 minutes)
# Capture current token list
vault list auth/token/accessors > /tmp/token-list-$(date +%Y%m%d-%H%M%S).txt

# Review recent audit logs
grep "token" /var/log/vault/audit/vault-audit.log | tail -1000 > /tmp/token-audit-$(date +%Y%m%d-%H%M%S).log

# 3. Analysis (15-30 minutes)
# Identify suspicious patterns
./audit-logger.sh report daily | grep -A5 -B5 "suspicious"

# 4. Eradication (30-60 minutes)
# Revoke all suspicious tokens
# Generate new service tokens
# Update applications with new tokens

# 5. Recovery (1-2 hours)
# Validate all services are working
# Monitor for continued suspicious activity
# Update token policies if needed
```

### Playbook 2: Unauthorized Access Response

#### Scenario
Detection of successful authentication from unauthorized sources

#### Response Actions
```bash
# 1. Immediate Containment (0-5 minutes)
# Block suspicious IP addresses
iptables -A INPUT -s <suspicious-ip> -j DROP

# Disable potentially compromised accounts
vault delete auth/userpass/users/<username>

# 2. Evidence Collection (5-15 minutes)
# Capture authentication logs
grep "auth" /var/log/vault/audit/vault-audit.log | grep $(date +%Y-%m-%d) > /tmp/auth-$(date +%Y%m%d-%H%M%S).log

# 3. Analysis (15-30 minutes)
# Review authentication patterns
# Check for privilege escalation
# Identify accessed secrets

# 4. Eradication (30-60 minutes)
# Reset all potentially compromised credentials
# Update authentication policies
# Implement additional MFA requirements

# 5. Recovery (1-2 hours)
# Restore legitimate user access
# Validate no ongoing unauthorized access
# Update monitoring rules
```

### Playbook 3: Data Breach Response

#### Scenario
Suspected or confirmed unauthorized access to sensitive data

#### Response Actions
```bash
# 1. Immediate Containment (0-15 minutes)
# Isolate affected systems
# Preserve evidence
./emergency-access.sh emergency-backup

# Enable enhanced audit logging
vault audit enable -path="breach" file file_path="/var/log/vault/breach-audit.log"

# 2. Legal/Compliance Notification (15-30 minutes)
# Notify legal counsel
# Prepare regulatory notifications
# Document breach scope and timeline

# 3. Technical Analysis (30 minutes - 2 hours)
# Identify compromised data
# Trace access patterns
# Determine exfiltration methods
# Assess ongoing risks

# 4. Eradication and Recovery (2-8 hours)
# Remove unauthorized access
# Patch vulnerabilities
# Strengthen access controls
# Validate data integrity

# 5. External Communications (As required)
# Customer notifications
# Regulatory reports
# Public disclosures (if required)
# Partner notifications
```

## Communication Procedures

### Internal Communications

#### Incident Team Communications
- **Primary**: Secure chat room (Slack/Teams)
- **Secondary**: Conference bridge
- **Documentation**: Shared incident document
- **Status Updates**: Every 30 minutes during active response

#### Stakeholder Notifications

| Stakeholder | Notification Timing | Method | Information Level |
|-------------|-------------------|---------|------------------|
| **Executive Team** | Within 1 hour (Sev 1-2) | Phone + Email | High-level summary |
| **IT Leadership** | Within 30 minutes | Email + Chat | Technical details |
| **Legal/Compliance** | Within 1 hour (Sev 1-2) | Phone + Email | Full details |
| **HR (if staff involved)** | Within 2 hours | Phone | Relevant details |
| **Facilities (if physical)** | Within 1 hour | Phone | Specific details |

### External Communications

#### Customer Communications
```
Timeline: Within 4 hours of confirmed impact
Method: Email, Portal notifications, Website updates
Approval: Legal, Executive, Communications teams
Content: Impact description, timeline, mitigation steps
```

#### Regulatory Notifications
```
Timeline: As required by regulations (typically 72 hours)
Method: Formal written notification
Approval: Legal counsel
Content: Detailed breach report, impact assessment, remediation plan
```

#### Vendor/Partner Notifications
```
Timeline: Within 24 hours if vendor systems affected
Method: Email to vendor security teams
Content: Relevant technical details, required actions
```

## Tools and Resources

### Incident Response Tools

#### Analysis Tools
- **Log Analysis**: ELK Stack, Splunk
- **Network Analysis**: Wireshark, TCPdump
- **System Analysis**: YARA rules, OSQuery
- **Memory Analysis**: Volatility, WinDbg
- **Disk Analysis**: Autopsy, The Sleuth Kit

#### Communication Tools
- **Primary**: Slack/Microsoft Teams
- **Voice**: Conference bridges
- **Documentation**: Confluence/SharePoint
- **Status Page**: StatusPage.io
- **Mass Notification**: PagerDuty

#### Forensic Tools
- **Imaging**: DD, FTK Imager
- **Analysis**: EnCase, X-Ways
- **Network**: Security Onion
- **Mobile**: Cellebrite, XRY
- **Cloud**: AWS CloudTrail, Azure Security Center

### Documentation Templates

#### Incident Report Template
```markdown
# Incident Report: [YYYY-MM-DD-###]

## Executive Summary
- **Incident Type**: 
- **Severity**: 
- **Start Time**: 
- **End Time**: 
- **Duration**: 
- **Impact**: 

## Timeline
| Time | Action | Owner |
|------|--------|-------|
|      |        |       |

## Root Cause
[Detailed root cause analysis]

## Lessons Learned
[What went well, what could be improved]

## Action Items
| Action | Owner | Due Date | Status |
|--------|-------|----------|--------|
|        |       |          |        |
```

## Testing and Exercises

### Tabletop Exercises

#### Quarterly Exercises
- **Scenario-based discussions**
- **Decision-making practice**
- **Process validation**
- **Team coordination**

#### Annual Full-Scale Exercise
- **Complete incident simulation**
- **All team participation**
- **External stakeholder involvement**
- **Comprehensive after-action review**

### Testing Schedule

| Exercise Type | Frequency | Participants | Duration |
|---------------|-----------|--------------|----------|
| **Tabletop** | Quarterly | Core team | 2 hours |
| **Technical Drill** | Monthly | Technical team | 1 hour |
| **Communication Test** | Monthly | Full team | 30 minutes |
| **Full Simulation** | Annually | All stakeholders | 4 hours |

## Metrics and Reporting

### Key Performance Indicators

#### Response Metrics
- **Mean Time to Detection (MTTD)**: Target < 15 minutes
- **Mean Time to Containment (MTTC)**: Target < 30 minutes
- **Mean Time to Recovery (MTTR)**: Target < 4 hours
- **False Positive Rate**: Target < 5%

#### Quality Metrics
- **Incident Classification Accuracy**: Target > 95%
- **Stakeholder Notification Compliance**: Target 100%
- **Post-Incident Review Completion**: Target 100%
- **Action Item Completion Rate**: Target > 90%

### Reporting Requirements

#### Internal Reports
- **Daily**: Incident status dashboard
- **Weekly**: Incident summary report
- **Monthly**: Trend analysis and metrics
- **Quarterly**: Program effectiveness review

#### External Reports
- **Regulatory**: As required by regulations
- **Customer**: Impact and resolution updates
- **Board**: Quarterly security briefing
- **Audit**: Annual incident response review

---

*This incident response plan is reviewed and updated quarterly to ensure effectiveness and compliance with current threats and regulatory requirements.*