
#!/usr/bin/env bash
set -euo pipefail

### ───────────────────────────────
### 0) CONFIG (edit me)
### ───────────────────────────────
export ORG="rendermani"
export REPO="hashi-nomad-vault-traefik"
export BRANCH="main"
export TRAEFIK_HOST="traefik.example.com"   # <-- change to your real host
export ACME_EMAIL="you@example.com"
export INFRA_PLAN_PATH="Infrastructure-plan.md"

# GitHub token with repo scope (fine-grained preferred). Do NOT paste tokens in logs.
# macOS/Linux: `read -s` avoids echoing; Windows use $env:... in PowerShell.
read -rsp "Enter GH_PAT (repo-scoped): " GH_PAT && echo
export GH_PAT

### ───────────────────────────────
### 1) Install CLIs and add MCP servers
### ───────────────────────────────
# Claude Flow CLI (alpha channel) + Claude Code CLI (if missing)
npm i -g claude-flow@alpha || true
npm i -g @anthropic-ai/claude-code || true

# Add the Claude-Flow MCP server to Claude Code (stdio)  :contentReference[oaicite:1]{index=1}
claude mcp add claude-flow npx claude-flow@alpha mcp start
claude mcp list

# Add the GitHub MCP server (LOCAL via Docker, read-only by policy)  :contentReference[oaicite:2]{index=2}
# The `claude mcp add` command takes a command + args; we wrap env vars with bash -lc.
claude mcp add github bash -lc \
"GITHUB_PERSONAL_ACCESS_TOKEN='${GH_PAT}' GITHUB_TOOLSETS='repos,issues,pull_requests,actions,code_security' GITHUB_READ_ONLY=0 docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN -e GITHUB_TOOLSETS -e GITHUB_READ_ONLY ghcr.io/github/github-mcp-server"
claude mcp list

### ───────────────────────────────
### 2) Persist enterprise rules to memory (agents must follow)
### ───────────────────────────────
# We store “golden rules” so any agent or workflow can fetch them programmatically.  :contentReference[oaicite:3]{index=3}
cat > /tmp/org-rules.json <<'JSON'
{
  "always_use_github_user": "rendermani",
  "always_use_repo": "hashi-nomad-vault-traefik",
  "never_tinker_on_servers": true,
  "on_automation_failure": "spawn analyst+research swarm; never hotfix directly",
  "stick_to_plan": true,
  "pause_and_escalate_if_plan_breaks": true,
  "mcp:preferred": ["claude-flow","github"],
  "security": {
    "secrets_handling": "no tokens in logs or code; fine-grained PAT; branch protections",
    "prod_access": "via GitHub Actions + SSH tunnels only; no ad-hoc SSH"
  }
}
JSON

claude-flow memory usage \
  --action store \
  --namespace "governance" \
  --key "org-rules" \
  --value "$(cat /tmp/org-rules.json)"

### ───────────────────────────────
### 3) Initialize a swarm and baseline monitors
### ───────────────────────────────
# Hierarchical, up to 48 agents, shared memory pool.  :contentReference[oaicite:4]{index=4}
SWARM_ID=$(claude-flow swarm init --topology hierarchical --max-agents 48 --name "hetzner-nomad-swarm" --memory-pool 512 | jq -r '.swarmId')
echo "Swarm: $SWARM_ID"

# Optional: watch health in another terminal  :contentReference[oaicite:5]{index=5}
# claude-flow swarm status "$SWARM_ID" --metrics --watch

### ───────────────────────────────
### 4) Spawn coordinators & governance
### ───────────────────────────────
# Agent types per wiki (coordinator/orchestrator/memory smart-agents).  :contentReference[oaicite:6]{index=6}
claude-flow agent spawn coordinator           --name "task-orchestrator"      --swarm-id "$SWARM_ID"
claude-flow agent spawn coordinator           --name "smart-agent"            --swarm-id "$SWARM_ID"
claude-flow agent spawn coordinator           --name "coordinator-swarm-init" --swarm-id "$SWARM_ID"
claude-flow agent spawn analyst               --name "memory-coordinator"     --swarm-id "$SWARM_ID"
claude-flow agent spawn reviewer              --name "compliance-officer-1"   --swarm-id "$SWARM_ID"
claude-flow agent spawn reviewer              --name "compliance-officer-2"   --swarm-id "$SWARM_ID"

