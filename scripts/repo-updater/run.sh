#!/bin/sh
# Container entrypoint: serves the "apply" page and runs the weekly check.
# CHECK_AT is the weekday (1 = Monday ... 7 = Sunday) followed by the hour, e.g. 709 = Sunday 09:00.
. "$(dirname "$0")/lib.sh"
: "${CHECK_AT:=709}"
log "start: $SERVER, weekly check at $CHECK_AT"
httpd -p "${HTTP_PORT:-8080}" -h "$BASE_DIR/scripts/repo-updater/www"
while true; do
  STAMP="$STATE_DIR/checked-$(date +%F)"
  if [ "$(date +%u%H)" = "$CHECK_AT" ] && [ ! -f "$STAMP" ]; then
    touch "$STAMP"
    find "$STATE_DIR" -name 'checked-*' -mtime +30 -delete 2>/dev/null
    sh "$BASE_DIR/scripts/repo-updater/check.sh"
  fi
  sleep 300
done
