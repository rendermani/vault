# REPO: hashi-nomad-vault-traefik  (Hetzner root server, SSH-only)

==> FILE: README.md
# Hashi Nomad + Vault + Traefik (Hetzner Root Server, SSH-only)

- **Ansible**: bootstrap Consul + Nomad (no vault{}), start Vault (raft) as Nomad job bound to localhost
- **Terraform**: enable Vault KV v2, AppRole, Nomad secrets engine, Consul ACLs, Nomad Variables
- **Nomad Pack**: Traefik with Vault-Agent sidecar (reads htpasswd, Consul token from Vault KV; AppRole from Nomad Variable)
- **UFW**: open 22/80/443 only; Consul/Nomad/Vault UIs bound to 127.0.0.1 (use SSH tunnels)

## Phases
1) `bootstrap.yml` → Consul + Nomad + Vault job (no Nomad↔Vault yet)
2) **On server**: `consul acl bootstrap`, `nomad acl bootstrap`, `vault operator init/unseal`
3) `terraform apply` → config Vault/Nomad/Consul; create AppRole + Nomad Variable
4) `site.yml` → enable Nomad `vault {}` and restart
5) `nomad-pack run` → deploy Traefik (canary + auto-revert)

==> FILE: .gitignore
infra/terraform/.terraform/
infra/terraform/terraform.tfstate*
*.auto.tfvars
*.secrets
.env
*.retry
**/.DS_Store

==> FILE: .github/workflows/provision.yml
name: provision
on: [workflow_dispatch]

jobs:
  ansible:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.SSH_KEY }}
      - name: Add host key
        run: ssh-keyscan -H ${{ secrets.SERVER_HOST }} >> ~/.ssh/known_hosts
      - name: Install Ansible
        run: sudo apt-get update && sudo apt-get install -y ansible
      - name: Bootstrap (Phase A)
        run: |
          ansible-playbook \
            -i infra/ansible/inventories/production/hosts.ini \
            infra/ansible/playbooks/bootstrap.yml

==> FILE: .github/workflows/configure.yml
name: configure
on: [workflow_dispatch]

jobs:
  terraform:
    runs-on: ubuntu-latest
    env:
      VAULT_ADDR: http://127.0.0.1:8200
      NOMAD_ADDR: http://127.0.0.1:4646
      CONSUL_ADDR: http://127.0.0.1:8500
    steps:
      - uses: actions/checkout@v4

      - name: Start SSH tunnels to server (Vault/Nomad/Consul)
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.SSH_KEY }}
      - name: Add host key
        run: ssh-keyscan -H ${{ secrets.SERVER_HOST }} >> ~/.ssh/known_hosts
      - name: Create tunnels
        run: |
          nohup ssh -o StrictHostKeyChecking=no -N \
            -L 8200:127.0.0.1:8200 \
            -L 8500:127.0.0.1:8500 \
            -L 4646:127.0.0.1:4646 \
            ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }} &
          sleep 3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.7.5 }

      - name: Terraform init
        working-directory: infra/terraform
        run: terraform init

      - name: Terraform apply
        working-directory: infra/terraform
        env:
          TF_VAR_vault_addr: http://127.0.0.1:8200
          TF_VAR_vault_bootstrap_token: ${{ secrets.VAULT_ROOT_TOKEN }}
          TF_VAR_nomad_addr: http://127.0.0.1:4646
          TF_VAR_nomad_bootstrap_token: ${{ secrets.NOMAD_MGMT_TOKEN }}
          TF_VAR_consul_addr: http://127.0.0.1:8500
          TF_VAR_consul_bootstrap_token: ${{ secrets.CONSUL_MGMT_TOKEN }}
          TF_VAR_traefik_htpasswd: ${{ secrets.TRAEFIK_HTPASSWD }}
        run: terraform apply -auto-approve

==> FILE: .github/workflows/deploy.yml
name: deploy
on:
  workflow_dispatch:
  push:
    paths: [ 'nomad/packs/**' ]

