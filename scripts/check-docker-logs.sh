#!/bin/bash

# Script Name: Docker Logs Checker
# Date Written: 2025-01-26
# Author: Your Name
# Usage: This script checks Docker container logs for specific keywords and records unique error messages, filtering duplicates and displaying only the latest message for each issue.

# Define the log file path
log_file="Logs/docker_logs_$(date +'%Y%m%d_%H%M%S').log"

# Create or clear the log file
mkdir -p Logs
> "$log_file"

# Function to write to both console and log file
write_log() {
    echo "$1" | tee -a "$log_file"
}

# Add a header to the log file
header=$(cat <<EOF
Script Name: Docker Logs Checker
Date: $(date +'%Y-%m-%d %H:%M:%S')
Usage: This script checks Docker container logs for specific keywords and records unique error messages, filtering duplicates and displaying only the latest message for each issue.
------------------------------------------------------------
EOF
)
write_log "$header"

# Get the list of containers (filtered by name if provided)
if [ "$1" ]; then
    containers=$(docker ps -q -f "name=$1")
    if [ -z "$containers" ]; then
        write_log "No container found with the name '$1'."
        exit 1
    fi
else
    containers=$(docker ps -q)
fi

# Keywords to search for
keywords=("error" "warn" "failed" "critical" "exception" "traceback" "timeout" "unavailable" "fatal" "could not resolve host" "unknown user/group" "no available indexers" "skipping \"/var/log/acpid.log\"" "connection reset by peer")

# Initialize an associative array to store unique error messages
declare -A unique_messages

# Function to extract core message by removing timestamp and other varying parts
get_core_message() {
    local log_message="$1"
    core_message=$(echo "$log_message" | sed -r 's/time=".*?" //; s/

\[.*?\]

//; s/[0-9]{2,}:[0-9]{2}:[0-9]{2}\.[0-9]+//; s/[0-9]{4}-[0-9]{2}-[0-9]{2}//')
    echo "$core_message" | xargs
}

# Check logs for each container and search for keywords
for container in $containers; do
    container_name=$(docker inspect --format '{{.Name}}' "$container" | sed 's#/##')
    write_log "Container: $container_name ($container)"

    has_issues=false
    for keyword in "${keywords[@]}"; do
        logs=$(docker logs "$container" 2>&1 | grep -i "$keyword")
        while IFS= read -r log; do
            core_message=$(get_core_message "$log")
            # Filter out specific log messages and store the latest message
            if [[ ! "$core_message" =~ Failed=0 ]] && [[ ! "$core_message" =~ Migrating.data.source=.* ]] && [[ ! "$core_message" =~ Logging.to.*\/mariadb-error.log.* ]] && [[ ! "$core_message" =~ PHP_ERROR_LOG.* ]]; then
                unique_messages["$core_message"]="$log"
                has_issues=true
            fi
        done <<< "$logs"
    done
    
    if $has_issues; then
        write_log "Problems found in container: $container_name"
        for core_message in "${!unique_messages[@]}"; do
            write_log "${unique_messages[$core_message]}"
        done
    else
        write_log "No issues found."
    fi
    
    write_log "--------------------------"
    write_log ""  # Add a blank line for readability
    write_log ""