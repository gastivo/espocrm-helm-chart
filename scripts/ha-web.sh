#!/bin/bash

# Wraps the official docker-entrypoint.sh for the web main container.
#
# ha-bootstrap.sh (init container) already runs clear-cache + migrate under a
# distributed lock before this container starts, and records completion per
# revision in data/.bootstrap-ready. The official entrypoint's own
# actionMigrate() (triggered by apache2-foreground) runs the same EspoCRM
# core `migrate` command again with no lock, colliding with clearCache()'s
# full data/cache wipe on the shared RWX PVC while other pods are serving
# traffic (GASTIVO-5567). This wrapper skips that redundant re-run once the
# instance is installed, while still keeping the permission fix
# (setPermissions) that securityContext relies on. On a genuinely fresh
# install, the official flow runs completely unmodified.

set -euo pipefail

source /usr/local/bin/docker-entrypoint.sh

warnInsecureCredentials
warnLegacyInstallation

IS_INSTALLED="$(bin/command config:get isInstalled 2>/dev/null || echo false)"

if [ "$IS_INSTALLED" != "true" ]; then
  echo "info: Instance not installed yet — running the official entrypoint's install flow."
  start
else
  echo "info: Instance already installed — bootstrap init container already migrated this revision under lock; skipping redundant clear-cache/migrate."
  copyPublicFiles
  copyClientFiles
  setPermissions
fi

applyConfigEnv

exec apache2-foreground