jobs:
  deploy-nomad:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: webfactory/ssh-agent@v0.9.0
        with: { ssh-private-key: ${{ secrets.SSH_KEY }} }
      - run: ssh-keyscan -H ${{ secrets.SERVER_HOST }} >> ~/.ssh/known_hosts
      - name: Install nomad-pack
        run: |
          curl -fsSL https://releases.hashicorp.com/nomad-pack/0.1.4/nomad-pack_0.1.4_linux_amd64.zip -o /tmp/np.zip
          sudo unzip -o /tmp/np.zip -d /usr/local/bin
      - name: Push pack & run
        run: |
          ssh ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }} "mkdir -p ~/traefik-pack"
          rsync -az nomad/packs/traefik/ ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }}:~/traefik-pack/
          ssh ${{ secrets.SERVER_USER }}@${{ secrets.SERVER_HOST }} \
            "nomad-pack run ~/traefik-pack -var hostname=${{ secrets.TRAEFIK_HOST }} -var acme_email=${{ secrets.ACME_EMAIL }}"

==> FILE: infra/ansible/inventories/production/hosts.ini
[nomad_servers]
your.server.fqdn ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3

==> FILE: infra/ansible/inventories/production/group_vars/all.yml
nomad_vault_enabled: false

nomad_version: "1.8.3"
consul_version: "1.19.2"
vault_version:  "1.17.5"

# Optional: restrict SSH (e.g., "1.2.3.4/32")
# admin_ipv4: "REPLACE_ME/32"

hashi_base_dir: /etc/hashicorp
consul_dir:     "{{ hashi_base_dir }}/consul"
nomad_dir:      "{{ hashi_base_dir }}/nomad"
vault_dir:      "{{ hashi_base_dir }}/vault"
secrets_dir:    /opt/secrets

consul_gossip_key: "REPLACE_ME"
nomad_gossip_key:  "REPLACE_ME"

vault_addr: "http://127.0.0.1:8200"
vault_kv_path: "kv/data/traefik"

traefik_host: "traefik.example.com"
acme_email:   "you@example.com"

==> FILE: infra/ansible/playbooks/bootstrap.yml
- hosts: all
  become: true
  roles:
    - base
    - firewall
    - docker
    - consul
    - nomad       # starts without vault{} integration
    - vault       # Vault job on Nomad (raft, localhost)

==> FILE: infra/ansible/playbooks/site.yml
- hosts: all
  become: true
  vars:
    nomad_vault_enabled: true
  roles:
    - nomad       # flips vault{} on and restarts Nomad
    - vault_agent # ensure Vault binary present (agent runs in job)

==> FILE: infra/ansible/roles/base/tasks/main.yml
- name: Ensure base packages
  apt:
    name: [curl, unzip, jq, gnupg, ca-certificates]
    state: present
    update_cache: yes

- name: Create base directories
  file:
    path: "{{ item }}"
    state: directory
    mode: "0755"
  loop:
    - "{{ hashi_base_dir }}"
    - "{{ consul_dir }}"
    - "{{ nomad_dir }}"
    - "{{ vault_dir }}"
    - "{{ secrets_dir }}"

==> FILE: infra/ansible/roles/firewall/tasks/main.yml
- name: Install ufw
  apt: { name: ufw, state: present }

- name: Allow SSH (optionally restrict to admin_ipv4)
  ufw:
    rule: allow
    port: "22"
    proto: tcp
    src: "{{ admin_ipv4 | default(omit) }}"

- name: Allow HTTP/HTTPS
  ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop: [80, 443]

- name: Enable firewall (deny by default)
  ufw: { state: enabled, policy: deny }

==> FILE: infra/ansible/roles/docker/tasks/main.yml
- name: Install Docker Engine (Debian/Ubuntu)
  shell: |
    set -e
    if ! command -v docker >/dev/null; then
      apt-get update
      apt-get install -y ca-certificates curl gnupg lsb-release
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io
      systemctl enable --now docker
    fi

==> FILE: infra/ansible/roles/consul/tasks/main.yml
- name: Install Consul
  shell: |
    set -e
    if ! command -v consul >/dev/null; then
      curl -fsSL https://releases.hashicorp.com/consul/{{ consul_version }}/consul_{{ consul_version }}_linux_amd64.zip -o /tmp/consul.zip
      unzip -o /tmp/consul.zip -d /usr/local/bin
    fi

