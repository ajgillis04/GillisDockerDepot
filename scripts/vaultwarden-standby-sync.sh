#!/bin/bash
# ------------------------------------------------------------------------------
# vaultwarden-standby-sync.sh - Copy the live Vaultwarden (GillisNAS) to the
# standby on Brainiac (server8), keep dated archives, and prove the copy starts.
# ------------------------------------------------------------------------------
# Runs nightly from the ajgillis crontab on Brainiac:
#   30 3 * * * /mnt/data/projects/GillisDockerDepot/scripts/vaultwarden-standby-sync.sh
#
# Steps:
#   1. On GillisNAS, run Vaultwarden's own "backup" command. It writes a consistent
#      copy of the SQLite database (db_YYYYMMDD_HHMMSS.sqlite3, UTC) next to the
#      live one, safely, while Vaultwarden keeps running.
#   2. Copy that snapshot plus attachments, sends, keys and config.json here.
#   3. Save a dated archive (kept for KEEP_DAYS days) in ARCHIVE_DIR.
#   4. Load it into the standby container (without the live config.json, so the
#      standby keeps its own safe settings) and wait for it to report healthy.
#   5. Keep the 7 newest snapshots on GillisNAS; they go into its weekly backup too.
# Any failure raises a Brainiac desktop alert and is logged to ARCHIVE_DIR/sync.log.
#
# Restore by hand: tar xzf <archive> into an empty Vaultwarden data folder; the
# database is db.sqlite3 and config.json holds the live server's settings.
#
# Needs: SSH key access to GillisNAS as GilAdmin (NAS_KEY), rsync on both ends.
# ------------------------------------------------------------------------------
set -uo pipefail

NAS=GilAdmin@192.168.2.10
NAS_KEY="$HOME/.ssh/sbs_nas_claude"
NAS_DATA=/share/Docker/GillisDockerDepot/appdata/vaultwarden/data
NAS_ENV='export PATH=$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin DOCKER_CONFIG=/tmp/.none;'
NAS_CONTAINER=vaultwarden.GillisNAS

REPO=/mnt/data/projects/GillisDockerDepot
STANDBY_DATA="$REPO/appdata/vaultwarden-standby/data"
ARCHIVE_DIR=/mnt/data/backups/vaultwarden
KEEP_DAYS=14
STAGE="$ARCHIVE_DIR/staging"
LOG="$ARCHIVE_DIR/sync.log"
COMPOSE=(docker compose -p mediaserver -f "$REPO/docker-compose-server8.yaml")
SERVICE=vaultwarden-standby
CONTAINER=vaultwarden-standby.Brainiac

SSH=(ssh -i "$NAS_KEY" -o BatchMode=yes -o ConnectTimeout=20)

mkdir -p "$ARCHIVE_DIR" "$STANDBY_DATA"
chmod 700 "$ARCHIVE_DIR"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
fail() {
  log "FAILED: $*"
  [ -x /usr/local/sbin/brainiac-alert ] && /usr/local/sbin/brainiac-alert critical "Vaultwarden standby" "$*"
  exit 1
}

log "start"

# 1. Snapshot on the NAS
out=$("${SSH[@]}" "$NAS" "$NAS_ENV docker exec $NAS_CONTAINER /vaultwarden backup" 2>&1) \
  || fail "snapshot on GillisNAS failed: $out"
snap=$(printf '%s' "$out" | sed -n "s/.*'data\/\(db_[0-9_]*\.sqlite3\)'.*/\1/p")
[ -n "$snap" ] || fail "couldn't read the snapshot name from: $out"

# 2. Copy everything we need into a fresh staging folder
rm -rf "$STAGE" && mkdir -p "$STAGE"
rsync -a -e "${SSH[*]}" \
  --exclude 'icon_cache/' --exclude 'tmp/' --exclude 'db.sqlite3*' --exclude 'db_*.sqlite3' \
  "$NAS:$NAS_DATA/" "$STAGE/" || fail "copying the data folder from GillisNAS failed"
rsync -a -e "${SSH[*]}" "$NAS:$NAS_DATA/$snap" "$STAGE/db.sqlite3" \
  || fail "copying snapshot $snap failed"
size=$(stat -c %s "$STAGE/db.sqlite3" 2>/dev/null || echo 0)
[ "$size" -gt 100000 ] || fail "snapshot $snap is only $size bytes"

# 3. Dated archive, pruned after KEEP_DAYS days
archive="$ARCHIVE_DIR/vaultwarden-$(date +%F).tgz"
tar czf "$archive" -C "$STAGE" . || fail "writing $archive failed"
chmod 600 "$archive"
find "$ARCHIVE_DIR" -maxdepth 1 -name 'vaultwarden-*.tgz' -mtime +"$KEEP_DAYS" -delete

# 4. Load into the standby and check it starts
"${COMPOSE[@]}" stop "$SERVICE" >/dev/null 2>&1
rsync -a --delete --exclude 'config.json' --exclude 'icon_cache/' "$STAGE/" "$STANDBY_DATA/" \
  || fail "loading the copy into the standby failed"
"${COMPOSE[@]}" up -d "$SERVICE" >/dev/null 2>&1 || fail "starting the standby failed"
status=starting
for _ in $(seq 1 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo missing)
  [ "$status" = healthy ] && break
  sleep 5
done
[ "$status" = healthy ] || fail "the standby didn't become healthy (status: $status) with tonight's copy"

# 5. Keep the 7 newest snapshots on the NAS
"${SSH[@]}" "$NAS" "cd $NAS_DATA && ls -1t db_*.sqlite3 2>/dev/null | tail -n +8 | xargs -r rm -f" \
  || log "warning: pruning old snapshots on GillisNAS failed"

log "ok: $snap ($size bytes) -> $(basename "$archive"), standby healthy"
