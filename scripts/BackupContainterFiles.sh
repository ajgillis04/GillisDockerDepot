#!/bin/bash

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

# Delete the log file if it exists
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
fi

echo "Backup started at: $DATE" >> "$LOG_FILE"

# Perform pre-backup health check
echo "Performing pre-backup health checks..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    check_container_status $CONTAINER
done

# Backup critical containers
mkdir -p $BACKUP_DIR
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

# Perform post-backup health check
echo "Performing post-backup health checks..." >> "$LOG_FILE"
for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    check_container_status $CONTAINER
done

# Log completion
DATE=$(date +%F-%H%M%S)
echo "Backup finished at: $DATE" >> "$LOG_FILE"

# Send email if any failures occurred
if grep -q "Failed" "$LOG_FILE"; then
    echo "Backup script encountered issues. Sending email..." >> "$LOG_FILE"
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
