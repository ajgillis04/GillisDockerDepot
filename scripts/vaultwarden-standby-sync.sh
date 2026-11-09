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
#
# Setting it up from scratch on the standby machine (done on Brainiac 2026-11-08):
#   1. SSH key: put a key that logs in to GillisNAS as GilAdmin at NAS_KEY and
#      check it with: ssh -i <key> GilAdmin@<NAS> 'echo ok'
#   2. .env: add VAULTWARDEN_STANDBY_PORT=9445 and
#      VAULTWARDEN_STANDBY_DOMAIN=https://<this machine's IP>:9445
#   3. Certificate: run the openssl lines in compose/server8/vaultwarden-standby.yaml.
#   4. First run by hand (it also starts the standby the first time):
#        scripts/vaultwarden-standby-sync.sh; tail appdata/_backups/vaultwarden/sync.log
#      The last line should end "standby healthy".
#   5. Add the cron line above with: crontab -e
#   6. Optional emailed alert if a night is missed: put a Healthchecks.io ping URL
#      on one line in appdata/_backups/vaultwarden/healthcheck-url (not in git).
#      The script pings it after each good run; Healthchecks emails if a ping is late.
# ------------------------------------------------------------------------------
set -uo pipefail

NAS=GilAdmin@192.168.2.10
NAS_KEY="$HOME/.ssh/sbs_nas_claude"
NAS_DATA=/share/Docker/GillisDockerDepot/appdata/vaultwarden/data
NAS_ENV='export PATH=$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin DOCKER_CONFIG=/tmp/.none;'
NAS_CONTAINER=vaultwarden.GillisNAS

REPO=/mnt/data/projects/GillisDockerDepot
STANDBY_DATA="$REPO/appdata/vaultwarden-standby/data"
ARCHIVE_DIR="$REPO/appdata/_backups/vaultwarden"   # git-ignored; /mnt/data itself is root-only
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
  # Healthchecks.io (if set up) emails right away on a /fail ping
  [ -s "$ARCHIVE_DIR/healthcheck-url" ] && curl -fsS -m 15 -o /dev/null --data-raw "$*" "$(head -1 "$ARCHIVE_DIR/healthcheck-url")/fail"
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
# Give the standby the live mail settings ONLY, so people who use email two-step
# codes can still log in there. Everything else stays as set in the compose file.
if [ -s "$STAGE/config.json" ]; then
  python3 - "$STAGE/config.json" "$STANDBY_DATA/config.json" <<'PY' || fail "writing the standby mail settings failed"
import json, sys
live = json.load(open(sys.argv[1]))
mail = {k: v for k, v in live.items() if k.startswith("smtp_") or k in ("_enable_smtp", "use_sendmail", "helo_name")}
with open(sys.argv[2], "w") as f:
    json.dump(mail, f, indent=2)
PY
  chmod 600 "$STANDBY_DATA/config.json"
fi
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

# 6. Tell Healthchecks.io (if set up) that tonight worked; it emails when a ping is missed
if [ -s "$ARCHIVE_DIR/healthcheck-url" ]; then
  curl -fsS -m 15 --retry 3 -o /dev/null "$(head -1 "$ARCHIVE_DIR/healthcheck-url")" \
    || log "warning: Healthchecks ping failed"
fi
