#!/bin/bash

# Waits until the bootstrap init container has completed for the current Helm release revision.
# Requires HELM_RELEASE_REVISION to be set as an environment variable.

set -e

READY_FILE="/var/www/html/data/.bootstrap-ready"

echo "info: Waiting for bootstrap revision ${HELM_RELEASE_REVISION}..."

until [ "$(cat "$READY_FILE" 2>/dev/null)" = "${HELM_RELEASE_REVISION}" ]; do
  current="$(cat "$READY_FILE" 2>/dev/null || echo 'none')"
  echo "info: Bootstrap not ready yet (want: ${HELM_RELEASE_REVISION}, got: ${current}), retrying in 5s..."
  sleep 5
done

echo "info: Bootstrap ready at revision ${HELM_RELEASE_REVISION}, proceeding."

