#!/bin/bash

# this script is used as entrypoint for the HA setup,
# it prepares the EspoCRM files and configuration before the main entrypoint runs.

set -e

PERMISSION_FIX=(
"/var/www/html/custom"
"/var/www/html/custom/Espo"
"/var/www/html/custom/Espo/Custom"
"/var/www/html/custom/Espo/Modules"
)

if [ "${SKIP_CHOWN:-false}" != "true" ]; then
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
