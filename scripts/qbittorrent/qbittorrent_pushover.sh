#!/usr/bin/env bash

# Usage with qbittorrent
#
# Preferences > Downloads > Run external program
# Run on torrent added:
#   /scripts/qbittorrent_pushover.sh -a 'added' -C '%C' -D '%D' -F '%F' -G '%G' -I '%I' -J '%J' -K '%K' -L '%L' -N '%N' -R '%R' -T '%T' -Z '%Z' 
# Run on torrent finished
#   /scripts/qbittorrent_pushover.sh -a 'finished' -C '%C' -D '%D' -F '%F' -G '%G' -I '%I' -J '%J' -K '%K' -L '%L' -N '%N' -R '%R' -T '%T' -Z '%Z' 

# Constants
readonly log_file='/config/qBittorrent/logs/pushover.log'
readonly message_priority='-1'  # quiet delivery (no sound)
readonly pushover_url='https://api.pushover.net/1/messages.json'

# Read from environment
readonly domain=${DOMAIN:-home.arpa} # qBittorrent server DNS name
readonly pushover_user_key=${PUSHOVER_USER_KEY:?Missing PUSHOVER_USER_KEY}
readonly pushover_api_token=${PUSHOVER_API_TOKEN:?Missing PUSHOVER_API_TOKEN}

# Arguments names match qBittorrent's parameter substitutions (as of v4.6.5).
# Can be found in Options > Run External Program > Supported parameters
while getopts 'a:hC:D:F:G:I:J:K:L:N:R:T:Z:' flag; do
  case "${flag}" in
    a) action="${OPTARG}" ;;
    h) help='true' ;;
    C) torrent_numfiles="${OPTARG}" ;;
    D) torrent_path_save="${OPTARG}" ;;
    F) torrent_path_content="${OPTARG}" ;;
    G) torrent_tags="${OPTARG}" ;;
    I) torrent_hash_v1="${OPTARG}" ;;
    J) torrent_hash_v2="${OPTARG}" ;;
    K) torrent_hash_id="${OPTARG}" ;;
    L) torrent_category="${OPTARG}" ;;
    N) torrent_name="${OPTARG}" ;;
    R) torrent_path_root="${OPTARG}" ;;
    T) torrent_tracker="${OPTARG}" ;;
    Z) torrent_size="${OPTARG}" ;;
    *) error "Unexpected option ${flag}" ;;
  esac
done

if [[ -n "${help}" ]]; then
  echo <<END
usage: ${0} [-a {added,finished}] [-h] [-v] [-C val] [-D val] [-F val] [-G val] [-I val] [-J val] [-K val] [-L val] [-N val] [-R val] [-T val] [-Z val]

options:
  -h                   Show this help message and exit.
  -a {added,finished}  Required. Specify the action that happened to the torrent.
  -C value             Number of files            (use %C from qBittorrent)
  -D value             Save path                  (use %D from qBittorrent)
  -F value             Content path               (use %F from qBittorrent)
  -G value             Tags (separated by comma)  (use %G from qBittorrent)
  -I value             Info hash v1               (use %I from qBittorrent)
  -J value             Info hash v2               (use %J from qBittorrent)
  -K value             Torrent ID                 (use %K from qBittorrent)
  -L value             Category                   (use %L from qBittorrent)
  -N value             Torrent name               (use %N from qBittorrent)
  -R value             Root path                  (use %R from qBittorrent)
  -T value             Current tracker            (use %T from qBittorrent)
  -Z value             Torrent size (bytes)       (use %Z from qBittorrent)

example usage:
  Using all parameters from qBittorrent:
    ${0} -a "added" -C "%C" -D "%D" -F "%F" -G "%G" -I "%I" -J "%J" -K "%K" -L "%L" -N "%N" -R "%R" -T "%T" -Z "%Z" 
END
  exit 0
fi

# Convert bytes to human readable range
readonly torrent_size_h="$(numfmt --to=iec-i "${torrent_size:=0}")"

# Preference order for values that overlap
readonly torrent_path="${torrent_path_save:-${torrent_path_content:-${torrent_path_root}}}"
readonly torrent_hash="${torrent_hash_id:-${torrent_hash_v2:-${torrent_hash_v1}}}"

# Construct notification title
case "${action}" in
  added)    title="⏳ Started Download" ;;
  finished) title="✅ Download Complete" ;;
  *)
    echo "Invalid action '${action}'. Must specify -a {'added', 'finished'}"
    exit 1
    ;;
esac

# Construct notification message
message="${title}

<b>Name:</b> ${torrent_name}
<b>Size:</b> ${torrent_size_h}B (${torrent_numfiles:-??} files)
<b>Path:</b> ${torrent_path}
<b>Tags:</b> ${torrent_tags}
<b>Category:</b> ${torrent_category}
<b>Hash:</b> ${torrent_hash}
<b>Tracker:</b> ${torrent_tracker}

View in:
  • <a href=https://iqbit.${domain}>iQbit</a>
  • <a href=https://qbittorrent.${domain}>qBittorrent</a>"

# Escape newlines in message, for logging purposes
message_escaped=${message//$'\n'/\\n}

# Log message
echo "Pushing notification.  Message: \"${message}\""
echo "[$(date)] Pushing notification.  Message: \"${message_escaped}\"" >> ${log_file}

# Send notification via Pushover API.
#  - Capture curl's output.
#  - Exclude the download meter with --silent, but include any actual errors
#      with --show-error, plus redirecting stderr to stdout
response=$(curl \
  --form-string "message=${message}" \
  --form-string "priority=${message_priority}" \
  --form-string "html=1" \
  --form-string "user=${pushover_user_key}" \
  --form-string "token=${pushover_api_token}" \
  --silent \
  --show-error \
  "${pushover_url}" 2>&1)

# Log curl's output
echo "${response}"
echo "[$(date -Isec)] Pushover API Response: ${response}" >> ${log_file}
