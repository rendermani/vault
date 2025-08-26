# Traefik Nomad Pack
# Phase 5: Modern application deployment using Nomad Pack instead of docker-compose

app {
  url    = "https://github.com/traefik/traefik"
  author = "Traefik Labs"
}

pack {
  name        = "traefik"
  description = "Modern reverse proxy and load balancer with Vault integration"
  url         = "https://github.com/your-org/nomad-packs/traefik"
  version     = "1.0.0"
}

dependency "consul" {
  alias  = "consul"
  source = "git::https://github.com/hashicorp/nomad-pack-community-registry.git//packs/consul"
}