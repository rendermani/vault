# Infrastructure as Code Compliance Procedures

## 📋 Overview

This document outlines the mandatory procedures for maintaining Infrastructure as Code (IaC) compliance in the Vault Progress Server project.

## 🚨 Critical Compliance Rules

### Rule 1: NO SSH WORKAROUNDS
**NEVER do SSH workarounds if automation is failing**

**❌ Prohibited Actions:**
```bash
# NEVER do these:
ssh user@server 'sudo systemctl start vault'
ssh user@server 'sudo systemctl restart nginx' 
ssh -t user@server 'sudo vim /etc/vault.d/vault.hcl'
scp config.hcl user@server:/opt/vault/config/
```

**✅ Compliant Alternatives:**
```bash
# Always use automation:
ansible-playbook -i inventory vault-service.yml --tags=restart
ansible-playbook -i inventory vault-config.yml
terraform apply -var-file=production.tfvars
nomad-pack run vault-cluster
```

**If Automation Fails:**
1. **DO NOT** use SSH workarounds
2. **DO** spawn analysis agents immediately:
   ```bash
   # Spawn research agents to investigate
   node spawn-agent.js researcher "Investigate vault service failure"
   node spawn-agent.js analyst "Analyze system logs and dependencies" 
   node spawn-agent.js system-architect "Design fix for automation failure"
   ```

### Rule 2: NO DIRECT CONFIG CHANGES
**NEVER change config files directly on the server**

**❌ Prohibited Actions:**
```bash
# NEVER edit configs directly:
ssh server 'sudo vim /etc/vault.d/vault.hcl'
ssh server 'sudo nano /etc/systemd/system/vault.service'
scp local-config.hcl server:/opt/vault/config/
```

**✅ Compliant Process:**
1. Update configuration in source control
2. Commit changes to git repository
3. Apply through automation:
   ```bash
   git add ansible/roles/vault/templates/vault.hcl.j2
   git commit -m "Update vault configuration"
   ansible-playbook -i inventory vault-config.yml
   ```

### Rule 3: STICK TO THE PLAN
**ALWAYS follow the planned sequence: Ansible → Terraform → Nomad Pack**

**Phase 1: Ansible Bootstrap**
- Server preparation
- Package installation
- Basic security configuration
- Service account creation

**Phase 2: Terraform Infrastructure**  
- Cloud resource provisioning
- Network configuration
- Security groups and firewall rules
- Load balancer setup

**Phase 3: Nomad Pack Deployment**
- Application deployment
- Service orchestration
- Health monitoring
- Auto-scaling configuration

**Deviation Procedures:**
- If deviation is necessary, document justification
- Get approval from Lead Engineer
- Update project plan accordingly
- Maintain audit trail

### Rule 4: SPAWN RESEARCHERS ON FAILURE
**ALWAYS spawn researchers and analysts if automation is failing**

**Automatic Triggers:**
- Ansible playbook failures
- Terraform plan/apply errors
- Nomad Pack deployment issues
- Service health check failures

**Required Agents:**
```bash
# Must spawn these agents for any automation failure:
node spawn-agent.js researcher "Root cause analysis of [specific failure]"
node spawn-agent.js analyst "System impact assessment" 
node spawn-agent.js system-architect "Design compliant solution"
```

### Rule 5: ONE BUTTON DEPLOYMENT
**Enforce minimal manual interaction deployment**

**Requirements:**
- Single command deployment: `make deploy`
- Idempotent operations (can run multiple times safely)
- Automated rollback capability
- Comprehensive health checks
- Zero-downtime deployments

## 🔍 Monitoring and Enforcement

### Automated Monitoring
The Compliance Officer system automatically monitors for:
- File system changes in critical directories
- Prohibited command executions
- Process monitoring for manual interventions
- Automation pipeline health

### File System Watchers
Monitored directories:
- `/etc/vault.d/` - Vault configuration
- `/opt/vault/` - Vault installation
- `/etc/systemd/system/` - Service definitions
- `/etc/nginx/` - Web server configuration
- `/etc/ssl/` - SSL certificates

