{{/*
espocrm.name expands the name of the chart.
*/}}
{{- define "espocrm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
espocrm.fullname creates a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "espocrm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
espocrm.chart prints chart name and version as used by the "helm.sh/chart" label.
*/}}
{{- define "espocrm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
espocrm.labels crates common labels.
*/}}
{{- define "espocrm.labels" -}}
helm.sh/chart: {{ include "espocrm.chart" . }}
{{ include "espocrm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
espocrm.selectorLabels creates selector labels.
*/}}
{{- define "espocrm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "espocrm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
espocrm.selectorLabelsWeb creates selector labels for the web component.
*/}}
{{- define "espocrm.selectorLabelsWeb" -}}
{{ include "espocrm.selectorLabels" . }}
app.kubernetes.io/component: web
{{- end }}

{{/*
espocrm.selectorLabelsDaemon creates selector labels for the daemon component.
*/}}
{{- define "espocrm.selectorLabelsDaemon" -}}
{{ include "espocrm.selectorLabels" . }}
app.kubernetes.io/component: daemon
{{- end }}

{{/*
espocrm.selectorLabelsWebsocket creates selector labels for the websocket component.
*/}}
{{- define "espocrm.selectorLabelsWebsocket" -}}
{{ include "espocrm.selectorLabels" . }}
app.kubernetes.io/component: websocket
{{- end }}

{{/*
espocrm.databaseSecretName returns the DB secret name.
*/}}
{{- define "espocrm.databaseSecretName" -}}
{{- if .Values.externalDatabase.existingSecret -}}
    {{- .Values.externalDatabase.existingSecret -}}
{{- else -}}
    {{- printf "%s-db" (include "espocrm.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
espocrm.adminSecretName returns the EspoCRM admin secret name.
*/}}
{{- define "espocrm.adminSecretName" -}}
{{- coalesce .Values.admin.existingSecret (printf "%s-admin" (include "espocrm.fullname" .)) -}}
{{- end -}}

{{/*
espocrm.secretKey returns the key in the admin secret that holds the password.
*/}}
{{- define "espocrm.adminSecretKey" -}}
{{- coalesce .Values.admin.existingKey "admin-password" -}}
{{- end -}}

{{/*
espocrm.websocketUrl returns the websocket URL of EspoCRM.
*/}}
{{- define "espocrm.websocketUrl" -}}
{{- printf "%s%s/wss" ( empty .Values.ingress.tlsSecretName | ternary "ws://" "wss://") .Values.ingress.host -}}
{{- end -}}

{{/*
espocrm.extraEnvFrom renders an additional secretRef envFrom entry when extraSecretRef is set.
*/}}
{{- define "espocrm.extraEnvFrom" -}}
{{- if .Values.extraSecretRef }}
- secretRef:
    name: {{ .Values.extraSecretRef }}
{{- end }}
{{- end }}

{{/*
espocrm.dataClaimName returns the PVC claim name for the data volume.
*/}}
{{- define "espocrm.dataClaimName" -}}
{{- if .Values.persistence.existingClaim -}}
    {{- .Values.persistence.existingClaim -}}
{{- else -}}
    {{- printf "%s-data" (include "espocrm.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
espocrm.ingress.extraHostsTLS returns a non-empty string when at least one extraHost has a tlsSecretName,
used to decide whether to render a tls: block at all.
*/}}
{{- define "espocrm.ingress.extraHostsTLS" -}}
{{- range .Values.ingress.extraHosts -}}
{{- if .tlsSecretName -}}true{{- end -}}
{{- end -}}
{{- end -}}
