#!/usr/bin/env sh

# +----------------------------------------------------------------------------+
# | Simple script for Gluetun dynamic port forwarding (ProtonVPN, et. al.)     |
# |                                                                            |
# |                                                                            |
# | When Gluetun connects to the VPN in port forwarding mode, a random port    |
# | is chosen (by the VPN provider) for you. qBittorrent doesn't know what     |
# | port to listen on, so it won't receive any incoming connections.           |
# |                                                                            |
# | This script just edits qBittorrent's config (via the API) to update the    |
# | correct listening port. That's it.                                         |
# |                                                                            |
# | Designed to be called by Gluetun via the "VPN_PORT_FORWARDING_UP_COMMAND"  |
# | environment variable.                                                      |
# | e.g. /bin/sh -c '/scripts/qbittorrent_port_forward.sh {{PORTS}}'           |
# |                                                                            |
# | See docs for Gluetun and qBittorrent for more details.                     |
# |                                                                            |
# | NOTE: Only uses wget because curl isn't included in the Alpine (busybox)   |
# |       image, so it's not available in the official gluetun or qbittorrent  |
# |       containers.                                                          |
# +----------------------------------------------------------------------------+


# Read first argument - the listening port
readonly port=${1:-6881}

# Qbittorrent API details
readonly qbit_url=${QBIT_URL:-http://localhost:8080}
readonly username=${QBIT_USER:-admin}
readonly password=${QBIT_PASS:-adminadmin}

echo "${0}: Authenticating to qBittorrent as '${username}' at ${qbit_url}"

# Step 1: Authenticate and extract the SID cookie
cookie=$(wget -qO- \
    --save-headers \
    --header="Referer: ${qbit_url}" \
    --post-data="username=${username}&password=${password}" \
    ${qbit_url}/api/v2/auth/login | grep -o "SID=[^;]*")

echo "${0}: Setting qBittorrent listening port to ${port}"

# Step 2: Use the SID cookie to set the listen port in Qbittorrent preferences
wget -qO- \
    --header="Referer: ${qbit_url}" \
    --header="Cookie: ${cookie}" \
    --post-data="json={\"listen_port\":${port}}" \
    ${qbit_url}/api/v2/app/setPreferences

echo "${0}: Finished. Check qBittorrent Web UI to verify the listen port was set to ${port}."
