#!/bin/bash

# Container AppData Backup Script
# --------------------------------
# This script backs up Docker container appdata directories, performs
# health checks, stops containers safely, and sends an email alert if
# any failures occur.
#
# Before using:
# 1. Update the variables in the CONFIGURATION section.
# 2. Ensure the script is executable: chmod +x BackupContainerFiles.sh
# 3. Add to cron: 0 6 * * 5 /path/to/BackupContainerFiles.sh
# 4. Ensure sendmail or an equivalent MTA is installed.

set -e

########################################
# CONFIGURATION — EDIT THESE VALUES
########################################

# Root directory where your Docker stack lives
SRC_ROOT="/path/to/your/docker/root"

# Directory containing container appdata folders
CONTAINER_DIR="$SRC_ROOT/appdata"

# Backup destination
BACKUP_ROOT="/path/to/your/backup/location"
BACKUP_DIR="$BACKUP_ROOT/appdata"

# Email address for failure notifications
EMAIL="your-email@example.com"

# Path to sendmail (adjust if needed)
SENDMAIL_BIN="/usr/sbin/sendmail"

########################################
# INTERNAL VARIABLES — DO NOT EDIT
########################################

DATE=$(date +%F-%H%M%S)
BACKUP_EXCLUDES="--exclude='appdata/'"
LOG_FILE="$BACKUP_ROOT/backup_log.txt"

########################################
# LOGGING FUNCTION
########################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

trap 'log "Script exited with status $? at $(date)"' EXIT

########################################
# PREPARE DIRECTORIES
########################################

echo "Ensuring backup directory exists: $BACKUP_DIR"
mkdir -p "$BACKUP_ROOT"
mkdir -p "$BACKUP_DIR"

# Reset log file
[ -f "$LOG_FILE" ] && rm -f "$LOG_FILE"

log "Backup started at: $(date '+%Y-%m-%d %H:%M:%S')"

########################################
# RSYNC OPTIONS
########################################

RSYNC_OPTS="-a"
RSYNC_APPDATA_OPTS="-a --ignore-existing"

if [[ "$1" == "delete" ]]; then
    RSYNC_OPTS="-a --delete"
    RSYNC_APPDATA_OPTS="-a --delete"
    log "Delete mode enabled: destination will be mirrored."
fi

########################################
# BACKUP ROOT CONFIGS (EXCLUDING APPDATA)
########################################

log "Backing up Docker root (excluding appdata)..."

if rsync $RSYNC_OPTS $BACKUP_EXCLUDES "$SRC_ROOT/" "$BACKUP_ROOT/" >> "$LOG_FILE" 2>&1; then
    log "Successfully backed up Docker root"
else
    log "Failed to back up Docker root"
fi

########################################
# DISCOVER CONTAINERS TO BACK UP
########################################

CRITICAL_CONTAINERS=()

while IFS= read -r dir; do
    base=$(basename "$dir")
    if docker ps -a --format "{{.Names}}" | grep -q "^${base}$"; then
        CRITICAL_CONTAINERS+=("$base")
    fi
done < <(find "$CONTAINER_DIR" -mindepth 1 -maxdepth 1 -type d)

########################################
# HEALTH CHECK FUNCTION
########################################

check_container_status() {
    CONTAINER=$1
    STATUS=$(docker ps --filter "name=$CONTAINER" --format "{{.Status}}")
    if [[ "$STATUS" == *healthy* || "$STATUS" == *Up* ]]; then
        log "$CONTAINER is running and healthy"
    else
        log "$CONTAINER has issues: $STATUS"
    fi
}

########################################
# PRE-BACKUP HEALTH CHECKS
########################################

log "Performing pre-backup health checks..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Checking health of $CONTAINER..."
    check_container_status "$CONTAINER"
done

########################################
# STOP CONTAINERS
########################################

log "Stopping containers for backup..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Stopping container: $CONTAINER"
    if docker stop "$CONTAINER" >> "$LOG_FILE" 2>&1; then
        log "Stopped $CONTAINER"
    else
        log "Failed to stop $CONTAINER"
    fi
done

########################################
# BACKUP APPDATA
########################################

log "Backing up container appdata..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    BACKUP_PATH="$CONTAINER_DIR/$CONTAINER"
    DEST_PATH="$BACKUP_DIR/$CONTAINER/"
    log "Backing up $CONTAINER from $BACKUP_PATH to $DEST_PATH..."
    if rsync $RSYNC_APPDATA_OPTS "$BACKUP_PATH/" "$DEST_PATH/" >> "$LOG_FILE" 2>&1; then
        log "Successfully backed up $CONTAINER"
    else
        log "Failed to back up $CONTAINER"
    fi
done

########################################
# OPTIONAL: SPECIAL BACKUP FOR PLEX
########################################

# Uncomment if you want Plex metadata extracted
# log "Backing up Plex configuration..."
# PLEX_PATH="$CONTAINER_DIR/plex/Plex Media Server"
# if rsync -a \
#     --include='.LocalAdminToken' \
#     --include='Preferences.xml' \
#     --include='Setup Plex.html' \
#     --exclude='*' \
#     "$PLEX_PATH/" "$BACKUP_DIR/plex/" >> "$LOG_FILE" 2>&1; then
#     log "Successfully backed up Plex"
# else
#     log "Failed to back up Plex"
# fi

########################################
# RESTART CONTAINERS
########################################

log "Restarting containers..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Restarting container: $CONTAINER"
    if docker start "$CONTAINER" >> "$LOG_FILE" 2>&1; then
        log "Restarted $CONTAINER"
    else
        log "Failed to restart $CONTAINER"
    fi
done

########################################
# POST-BACKUP HEALTH CHECKS
########################################

log "Performing post-backup health checks..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Checking health of $CONTAINER after restart..."
    check_container_status "$CONTAINER"
done

########################################
# SUMMARY
########################################

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log "Backup finished at: $END_TIME"

FAIL_COUNT=$(grep -c "Failed" "$LOG_FILE")
SUCCESS_COUNT=$(grep -c "Successfully" "$LOG_FILE")
TOTAL_CONTAINERS=${#CRITICAL_CONTAINERS[@]}

log "Summary Report:"
log "Total containers targeted: $TOTAL_CONTAINERS"
log "Successful operations: $SUCCESS_COUNT"
log "Failures detected: $FAIL_COUNT"

########################################
# EMAIL NOTIFICATION ON FAILURE
########################################

if grep -q "Failed" "$LOG_FILE"; then
    log "Backup encountered issues. Sending email alert..."
    SUBJECT="Container Backup Issues - $DATE"
    {
        echo "To: $EMAIL"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/plain"
        echo
        echo "Errors were detected during the backup process."
        echo "Log output:"
        echo
        cat "$LOG_FILE"
    } | "$SENDMAIL_BIN" -t
fi