- name: Consul data dir
  file: { path: /var/lib/consul, state: directory, mode: "0755" }

- name: Write consul.hcl (localhost)
  copy:
    dest: /etc/consul.hcl
    mode: "0644"
    content: |
      server           = true
      bootstrap_expect = 1
      data_dir         = "/var/lib/consul"
      encrypt          = "{{ consul_gossip_key }}"
      addresses { http = "127.0.0.1" }
      ui               = true

- name: Systemd unit
  copy:
    dest: /etc/systemd/system/consul.service
    mode: "0644"
    content: |
      [Unit]
      Description=Consul
      After=network-online.target
      [Service]
      ExecStart=/usr/local/bin/consul agent -config-file=/etc/consul.hcl
      Restart=on-failure
      [Install]
      WantedBy=multi-user.target

- systemd: { name: consul, daemon_reload: yes, state: started, enabled: yes }

==> FILE: infra/ansible/roles/nomad/templates/nomad.hcl.j2
log_level = "INFO"
data_dir  = "/var/lib/nomad"
bind_addr = "0.0.0.0"

server { enabled = true; bootstrap_expect = 1 }

client {
  enabled = true

  host_volume "vaultdata" {
    path      = "/var/lib/vault"
    read_only = false
  }
  host_volume "traefik-acme" {
    path      = "/var/lib/traefik"
    read_only = false
  }
}

addresses { http = "127.0.0.1" }

consul {
  address = "127.0.0.1:8500"
  # token   = "<CONSUL_TOKEN_FOR_NOMAD_CLIENT>"
}

tls { http = false; rpc = false }

plugin "raw_exec" { config { enabled = true } }

{% if nomad_vault_enabled %}
vault {
  enabled = true
  address = "{{ vault_addr }}"
}
{% endif %}

==> FILE: infra/ansible/roles/nomad/tasks/main.yml
- name: Install Nomad
  shell: |
    set -e
    if ! command -v nomad >/dev/null; then
      curl -fsSL https://releases.hashicorp.com/nomad/{{ nomad_version }}/nomad_{{ nomad_version }}_linux_amd64.zip -o /tmp/nomad.zip
      unzip -o /tmp/nomad.zip -d /usr/local/bin
    fi

- name: Ensure data dirs
  file: { path: /var/lib/nomad,  state: directory, mode: "0755" }
- file: { path: /var/lib/vault,  state: directory, mode: "0755" }
- file: { path: /var/lib/traefik, state: directory, mode: "0755" }

- name: Write config
  template: { src: nomad.hcl.j2, dest: /etc/nomad.hcl, mode: "0644" }
  notify: Restart Nomad

- name: Systemd unit
  copy:
    dest: /etc/systemd/system/nomad.service
    mode: "0644"
    content: |
      [Unit]
      Description=Nomad
      After=network-online.target consul.service docker.service
      [Service]
      ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.hcl
      Restart=on-failure
      [Install]
      WantedBy=multi-user.target

- systemd: { name: nomad, daemon_reload: yes, state: started, enabled: yes }

==> FILE: infra/ansible/roles/nomad/handlers/main.yml
- name: Restart Nomad
  systemd: { name: nomad, state: restarted }

==> FILE: infra/ansible/roles/vault/tasks/main.yml
- name: Install Vault binary
  shell: |
    set -e
    if ! command -v vault >/dev/null; then
      curl -fsSL https://releases.hashicorp.com/vault/{{ vault_version }}/vault_{{ vault_version }}_linux_amd64.zip -o /tmp/vault.zip
      unzip -o /tmp/vault.zip -d /usr/local/bin
    fi

