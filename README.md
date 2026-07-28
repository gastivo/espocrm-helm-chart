# EspoCRM Helm Chart

Helm Chart for deploying [EspoCRM](https://www.espocrm.com) on Kubernetes.

## Architecture

The chart deploys three separate deployments:

| Deployment          | Description                    | Scalable |
|---------------------|--------------------------------|----------|
| `espocrm-web`       | Web application (Apache + PHP) | ✅ Yes   |
| `espocrm-daemon`    | Background job processor       | ✅ Yes   |
| `espocrm-websocket` | WebSocket server               | ✅ Yes   |

## Prerequisites

- External database (MySQL or PostgreSQL) with credentials

## Installation

```bash
helm upgrade --install espocrm oci://ghcr.io/gastivo/helm-charts/espocrm:1.0.0 -n espocrm --create-namespace
```

## Configuration

### Admin Password

The admin password can be set explicitly, left empty for auto-generation, or pulled from an existing secret:

```yaml
# Option A: Set password explicitly (not recommended)
admin:
  username: admin
  password: "mypassword"

# Option B: Leave empty – a random password is auto-generated on first install
# and preserved across upgrades via the existing secret lookup
admin:
  username: admin
  password: ""

# Option C: Use an existing Kubernetes Secret
admin:
  existingSecret: "my-admin-secret"
  existingKey: "admin-password" # key inside the secret
```

> **Note:** When using Option B, retrieve the generated password with:
> ```bash
> kubectl get secret espocrm-admin -n espocrm -o jsonpath='{.data.admin-password}' | base64 -d
> ```

### EspoCRM Config Override

Set the PHP content directly in your `values.yaml`. The chart renders it into a ConfigMap and mounts it automatically:

```yaml
config:
  configOverride: |
    <?php
    return [
      'addressFormat' => 2,
      'siteUrl' => 'https://crm.example.com',
    ];
  configInternalOverride: |
    <?php
    return [
      'oidcClientSecret' => getenv('ESPOCRM_OIDC_CLIENT_SECRET') ?: null,
    ];
```

**Option B – Existing ConfigMap (umbrella chart / GitOps)**

Point `config.existingConfigMap` at a ConfigMap that already exists in the cluster. The chart will mount it automatically — no `extraVolumeMounts` / `extraVolumes` needed. When this option is set, `configOverride` and `configInternalOverride` are ignored and no ConfigMap is rendered by the chart.

```yaml
config:
  existingConfigMap: "my-espo-config"   # must exist before helm install/upgrade
```

Example ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-espo-config
data:
  config-override.php: |
    <?php
    return [
      'addressFormat' => 2,
      'siteUrl' => 'https://crm.example.com',
    ];
  config-internal-override.php: |
    <?php
    return [
      'oidcClientSecret' => getenv('ESPOCRM_OIDC_CLIENT_SECRET') ?: null,
    ];
```

### Database

Only an external database is supported. The DB password can either be set directly or referenced via an existing secret:

```yaml
# Option A: Set password directly (chart creates the secret)
externalDatabase:
  platform: Postgresql # Mysql or Postgresql
  host: "postgresql.postgresql.svc.cluster.local"
  port: 5432
  user: "espocrm"
  password: "secret"
  database: "espocrm"

# Option B: Use an existing secret
externalDatabase:
  existingSecret: "my-db-secret"
  secretKey: "db-password"
```

### Logs

By default, EspoCRM's file-based logging is reconfigured to write structured JSON logs to `stdout` via Monolog.

> **⚠️ Important when using a custom `config.configOverride`:**
> The default logging configuration lives in the built-in `config-override.php`. As soon as you provide your own
> `config.configOverride`, it **replaces** that file entirely — stdout logging is then lost unless you carry the
> logging block over into your own override.

you should copy the content of the shipped [config-override.php](./config/config-override.php) into your custom override to preserve stdout logging,

### Autoscaling

All three deployments (`web`, `daemon`, `websocket`) support HPA:

```yaml
web:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
    # targetMemoryUtilizationPercentage: 80
    # metrics: []   # Custom HPA v2 metrics
    # behavior: {}  # Custom scale behavior

daemon:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPUUtilizationPercentage: 80

websocket:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

### Persistence

```yaml
persistence:
  size: 1Gi
  accessModes:
    - ReadWriteMany
  # storageClass: ""
  # existingClaim: ""
  # annotations: {}
```

### Shared Volumes

All three deployments (`web`, `daemon`, `websocket`) and the bootstrap job mount the **same PVC** simultaneously. The PVC is therefore created with `accessMode: ReadWriteMany` (RWX) — the configured `storageClass` must support RWX (e.g. NFS, CephFS, Azure Files, EFS). `ReadWriteOnce` storage classes (e.g. standard cloud block storage) will **not**
work.

#### PVC layout

A single PVC (`<release>-data`) is partitioned into three sub-directories via `subPath`:

| subPath         | Mount path in container       | Purpose                                     |
|-----------------|-------------------------------|---------------------------------------------|
| `data`          | `/var/www/html/data`          | EspoCRM config, cache, logs, uploaded files |
| `custom`        | `/var/www/html/custom`        | Custom back-end extensions & overrides      |
| `client-custom` | `/var/www/html/client/custom` | Custom front-end assets                     |

### Extensions

To pre-install extensions during bootstrap, place `.zip` files in a directory and configure:

```yaml
bootstrap:
  extensionsPath: "/extensions"  # Path inside container
```

Mount the directory containing your `.zip` files using `extraVolumes` and `extraVolumeMounts`:

```yaml
extraVolumes:
  - name: extensions
    configMap:
      name: my-extensions  # or use emptyDir, PVC, etc.

extraVolumeMounts:
  - name: extensions
    mountPath: /extensions
    readOnly: true
```

The bootstrap job installs all `.zip` files found in `extensionsPath`. Existing extensions (by name+version) are skipped unless the PVC was recreated.

### Environment Variables

Add custom environment variables via ConfigMap or inline:

```yaml
# Option A: Inline variables (chart creates ConfigMap)
extraEnv:
  ESPOCRM_LANGUAGE: "de_DE"
  ESPOCRM_DEFAULT_CURRENCY: "EUR"
  ESPOCRM_THOUSAND_SEPARATOR: "."

# Option B: Reference existing Secrets or ConfigMaps
extraEnvFrom:
  secretRef:
    - my-secret-1
    - my-secret-2
  configMapRef:
    - my-configmap
```

All variables are available in all deployments (`web`, `daemon`, `websocket`).

### PHP Configuration

Override `php.ini` settings per deployment:

```yaml
web:
  php_ini: |
    memory_limit=256M
    upload_max_filesize=20M
    post_max_size=20M

daemon:
  php_ini: |
    memory_limit=512M
    max_execution_time=0

bootstrap:
  php_ini: |
    memory_limit=-1  # Unlimited for large installations
```

### Metrics & Monitoring

If you have the EspoCRM metrics extension installed:

```yaml
metrics:
  available: true  # Set to true if extension is installed
  serviceMonitor:
    enabled: true
    path: "/api/v1/metrics"
    interval: 30s
    scrapeTimeout: 10s
    annotations: { }
    relabelings: [ ]
```

The chart creates a ServiceMonitor for Prometheus Operator when `serviceMonitor.enabled: true`.
