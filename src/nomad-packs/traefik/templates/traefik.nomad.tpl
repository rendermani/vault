job "traefik" {
  region      = "[[ .traefik.region ]]"
  datacenters = ["[[ .traefik.datacenter ]]"]
  type        = "service"
  priority    = 90

  # Update strategy for zero-downtime deployments
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
  }

  # Spread across nodes for high availability
  spread {
    [[ range $spread := .traefik.spread ]]
    attribute = "[[ $spread.attribute ]]"
    target "[[ $spread.target ]]" {
      percent = [[ $spread.percent ]]
    }
    [[ end ]]
  }

  group "traefik" {
    count = [[ .traefik.count ]]

    # Constraints for proper placement
    [[ range $constraint := .traefik.constraints ]]
    constraint {
      attribute = "[[ $constraint.attribute ]]"
      operator  = "[[ $constraint.operator ]]"
      value     = "[[ $constraint.value ]]"
    }
    [[ end ]]

    # Persistent volume for ACME certificates
    [[ if .traefik.storage.acme_enabled ]]
    volume "acme-certs" {
      type            = "host"
      source          = "[[ .traefik.storage.volume_name ]]"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "multi-node-multi-writer"
    }
    [[ end ]]

    # Restart policy for resilience
    restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    # Network configuration
    network {
      [[ if .traefik.host_network ]]
      mode = "host"
      [[ else ]]
      mode = "bridge"
      [[ end ]]
      
      port "web" {
        static = [[ .traefik.entrypoints.web.port ]]
      }
      
      port "websecure" {
        static = [[ .traefik.entrypoints.websecure.port ]]
      }
      
      port "traefik" {
        static = [[ .traefik.entrypoints.traefik.port ]]
      }
      
      port "metrics" {
        static = [[ .traefik.entrypoints.metrics.port ]]
      }
    }

    # Vault Agent Sidecar for Secret Management
    [[ if .traefik.vault_agent_enabled ]]
    task "vault-agent" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:1.15"
        args = ["vault", "agent", "-config=/vault/config/vault-agent.hcl"]
        
        mount {
          type     = "bind"
          target   = "/vault/config"
          source   = "local/vault-agent"
          readonly = false
        }
        
        mount {
          type     = "bind" 
          target   = "/vault/secrets"
          source   = "secrets"
          readonly = false
        }
      }

      # Vault Agent configuration
      template {
        data = <<-EOH
          vault {
            address = "[[ .traefik.vault_address ]]"
            retry {
              num_retries = 5
            }
          }

          auto_auth {
            method "jwt" {
              mount_path = "auth/jwt"
              config = {
                role = "[[ .traefik.vault_role ]]"
                path = "/secrets/token"
              }
            }

            sink "file" {
              config = {
                path = "/vault/secrets/.vault-token"
              }
            }
          }

          listener "unix" {
            address     = "/vault/secrets/agent.sock"
            tls_disable = true
          }

          template {
            source      = "/vault/config/cloudflare-key.tpl"
            destination = "/vault/secrets/cloudflare-key"
            perms       = 0600
          }

          template {
            source      = "/vault/config/cloudflare-email.tpl" 
            destination = "/vault/secrets/cloudflare-email"
            perms       = 0600
          }

          template {
            source      = "/vault/config/dashboard-auth.tpl"
            destination = "/vault/secrets/dashboard-auth"
            perms       = 0600
          }
        EOH
        
        destination = "local/vault-agent/vault-agent.hcl"
        change_mode = "restart"
      }

      # Cloudflare API Key template
      template {
        data = <<-EOH
          {{- with secret "kv/data/cloudflare" -}}
          {{ .Data.data.api_key }}
          {{- end -}}
        EOH
        
        destination = "local/vault-agent/cloudflare-key.tpl"
        change_mode = "restart"
      }

      # Cloudflare Email template
      template {
        data = <<-EOH
          {{- with secret "kv/data/cloudflare" -}}
          {{ .Data.data.email }}
          {{- end -}}
        EOH
        
        destination = "local/vault-agent/cloudflare-email.tpl"
        change_mode = "restart"
      }

      # Dashboard authentication template
      template {
        data = <<-EOH
          {{- with secret "kv/data/traefik/dashboard" -}}
          {{ .Data.data.basic_auth }}
          {{- end -}}
        EOH
        
        destination = "local/vault-agent/dashboard-auth.tpl"
        change_mode = "restart"
      }

      resources {
        cpu    = [[ .traefik.vault_agent_resources.cpu ]]
        memory = [[ .traefik.vault_agent_resources.memory ]]
      }

      # Vault integration
      vault {
        policies = [[ .traefik.vault_policies | toJSON ]]
        change_mode = "restart"
      }

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }
    }
    [[ end ]]

    # Main Traefik Task
    task "traefik" {
      driver = "docker"

      config {
        image = "traefik:[[ .traefik.traefik_version ]]"
        args = [
          "--configfile=/local/traefik.yml"
        ]

        ports = ["web", "websecure", "traefik", "metrics"]

        mount {
          type     = "bind"
          target   = "/etc/traefik/dynamic"
          source   = "local/dynamic"
          readonly = false
        }

        [[ if .traefik.vault_agent_enabled ]]
        mount {
          type     = "bind"
          target   = "/vault/secrets"
          source   = "secrets"
          readonly = true
        }
        [[ end ]]
      }

      # Mount ACME certificate volume
      [[ if .traefik.storage.acme_enabled ]]
      volume_mount {
        volume      = "acme-certs"
        destination = "[[ .traefik.storage.mount_path ]]"
        read_only   = false
      }
      [[ end ]]

      # Main Traefik configuration
      template {
        data = <<-EOH
          # Traefik Configuration - Production Ready
          global:
            checknewversion: false
            sendanonymoususage: false

          # Entry Points
          entrypoints:
            web:
              address: ":{{ env "NOMAD_PORT_web" }}"
              [[ if .traefik.entrypoints.web.redirect_to_tls ]]
              http:
                redirections:
                  entrypoint:
                    to: websecure
                    scheme: https
                    permanent: true
              [[ end ]]

            websecure:
              address: ":{{ env "NOMAD_PORT_websecure" }}"
              http:
                tls:
                  options: secure@file

            traefik:
              address: ":{{ env "NOMAD_PORT_traefik" }}"

            metrics:
              address: ":{{ env "NOMAD_PORT_metrics" }}"

          # Providers
          providers:
            file:
              directory: /etc/traefik/dynamic
              watch: true

            [[ if .traefik.consul_integration ]]
            consulcatalog:
              endpoints:
                - "[[ .traefik.consul_address ]]"
              exposedByDefault: false
              watch: true
              connectAware: true
              connectByDefault: false
              serviceName: "traefik"
              pollInterval: "5s"
              stale: false
            [[ end ]]

            [[ if .traefik.nomad_provider_enabled ]]
            nomad:
              endpoints:
                - "[[ .traefik.nomad_address ]]"
              exposedByDefault: false
              watch: true
              pollInterval: "5s"
            [[ end ]]

          # ACME (Let's Encrypt)
          [[ if .traefik.acme_enabled ]]
          certificatesresolvers:
            letsencrypt:
              acme:
                email: [[ .traefik.acme_email ]]
                storage: /acme/acme.json
                caserver: [[ .traefik.acme_ca_server ]]
                dnschallenge:
                  provider: [[ .traefik.acme_dns_challenge.provider ]]
                  delaybeforecheck: [[ .traefik.acme_dns_challenge.delay ]]
                  resolvers:
                    - "1.1.1.1:53"
                    - "8.8.8.8:53"
          [[ end ]]

          # API and Dashboard
          api:
            dashboard: [[ .traefik.dashboard_enabled ]]
            debug: [[ .traefik.debug_enabled ]]
            insecure: [[ .traefik.api_insecure ]]

          # Ping endpoint for health checks
          ping:
            entrypoint: "traefik"

          # Logging
          log:
            level: [[ .traefik.log_level ]]
            format: json

          [[ if .traefik.access_log.enabled ]]
          accesslog:
            format: [[ .traefik.access_log.format ]]
            filters:
              statuscodes: [[ .traefik.access_log.filters.status_codes | join "," ]]
              retryattempts: [[ .traefik.access_log.filters.retry_attempts ]]
              minduration: "[[ .traefik.access_log.filters.min_duration ]]"
          [[ end ]]

          # Metrics
          [[ if .traefik.metrics.prometheus.enabled ]]
          metrics:
            prometheus:
              addEntryPointsLabels: [[ .traefik.metrics.prometheus.add_entrypoints_labels ]]
              addServicesLabels: [[ .traefik.metrics.prometheus.add_services_labels ]]
              addRoutersLabels: [[ .traefik.metrics.prometheus.add_routers_labels ]]
              buckets: [[ .traefik.metrics.prometheus.buckets | join "," ]]
              entrypoint: "metrics"
          [[ end ]]

          # Tracing
          [[ if .traefik.tracing.jaeger.enabled ]]
          tracing:
            jaeger:
              samplingServerURL: [[ .traefik.tracing.jaeger.sampling_server ]]
              localAgentHostPort: [[ .traefik.tracing.jaeger.local_agent ]]
              samplingType: [[ .traefik.tracing.jaeger.sampling_type ]]
              samplingParam: [[ .traefik.tracing.jaeger.sampling_param ]]
          [[ end ]]

          # Pilot (optional)
          [[ if .traefik.pilot_enabled ]]
          pilot:
            dashboard: false
          [[ end ]]
        EOH

        destination = "local/traefik.yml"
        change_mode = "restart"
      }

      # Dynamic configuration for middlewares
      template {
        data = <<-EOH
          # Security Headers Middleware
          http:
            middlewares:
              secure-headers:
                headers:
                  accessControlAllowMethods:
                    - GET
                    - OPTIONS
                    - PUT
                  accessControlMaxAge: 100
                  hostsProxyHeaders:
                    - "X-Forwarded-Host"
                  referrerPolicy: "same-origin"
                  sslRedirect: true
                  stsSeconds: 31536000
                  stsIncludeSubdomains: true
                  stsPreload: true
                  forceSTSHeader: true
                  frameDeny: true
                  contentTypeNosniff: true
                  browserXssFilter: true
                  customRequestHeaders:
                    X-Forwarded-Proto: "https"
                  customResponseHeaders:
                    X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
                    Server: ""

              # Rate Limiting
              rate-limit:
                rateLimit:
                  burst: 100
                  period: 10s

              # Real IP
              real-ip:
                ipWhiteList:
                  sourceCriterion: "requestHeaderOrRemoteAddr"
                  requestHeaderName: "X-Real-IP"

              # Compression
              gzip:
                compress: {}

              # Dashboard Authentication (if enabled)
              [[ if and .traefik.dashboard_enabled .traefik.dashboard_auth ]]
              dashboard-auth:
                basicAuth:
                  usersFile: "/vault/secrets/dashboard-auth"
              [[ end ]]
        EOH

        destination = "local/dynamic/middlewares.yml"
        change_mode = "restart"
      }

      # TLS Options
      template {
        data = <<-EOH
          tls:
            options:
              secure:
                minVersion: "[[ .traefik.tls_options.min_version ]]"
                cipherSuites:
                  [[ range $cipher := .traefik.tls_options.cipher_suites ]]
                  - "[[ $cipher ]]"
                  [[ end ]]
                curvePreferences:
                  [[ range $curve := .traefik.tls_options.curve_preferences ]]
                  - "[[ $curve ]]"
                  [[ end ]]
                sniStrict: [[ .traefik.tls_options.sni_strict ]]
        EOH

        destination = "local/dynamic/tls.yml"
        change_mode = "restart"
      }

      # Service routes for HashiCorp services
      template {
        data = <<-EOH
          http:
            routers:
              # Traefik Dashboard
              traefik-dashboard:
                rule: "Host(`traefik.cloudya.net`)"
                service: "api@internal"
                [[ if .traefik.acme_enabled ]]
                tls:
                  certresolver: letsencrypt
                [[ end ]]
                middlewares:
                  - "secure-headers@file"
                  [[ if and .traefik.dashboard_enabled .traefik.dashboard_auth ]]
                  - "dashboard-auth@file"
                  [[ end ]]

              # Vault Service
              vault-api:
                rule: "Host(`vault.cloudya.net`)"
                service: "vault"
                [[ if .traefik.acme_enabled ]]
                tls:
                  certresolver: letsencrypt
                [[ end ]]
                middlewares:
                  - "secure-headers@file"
                  - "rate-limit@file"

              # Consul UI
              consul-ui:
                rule: "Host(`consul.cloudya.net`)"
                service: "consul"
                [[ if .traefik.acme_enabled ]]
                tls:
                  certresolver: letsencrypt
                [[ end ]]
                middlewares:
                  - "secure-headers@file"

              # Nomad UI  
              nomad-ui:
                rule: "Host(`nomad.cloudya.net`)"
                service: "nomad"
                [[ if .traefik.acme_enabled ]]
                tls:
                  certresolver: letsencrypt
                [[ end ]]
                middlewares:
                  - "secure-headers@file"

            services:
              vault:
                loadBalancer:
                  servers:
                    - url: "https://vault.service.consul:8200"
                  healthCheck:
                    path: "/v1/sys/health"
                    interval: "30s"
                    timeout: "5s"

              consul:
                loadBalancer:
                  servers:
                    - url: "http://consul.service.consul:8500"
                  healthCheck:
                    path: "/v1/status/leader"
                    interval: "30s"
                    timeout: "5s"

              nomad:
                loadBalancer:
                  servers:
                    - url: "http://nomad.service.consul:4646"
                  healthCheck:
                    path: "/v1/status/leader"
                    interval: "30s"
                    timeout: "5s"
        EOH

        destination = "local/dynamic/services.yml"
        change_mode = "restart"
      }

      # Environment variables
      [[ if .traefik.vault_agent_enabled ]]
      env {
        CF_API_EMAIL_FILE = "/vault/secrets/cloudflare-email"
        CF_API_KEY_FILE = "/vault/secrets/cloudflare-key"
      }
      [[ end ]]

      # Resource allocation
      resources {
        cpu        = [[ .traefik.resources.cpu ]]
        memory     = [[ .traefik.resources.memory ]]
        memory_max = [[ .traefik.resources.memory_max ]]
      }

      # Health checks
      service {
        name = "traefik"
        port = "traefik"
        
        tags = [
          "traefik",
          "load-balancer",
          "reverse-proxy",
          "urlprefix-traefik.cloudya.net/",
          "traefik.enable=true",
          "traefik.http.routers.traefik-dashboard.tls=true"
        ]

        [[ if .traefik.health_checks.http.enabled ]]
        check {
          type     = "http"
          path     = "[[ .traefik.health_checks.http.path ]]"
          interval = "[[ .traefik.health_checks.http.interval ]]"
          timeout  = "[[ .traefik.health_checks.http.timeout ]]"
          check_restart {
            limit           = 3
            grace           = "[[ .traefik.health_checks.http.grace_period ]]"
            ignore_warnings = false
          }
        }
        [[ end ]]

        [[ if .traefik.health_checks.tcp.enabled ]]
        check {
          type     = "tcp"
          interval = "[[ .traefik.health_checks.tcp.interval ]]"
          timeout  = "[[ .traefik.health_checks.tcp.timeout ]]"
        }
        [[ end ]]
      }

      # Additional services for metrics
      [[ if .traefik.metrics.prometheus.enabled ]]
      service {
        name = "traefik-metrics"
        port = "metrics"
        
        tags = [
          "metrics",
          "prometheus"
        ]

        check {
          type     = "http"
          path     = "/metrics"
          interval = "30s"
          timeout  = "5s"
        }
      }
      [[ end ]]

      # Vault integration for main task
      [[ if .traefik.vault_integration ]]
      vault {
        policies = [[ .traefik.vault_policies | toJSON ]]
        change_mode = "restart"
      }
      [[ end ]]

      # Task dependencies
      [[ if .traefik.vault_agent_enabled ]]
      lifecycle {
        hook = "poststart"
        sidecar = false
      }
      [[ end ]]
    }

    # Service mesh integration (if Consul Connect enabled)
    service {
      name = "traefik"
      port = "websecure"
      
      connect {
        sidecar_service {}
      }
    }
  }
}