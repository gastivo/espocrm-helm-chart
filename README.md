# EspoCRM Helm Chart

Helm Chart for deploying [EspoCRM](https://www.espocrm.com) on Kubernetes.

## Architecture

The chart deploys three separate deployments:

| Deployment          | Description                    | Scalable |
|---------------------|--------------------------------|----------|
| `espocrm-web`       | Web application (Apache + PHP) | ✅ Yes    |
| `espocrm-daemon`    | Background job processor       | ✅ Yes    |
| `espocrm-websocket` | WebSocket server               | ✅ Yes    |

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

### EspoCROM Config Override

you can bring your own config overrides by mounting them to the following paths:

- `config-override.php` -> `/var/www/html/data/config-override-cm.php` (see [here](./config/config-override.php))
- `config-override-internal.php` -> `/var/www/html/data/config-internal-override-cm.php` (see [here](./config/config-override.php))

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

EspoCRM's default file-based logging is reconfigured to write structured JSON logs to `stdout` via Monolog.
This makes logs directly consumable by Kubernetes log collectors (e.g. Fluentd, Loki, Datadog).

### Autoscaling

All three deployments (`web`, `daemon`, `websocket`) support HPA.

```yaml
web:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80

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
  size: 2Gi
  # storageClass: ""
  # existingClaim: ""
```

### Shared Volumes

All three deployments (`web`, `daemon`, `websocket`) and the bootstrap job mount the **same PVC** simultaneously.
The PVC is therefore created with `accessMode: ReadWriteMany` (RWX) — the configured `storageClass` must support RWX
(e.g. NFS, CephFS, Azure Files, EFS). `ReadWriteOnce` storage classes (e.g. standard cloud block storage) will **not**
work.

#### PVC layout

A single PVC (`<release>-data`) is partitioned into three sub-directories via `subPath`:

| subPath         | Mount path in container       | Purpose                                     |
|-----------------|-------------------------------|---------------------------------------------|
| `data`          | `/var/www/html/data`          | EspoCRM config, cache, logs, uploaded files |
| `custom`        | `/var/www/html/custom`        | Custom back-end extensions & overrides      |
| `client-custom` | `/var/www/html/client/custom` | Custom front-end assets                     |