- name: Submit Vault job (raft; localhost listener)
  shell: |
    cat >/tmp/vault.nomad <<'EOF'
    job "vault" {
      datacenters = ["dc1"]
      type = "service"
      group "vault" {
        network { port "http" { static = 8200; to = 8200 } }
        volume "vaultdata" { type="host"; source="vaultdata"; read_only=false }

        task "vault" {
          driver = "raw_exec"
          config { command = "/usr/local/bin/vault"; args = ["server","-config=/local/vault.hcl"] }
          template {
            destination = "local/vault.hcl"
            data = <<-EOT
            storage "raft" { path = "/var/lib/vault"; node_id = "vault-1" }
            listener "tcp" { address = "127.0.0.1:8200" tls_disable = "true" }
            api_addr = "http://127.0.0.1:8200"
            cluster_addr = "http://127.0.0.1:8201"
            disable_mlock = true
            EOT
          }
          resources { cpu=200; memory=256 }
          volume_mount { volume="vaultdata"; destination="/var/lib/vault" }
          service { name="vault"; port="http"; check { type="http"; path="/v1/sys/health"; interval="5s"; timeout="2s" } }
        }
      }
      volume "vaultdata" { type="host"; source="vaultdata"; read_only=false }
    }
    EOF
    nomad job run /tmp/vault.nomad

==> FILE: infra/ansible/roles/vault_agent/tasks/main.yml
- name: Ensure Vault binary exists for agent
  shell: |
    set -e
    if ! command -v vault >/dev/null; then
      curl -fsSL https://releases.hashicorp.com/vault/{{ vault_version }}/vault_{{ vault_version }}_linux_amd64.zip -o /tmp/vault.zip
      unzip -o /tmp/vault.zip -d /usr/local/bin
    fi

==> FILE: infra/terraform/providers.tf
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    vault  = { source = "hashicorp/vault",  version = "~> 4.3" }
    nomad  = { source = "hashicorp/nomad",  version = "~> 2.1" }
    consul = { source = "hashicorp/consul", version = "~> 2.21" }
  }
}

provider "vault"  { address = var.vault_addr  token = var.vault_bootstrap_token }
provider "nomad"  { address = var.nomad_addr  secret_id = var.nomad_bootstrap_token }
provider "consul" { address = var.consul_addr token = var.consul_bootstrap_token scheme = "http" }

==> FILE: infra/terraform/variables.tf
variable "vault_addr"             { type = string }
variable "vault_bootstrap_token"  { type = string, sensitive = true }
variable "nomad_addr"             { type = string }
variable "nomad_bootstrap_token"  { type = string, sensitive = true }
variable "consul_addr"            { type = string }
variable "consul_bootstrap_token" { type = string, sensitive = true }

variable "traefik_vault_kv_path"  { type = string, default = "kv" }
variable "traefik_htpasswd"       { type = string, sensitive = true }

==> FILE: infra/terraform/outputs.tf
output "traefik_approle_role_id"   { value = vault_approle_auth_backend_role.traefik_agent.role_id                           sensitive = true }
output "traefik_approle_secret_id" { value = vault_approle_auth_backend_role_secret_id.traefik_agent.secret_id              sensitive = true }
output "consul_traefik_token"      { value = consul_acl_token.traefik.secret_id                                            sensitive = true }
output "nomad_variable_path"       { value = nomad_variable.traefik_approle.path }

==> FILE: infra/terraform/vault_kv.tf
resource "vault_mount" "kv" {
  path    = var.traefik_vault_kv_path
  type    = "kv-v2"
  options = { version = "2" }
}

resource "vault_kv_secret_v2" "traefik" {
  mount     = vault_mount.kv.path
  name      = "traefik"                          # kv/data/traefik
  data_json = jsonencode({
    htpasswd          = var.traefik_htpasswd,
    CONSUL_HTTP_ADDR  = var.consul_addr,
    CONSUL_HTTP_TOKEN = consul_acl_token.traefik.secret_id
  })
}

==> FILE: infra/terraform/vault_policy_traefik.tf
resource "vault_policy" "traefik_read_kv" {
  name   = "traefik-read-kv"
  policy = <<-HCL
    path "${vault_mount.kv.path}/data/traefik"     { capabilities = ["read"] }
    path "${vault_mount.kv.path}/metadata/traefik" { capabilities = ["read","list"] }
    path "nomad/creds/traefik"                     { capabilities = ["read"] }
  HCL
}

==> FILE: infra/terraform/vault_approle.tf
resource "vault_auth_backend" "approle" { type = "approle" }

