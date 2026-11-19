#!/bin/bash

# Container AppData Backup Script
# --------------------------------
# Once a week: copies the whole Docker folder while containers run, stops them,
# copies what changed so the copy is consistent, restarts them, and emails if
# anything failed.
#
# Expects one folder per container in $SRC_ROOT/appdata, named like the container
# (optionally with a ".HOST_NAME" suffix, e.g. appdata/plex -> plex.MyNAS).
# Only containers running when the script starts are stopped and restarted, so
# anything you stopped on purpose stays stopped.
#
# Before using:
# 1. Fill in the CONFIGURATION section.
# 2. chmod +x BackupContainerFiles.sh
# 3. See the plan without changing anything:  BackupContainerFiles.sh test
# 4. Cron (as root), e.g. Friday 06:00:       0 6 * * 5 /path/to/BackupContainerFiles.sh
#    "BackupContainerFiles.sh delete" mirrors instead (removes files gone from the source).

set -e

# Cron's PATH may not include docker (on QNAP it lives in Container Station).
export PATH="$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/usr/local/bin"

########################################
# CONFIGURATION — YOUR VALUES
########################################

# Container name suffix: containers are named <service>.<HOST_NAME>.
# Leave empty if your containers are named plainly (plex, sonarr, ...).
HOST_NAME=""

# Root directory where your Docker stack lives
SRC_ROOT="/path/to/your/docker/root"

# Directory containing container appdata folders
CONTAINER_DIR="$SRC_ROOT/appdata"

# Backup destination
BACKUP_ROOT="/path/to/your/backup/location"
BACKUP_DIR="$BACKUP_ROOT/appdata"

# Email address for failure notifications
EMAIL="your-email@example.com"

# Anything that works like "sendmail -t". QNAP's own sendmail is often broken;
# scripts/send_mail.sh in this repo sends through Gmail with an app password.
SENDMAIL_BIN="/usr/sbin/sendmail"
export NAS_MAIL_FROM_NAME="${HOST_NAME:-$(hostname)}"   # sender name for send_mail.sh

# Left running: DNS, remote access and off-site sync. Their files are still
# copied in the first pass.
KEEP_RUNNING="pihole cloudflared syncthing"

# Started first and stopped last, because other containers depend on them
# (databases, VPN containers that others share a network with).
START_FIRST="mariadb gluetun"

# Started last (e.g. a reverse proxy that looks up its upstreams when it starts).
START_LAST=""

# Running containers with no appdata folder that you know are stateless.
# Any others are reported in the email so new ones get noticed.
NO_APPDATA_OK=""

########################################
# INTERNAL VARIABLES — DO NOT EDIT
########################################

DATE=$(date +%F-%H%M%S)
LOG_FILE="$BACKUP_ROOT/backup_log.txt"
CONTAINERS_STOPPED=0
SUFFIX="${HOST_NAME:+.$HOST_NAME}"

########################################
# LOGGING FUNCTION
########################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Runs a command, appends its output to the log, and keeps the exit code in CMD_RC
# and the last few output lines in CMD_ERR, so a failure line can say what went wrong.
run_cmd() {
    local out
    CMD_RC=0
    out=$("$@" 2>&1) || CMD_RC=$?
    [ -n "$out" ] && echo "$out" >> "$LOG_FILE"
    CMD_ERR=$(echo "$out" | grep -v '^$' | tail -3 | tr '\n' ' ' | cut -c1-400 || true)
    return 0   # set -e: never abort the backup here; callers check CMD_RC
}

########################################
# DISCOVER CONTAINERS TO BACK UP
########################################

in_list() {
    case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null)
FIRST=(); MIDDLE=(); LAST=()

while IFS= read -r dir; do
    base=$(basename "$dir")
    in_list "$base" "$KEEP_RUNNING" && continue
    echo "$RUNNING" | grep -qxF "${base}${SUFFIX}" || continue
    if in_list "$base" "$START_FIRST"; then
        FIRST+=("${base}${SUFFIX}")
    elif in_list "$base" "$START_LAST"; then
        LAST+=("${base}${SUFFIX}")
    else
        MIDDLE+=("${base}${SUFFIX}")
    fi
done < <(find "$CONTAINER_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

# In start order. Stopping walks it backwards.
CRITICAL_CONTAINERS=("${FIRST[@]}" "${MIDDLE[@]}" "${LAST[@]}")

# Running containers with no appdata/<name> folder only get the live copy.
NO_APPDATA=""
for c in $RUNNING; do
    case "$c" in *"$SUFFIX") c="${c%"$SUFFIX"}" ;; *) continue ;; esac
    [ -d "$CONTAINER_DIR/$c" ] && continue
    in_list "$c" "$NO_APPDATA_OK" && continue
    NO_APPDATA="$NO_APPDATA $c"
done

if [[ "$1" == "test" ]]; then
    echo "Test only: nothing was stopped or copied."
    echo "Would stop and restart ${#CRITICAL_CONTAINERS[@]} containers, in this start order:"
    printf '  %s\n' "${CRITICAL_CONTAINERS[@]}"
    echo "Left running: $KEEP_RUNNING"
    echo "Running with no appdata folder (live copy only): ${NO_APPDATA:- none} (known OK: ${NO_APPDATA_OK:-none})"
    exit 0
fi

########################################
# RESTART, EVEN IF THE SCRIPT DIES
########################################

