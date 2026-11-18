{{- define "event360.labels" -}}
app.kubernetes.io/part-of: event360
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "event360.image" -}}
{{ .root.Values.image.registry }}/{{ .image }}:{{ .root.Values.image.tag }}
{{- end }}