### ───────────────────────────────
### 5) Spawn coders (enterprise-level, no server tinkering)
### ───────────────────────────────
# Specialize by capabilities to map onto your repo’s Ansible/Terraform/Nomad/Vault code.  :contentReference[oaicite:7]{index=7}
for NAME in coder-ansible coder-terraform coder-nomad coder-vault coder-consul coder-traefik coder-ghactions coder-docs; do
  claude-flow agent spawn coder --name "$NAME" \
    --capabilities "ansible,terraform,nomad,vault,consul,traefik,github-actions" \
    --memory-access read-write \
    --swarm-id "$SWARM_ID"
done

### ───────────────────────────────
### 6) Spawn testing & validation (2 per area) + production validator
### ───────────────────────────────
# Areas: vault, nomad, consul, traefik, e2e, security, network, ci-pipeline  :contentReference[oaicite:8]{index=8}
for AREA in vault nomad consul traefik e2e security network ci; do
  claude-flow agent spawn tester --name "tester-${AREA}-1" --swarm-id "$SWARM_ID"
  claude-flow agent spawn tester --name "tester-${AREA}-2" --swarm-id "$SWARM_ID"
done
# Dedicated production validator (no mocks; real endpoints + SSL checks).  :contentReference[oaicite:9]{index=9}
claude-flow agent spawn tester --name "production-validator" --swarm-id "$SWARM_ID"

### ───────────────────────────────
### 7) Spawn architecture & deep analysis + CI/CD & GH integration
### ───────────────────────────────
claude-flow agent spawn architect --name "system-architect"        --swarm-id "$SWARM_ID"
claude-flow agent spawn analyst   --name "code-analyzer"           --swarm-id "$SWARM_ID"
claude-flow agent spawn reviewer  --name "analyze-code-quality"    --swarm-id "$SWARM_ID"
claude-flow agent spawn coder     --name "cicd-engineer"           --swarm-id "$SWARM_ID"
claude-flow agent spawn coordinator --name "ops-cicd-github"       --swarm-id "$SWARM_ID"

### ───────────────────────────────
### 8) Auto-agent (enterprise) to round us into ~30–40 agents
### ───────────────────────────────
# Will add extra researchers/analysts/testers automatically if needed.  :contentReference[oaicite:10]{index=10}
claude-flow automation auto-agent --task-complexity enterprise --swarm-id "$SWARM_ID"