restart_containers() {
    [ "$CONTAINERS_STOPPED" = "1" ] || return 0
    CONTAINERS_STOPPED=0
    log "Restarting critical containers after backup..."
    for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
        log "Restarting container: $CONTAINER"
        run_cmd docker start "$CONTAINER"
        if [ "$CMD_RC" = 0 ]; then
            log "Restarted $CONTAINER"
        else
            log "Failed to restart $CONTAINER (docker exit $CMD_RC): $CMD_ERR"
        fi
    done
}

trap 'status=$?; restart_containers; log "Script exited with status $status at $(date)"' EXIT

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
RSYNC_APPDATA_OPTS="-a"

if [[ "$1" == "delete" ]]; then
    RSYNC_OPTS="-a --delete"
    RSYNC_APPDATA_OPTS="-a --delete"
    log "Delete mode enabled: destination will be mirrored."
fi

########################################
# FIRST PASS: EVERYTHING, WHILE RUNNING
########################################

# Does the slow copying with services still up, so the stopped pass below is short.
log "Backing up $SRC_ROOT while containers run..."

run_cmd rsync $RSYNC_OPTS "$SRC_ROOT/" "$BACKUP_ROOT/"
if [ "$CMD_RC" = 0 ]; then
    log "Successfully backed up $SRC_ROOT"
elif [ "$CMD_RC" = 24 ]; then
    # rsync 24 = files vanished mid-copy (database temp files of running apps).
    # Normal here; the stopped pass below copies those containers cleanly.
    log "Successfully backed up $SRC_ROOT (some files changed during the live copy, which is normal)"
else
    log "Failed to back up $SRC_ROOT (rsync exit $CMD_RC): $CMD_ERR"
fi

########################################
# HEALTH CHECK FUNCTION
########################################

check_container_status() {
    CONTAINER=$1
    STATUS=$(docker ps --filter "name=^${CONTAINER}\$" --format "{{.Status}}")
    if [[ "$STATUS" == *healthy* || "$STATUS" == *Up* ]]; then
        log "$CONTAINER is running and healthy"
    else
        log "Failed health check: $CONTAINER has issues: $STATUS"
    fi
}

########################################
# STOP CONTAINERS
########################################

log "Stopping critical containers for final backup..."
CONTAINERS_STOPPED=1

for (( i=${#CRITICAL_CONTAINERS[@]}-1; i>=0; i-- )); do
    CONTAINER="${CRITICAL_CONTAINERS[$i]}"
    log "Stopping container: $CONTAINER"
    run_cmd docker stop "$CONTAINER"
    if [ "$CMD_RC" = 0 ]; then
        log "Stopped $CONTAINER"
    else
        log "Failed to stop $CONTAINER (docker exit $CMD_RC): $CMD_ERR"
    fi
done

########################################
# SECOND PASS: WHAT CHANGED, WHILE STOPPED
########################################

log "Backing up critical containers..."

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    NAME="${CONTAINER%"$SUFFIX"}"
    BACKUP_PATH="$CONTAINER_DIR/$NAME"
    DEST_PATH="$BACKUP_DIR/$NAME/"
    log "Backing up $CONTAINER from $BACKUP_PATH to $DEST_PATH..."
    run_cmd rsync $RSYNC_APPDATA_OPTS "$BACKUP_PATH/" "$DEST_PATH/"
    if [ "$CMD_RC" = 0 ]; then
        log "Successfully backed up $CONTAINER"
    else
        log "Failed to back up $CONTAINER (rsync exit $CMD_RC): $CMD_ERR"
    fi
done

########################################
# RESTART CONTAINERS
########################################

restart_containers

########################################
# POST-BACKUP HEALTH CHECKS
########################################

log "Performing post-backup health checks..."
sleep 60

for CONTAINER in "${CRITICAL_CONTAINERS[@]}"; do
    check_container_status "$CONTAINER"
done

########################################
# SUMMARY
########################################

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
log "Backup finished at: $END_TIME"

FAIL_COUNT=$(grep -c "Failed" "$LOG_FILE" || true)
SUCCESS_COUNT=$(grep -c "Successfully" "$LOG_FILE" || true)
TOTAL_CONTAINERS=${#CRITICAL_CONTAINERS[@]}

log "Summary Report:"
log "Total containers targeted: $TOTAL_CONTAINERS"
log "Successful operations: $SUCCESS_COUNT"
log "Failures detected: $FAIL_COUNT"
if [ -n "$NO_APPDATA" ]; then
    log "Warning: running containers with no appdata folder (live copy only, never stopped):$NO_APPDATA"
fi

########################################
# EMAIL NOTIFICATION ON FAILURE OR WARNING
########################################

if grep -qE "Failed|Warning:" "$LOG_FILE"; then
    log "Backup encountered issues. Sending email alert..."
    SUBJECT="Container Backup Issues on ${HOST_NAME:-$(hostname)} ($FAIL_COUNT failed) - $DATE"
    if ! {
        echo "To: $EMAIL"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo "Problems found during the weekly container backup."
        echo
        echo "What failed (with the error from rsync or docker):"
        grep -E "Failed|Warning:" "$LOG_FILE" | sed 's/^/  /'
        echo
        grep -E "Summary|Total containers|Successful operations|Failures detected" "$LOG_FILE"
        echo
        echo "Full log: $LOG_FILE"
        echo "To check the plan without stopping anything: $0 test"
    } | "$SENDMAIL_BIN" -t; then
        log "Could not send the email alert"
    fi
fi