resource "vault_approle_auth_backend_role" "traefik_agent" {
  backend            = vault_auth_backend.approle.path
  role_name          = "traefik-agent"
  token_policies     = [vault_policy.traefik_read_kv.name]
  token_ttl          = "1h"
  token_max_ttl      = "24h"
  secret_id_ttl      = "24h"
  secret_id_num_uses = 0
  token_num_uses     = 0
}

resource "vault_approle_auth_backend_role_secret_id" "traefik_agent" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.traefik_agent.role_name
}

==> FILE: infra/terraform/nomad_policy.tf
resource "nomad_acl_policy" "read_services" {
  name = "read-services"
  rules_hcl = <<-HCL
    namespace "*" { policy = "read" }
    agent { policy = "read" }
    node  { policy = "read" }
  HCL
}

resource "nomad_acl_policy" "traefik_vars_read" {
  name = "traefik-vars-read"
  rules_hcl = <<-HCL
    namespace "default" { policy = "read" }
    variables { path "traefik/approle" { capabilities = ["read"] } }
  HCL
}

==> FILE: infra/terraform/vault_nomad_secrets.tf
resource "vault_nomad_secret_backend" "nomad" {
  path        = "nomad"
  description = "Dynamic Nomad tokens"
  token       = var.nomad_bootstrap_token
  address     = var.nomad_addr
}

resource "vault_nomad_secret_backend_role" "traefik" {
  backend  = vault_nomad_secret_backend.nomad.path
  name     = "traefik"
  type     = "client"
  global   = true
  policies = [
    nomad_acl_policy.read_services.name,
    nomad_acl_policy.traefik_vars_read.name
  ]
  ttl     = "1h"
  max_ttl = "24h"
}

==> FILE: infra/terraform/nomad_variables.tf
resource "nomad_variable" "traefik_approle" {
  path      = "traefik/approle"
  namespace = "default"
  items_json = jsonencode({
    role_id   = vault_approle_auth_backend_role.traefik_agent.role_id,
    secret_id = vault_approle_auth_backend_role_secret_id.traefik_agent.secret_id
  })
}

==> FILE: infra/terraform/consul_providers.tf
# (provider is already in providers.tf; kept as placeholder if you prefer splitting)

==> FILE: infra/terraform/consul_acl_traefik.tf
resource "consul_acl_policy" "traefik_read_catalog" {
  name = "traefik-read-catalog"
  rules = <<-HCL
    node_prefix ""    { policy = "read" }
    service_prefix "" { policy = "read" }
    agent_prefix ""   { policy = "read" }
    query_prefix ""   { policy = "read" }
  HCL
}

resource "consul_acl_token" "traefik" {
  description = "Traefik Catalog read token"
  policies    = [consul_acl_policy.traefik_read_catalog.name]
  local       = true
}

==> FILE: nomad/packs/traefik/pack.hcl
pack {
  name        = "traefik"
  description = "Traefik on Nomad with Vault-Agent sidecar"
  version     = "0.1.0"
}

==> FILE: nomad/packs/traefik/variables.hcl
variable "datacenters"   { type = list(string); default = ["dc1"] }
variable "traefik_image" { type = string; default = "traefik:2.11" }
variable "hostname"      { type = string }
variable "acme_email"    { type = string }
variable "vault_addr"    { type = string; default = "http://127.0.0.1:8200" }
variable "vault_kv_path" { type = string; default = "kv/data/traefik" }

