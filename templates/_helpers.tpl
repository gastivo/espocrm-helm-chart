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
espocrm.extraEnvFrom renders an additional environment variables
*/}}
{{- define "espocrm.extraEnvFrom" -}}
{{- range .Values.extraEnvFrom.secretRef }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- range .Values.extraEnvFrom.configMapRef }}
- configMapRef:
    name: {{ . }}
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
espocrm.commonVolumeMounts renders the volumeMounts shared by all three deployments
(web, daemon, websocket) and the bootstrap init-container:
  - PVC sub-paths (data, custom, client-custom)
  - ha-entrypoint.sh script
  - conditional config-override mounts
  - extraVolumeMounts
Usage: {{- include "espocrm.commonVolumeMounts" . | nindent 12 }}
*/}}
{{- define "espocrm.commonVolumeMounts" -}}
- name: espocrm-data
  mountPath: /var/www/html/data
  subPath: data
- name: espocrm-data
  mountPath: /var/www/html/custom
  subPath: custom
- name: espocrm-data
  mountPath: /var/www/html/client/custom
  subPath: client-custom
- name: espocrm-misc
  mountPath: /usr/local/bin/ha-entrypoint.sh
  subPath: ha-entrypoint.sh
  readOnly: true
{{- include "espocrm.configOverrideMounts" . }}
{{- with .Values.extraVolumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
espocrm.commonVolumes renders the volumes shared by all three deployments.
Usage: {{- include "espocrm.commonVolumes" . | nindent 8 }}
*/}}
{{- define "espocrm.commonVolumes" -}}
- name: espocrm-misc
  configMap:
    name: {{ include "espocrm.fullname" . }}-misc
    defaultMode: 0755
- name: espocrm-data
  persistentVolumeClaim:
    claimName: {{ include "espocrm.dataClaimName" . }}
{{- include "espocrm.configOverrideVolume" . }}
{{- with .Values.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
espocrm.configOverrideVolume renders the config-override volume when either inline values or an
existingConfigMap are configured.
Usage: {{- include "espocrm.configOverrideVolume" . | nindent 8 }}
*/}}
{{- define "espocrm.configOverrideVolume" -}}
{{- if or .Values.config.existingConfigMap .Values.config.configOverride .Values.config.configInternalOverride }}
- name: espocrm-config-override
  configMap:
    name: {{ .Values.config.existingConfigMap | default (printf "%s-config-override" (include "espocrm.fullname" .)) }}
{{- end }}
{{- end }}

{{/*
espocrm.configOverrideMounts renders volumeMounts for config-override.php and/or config-internal-override.php.
Usage: {{- include "espocrm.configOverrideMounts" . | nindent 12 }}
*/}}
{{- define "espocrm.configOverrideMounts" -}}
{{- if or .Values.config.existingConfigMap .Values.config.configOverride }}
- name: espocrm-config-override
  mountPath: /tmp/config-override.php
  subPath: config-override.php
  readOnly: true
{{- end }}
{{- if or .Values.config.existingConfigMap .Values.config.configInternalOverride }}
- name: espocrm-config-override
  mountPath: /tmp/config-internal-override.php
  subPath: config-internal-override.php
  readOnly: true
{{- end }}
{{- end }}

{{/*
espocrm.bootstrapID computes a stable deployment fingerprint used by ha-bootstrap.sh / ha-wait-bootstrap.sh
to decide whether the bootstrap has already run for this deployment.

It is a 16-character hex prefix of the SHA-256 of:
  - the container image tag (changes on every real rollout)
  - the rendered configmap-env content (changes on every values change)

This replaces the plain .Release.Revision which stays at "1" in ArgoCD umbrella-chart setups.
*/}}
{{- define "espocrm.bootstrapID" -}}
{{- printf "%s|%s" (.Values.image.tag | default .Chart.AppVersion) (include (print $.Template.BasePath "/configmap-env.yaml") .) | sha256sum | trunc 16 -}}
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

{{/*
espocrm.affinity renders the full affinity block for a component.
Call with a dict: (dict "component" "web" "componentValues" .Values.web "context" .)

Accepts two formats:
  1. Preset object:           affinity:
                                podAntiAffinity: soft   (none | soft | hard)
  2. Full custom object:      affinity:
                                podAffinity: { ... }
*/}}
{{- define "espocrm.affinity" -}}
{{- $comp := .componentValues -}}
{{- $val := $comp.affinity | default dict -}}
{{- if and (kindIs "map" $val) (hasKey $val "podAntiAffinity") -}}
  {{- $preset := $val.podAntiAffinity | default "none" -}}
  {{- template "espocrm.affinity.preset" (dict "preset" $preset "component" .component "context" .context) -}}
{{- else if kindIs "map" $val -}}
{{- toYaml $val }}
{{- end -}}
{{- end -}}

{{/*
espocrm.affinity.preset renders a podAntiAffinity block from a preset string (none|soft|hard).
*/}}
{{- define "espocrm.affinity.preset" -}}
{{- if and .preset (ne .preset "none") -}}
podAntiAffinity:
  {{- if eq .preset "hard" }}
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "espocrm.selectorLabels" .context | nindent 10 }}
          app.kubernetes.io/component: {{ .component }}
      topologyKey: kubernetes.io/hostname
  {{- else if eq .preset "soft" }}
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "espocrm.selectorLabels" .context | nindent 12 }}
            app.kubernetes.io/component: {{ .component }}
        topologyKey: kubernetes.io/hostname
  {{- end }}
{{- end -}}
{{- end -}}