### ───────────────────────────────
### 9) Prepare an executable workflow that:
###    - reads Infrastructure-plan.md
###    - adds prod validation (no “TRAEFIK DEFAULT CERTIFICATE”)
###    - scales tests across Vault/Nomad/Consul/Traefik
###    - fixes the 8090 monitoring webapp in PARALLEL
### ───────────────────────────────
cat > /tmp/enterprise-setup.json <<JSON
{
  "name": "Hetzner Nomad-Vault-Consul-Traefik Enterprise Setup",
  "metadata": {
    "repo": "${ORG}/${REPO}",
    "branch": "${BRANCH}",
    "infraPlanPath": "${INFRA_PLAN_PATH}",
    "traefikHost": "${TRAEFIK_HOST}",
    "acmeEmail": "${ACME_EMAIL}",
    "governanceMemoryKey": "org-rules"
  },
  "agents": [
    {"id":"orchestrator","type":"coordinator","name":"task-orchestrator"},
    {"id":"smart","type":"coordinator","name":"smart-agent"},
    {"id":"swarm-init","type":"coordinator","name":"coordinator-swarm-init"},
    {"id":"mem","type":"analyst","name":"memory-coordinator"},

    {"id":"arch","type":"architect","name":"system-architect"},
    {"id":"analysis","type":"analyst","name":"code-analyzer"},
    {"id":"review","type":"reviewer","name":"analyze-code-quality"},

    {"id":"dev-ansible","type":"coder","name":"coder-ansible"},
    {"id":"dev-terraform","type":"coder","name":"coder-terraform"},
    {"id":"dev-nomad","type":"coder","name":"coder-nomad"},
    {"id":"dev-vault","type":"coder","name":"coder-vault"},
    {"id":"dev-consul","type":"coder","name":"coder-consul"},
    {"id":"dev-traefik","type":"coder","name":"coder-traefik"},
    {"id":"dev-gha","type":"coder","name":"coder-ghactions"},
    {"id":"dev-docs","type":"coder","name":"coder-docs"},

    {"id":"gov-1","type":"reviewer","name":"compliance-officer-1"},
    {"id":"gov-2","type":"reviewer","name":"compliance-officer-2"},

    {"id":"pv","type":"tester","name":"production-validator"},

    {"id":"t-vault-1","type":"tester","name":"tester-vault-1"},
    {"id":"t-vault-2","type":"tester","name":"tester-vault-2"},
    {"id":"t-nomad-1","type":"tester","name":"tester-nomad-1"},
    {"id":"t-nomad-2","type":"tester","name":"tester-nomad-2"},
    {"id":"t-consul-1","type":"tester","name":"tester-consul-1"},
    {"id":"t-consul-2","type":"tester","name":"tester-consul-2"},
    {"id":"t-traefik-1","type":"tester","name":"tester-traefik-1"},
    {"id":"t-traefik-2","type":"tester","name":"tester-traefik-2"},
    {"id":"t-e2e-1","type":"tester","name":"tester-e2e-1"},
    {"id":"t-e2e-2","type":"tester","name":"tester-e2e-2"},
    {"id":"t-sec-1","type":"tester","name":"tester-security-1"},
    {"id":"t-sec-2","type":"tester","name":"tester-security-2"},
    {"id":"t-net-1","type":"tester","name":"tester-network-1"},
    {"id":"t-net-2","type":"tester","name":"tester-network-2"},
    {"id":"t-ci-1","type":"tester","name":"tester-ci-1"},
    {"id":"t-ci-2","type":"tester","name":"tester-ci-2"},

    {"id":"cicd","type":"coder","name":"cicd-engineer"},
    {"id":"ops-github","type":"coordinator","name":"ops-cicd-github"},

    {"id":"migr","type":"coordinator","name":"migration-plan"},
    {"id":"auto","type":"coordinator","name":"automation-smart-agent"}
  ],
  "policies": {
    "mustReadMemoryKey": "governance/org-rules",
    "neverServerTinker": true,
    "mustUseRepoOwner": "rendermani",
    "onFailure": "spawn analyst+research sub-swarm and STOP; open a discussion to user"
  },
  "tasks": [
    {
      "id": "read-plan",
      "name": "Ingest Infrastructure-plan.md",
      "assignTo": "smart",
      "description": "Using GitHub MCP, read ${INFRA_PLAN_PATH} in ${ORG}/${REPO}@${BRANCH} and summarize key deploy steps, secrets flow, and validations."
    },
    {
      "id": "ci-validators",
      "name": "Create GitHub Actions validators",
      "assignTo": "dev-gha",
      "depends": ["read-plan"],
      "description": "Add workflows: validate-traefik-ssl.yml (curl -vkI https://${TRAEFIK_HOST} ensure no 'TRAEFIK DEFAULT CERTIFICATE'); smoke-consul-nomad-vault.yml with SSH tunnels & API health; deploy.yml dependsOn configure.yml."
    },
    {
      "id": "prod-check",
      "name": "Run production validator (no mocks)",
      "assignTo": "pv",
      "depends": ["ci-validators"],
      "description": "Hit https://${TRAEFIK_HOST}/dashboard/ with auth header from Vault KV via Nomad pack; assert cert CN!=TRAEFIK DEFAULT CERTIFICATE; check 200/302 and TLS issuer != Traefik Default."
    },
    {
      "id": "area-tests",
      "name": "Parallel area tests",
      "assignTo": ["t-vault-1","t-vault-2","t-nomad-1","t-nomad-2","t-consul-1","t-consul-2","t-traefik-1","t-traefik-2","t-e2e-1","t-e2e-2","t-sec-1","t-sec-2","t-net-1","t-net-2","t-ci-1","t-ci-2"],
      "depends": ["read-plan"],
      "description": "Author and run integration tests: Vault (init/unseal idempotence; approle; kvv2 reads), Nomad (jobs healthy; variables present), Consul (ACL policies; catalog), Traefik (ACME HTTP-01 OK; dashboard fenced), e2e (blue/green job revert), security (UFW 22/80/443 only; localhost bindings), network (SSH tunnel checks), ci (workflows green)."
    },
    {
      "id": "8090-fix",
      "name": "Fix monitoring webapp on :8090",
      "assignTo": ["dev-ansible","dev-terraform","t-e2e-1","t-e2e-2"],
      "parallel": true,
      "description": "Diagnose Docker container on port 8090: add healthchecks, wire logs and progress bars; create PR with Dockerfile/compose fixes and Grafana/Promtail scraping. Tests must validate /health and chart rendering."
    },
    {
      "id": "governance",
      "name": "Compliance gate",
      "assignTo": ["gov-1","gov-2","review"],
      "depends": ["ci-validators","area-tests","8090-fix"],
      "description": "Run code review & compliance checks; enforce rules (no server tinkering; only GitHub workflows modify infra)."
    }
  ],
  "execution": {
    "mode": "non-interactive",
    "strategy": "parallel",
    "maxConcurrency": 8,
    "errorHandling": "fail-fast",
    "checkpoint": true,
    "memorySync": true
  }
}
JSON

