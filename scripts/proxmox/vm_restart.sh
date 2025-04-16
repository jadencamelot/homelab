#!/usr/bin/env bash

# Script to forcibly restart a VM if it's running but a curl health check fails.
# Designed to be run as a cron job, as root.
#
# Can be selectively disabled by including the string "disabled" to a flag file
# specified at path ${flag_file}.

readonly vmid="${1:-100}"
readonly user="$(id -un)"
readonly qm='/usr/sbin/qm'  # Not on $PATH in cron, absolute path required
readonly log_file='/var/log/jb_scripts/vm_restart.log'
readonly flag_file='/var/tmp/jb_scripts/vm_restart.flag'      # 'enabled' / 'disabled'
readonly status_file='/var/tmp/jb_scripts/vm_restart.status'  # Store most recent vm status
readonly pushover_user_key_file='/root/jb_scripts/.secrets/pushover_user_key.txt'
readonly pushover_api_token_file='/root/jb_scripts/.secrets/pushover_api_token.txt'
readonly pushover_message_priority='-1'  # quiet delivery (no sound)
readonly pushover_message_ttl='604800'   # 7 days, in seconds
readonly pushover_url='https://api.pushover.net/1/messages.json'

# Newline char (for easier message formatting)
readonly n="
"

# Read secrets from file
readonly pushover_user_key=$(cat "${pushover_user_key_file}")
readonly pushover_api_token=$(cat "${pushover_api_token_file}")

# Ensure log file directory exists
mkdir -p "$(dirname "${log_file}")"

logprint() {
    # Echo to stderr and log file, but NOT to stdout
    # This leaves stdout available to for returning values from a function
    echo "[$(date)] (${user}) ${1}" | tee -a ${log_file} 1>&2
}

get_vm_status() {
    # Get current status of VM
    # NOTE: qm returns something like 'status: running', so we use cut and tr to remove the 'status: ' bit
    local status=$(${qm} status "$vmid" 2>/dev/null | grep -e 'status:' | cut -d: -f2 | tr -d '[:space:]')

    # Save new status to disk
    echo "${status}" >${status_file}

    # Return current status
    echo "${status}"
}

print_vm_status() {
    local extra_message=${1}
    logprint "VM ${vmid} status: ${vm_status} (was ${vm_status_prev})${extra_message}"
}

send_pushover_notification() {
    local readonly title=${1}
    local readonly message=${2}

    # Escape newlines in message, for logging purposes
    message_escaped=${message//$'\n'/\\n}

    # Log message
    logprint "Pushing notification.  Title: \"${title}\"  Message: \"${message_escaped}\""

    # Send notification via Pushover API.
    #  - Capture curl's output.
    #  - Exclude the download meter with --silent, but include any actual errors
    #      with --show-error, plus redirecting stderr to stdout
    response=$(curl \
    --form-string "title=${title}" \
    --form-string "message=${message}" \
    --form-string "priority=${pushover_message_priority}" \
    --form-string "ttl=${pushover_message_ttl}" \
    --form-string "html=1" \
    --form-string "user=${pushover_user_key}" \
    --form-string "token=${pushover_api_token}" \
    --silent \
    --show-error \
    "${pushover_url}" 2>&1)

    # Log curl's output
    logprint "Pushover API Response: ${response}"
}

notify_on_status() {
    if [[ "${vm_status}" == "${vm_status_prev}" ]]; then
        # Exit early - only send notification if the status has changed since last run
        return 0;
    fi

    local title
    local message
    local serious_message

    case "${vm_status}" in
        running)
            title="YEAH!"
            message="VM is alive again YEAH :)"
            serious_message="Please allow ~1 minute for all services to fully start up."
            ;;
        stopped|paused)
            title="Oops"
            message="Jaden is probably working on something"
            serious_message="VM is currently ${vm_status}"
            ;;
        internal-error|*)
            title="Ai Ya"
            message="I do not know why it is <b>${vm_status}</b>, just wait :("
            print_vm_status " - NOT RESTARTING."
            ;;
    esac
    status_message="<b>VM Status:</b> <i>${vm_status}</i> (was <i>${vm_status_prev}</i>)"
    send_pushover_notification "${title}" "${message}${n}${n}${serious_message}${n}${n}${status_message}"
}

# Check enable/disable flag file
if [[ -e ${flag_file} ]] && grep -i -e 'disabled' -q "${flag_file}"; then
    logprint "SCRIPT DISABLED in ${flag_file} - ABORTING"
    exit 0
fi

# Save most recent previous status (so we can detect if the status has changed since last run)
vm_status_prev="$(cat "${status_file}")"

# Get VM status
vm_status=$(get_vm_status)

# Send push notification (only if the VM status has changed)
notify_on_status

case ${vm_status} in
    running) ;;  # Expected case - continue with script
    stopped|paused|internal-error|*)
        # stopped|paused
        #     If the VM is stopped or paused, assume it's deliberate by the user
        #     and therefore we don't want to forcibly restart it
        # internal-error
        #     Unexpected case - leave it be, there is probably something wrong
        #     with the VM (eg. invalid config) that a restart won't fix
        # *
        #     Unexpected catch-all - don't trigger restart on weird edge cases
        print_vm_status " - NOT RESTARTING."
        exit 0  # Don't restart
        ;;
esac

# Health check
readonly healthcheck_url='http://ubuntu-nord.home.arpa:80/healthcheck'
readonly curl_retries=3
curl_http_code=$(curl \
    -o /dev/null \
    --silent \
    --write-out '%{http_code}\n' \
    --connect-timeout 5 \
    --fail \
    --retry ${curl_retries} \
    --retry-all-errors \
    "${healthcheck_url}" \
)
curl_exit_code=${?}
exit_early='false'
exit_code=0
case ${curl_exit_code} in
    0)
        health_check="Health check PASSED. Host is up - NOT RESTARTING."
        exit_early='true'
        ;;
    7)
        health_check="Health check FAILED - connection refused (code 7). Triggering restart..."
        ;;
    22)
        health_check="Health check returned HTTP error code ${curl_http_code}. Host is up - NOT RESTARTING."
        exit_early='true'
        ;;
    28)
        health_check="Health check FAILED - timed out (code 28) after ${curl_retries} retries. Triggering restart..."
        ;;
    *)
        health_check="Unknown error code ${curl_exit_code} from health check. NOT RESTARTING."
        exit_code=${curl_exit_code}
        ;;
esac
print_vm_status ". ${health_check}"
if [[ ${exit_early} == 'true' ]]; then
    exit ${exit_code}
fi

title="Uh oh"
message="VM down! VM down! please be patient :("
serious_message="Triggering VM restart, please wait ~3 minutes"
health_check_message="<b>Debug info:</b> <i>'${health_check}'</i>"
send_pushover_notification "${title}" "${message}${n}${n}${serious_message}${n}${n}${health_check_message}"

# Attempt shutdown
readonly qm_timeout=120
logprint "Shutting down VM ${vmid}... (force stop after ${qm_timeout} sec)"
${qm} shutdown ${vmid} --timeout ${qm_timeout} --forceStop true
logprint "Completed shutdown command for VM ${vmid} (either shut down or killed)"
vm_status_prev="$(cat "${status_file}")"
vm_status=$(get_vm_status)
print_vm_status

# Start VM
logprint "Starting VM ${vmid}..."
${qm} start ${vmid}
logprint "Completed start command for VM ${vmid}"

# Check again after a bit, to give it time to start
sleep 10
vm_status_prev="$(cat "${status_file}")"
vm_status=$(get_vm_status)
print_vm_status
logprint "Finished."

# Send push notification for new status
notify_on_status
