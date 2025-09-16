#!/bin/bash

# If script does not run, encoding might be wrong. Run:
# sed -i -e 's/\r$//' scritps/BackupContainterFiles.sh
# chmod +x scripts/BackupContainterFiles.sh
# sudo ./scripts/BackupContainterFiles.sh
# sudo crontab -e
# 0 3 * * * /share/Docker/GillisDockerDepot/scripts/BackupContainterFiles.sh

# Set the script to exit immediately if any command fails
set -e

DATE=$(date +%F-%H%M%S)
BACKUP_DIR=/share/Backups/GillisNAS/Docker/GillisDockerDepot
CONTAINER_DIR=/share/Docker/GillisDockerDepot/appdata
ENV_PATH="/share/Docker/GillisDockerDepot/.env"
SECRETS_PATH="/share/Docker/GillisDockerDepot/secrets"
LOG_FILE="$BACKUP_DIR/backup_log.txt"
EMAIL="andy.gillis@gmail.com"  # Replace with your email

# Logging function with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

trap 'log "Script exited with status $? at $(date)"' EXIT

# Ensure the backup directory exists
echo "Ensuring backup directory exists: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Delete the log file if it exists
if [ -f "$LOG_FILE" ]; then
    echo "Removing existing log file: $LOG_FILE"
    rm -f "$LOG_FILE"
fi

START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log "Backup started at: $START_TIME"


# Containers to backup
# Dynamically build list of containers with matching appdata folders
CRITICAL_CONTAINERS=()
while IFS= read -r dir; do
    base=$(basename "$dir")
    if docker ps -a --format "{{.Names}}" | grep -q "^${base}\.GillisNAS$"; then
        CRITICAL_CONTAINERS+=("${base}.GillisNAS")
    fi
done < <(find "$CONTAINER_DIR" -mindepth 1 -maxdepth 1 -type d)

# Function to check container health
check_container_status() {
    CONTAINER=$1
    STATUS=$(docker ps --filter "name=$CONTAINER" --format "{{.Status}}")
    if [[ "$STATUS" == *healthy* || "$STATUS" == *Up* ]]; then
        log "$CONTAINER is running and healthy"
    else
        log "$CONTAINER has issues: $STATUS"
    fi
}

# Perform pre-backup health checks
log "Performing pre-backup health checks..."
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Checking health of $CONTAINER..."
    check_container_status $CONTAINER
done

# Stop critical containers
log "Stopping critical containers for final backup..."
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Stopping container: $CONTAINER"
    if docker stop "$CONTAINER" >> "$LOG_FILE" 2>&1; then
        log "Stopped $CONTAINER"
    else
        log "Failed to stop $CONTAINER"
    fi
done

# Backup critical containers
log "Backing up critical containers..."
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    BACKUP_PATH="$CONTAINER_DIR/${CONTAINER%.*}"
    DEST_PATH="$BACKUP_DIR/${CONTAINER%.*}/"
    log "Backing up $CONTAINER from $BACKUP_PATH to $DEST_PATH..."
    if sudo rsync -a --ignore-existing "$BACKUP_PATH/" "$DEST_PATH/" >> "$LOG_FILE" 2>&1; then
        log "Successfully backed up $CONTAINER"
    else
        log "Failed to back up $CONTAINER"
    fi
done

# Special backup for Plex
log "Backing up Plex configuration..."
PlexBackupPath="$CONTAINER_DIR/plex/Plex Media Server"
log "Backing up Plex files from $PlexBackupPath"

if rsync -a \
    --include='.LocalAdminToken' \
    --include='Preferences.xml' \
    --include='Setup Plex.html' \
    --exclude='*' \
    "$PlexBackupPath/" "$BACKUP_DIR/plex/" >> "$LOG_FILE" 2>&1; then
    log "Successfully backed up Plex"
else
    log "Failed to back up Plex"
fi

# Backup secrets
if [ -d "$SECRETS_PATH" ]; then
    log "Backing up secrets from $SECRETS_PATH..."
    if rsync -a --ignore-existing "$SECRETS_PATH/" "$BACKUP_DIR/secrets/" >> "$LOG_FILE" 2>&1; then
        log "Successfully backed up secrets"
    else
        log "Failed to back up secrets"
    fi
else
    log "Secrets directory does not exist at $SECRETS_PATH. Skipping..."
fi

# Backup .env file(s)
if [ -f "$ENV_PATH" ]; then
    log "Backing up .env file from $ENV_PATH..."
    if cp "$ENV_PATH" "$BACKUP_DIR/.env"; then
        log "Successfully backed up .env file"
    else
        log "Failed to back up .env file"
    fi
else
    log ".env file does not exist at $ENV_PATH. Skipping..."
fi

# Restart containers after backup
log "Restarting critical containers after backup..."
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Restarting container: $CONTAINER"
    if docker start "$CONTAINER" >> "$LOG_FILE" 2>&1; then
        log "Restarted $CONTAINER"
    else
        log "Failed to restart $CONTAINER"
    fi
done


# Perform post-backup health checks
log "Performing post-backup health checks..."
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    log "Checking health of $CONTAINER after restart..."
    check_container_status $CONTAINER
done

# Log completion
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log "Backup finished at: $END_TIME"

# Summary report
FAIL_COUNT=$(grep -c "Failed" "$LOG_FILE")
SUCCESS_COUNT=$(grep -c "Successfully" "$LOG_FILE")
TOTAL_CONTAINERS=${#CRITICAL_CONTAINERS[@]}

log "Summary Report:"
log "Total containers targeted: $TOTAL_CONTAINERS"
log "Successful operations: $SUCCESS_COUNT"
log "Failures detected: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
    log "All backup operations completed successfully."
else
    log "Some issues were encountered during backup. See details above."
fi

# Send email if any failures occurred
if grep -q "Failed" "$LOG_FILE"; then
    log "Backup script encountered issues. Sending email..."
    SUBJECT="Backup Script Issues - $DATE"
    {
        echo "To: $EMAIL"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/plain"
        echo
        echo "Errors were found during the backup script. Here is the log content:"
        echo
        cat "$LOG_FILE"
    } | sendmail -t
fi
