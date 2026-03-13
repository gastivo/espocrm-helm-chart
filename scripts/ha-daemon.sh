#!/bin/bash
# Wrapper for EspoCRM daemon that forwards file logs to stdout
#
# Problem: The daemon spawns cron.php as child processes whose stdout/stderr
# are buffered by Symfony Process and never reach Docker.
#
# Solution: Log to file + tail -f to forward logs to stdout for Docker/kubectl.

set -euo pipefail

LOG_FILE="/tmp/espocrm_daemon.log"

# Ensure log file exists
touch "$LOG_FILE"

# Start tail -f in background to forward file logs to stdout
tail -f "$LOG_FILE" &
TAIL_PID=$!

# Cleanup tail on exit, ensuring logs are flushed
cleanup() {
    if kill "$TAIL_PID" 2>/dev/null; then
        wait "$TAIL_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Run the original EspoCRM daemon script
exec /usr/local/bin/docker-daemon.sh
