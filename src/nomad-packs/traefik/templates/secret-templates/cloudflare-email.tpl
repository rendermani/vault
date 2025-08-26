{{- with secret "kv/data/cloudflare" -}}
{{ .Data.data.email }}
{{- end -}}