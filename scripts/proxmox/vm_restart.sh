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
readonly flag_file='/var/tmp/jb_scripts/vm_restart.flag'

# Ensure log file directory exists
mkdir -p "$(dirname "${log_file}")"

logprint() {
    # Echo to stderr and log file, but NOT to stdout
    # This leaves stdout available to for returning values from a function
    echo "[$(date)] (${user}) ${1}" | tee -a ${log_file} 1>&2
}

get_vm_status() {
    ${qm} status "$vmid" 2>/dev/null | grep -e 'status:'
}

print_vm_status() {
    local extra_message=${1}
    logprint "VM ${vmid} ${vm_status}${extra_message}"
}

# Check that VM is running (no need to reboot a stopped VM)
vm_status=$(get_vm_status)
# TODO - use bash regexp rather than invoking grep unneccessarily
if ! echo ${vm_status} | grep -q -e 'running'; then
    print_vm_status " - NOT RESTARTING."
    exit 0  # VM is stopped/not running; nothing to do
fi

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
case ${curl_exit_code} in
    0)
        print_vm_status ". Health check PASSED. Host is up - NOT RESTARTING."
        exit 0
        ;;
    7)
        print_vm_status \
        ". Health check FAILED - connection refused (code 7). Triggering restart..."
        ;;
    22)
        print_vm_status \
        ". Health check returned HTTP error code ${curl_http_code}. Host is up - NOT RESTARTING."
        exit 0
        ;;
    28)
        print_vm_status \
        ". Health check FAILED - timed out (code 28) after ${curl_retries} retries. Triggering restart..."
        ;;
    *)
        print_vm_status \
        ". Unknown error code ${curl_exit_code} from health check. NOT RESTARTING."
        exit ${curl_exit_code}
        ;;
esac

# Check enable/disable flag file
if [[ -e ${flag_file} ]] && grep -i -e 'disabled' -q "${flag_file}"; then
    logprint "SCRIPT DISABLED in ${flag_file} - ABORTING"
    exit 0
fi

# Attempt shutdown
readonly qm_timeout=120
logprint "Shutting down VM ${vmid}... (force stop after ${qm_timeout} sec)"
${qm} shutdown ${vmid} --timeout ${qm_timeout} --forceStop true
logprint "Completed shutdown command for VM ${vmid} (either shut down or killed)"
vm_status=$(get_vm_status)
print_vm_status

# Start VM
logprint "Starting VM ${vmid}..."
${qm} start ${vmid}
logprint "Completed start command for VM ${vmid}"
vm_status=$(get_vm_status)
print_vm_status

# Check again after a bit, in case it hadn't started
sleep 10
vm_status=$(get_vm_status)
print_vm_status
logprint "Finished."
