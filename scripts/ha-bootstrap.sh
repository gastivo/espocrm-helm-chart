#!/bin/bash

# this script is used on each deployment as pre-start job to prepare the EspoCRM files and configuration before the main entrypoint runs.
# It ensures that the upgrade process run only once per deployment and that the configuration overrides are applied correctly.

set -e

SOURCE_FILES="/usr/src/espocrm"

echo "info: Copying EspoCRM files from $SOURCE_FILES to /var/www/html/"
cp -a "$SOURCE_FILES/." /var/www/html/

echo "info: Running EspoCRM entrypoint..."
export ESPOCRM_CONFIG_LOGGER_LEVEL=DEBUG

/usr/local/bin/docker-entrypoint.sh

EXTENSIONS_PATH="${ESPOCRM_EXTENSIONS_PATH:-}"

if [ -n "$EXTENSIONS_PATH" ] && [ -d "$EXTENSIONS_PATH" ]; then

  if ls "$EXTENSIONS_PATH"/*.zip 1>/dev/null 2>&1; then
    echo "info: Installing extensions from $EXTENSIONS_PATH..."

    for zip in "$EXTENSIONS_PATH"/*.zip; do
      echo "info: Installing extension: $(basename "$zip")"
      /var/www/html/bin/command extension --file="$zip"
    done

    echo "info: All extensions installed."
  else
    echo "info: No .zip files found in $EXTENSIONS_PATH"
  fi
else
  echo "info: No extensions path provided or directory does not exist. Skipping extension installation."
fi

echo "info: EspoCRM bootstrap completed successfully."
