#!/usr/bin/env bash
# server_info.sh - Print a system summary for the Ansible control server
# (AWS EC2 instance running RHEL 10).
#
# Every check falls back to "N/A" when a command or the EC2 metadata
# service is unavailable, so the script never stops part-way.

# Treat unset variables as errors, but do NOT use "set -e": a failing check
# should print "N/A" and let the script continue.
set -u

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Print a section header. "local" keeps the title variable inside the function.
section() {
    local title="$1"
    echo
    echo "==================== ${title} ===================="
}

# Return success if a command exists on this system.
have() {
    command -v "$1" >/dev/null 2>&1
}

# Print a "label: value" line, using N/A when the value is empty.
show() {
    local label="$1"
    local value="${2:-}"
    printf '%-20s %s\n' "${label}:" "${value:-N/A}"
}

# ---------------------------------------------------------------------------
# System
# ---------------------------------------------------------------------------
section "System"

# Hostname: prefer the hostname command, otherwise read the kernel's value.
if have hostname; then
    show "Hostname" "$(hostname 2>/dev/null)"
else
    show "Hostname" "$(cat /proc/sys/kernel/hostname 2>/dev/null)"
fi

# OS name: PRETTY_NAME from /etc/os-release (e.g. "Red Hat Enterprise Linux 10.0").
os_name=""
if [ -r /etc/os-release ]; then
    os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-}")"
fi
show "OS" "$os_name"

# Kernel release.
show "Kernel" "$(uname -r 2>/dev/null)"

# Uptime in readable form ("up 3 days, 4 hours").
if have uptime; then
    show "Uptime" "$(uptime -p 2>/dev/null)"
else
    show "Uptime" ""
fi

# Current date and time, including the time zone.
show "Date" "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"

# ---------------------------------------------------------------------------
# CPU and memory
# ---------------------------------------------------------------------------
section "CPU and Memory"

# Number of CPU cores available to the OS.
if have nproc; then
    show "CPU cores" "$(nproc 2>/dev/null)"
else
    show "CPU cores" "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
fi

# CPU model name from the first processor entry in /proc/cpuinfo.
cpu_model="$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)"
show "CPU model" "$cpu_model"

# Load average for the last 1, 5 and 15 minutes.
show "Load average" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

# Memory usage in human-readable units.
echo
echo "Memory:"
if have free; then
    free -h
else
    echo "N/A"
fi

# ---------------------------------------------------------------------------
# Disk usage
# ---------------------------------------------------------------------------
section "Disk Usage"

# Filesystem usage in human-readable units, excluding in-memory filesystems.
if have df; then
    df -h -x tmpfs -x devtmpfs 2>/dev/null || echo "N/A"
else
    echo "N/A"
fi

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
section "Network"

if have ip; then
    # IPv4 addresses on every interface except loopback (lo).
    # Output format: "<interface> <address/prefix>".
    ipv4_list="$(ip -o -4 addr show 2>/dev/null | awk '$2 != "lo" {print $2, $4}')"
    echo "IPv4 addresses:"
    if [ -n "$ipv4_list" ]; then
        echo "$ipv4_list" | sed 's/^/  /'
    else
        echo "  N/A"
    fi

    # Default gateway: the address after "via" in the default route.
    gateway="$(ip -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "via") {print $(i+1); exit}}')"
    show "Default gateway" "$gateway"
else
    echo "IPv4 addresses:"
    echo "  N/A"
    show "Default gateway" ""
fi

# ---------------------------------------------------------------------------
# AWS EC2 metadata (IMDSv2)
# ---------------------------------------------------------------------------
section "AWS EC2 Metadata"

# Base URL of the EC2 instance metadata service.
IMDS="http://169.254.169.254/latest"
token=""

# IMDSv2 step 1: request a session token with a PUT request (valid 6 hours).
# Short timeouts keep the script fast when it is not running on EC2.
if have curl; then
    token="$(curl -s -f --connect-timeout 2 --max-time 3 -X PUT \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        "${IMDS}/api/token" 2>/dev/null)"
fi

# IMDSv2 step 2: read one metadata path, sending the token in a header.
# Prints nothing when there is no token or the path does not exist
# (for example, public-ipv4 on an instance without a public IP).
imds_get() {
    local path="$1"
    [ -n "$token" ] || return 0
    curl -s -f --connect-timeout 2 --max-time 3 \
        -H "X-aws-ec2-metadata-token: ${token}" \
        "${IMDS}/meta-data/${path}" 2>/dev/null
}

# Print each value; show() substitutes N/A for empty results.
show "Instance ID"       "$(imds_get instance-id)"
show "Instance type"     "$(imds_get instance-type)"
show "Availability zone" "$(imds_get placement/availability-zone)"
show "Public IP"         "$(imds_get public-ipv4)"
show "Private IP"        "$(imds_get local-ipv4)"

# ---------------------------------------------------------------------------
# Ansible
# ---------------------------------------------------------------------------
section "Ansible"

# The first line of "ansible --version" contains the version number.
if have ansible; then
    show "Ansible version" "$(ansible --version 2>/dev/null | head -n 1)"
else
    show "Ansible version" ""
fi

# ---------------------------------------------------------------------------
# Top processes
# ---------------------------------------------------------------------------
section "Top 5 Processes by Memory"

# Header line plus the 5 processes using the most memory.
if have ps; then
    ps -eo pid,user,%mem,%cpu,comm --sort=-%mem 2>/dev/null | head -n 6 || echo "N/A"
else
    echo "N/A"
fi

# ---------------------------------------------------------------------------
# Logged-in users
# ---------------------------------------------------------------------------
section "Logged-in Users"

# One line per login session; print N/A if nobody is logged in.
if have who; then
    users_out="$(who 2>/dev/null)"
    echo "${users_out:-N/A}"
else
    echo "N/A"
fi

echo
