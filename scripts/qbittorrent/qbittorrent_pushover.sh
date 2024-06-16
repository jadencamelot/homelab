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
readonly message_ttl='345600'   # 4 days, in seconds
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

if [[ "${help}" == "true" ]]; then
  echo "\
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
    ${0} -a 'added' -C '%C' -D '%D' -F '%F' -G '%G' -I '%I' -J '%J' -K '%K' -L '%L' -N '%N' -R '%R' -T '%T' -Z '%Z' "
  exit 0
fi

# Convert bytes to human readable range, 2 decimal places
readonly torrent_size_h="$(numfmt --to=iec-i --format=%.2f "${torrent_size:=0}")B"

# Preference order for values that overlap
readonly torrent_path="${torrent_path_save:-${torrent_path_content:-${torrent_path_root}}}"
readonly torrent_hash="${torrent_hash_id:-${torrent_hash_v2:-${torrent_hash_v1}}}"

# Construct notification message & title
case "${action}" in
  added)
    title="Download Started"
    message="<b>⏳ ${torrent_name}</b>

<b>Folder:</b> <i>${torrent_path_save}</i>
<b>Category:</b> ${torrent_category}
${torrent_tags:+"(<b>Tags:</b> ${torrent_tags})"}"
    ;;
  finished)
    title="Download Complete"
    message="<b>✅ ${torrent_name}</b>

<b>Size:</b> ${torrent_size_h} (${torrent_numfiles:-??} files)
<b>Folder:</b> <i>${torrent_path_content}</i>
<b>Tracker:</b> <i>${torrent_tracker}</i>
<b>Category:</b> ${torrent_category}
${torrent_tags:+"(<b>Tags:</b> ${torrent_tags})"}"
    ;;
  *)
    echo "Invalid action '${action}'. Must specify -a {'added', 'finished'}"
    exit 1
    ;;
esac

# Escape newlines in message, for logging purposes
message_escaped=${message//$'\n'/\\n}

# Log message
echo "Pushing notification.  Title: \"${title}\"  Message: \"${message}\""
echo "[$(date)] Pushing notification.  Title: \"${title}\"  Message: \"${message_escaped}\"" >> ${log_file}

# Send notification via Pushover API.
#  - Capture curl's output.
#  - Exclude the download meter with --silent, but include any actual errors
#      with --show-error, plus redirecting stderr to stdout
response=$(curl \
  --form-string "title=${title}" \
  --form-string "message=${message}" \
  --form-string "priority=${message_priority}" \
  --form-string "ttl=${message_ttl}" \
  --form-string "html=1" \
  --form-string "url=https://iqbit.${domain}" \
  --form-string "url_title=Open iQbit" \
  --form-string "user=${pushover_user_key}" \
  --form-string "token=${pushover_api_token}" \
  --silent \
  --show-error \
  "${pushover_url}" 2>&1)

# Log curl's output
echo "${response}"
echo "[$(date -Isec)] Pushover API Response: ${response}" >> ${log_file}
