{{- with secret "kv/data/traefik/dashboard" -}}
{{ .Data.data.basic_auth }}
{{- end -}}