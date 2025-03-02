#!/bin/bash

# If script does not run, encoding might be wrong. Run:
# sed -i -e 's/\r$//' BackupContainterFiles.sh

# Set the script to exit immediately if any command fails
set -e

DATE=$(date +%F-%H%M%S)
BACKUP_DIR=/share/Backups/GillisNAS/ContainerNew
CONTAINER_DIR=/share/Docker/GillisNAS/appdata
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
        echo "$CONTAINER is running and healthy" >> "$LOG_FILE"
    else
        echo "$CONTAINER has issues: $STATUS" >> "$LOG_FILE"
    fi
}

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Delete the log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
fi

echo "Backup started at: $DATE" >> "$LOG_FILE"

# Perform pre-backup health checks
echo "Performing pre-backup health checks..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    check_container_status $CONTAINER
done

# Stop critical containers
echo "Stopping critical containers for final backup..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    docker stop $CONTAINER >> "$LOG_FILE" 2>&1 && \
        echo "Stopped $CONTAINER" >> "$LOG_FILE" || \
        echo "Failed to stop $CONTAINER" >> "$LOG_FILE"
done

# Backup critical containers
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    BACKUP_PATH="$CONTAINER_DIR/${CONTAINER%.*}/config"
    DEST_PATH="$BACKUP_DIR/${CONTAINER%.*}/"
    echo "Backing up $CONTAINER" >> "$LOG_FILE"
    rsync -a --ignore-existing "$BACKUP_PATH/" "$DEST_PATH/" 2>>"$LOG_FILE" && \
        echo "Copied $CONTAINER" >> "$LOG_FILE" || \
        echo "Failed $CONTAINER" >> "$LOG_FILE"
done

# Special backup for Plex
echo "Backing up Plex configuration..." >> "$LOG_FILE"
PlexBackupPath="$CONTAINER_DIR/plex/Plex Media Server"
rsync -a \
    --include='.LocalAdminToken' \
    --include='Preferences.xml' \
    --include='Setup Plex.html' \
    --exclude='*' \
    "$PlexBackupPath/" "$BACKUP_DIR/plex/" 2>>"$LOG_FILE" && \
    echo "Copied Plex" >> "$LOG_FILE" || \
    echo "Failed Plex" >> "$LOG_FILE"

# Restart containers after backup
echo "Restarting critical containers after backup..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    docker start $CONTAINER >> "$LOG_FILE" 2>&1 && \
        echo "Restarted $CONTAINER" >> "$LOG_FILE" || \
        echo "Failed to restart $CONTAINER" >> "$LOG_FILE"
done

# Perform post-backup health checks
echo "Performing post-backup health checks..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    check_container