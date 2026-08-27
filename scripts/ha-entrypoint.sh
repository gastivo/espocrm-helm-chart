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

# Only the 9.x image layout needs the application materialised: there /var/www/html is empty and
# the application ships at /usr/src/espocrm. The 10.x image already has it at /var/www/html and
# keeps only client/ and public/ in /usr/src/espocrm — copying that would additionally write
# client/custom/modules/dummy.txt into the PVC on every pod start, since this copy (unlike
# upstream's own copyClientFiles()) does not exclude custom/. Keyed off the source layout so one
# chart serves both image versions.
if [ -d "$SOURCE_FILES/application" ]; then
  echo "info: 9.x image layout detected — copying EspoCRM files from $SOURCE_FILES to /var/www/html/"
  cp -a "$SOURCE_FILES/." /var/www/html/
else
  echo "info: 10.x image layout detected — application already present at /var/www/html."
fi

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

echo "info: Executing: $*"

exec "$@"