### Command Filtering
Prohibited patterns automatically detected:
- `ssh.*systemctl`
- `ssh.*service`  
- `ssh.*vim /etc/`
- `scp.*config`
- `sudo.*without.*ansible`

## 🚨 Violation Response Procedures

### Critical Violations (BLOCK OPERATION)
1. **Immediate Action:** Stop the operation
2. **Alert:** Notify Lead Engineer and Security Officer
3. **Documentation:** Record violation details
4. **Resolution:** Use compliant automation instead

### High Priority Violations (REQUIRE JUSTIFICATION)
1. **Document:** Reason for deviation
2. **Approve:** Get Lead Engineer approval
3. **Timeline:** Set deadline for compliance correction
4. **Follow-up:** Ensure automation is fixed

### Medium Priority Violations (AUTO SPAWN AGENTS)
1. **Automatic:** Spawn analysis agents
2. **Investigation:** Root cause analysis
3. **Solution:** Design compliant alternative
4. **Implementation:** Apply fix through automation

## 📊 Compliance Reporting

### Daily Reports
- Violation count and severity
- Compliance score trends
- Automation success rates
- Agent spawn statistics

### Weekly Reviews
- Compliance procedure effectiveness
- Team training needs assessment
- Automation improvement opportunities
- Incident post-mortems

### Monthly Audits
- Full compliance assessment
- Policy updates if needed
- Team certification status
- Process optimization review

## 🚀 Emergency Procedures

### Emergency Access (Break Glass)
**Only when automation is completely broken**

**Authorization Required:**
- Lead Engineer approval
- Security Officer approval
- Maximum 1-hour window

**Mandatory Follow-up:**
1. Document all emergency changes
2. Reverse changes through automation within 24 hours
3. Conduct post-incident review
4. Update automation to prevent recurrence

### Emergency Steps:
1. **Declare Emergency:** Notify compliance officer
2. **Document Intent:** What needs to be fixed manually
3. **Perform Action:** Minimal necessary changes only
4. **Immediate Cleanup:** Remove emergency access
5. **Automation Fix:** Implement proper automation within 24h

## 👥 Team Responsibilities

### All Team Members
- Follow IaC principles at all times
- Use automation for all changes
- Report automation failures immediately
- Never use SSH workarounds

### Lead Engineer
- Approve any plan deviations
- Review compliance reports
- Ensure team follows procedures
- Emergency access authorization

### DevOps Engineers
- Maintain automation pipelines
- Fix automation failures promptly
- Monitor system health
- Improve deployment processes

### Security Officer
- Review security compliance
- Audit access controls
- Approve emergency procedures
- Monitor violation reports

## 🎓 Training Requirements

### Required Training
- IaC Principles and Best Practices
- Ansible Playbook Development
- Terraform Configuration Management
- Nomad Pack Deployment Strategies
- Compliance Officer System Usage

### Certification
- All team members must pass IaC certification
- Quarterly recertification required
- No server access without valid certification
- Training records maintained in compliance system

### Training Schedule
- **New Team Members:** Within first week
- **Existing Team:** Quarterly updates
- **After Violations:** Immediate remedial training
- **New Tool/Process:** Before implementation

## 📞 Escalation Procedures

### Level 1: Automated Detection
- Compliance Officer system alerts
- Automatic agent spawning
- Real-time violation logging

### Level 2: Team Resolution
- Team Lead notification
- Analysis agent investigation
- Compliant solution implementation

### Level 3: Management Escalation
- Lead Engineer involvement
- Process review and adjustment
- Additional training if needed

### Level 4: Emergency Response
- Security Officer activation
- Emergency access procedures
- Post-incident analysis

## 📈 Continuous Improvement

### Metrics Tracking
- Compliance score trends
- Violation frequency analysis
- Automation success rates
- Recovery time objectives

### Process Optimization
- Regular procedure reviews
- Automation enhancement opportunities
- Tool evaluation and adoption
- Team feedback integration

### Success Criteria
- **Compliance Score:** >98%
- **Automation Coverage:** 100%
- **Manual Interventions:** <1 per month
- **Recovery Time:** <5 minutes

---

**Remember: "One button deployment with minimal manual interaction"**

*For questions or clarification, contact the Compliance Officer system or Lead Engineer.*