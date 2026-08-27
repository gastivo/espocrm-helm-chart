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

# Materialising the application only applies to the 9.x image layout, where /var/www/html is
# empty and the application ships at /usr/src/espocrm. The 10.x image ships the application at
# /var/www/html and leaves only client/ and public/ in /usr/src/espocrm — copying that would be
# pointless and would write client/custom/modules/dummy.txt into the PVC on every pod start,
# because unlike upstream's own copyClientFiles() this copy does not exclude custom/.
# Keyed off the source layout so one chart serves both image versions.
if [ -d "$SOURCE_FILES/application" ]; then
  echo "info: 9.x image layout detected — copying EspoCRM files from $SOURCE_FILES to /var/www/html/"
  cp -a "$SOURCE_FILES/." /var/www/html/
else
  echo "info: 10.x image layout detected — application already present at /var/www/html, nothing to copy."
fi

# NOTE: the config files must NOT be removed here. A former block deleted data/config.php and
# data/config-internal.php whenever the ready marker was absent, to force a reinstall. Since
# EspoCRM 10 that is unrecoverable: the entrypoint branches only on isInstalled, so without the
# config it installs from scratch against populated tables and dies silently under `set -e`.
# It also rotates cryptKey, which makes encrypted values in the surviving database undecryptable.

export ESPOCRM_CONFIG_LOGGER_LEVEL=DEBUG

echo "info: Running EspoCRM entrypoint..."

# Under 9.x this performs the install/upgrade. Under 10.x it is a no-op: start() only runs when
# the first argument is apache2*/php-fpm, which an init container cannot supply because it has to
# exit rather than exec a web server. The explicit migration below covers the 10.x path.
# Redirect stderr to stdout so entrypoint messages appear in kubectl logs
/usr/local/bin/docker-entrypoint.sh 2>&1

# Read isInstalled straight from the config files rather than via `bin/command config:get`:
# no database connection is needed, it works before the instance is installed, and it does not
# depend on a console command being registered the same way in both image versions.
IS_INSTALLED="$(php -r '
    foreach (["/var/www/html/data/config-internal.php", "/var/www/html/data/config.php"] as $file) {
        if (!file_exists($file)) {
            continue;
        }
        $config = include $file;
        if (is_array($config) && array_key_exists("isInstalled", $config)) {
            echo $config["isInstalled"] ? "true" : "false";
            exit;
        }
    }
    echo "false";
' 2>/dev/null || echo false)"

echo "info: Instance installed: ${IS_INSTALLED}"

if [ "$IS_INSTALLED" = "true" ]; then
  # This is what actionMigrate() does. Under 10.x it is the only place the migration runs at all;
  # under 9.x the entrypoint above already upgraded, so it is a no-op. Either way it costs ~60ms
  # once the version matches, and it happens here under the bootstrap lock rather than
  # concurrently in every web pod.
  echo "info: Clearing cache and running migration under the bootstrap lock."
  /var/www/html/bin/command clear-cache
  /var/www/html/bin/command migrate
else
  echo "warning: Instance is not installed — skipping migration and extension installation."
  echo "warning:   Since EspoCRM 10 the initial installation happens in the web container's own"
  echo "warning:   entrypoint, which starts only after this init container. Without config.php"
  echo "warning:   the database parameters do not exist yet, so 'bin/command extension' would"
  echo "warning:   fail with \"No database params in config\" and put this init container into"
  echo "warning:   CrashLoopBackOff, blocking the very installation it depends on."
  echo "warning:   The next 'helm upgrade' bumps HELM_RELEASE_REVISION, so this bootstrap runs"
  echo "warning:   again against the now-installed instance and installs the extensions then."
fi

if [ "$IS_INSTALLED" = "true" ]; then
  EXTENSIONS_PATH="${ESPOCRM_EXTENSIONS_PATH:-}"
else
  # See the warning above: installing extensions before the instance exists aborts this container.
  EXTENSIONS_PATH=""
fi

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

echo "info: setting ownership of /var/www/html/custom..."
chown -R www-data:www-data /var/www/html/custom

echo "info: EspoCRM bootstrap completed successfully."

echo "info: Writing ready marker to $READY_FILE (revision: ${HELM_RELEASE_REVISION})"
echo "${HELM_RELEASE_REVISION}" > "$READY_FILE"
