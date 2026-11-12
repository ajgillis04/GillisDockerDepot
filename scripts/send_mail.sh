#!/bin/sh
# ------------------------------------------------------------------------------
# send_mail.sh - send an email through Gmail from any NAS user, like "sendmail -t".
#
# QNAP's /usr/sbin/sendmail (ssmtp) depends on Notification Center's Gmail OAuth
# token, which breaks for non-root users and whenever Google expires it. This uses
# curl and a Gmail app password instead.
#
# Usage (drop-in for sendmail -t; sendmail flags like -t, -i, -f are ignored):
#   { echo "To: someone@example.com"; echo "Subject: Hi"; echo; echo "Body"; } | send_mail.sh
#   send_mail.sh extra@example.com < message.txt     # extra recipients as arguments
#
# Recipients come from the To:, Cc: and Bcc: headers (Bcc is removed before sending).
# A From: header is added if missing.
#
# Setup:
#   secrets/nas_gmail_app_pass  Gmail app password (chmod 600, owned by the user that
#                               runs the scripts)
#   NAS_MAIL_FROM               Gmail account the app password belongs to
#                               (environment, or the default below)
# ------------------------------------------------------------------------------

REPO_DIR="/share/Docker/GillisDockerDepot"
PASS_FILE="${NAS_MAIL_PASS_FILE:-$REPO_DIR/secrets/nas_gmail_app_pass}"
FROM="${NAS_MAIL_FROM:-andy.gillis@gmail.com}"
FROM_NAME="${NAS_MAIL_FROM_NAME:-GillisNAS}"
SMTP_URL="smtp://smtp.gmail.com:587"

EXTRA_RCPTS=""
for a in "$@"; do
  case "$a" in
    -*) ;;                                   # sendmail flags: ignore
    *@*) EXTRA_RCPTS="$EXTRA_RCPTS $a" ;;
  esac
done

[ -r "$PASS_FILE" ] || { echo "send_mail.sh: cannot read $PASS_FILE" >&2; exit 1; }

umask 077
MSG=$(mktemp) && OUT=$(mktemp) && NETRC=$(mktemp) || exit 1
trap 'rm -f "$MSG" "$OUT" "$NETRC"' EXIT
cat > "$MSG"

# Recipients from To/Cc/Bcc headers (with folded continuation lines), header part only.
RCPTS=$(awk '
  /^\r?$/ { exit }
  /^[ \t]/ { if (keep) print; next }
  { keep = tolower($0) ~ /^(to|cc|bcc):/; if (keep) { sub(/^[^:]*:/, ""); print } }
' "$MSG" | tr ',' '\n' | sed -n 's/.*<\([^>]*\)>.*/\1/p; /</!s/^[ \t]*\([^ \t\r]*@[^ \t\r]*\).*/\1/p')
RCPTS="$RCPTS$EXTRA_RCPTS"
[ -n "$(echo $RCPTS)" ] || { echo "send_mail.sh: no recipients" >&2; exit 1; }

# Outgoing message: drop Bcc headers, add From and Date if missing.
HAS_FROM=$(awk '/^\r?$/{exit} tolower($0) ~ /^from:/{print "y"; exit}' "$MSG")
HAS_DATE=$(awk '/^\r?$/{exit} tolower($0) ~ /^date:/{print "y"; exit}' "$MSG")
{
  [ -n "$HAS_FROM" ] || echo "From: $FROM_NAME <$FROM>"
  [ -n "$HAS_DATE" ] || echo "Date: $(LC_ALL=C date -R)"
  awk '
    body { print; next }
    /^\r?$/ { body = 1; print; next }
    /^[ \t]/ { if (!skip) print; next }
    { skip = tolower($0) ~ /^bcc:/; if (!skip) print }
  ' "$MSG"
} > "$OUT"

printf 'machine smtp.gmail.com login %s password %s\n' "$FROM" "$(tr -d ' \r\n' < "$PASS_FILE")" > "$NETRC"

RCPT_ARGS=""
for r in $RCPTS; do RCPT_ARGS="$RCPT_ARGS --mail-rcpt $r"; done

# shellcheck disable=SC2086
curl -sS --url "$SMTP_URL" --ssl-reqd --netrc-file "$NETRC" \
  --mail-from "$FROM" $RCPT_ARGS --upload-file "$OUT"
