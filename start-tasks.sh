#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# 0) EDIT ME
# ─────────────────────────────────────────────────────────────
export SWARM_ID="hetzner-nomad-swarm"   # your existing hive/swarm id
export ORG="rendermani"
export REPO="vault"
export BRANCH="main"
export TRAEFIK_HOST="traefik.cloudya.d"     # <-- set real FQDN
export ACME_EMAIL="ml@webrender.de"
export INFRA_PLAN_PATH="Infrastructure-plan.md"

# Quick sanity — show agents so you can confirm names
claude-flow agent list --json | jq -r '.[] | "\(.type)\t\(.name)\t\(.id)"' || true

# Helper to shorten command lines (title, assignee, priority)
task() {
  local title="$1"; local assignee="$2"; local prio="${3:-7}"
  claude-flow task create "$title" \
    --assign "$assignee" \
    --priority "$prio" \
    --swarm-id "$SWARM_ID"
}

# ─────────────────────────────────────────────────────────────
# 1) PLAN INGEST + COORDINATION
# ─────────────────────────────────────────────────────────────
task "Ingest ${ORG}/${REPO}@${BRANCH}:${INFRA_PLAN_PATH} and summarize deploy flow, secrets paths, acceptance criteria. Output a checklist and risks." "smart-agent" 9
task "Set working context to ${ORG}/${REPO} (branch ${BRANCH}); enforce governance rules (no server tinkering, always GitHub ops) across all tasks." "task-orchestrator" 9

# ─────────────────────────────────────────────────────────────
# 2) CI VALIDATORS (PRs only; no server tinkering)
# ─────────────────────────────────────────────────────────────
task "Create PR: add .github/workflows/validate-traefik-ssl.yml; assert HTTPS OK, not 'TRAEFIK DEFAULT CERTIFICATE', dashboard 401/403 unauth + 2xx/3xx auth." "coder-ghactions" 9
task "Create PR: add .github/workflows/smoke-consul-nomad-vault.yml with SSH tunnels (127.0.0.1:8500/4646/8200) and health checks; upload artifacts." "coder-ghactions" 9
task "Wire both workflows to a 'production' environment; require compliance reviewers; block deploy jobs until these pass." "ops-cicd-github" 8

# ─────────────────────────────────────────────────────────────
# 3) PRODUCTION VALIDATOR (real endpoints, no mocks)
# ─────────────────────────────────────────────────────────────
task "Run PROD validator against https://${TRAEFIK_HOST}/; reject if any cert contains 'TRAEFIK DEFAULT CERTIFICATE'; verify redirect HTTP→HTTPS; verify dashboard auth." "production-validator" 9

# ─────────────────────────────────────────────────────────────
# 4) PARALL
