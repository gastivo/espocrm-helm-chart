#!/bin/bash

# this script is used as entrypoint for the HA setup,
# it prepares the EspoCRM files and configuration before the main entrypoint runs.

set -e

SOURCE_FILES="/usr/src/espocrm"

echo "info: Copying EspoCRM files from $SOURCE_FILES to /var/www/html/"
cp -a "$SOURCE_FILES/." /var/www/html/

echo "info: Setting ownership of /var/www/html/ to www-data"
chown -R -f www-data:www-data /var/www/html/ || true

echo "info: Copy done, executing: $*"

exec "$@"
