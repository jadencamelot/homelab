#!/usr/bin/env bash

readonly message="${1:-This was sent via curl, but no message body was specified.}"
readonly title="${2:-qBittorrent}"
readonly logfile='/config/qBittorrent/logs/pushover.log'

# Log that the script was called, and the arguments
echo "[$(date -Isec)] Pushing notification.  Title: \"${title}\"  Message: \"${message}\"" >> ${logfile}

# Capture curl's output. Exclude the download meter with --silent, but include any actual errors with --show-error
response=$(curl "https://api.pushover.net/1/messages.json" \
    -d message="${message}" \
    -d title="${title}" \
    -d user="${PUSHOVER_USER_KEY}" \
    -d token="${PUSHOVER_API_TOKEN}" \
    -XPOST \
    --silent \
    --show-error \
)

# Log curl's output
echo "[$(date -Isec)] Pushover API Response: ${response}" >> ${logfile}
