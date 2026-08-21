{{- define "metrics-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metrics-gateway.fullname" -}}
{{- $name := include "metrics-gateway.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "metrics-gateway.labels" -}}
app.kubernetes.io/name: {{ include "metrics-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "metrics-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "metrics-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
