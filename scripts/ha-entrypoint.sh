#!/bin/bash

# this script is used as entrypoint for the HA setup,
# it prepares the EspoCRM files and configuration before the main entrypoint runs.

set -e

SOURCE_FILES="/usr/src/espocrm"

PERMISSION_FIX=(
"/var/www/html/custom"
"/var/www/html/custom/Espo"
"/var/www/html/custom/Espo/Custom"
"/var/www/html/custom/Espo/Modules"
)

echo "info: Copying EspoCRM files from $SOURCE_FILES to /var/www/html/"
cp -a "$SOURCE_FILES/." /var/www/html/

if [ "${SKIP_CHOWN:-false}" != "true" ]; then
  echo "info: Setting ownership of /var/www/html/ to www-data (skipping mount points)"
  find /var/www/html -xdev -exec chown www-data:www-data {} + || true
  
  echo "info: Setting ownership for /var/www/html/custom to www-data"
  for dir in "${PERMISSION_FIX[@]}"; do
    if [ -d "$dir" ]; then
      chown www-data:www-data "$dir" || true
    fi
  done
else
  echo "info: Skipping chown (SKIP_CHOWN=true)"
fi

echo "info: Copy done, executing: $*"

exec "$@"
