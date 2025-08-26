{{- with secret "kv/data/cloudflare" -}}
{{ .Data.data.api_key }}
{{- end -}}