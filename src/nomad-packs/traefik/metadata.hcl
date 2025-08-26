# Traefik Nomad Pack for Phase 6 Production Deployment
# Enterprise-grade reverse proxy with Vault integration and SSL certificates

app {
  url    = "https://github.com/traefik/traefik"
  author = "Traefik Labs"
}

pack {
  name        = "traefik"
  description = "Production-ready Traefik reverse proxy with Vault-Agent sidecar, Let's Encrypt SSL, and Consul service discovery"
  url         = "https://github.com/cloudya/vault/nomad-packs/traefik"
  version     = "2.0.0"
}

dependency "consul" {
  alias  = "consul"
  source = "git::https://github.com/hashicorp/nomad-pack-community-registry.git//packs/consul"
}

dependency "vault" {
  alias  = "vault"  
  source = "git::https://github.com/hashicorp/nomad-pack-community-registry.git//packs/vault"
}