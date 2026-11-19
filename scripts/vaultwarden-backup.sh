#!/bin/sh
# ------------------------------------------------------------------------------
# vaultwarden-backup.sh - nightly backup of a Vaultwarden container (SQLite).
#
# Takes a consistent database snapshot with Vaultwarden's own "/vaultwarden backup"
# command (safe while it runs), packs it with the key, settings, attachments and
# sends into a dated .tgz, keeps KEEP_DAYS days of them, and emails on failure.
# Point DEST at a folder that Syncthing (or anything else) copies off-site.
#
# Before using: fill in the CONFIGURATION section, chmod +x, run it once by hand.
# Cron (as root), e.g. 03:30 nightly:  30 3 * * * /path/to/vaultwarden-backup.sh
#
# Restore: stop the container, empty its data folder, untar the archive there,
#          rename db_*.sqlite3 to db.sqlite3, start the container.
# For a warm standby copy on another machine, see vaultwarden-standby-sync.sh.
# ------------------------------------------------------------------------------

# Cron's PATH may not include docker (on QNAP it lives in Container Station).
export PATH="$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin:/usr/local/bin"

########################################
# CONFIGURATION — YOUR VALUES
########################################

CONTAINER="vaultwarden"                          # container name
DATA="/path/to/appdata/vaultwarden/data"         # host folder mounted at /data
DEST="/path/to/backups/vaultwarden"              # where the archives go
KEEP_DAYS=14
EMAIL="your-email@example.com"                   # failure alerts
SENDMAIL_BIN="/usr/sbin/sendmail"                # or scripts/send_mail.sh from this repo
OWNER="1000:100"                                 # owner of the archives (e.g. your sync user)
export NAS_MAIL_FROM_NAME="$(hostname)"          # sender name for send_mail.sh

########################################

STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="$DEST/vaultwarden-$STAMP.tgz"
LOG="$DEST/backup.log"

mkdir -p "$DEST" && chmod 700 "$DEST"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

fail() {
    log "FAILED: $1"
    {
        echo "To: $EMAIL"
        echo "Subject: Vaultwarden backup FAILED on $(hostname) - $STAMP"
        echo
        echo "The nightly Vaultwarden backup failed:"
        echo "  $1"
        echo
        echo "Last log lines ($LOG):"
        tail -15 "$LOG"
    } | "$SENDMAIL_BIN" -t || log "Could not send the failure email"
    exit 1
}

log "Start"

# 1. Consistent snapshot inside the data folder (db_YYYYMMDD_HHMMSS.sqlite3).
OUT=$(docker exec "$CONTAINER" /vaultwarden backup 2>&1) || fail "vaultwarden backup command: $OUT"
SNAP=$(echo "$OUT" | grep -o "db_[0-9_]*\.sqlite3" | tail -1)
[ -n "$SNAP" ] && [ -s "$DATA/$SNAP" ] || fail "no snapshot file found in output: $OUT"
log "Snapshot $SNAP ($(wc -c < "$DATA/$SNAP") bytes)"

# 2. Archive the snapshot plus what's needed to restore. The snapshot is removed
#    from the data folder through the container, which owns it.
ITEMS="$SNAP"
for f in rsa_key.pem rsa_key.pub.pem config.json attachments sends; do
    [ -e "$DATA/$f" ] && ITEMS="$ITEMS $f"
done
tar czf "$ARCHIVE.part" -C "$DATA" $ITEMS 2>>"$LOG" || { rm -f "$ARCHIVE.part"; docker exec "$CONTAINER" rm -f "/data/$SNAP"; fail "tar failed"; }
docker exec "$CONTAINER" rm -f "/data/$SNAP"
gzip -t "$ARCHIVE.part" 2>>"$LOG" || { rm -f "$ARCHIVE.part"; fail "archive failed gzip test"; }
tar tzf "$ARCHIVE.part" | grep -q "^$SNAP$" || { rm -f "$ARCHIVE.part"; fail "snapshot missing from archive"; }
mv "$ARCHIVE.part" "$ARCHIVE"
chown "$OWNER" "$ARCHIVE" 2>/dev/null; chmod 600 "$ARCHIVE"
log "Archive $ARCHIVE ($(wc -c < "$ARCHIVE") bytes): $ITEMS"

# 3. Keep KEEP_DAYS days, and keep the log short.
find "$DEST" -name 'vaultwarden-*.tgz' -mtime +$KEEP_DAYS -exec rm -f {} \;
tail -300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
log "Done, $(ls "$DEST"/vaultwarden-*.tgz | wc -l) archives kept"