### ───────────────────────────────
### 10) Launch the enterprise workflow (non-interactive)
### ───────────────────────────────
# The automation command executes the JSON workflow; use stream-json for rich piping if you like.  :contentReference[oaicite:11]{index=11}
claude-flow automation run-workflow /tmp/enterprise-setup.json \
  --claude \
  --non-interactive \
  --output-format stream-json \
  --variables "{\"repo\":\"${ORG}/${REPO}\",\"branch\":\"${BRANCH}\",\"traefikHost\":\"${TRAEFIK_HOST}\"}"

### ───────────────────────────────
### 11) Repo analysis & visibility
### ───────────────────────────────
# Have agents analyze the repo via GitHub MCP with security focus.  :contentReference[oaicite:12]{index=12}
claude-flow github repo analyze "${ORG}/${REPO}" --analysis-type security --depth deep

### ───────────────────────────────
### 12) Real-time monitoring & scaling
### ───────────────────────────────
claude-flow agent list --swarm-id "$SWARM_ID" --detailed
claude-flow swarm status "$SWARM_ID" --metrics
# If you need more parallelism in the middle of a run:  :contentReference[oaicite:13]{index=13}
# claude-flow swarm scale 40 --swarm-id "$SWARM_ID" --strategy adaptive --min 20 --max 48

### ───────────────────────────────
### 13) Neural self-optimization (optional)
### ───────────────────────────────
# Train a small coordination pattern from task outcomes to self-tune agent mix.  :contentReference[oaicite:14]{index=14}
claude-flow neural train --pattern-type coordination --training-data "./metrics/workflow-outcomes.json" --epochs 50 --model-id "coord-v1" || true
claude-flow neural status coord-v1 --performance || true

### ───────────────────────────────
### 14) If anything FAILS: spawn analyst+research team automatically
### ───────────────────────────────
# (You can re-run this anytime to open a failure investigation swarm.)
claude-flow automation smart-spawn --requirement "post-failure root-cause analysis for ${ORG}/${REPO}" --max-agents 6

echo "✅ Enterprise setup commands executed."