==> FILE: nomad/packs/traefik/jobs/traefik.nomad.hcl.tmpl
job "traefik" {
  datacenters = {{ toJson var.datacenters }}
  type = "service"

  group "traefik" {
    count = 1

    network {
      port "http"  { to = 80 }
      port "https" { to = 443 }
      port "dash"  { to = 8080 }
    }

    volume "acme" { type="host"; source="traefik-acme"; read_only=false }

    task "traefik" {
      driver = "docker"
      config {
        image = "{{ var.traefik_image }}"
        ports = ["http","https","dash"]
        args = [
          "--providers.file.filename=/secrets/traefik-dynamic.yml",
          "--providers.consulcatalog=true",
          "--providers.consulcatalog.endpoint.address=127.0.0.1:8500",

          "--api.dashboard=true",

          "--entrypoints.web.address=:80",
          "--entrypoints.web.http.redirections.entrypoint.to=websecure",
          "--entrypoints.web.http.redirections.entrypoint.scheme=https",

          "--entrypoints.websecure.address=:443",

          # ACME HTTP-01
          "--certificatesresolvers.letsencrypt.acme.email={{ var.acme_email }}",
          "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json",
          "--certificatesresolvers.letsencrypt.acme.httpchallenge=true",
          "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
        ]
      }

      lifecycle {
        hook = "prestart"
        command = "/bin/sh"
        args = ["-lc", "set -a; [ -f /secrets/env ] && . /secrets/env || true; set +a"]
      }

      template {
        destination = "/secrets/traefik-dynamic.yml"
        perms       = "0640"
        data        = file("files/traefik-dynamic.yml.tpl")
      }

      volume_mount { volume="acme"; destination="/data"; read_only=false }
      resources { cpu=300; memory=256 }

      service {
        name = "traefik"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.api.rule=Host(`{{ var.hostname }}`) && PathPrefix(`/dashboard`)",
          "traefik.http.routers.api.entrypoints=websecure",
          "traefik.http.routers.api.tls.certresolver=letsencrypt",
          "traefik.http.routers.api.middlewares=auth@file",
        ]
        check { type="tcp"; port="http"; interval="10s"; timeout="2s" }
      }
    }

    task "vault-agent" {
      driver = "raw_exec"
      config { command = "vault"; args = ["agent","-config=/local/agent.hcl"] }
      env { VAULT_ADDR = "{{ var.vault_addr }}" }

      template {
        destination = "local/role_id"
        data = <<-EOT
          {{- with nomadVar "traefik/approle" -}}{{ .Data.data.role_id }}{{- end -}}
        EOT
        change_mode = "restart"
      }
      template {
        destination = "local/secret_id"
        data = <<-EOT
          {{- with nomadVar "traefik/approle" -}}{{ .Data.data.secret_id }}{{- end -}}
        EOT
        change_mode = "restart"
      }

      template { destination = "local/agent.hcl";       data = file("files/vault-agent.hcl.tpl") }
      template { destination = "local/traefik-env.tpl"; data = file("files/vault-agent-traefik.tpl") }

      resources { cpu=100; memory=64 }
      volume_mount { volume="acme"; destination="/data"; read_only=false }
    }

    restart { attempts=3; interval="30s"; delay="10s"; mode="delay" }
    update  { max_parallel=1; canary=1; min_healthy_time="10s"; healthy_deadline="2m"; auto_revert=true }
  }

  volume "traefik-acme" { type="host"; source="traefik-acme"; read_only=false }
}

==> FILE: nomad/packs/traefik/files/traefik-dynamic.yml.tpl
http:
  middlewares:
    auth:
      basicAuth:
        users:
          - "{{ with secret \"{{ var.vault_kv_path }}\" }}{{ .Data.data.htpasswd }}{{ end }}"

==> FILE: nomad/packs/traefik/files/vault-agent.hcl.tpl
pid_file = "/tmp/vault-agent.pid"
exit_after_auth = false

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/local/role_id"
      secret_id_file_path = "/local/secret_id"
    }
  }
  sink "file" {
    config = { path = "/secrets/vault-token" }
  }
}

template {
  source      = "/local/traefik-env.tpl"
  destination = "/secrets/env"
}

==> FILE: nomad/packs/traefik/files/vault-agent-traefik.tpl
{{- with secret "kv/data/traefik" -}}
{{- if .Data.data.CONSUL_HTTP_ADDR }}CONSUL_HTTP_ADDR={{ .Data.data.CONSUL_HTTP_ADDR }}{{ end }}
{{- if .Data.data.CONSUL_HTTP_TOKEN }}CONSUL_HTTP_TOKEN={{ .Data.data.CONSUL_HTTP_TOKEN }}{{ end }}
{{- range $k, $v := .Data.data }}
{{- if and (ne $k "htpasswd") (ne $k "CONSUL_HTTP_ADDR") (ne $k "CONSUL_HTTP_TOKEN") }}
{{ $k }}={{ $v }}
{{- end }}
{{- end }}
{{- end -}}

==> FILE: nomad/packs/traefik/files/traefik-static.toml.tmpl
[api]
  dashboard = true
