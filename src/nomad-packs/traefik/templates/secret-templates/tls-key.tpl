{{- with secret "pki/issue/traefik" "common_name=traefik.cloudya.net" "alt_names=vault.cloudya.net,consul.cloudya.net,nomad.cloudya.net" -}}
{{ .Data.private_key }}
{{- end -}}