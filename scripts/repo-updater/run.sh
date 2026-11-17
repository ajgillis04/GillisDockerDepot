#!/bin/sh
# Container entrypoint: serves the upgrade page and runs the monthly check.
# CHECK_AT is the day of the month (two digits) followed by the hour,
# e.g. 0109 = the 1st at 09:00 (a few hours after Watchtower's monthly run).
. "$(dirname "$0")/lib.sh"
: "${CHECK_AT:=0109}"
log "start: $SERVER, monthly check at $CHECK_AT"
# Fetch over the plain public URL (replaces old URLs with an embedded token).
# A separate push URL, where one is set, keeps working.
if [ "$(git remote get-url origin 2>/dev/null)" != "$REPO_URL" ]; then
  PUSH=$(git remote get-url --push origin 2>/dev/null)
  git remote set-url origin "$REPO_URL"
  case "$PUSH" in git@*|ssh://*) git remote set-url --push origin "$PUSH" ;; esac
  log "start: origin fetch URL set to $REPO_URL"
fi
httpd -p "${HTTP_PORT:-8080}" -h "$BASE_DIR/scripts/repo-updater/www"
while true; do
  STAMP="$STATE_DIR/checked-$(date +%Y-%m)"
  if [ "$(date +%d%H)" = "$CHECK_AT" ] && [ ! -f "$STAMP" ]; then
    touch "$STAMP"
    find "$STATE_DIR" -name 'checked-*' -mtime +400 -delete 2>/dev/null
    sh "$BASE_DIR/scripts/repo-updater/check.sh"
  fi
  sleep 300
done
