#!/bin/bash

# this script is used on each deployment as pre-start job to prepare the EspoCRM files and configuration before the main entrypoint runs.
# It ensures that the upgrade process run only once per deployment and that the configuration overrides are applied correctly.

set -e

READY_FILE="/var/www/html/data/.bootstrap-ready"
LOCK_DIR="/var/www/html/data/.bootstrap-lock-${HELM_RELEASE_REVISION}"

# ── Distributed lock ────────────────────────────────────────────────────────
# mkdir is atomic on shared POSIX filesystems (NFS/RWX PVCs included).
# The EXIT trap releases the lock in all cases (clean exit, set -e abort,
# SIGTERM). Waiting pods retry mkdir on every loop iteration, so as soon as
# the lock disappears they race to take over.

# Copy config overrides from /tmp (ConfigMap mount) into the data directory
if [ -f /tmp/config-override.php ]; then
  echo "info: Copying config-override.php to /var/www/html/data/"
  cp /tmp/config-override.php /var/www/html/data/config-override.php
fi
if [ -f /tmp/config-internal-override.php ]; then
  echo "info: Copying config-internal-override.php to /var/www/html/data/"
  cp /tmp/config-internal-override.php /var/www/html/data/config-internal-override.php
fi

# Fast path: already done by a previous pod
if [ "$(cat "$READY_FILE" 2>/dev/null)" = "${HELM_RELEASE_REVISION}" ]; then
  echo "info: Bootstrap for revision ${HELM_RELEASE_REVISION} already completed. Skipping."
  exit 0
fi

# Remove lock dirs from old revisions
find "$(dirname "$LOCK_DIR")" -maxdepth 1 -name '.bootstrap-lock-*' \
  ! -name ".bootstrap-lock-${HELM_RELEASE_REVISION}" -exec rm -rf {} + 2>/dev/null || true

# Race for the lock; losers wait and retry mkdir each iteration
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  if [ "$(cat "$READY_FILE" 2>/dev/null)" = "${HELM_RELEASE_REVISION}" ]; then
    echo "info: Bootstrap completed by another pod while waiting. Skipping."
    exit 0
  fi
  current="$(cat "$READY_FILE" 2>/dev/null || echo 'none')"
  echo "info: Another pod holds the bootstrap lock (want: ${HELM_RELEASE_REVISION}, got: ${current}), retrying in 5s..."
  sleep 5
done

echo "info: Acquired bootstrap lock for revision ${HELM_RELEASE_REVISION}."

# Release lock on every exit (normal, error, SIGTERM)
trap 'rm -rf "$LOCK_DIR"' EXIT
# ────────────────────────────────────────────────────────────────────────────

SOURCE_FILES="/usr/src/espocrm"

echo "info: Copying EspoCRM files from $SOURCE_FILES to /var/www/html/"

# On a clean install (no ready marker from any previous revision), remove stale
# config files that a previously crashed bootstrap run may have left behind.
# Without this, the entrypoint sees isInstalled=1 and skips the installation.
if [ ! -f "$READY_FILE" ]; then
  echo "info: No previous bootstrap marker found — cleaning stale config files for fresh install."
  rm -f /var/www/html/data/config.php /var/www/html/data/config-internal.php
fi

cp -a "$SOURCE_FILES/." /var/www/html/

echo "info: Running EspoCRM entrypoint..."
export ESPOCRM_CONFIG_LOGGER_LEVEL=DEBUG

# Redirect stderr to stdout so entrypoint messages appear in kubectl logs
/usr/local/bin/docker-entrypoint.sh 2>&1

EXTENSIONS_PATH="${ESPOCRM_EXTENSIONS_PATH:-}"

if [ -n "$EXTENSIONS_PATH" ] && [ -d "$EXTENSIONS_PATH" ]; then

  if ls "$EXTENSIONS_PATH"/*.zip 1>/dev/null 2>&1; then
    echo "info: Installing extensions from $EXTENSIONS_PATH..."

    # If the extensions upload directory is missing or empty the PVC was likely
    # wiped (e.g. after a PVC recreation). In that case the DB may still report
    # extensions as installed but the actual files are gone, so we must ignore
    # the DB state and reinstall every extension unconditionally.
    pvc_has_ext_files=false
    if [ -d /var/www/html/data/upload/extensions ] \
       && [ -n "$(ls -A /var/www/html/data/upload/extensions 2>/dev/null)" ]; then
      pvc_has_ext_files=true
    fi
    echo "info: PVC extension files present: ${pvc_has_ext_files}"

    for zip in "$EXTENSIONS_PATH"/*.zip; do
      # Read name + version from the ZIP manifest (handle both 'manifest.json' and '/manifest.json')
      ext_name=$(php -r "
        \$z = new ZipArchive();
        \$z->open('$zip');
        \$content = \$z->getFromName('manifest.json');
        if (\$content === false) \$content = \$z->getFromName('/manifest.json');
        \$m = json_decode(\$content);
        echo \$m->name ?? '';
      " 2>/dev/null)

      ext_version=$(php -r "
        \$z = new ZipArchive();
        \$z->open('$zip');
        \$content = \$z->getFromName('manifest.json');
        if (\$content === false) \$content = \$z->getFromName('/manifest.json');
        \$m = json_decode(\$content);
        echo \$m->version ?? '';
      " 2>/dev/null)

      if [ -z "$ext_name" ] || [ -z "$ext_version" ]; then
        echo "warning: Could not read manifest from $(basename "$zip"), installing anyway..."
        /var/www/html/bin/command extension --file="$zip"
        continue
      fi

      # Check if this exact name+version is already installed in the DB
      already_installed=$(/var/www/html/bin/command extension --list 2>/dev/null \
        | awk "/Name: ${ext_name}/{found=1} found && /Version: ${ext_version}/{ver=1} found && /Installed: yes/{inst=1} found && /^$/{if(ver && inst) print \"yes\"; found=0; ver=0; inst=0}" \
        | head -1)

      if [ "$already_installed" = "yes" ] && [ "$pvc_has_ext_files" = "true" ]; then
        echo "info: Skipping $(basename "$zip") — ${ext_name} v${ext_version} already installed and files present on PVC."
      else
        if [ "$already_installed" = "yes" ] && [ "$pvc_has_ext_files" = "false" ]; then
          echo "info: ${ext_name} v${ext_version} is installed in DB but PVC has no extension files — reinstalling..."
        else
          echo "info: Installing $(basename "$zip") — ${ext_name} v${ext_version}..."
        fi
        /var/www/html/bin/command extension --file="$zip"
      fi
    done

    echo "info: All extensions processed."
  else
    echo "info: No .zip files found in $EXTENSIONS_PATH"
  fi
else
  echo "info: No extensions path provided or directory does not exist. Skipping extension installation."
fi

echo "info: EspoCRM bootstrap completed successfully."

echo "info: Writing ready marker to $READY_FILE (revision: ${HELM_RELEASE_REVISION})"
echo "${HELM_RELEASE_REVISION}" > "$READY_FILE"
