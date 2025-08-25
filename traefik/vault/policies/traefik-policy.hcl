# Traefik Policy for accessing certificates and configuration
path "secret/data/traefik/dashboard" {
  capabilities = ["read"]
}

path "secret/data/traefik/certificates" {
  capabilities = ["read"]
}

path "secret/data/traefik/config/*" {
  capabilities = ["read"]
}

path "secret/metadata/traefik/*" {
  capabilities = ["list", "read"]
}

# PKI for SSL certificates
path "pki/issue/traefik-cert" {
  capabilities = ["create", "update"]
}

path "pki/cert/ca" {
  capabilities = ["read"]
}

# Read own token info
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Nomad integration
path "nomad/creds/traefik-role" {
  capabilities = ["read"]
}