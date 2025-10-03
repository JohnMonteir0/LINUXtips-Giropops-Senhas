{{/*
App labels
- app: from component labels.app (fallback to chart name)
- env: from global .Values.environment (fallback "dev")
Usage in templates:
  {{ include "app.labels" (dict "cfg" $config "root" $) }}
*/}}
{{- define "app.labels" -}}
{{- $cfg := .cfg -}}
{{- $root := .root -}}
app: {{ default $root.Chart.Name ($cfg.labels.app) | quote }}
env: {{ default "dev" $root.Values.environment | quote }}
{{- end }}

{{/*
Container ports
Given a component .ports list with (name, port, targetPort):
- containerPort uses targetPort if present, else port
Usage:
  {{ include "app.ports" $config | nindent 12 }}
*/}}
{{- define "app.ports" -}}
{{- range .ports }}
- name: {{ .name | default (printf "p-%v" .port) }}
  containerPort: {{ .targetPort | default .port }}
{{- end }}
{{- end }}

{{/*
Database configmap (optional helper)
Usage:
  {{ include "database.configmap" (dict "component" "giropops-senhas" "config" $yourDbCfg ) }}
*/}}
{{- define "database.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .component }}-db-config
data:
  app-config.yaml: |
    {{- toYaml .config | nindent 4 }}
{{- end }}

{{/*
Observability configmap (optional helper)
Usage:
  {{ include "observability.configmap" (dict "component" "otel-collector-config" "config" $yourOtelCfg ) }}
*/}}
{{- define "observability.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .component }}-observability-config
data:
  otel-collector-config.yaml: |
    {{- toYaml .config | nindent 4 }}
{{- end }}
