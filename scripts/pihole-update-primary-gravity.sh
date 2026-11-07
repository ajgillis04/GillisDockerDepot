#!/bin/sh
# Asks the primary Pi-hole to update its blocklists (gravity) through the Pi-hole v6 API.
#
# Why: Pi-hole's own schedule inside its container is weekly and resets when the
# container is recreated. Run this daily from cron on another machine, a few
# minutes before nebula-sync, so both Pi-holes refresh their lists every day.
#
# Uses the same secret as nebula-sync (one line: http://<primary-ip>|<password>).
# The password is never printed.
#
# Cron example (server3): 0 4 * * * /usr/local/GillisDockerDepot/scripts/pihole-update-primary-gravity.sh
# Log: last run in ~/pihole-update-primary-gravity.log

SECRET="${SECRET:-/usr/local/GillisDockerDepot/secrets/nebula_sync_primary}"
LOG="${LOG:-$HOME/pihole-update-primary-gravity.log}"

exec >"$LOG" 2>&1
echo "$(date '+%F %T') start"

LINE=$(head -n 1 "$SECRET" | tr -d '\r\n') || { echo "cannot read secret"; exit 1; }
URL=${LINE%%|*}
PASS=${LINE#*|}
[ -n "$URL" ] && [ -n "$PASS" ] && [ "$URL" != "$LINE" ] || { echo "secret is not in url|password form"; exit 1; }

# JSON-escape backslashes and double quotes in the password
PASS_JSON=$(printf '%s' "$PASS" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

AUTH=$(printf '{"password":"%s"}' "$PASS_JSON" | curl -s --max-time 20 -H 'Content-Type: application/json' -d @- "$URL/api/auth")
SID=$(printf '%s' "$AUTH" | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p')
unset PASS PASS_JSON LINE
[ -n "$SID" ] || { echo "login failed: $(printf '%s' "$AUTH" | sed 's/"sid":"[^"]*"/"sid":"<hidden>"/' | head -c 200)"; exit 1; }

# Gravity streams its progress; keep only the summary lines
curl -s --max-time 900 -X POST -H "X-FTL-SID: $SID" "$URL/api/action/gravity" \
  | tr -d '\033' | grep -E "Number of gravity|Done|rror|ail" | tail -5
RC=$?

curl -s --max-time 10 -X DELETE -H "X-FTL-SID: $SID" "$URL/api/auth" >/dev/null
echo "$(date '+%F %T') end"
exit $RC
