# Generated environment configuration
environment: ${environment}
server_ip: ${server_ip}
security_level: ${security_level}
generated_at: ${timestamp}

# HashiCorp Configuration
consul:
  address: ${consul_addr}
  datacenter: dc1
  encrypt: true

nomad:
  address: ${nomad_addr}
  datacenter: dc1
  region: global

vault:
  address: ${vault_addr}
  
# Environment-specific settings
%{ if environment == "develop" ~}
development:
  debug_enabled: true
  security_hardening: false
  acl_enabled: false
%{ endif ~}

%{ if environment == "staging" ~}
staging:
  debug_enabled: false
  security_hardening: true
  acl_enabled: true
%{ endif ~}

%{ if environment == "production" ~}
production:
  debug_enabled: false
  security_hardening: true
  acl_enabled: true
  tls_enabled: true
  monitoring_enabled: true
%{ endif ~}