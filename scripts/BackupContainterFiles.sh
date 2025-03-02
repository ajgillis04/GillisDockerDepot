#!/bin/bash

# If script does not run, encoding might be wrong. Run:
# sed -i -e 's/\r$//' BackupContainterFiles.sh

# Set the script to exit immediately if any command fails
set -e

DATE=$(date +%F-%H%M%S)
BACKUP_DIR=/share/Backups/GillisNAS/ContainerNew
CONTAINER_DIR=/share/Docker/GillisDockerDepot/appdata
ENV_PATH="/share/Docker/GillisDockerDepot/.env"
SECRETS_PATH="/share/Docker/GillisDockerDepot/secrets"
LOG_FILE="$BACKUP_DIR/backup_log.txt"
EMAIL="andy.gillis@gmail.com"  # Replace with your email

# Containers to backup
CRITICAL_CONTAINERS=(
    vaultwarden.GillisNAS
    transmission-openvpn.GillisNAS
    sonarr.GillisNAS
    tautulli.GillisNAS
    lidarr.GillisNAS
    calibre.GillisNAS
    heimdall.GillisNAS
    pihole.GillisNAS
    heimdallint.GillisNAS
    guacamole.GillisNAS
    prowlarr.GillisNAS
    radarr.GillisNAS
    readarr.GillisNAS
    sabnzbd.GillisNAS
    bazarr.GillisNAS
    overseerr.GillisNAS
    plex.GillisNAS
    tdarr.GillisNAS
    wizarr.GillisNAS
)

# Function to check container health
check_container_status() {
    CONTAINER=$1
    STATUS=$(docker ps --filter "name=$CONTAINER" --format "{{.Status}}")
    if [[ "$STATUS" == *healthy* || "$STATUS" == *Up* ]]; then
        echo "$CONTAINER is running and healthy" | tee -a "$LOG_FILE"
    else
        echo "$CONTAINER has issues: $STATUS" | tee -a "$LOG_FILE"
    fi
}

# Ensure the backup directory exists
echo "Ensuring backup directory exists: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Delete the log file if it exists
if [ -f "$LOG_FILE" ]; then
    echo "Removing existing log file: $LOG_FILE"
    rm -f "$LOG_FILE"
fi

echo "Starting backup process at $DATE"
echo "Backup started at: $DATE" | tee -a "$LOG_FILE"

# Perform pre-backup health checks
echo "Performing pre-backup health checks..." | tee -a "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    echo "Checking health of $CONTAINER..."
    check_container_status $CONTAINER
done

# Stop critical containers
echo "Stopping critical containers for final backup..." | tee -a "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    echo "Stopping container: $CONTAINER"
    docker stop $CONTAINER >> "$LOG_FILE" 2>&1 && \
        echo "Stopped $CONTAINER" | tee -a "$LOG_FILE" || \
        echo "Failed to stop $CONTAINER" | tee -a "$LOG_FILE"
done

# Backup critical containers
echo "Backing up critical containers..." | tee -a "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    BACKUP_PATH="$CONTAINER_DIR/${CONTAINER%.*}"
    DEST_PATH="$BACKUP_DIR/${CONTAINER%.*}/"
    echo "Backing up $CONTAINER from $BACKUP_PATH to $DEST_PATH..."
    sudo rsync -a --ignore-existing "$BACKUP_PATH/" "$DEST_PATH/" 2>>"$LOG_FILE" && \
        echo "Successfully backed up $CONTAINER" | tee -a "$LOG_FILE" || \
        echo "Failed to back up $CONTAINER" | tee -a "$LOG_FILE"
done

# Special backup for Plex
echo "Backing up Plex configuration..." | tee -a "$LOG_FILE"
PlexBackupPath="$CONTAINER_DIR/plex/Plex Media Server"
echo "Backing up Plex files from $PlexBackupPath"
rsync -a \
    --include='.LocalAdminToken' \
    --include='Preferences.xml' \
    --include='Setup Plex.html' \
    --exclude='*' \
    "$PlexBackupPath/" "$BACKUP_DIR/plex/" 2>>"$LOG_FILE" && \
    echo "Successfully backed up Plex" | tee -a "$LOG_FILE" || \
    echo "Failed to back up Plex" | tee -a "$LOG_FILE"

# Backup secrets
if [ -d "$SECRETS_PATH" ]; then
    echo "Backing up secrets from $SECRETS_PATH..."
    rsync -a --ignore-existing "$SECRETS_PATH/" "$BACKUP_DIR/secrets/" 2>>"$LOG_FILE" && \
        echo "Successfully backed up secrets" | tee -a "$LOG_FILE" || \
        echo "Failed to back up secrets" | tee -a "$LOG_FILE"
else
    echo "Secrets directory does not exist at $SECRETS_PATH. Skipping..." | tee -a "$LOG_FILE"
fi

# Backup .env file(s)
if [ -f "$ENV_PATH" ]; then
    echo "Backing up .env file from $ENV_PATH..."
    cp "$ENV_PATH" "$BACKUP_DIR/.env" && \
        echo "Successfully backed up .env file" | tee -a "$LOG_FILE" || \
        echo "Failed to back up .env file" | tee -a "$LOG_FILE"
else
    echo ".env file does not exist at $ENV_PATH. Skipping..." | tee -a "$LOG_FILE"
fi

# Restart containers after backup
echo "Restarting critical containers after backup..." | tee -a "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    echo "Restarting container: $CONTAINER"
    docker start $CONTAINER >> "$LOG_FILE" 2>&1 && \
        echo "Restarted $CONTAINER" | tee -a "$LOG_FILE" || \
        echo "Failed to restart $CONTAINER" | tee -a "$LOG_FILE"
done

# Perform post-backup health checks
echo "Performing post-backup health checks..." | tee -a "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    echo "Checking health of $CONTAINER after restart..."
    check_container_status $CONTAINER
done

# Log completion
DATE=$(date +%F-%H%M%S)
echo "Backup finished at: $DATE" | tee -a "$LOG_FILE"

# Send email if any failures occurred
if grep -q "Failed" "$LOG_FILE"; then
    echo "Backup script encountered issues. Sending email..." | tee -a "$LOG_FILE"
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
