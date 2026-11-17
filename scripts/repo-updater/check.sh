#!/bin/sh
# Monthly (see run.sh): if GitHub has new commits, pull them (files only, nothing restarts), work out
# which containers those commits change, and email the list with an Upgrade button.
# "Changed" = the service's compose settings hash differs between before and after the
# pull, both computed here by the same Compose, so older drift doesn't count.
# Run by hand: docker exec repo-updater.<host> sh <BASE_DIR>/scripts/repo-updater/check.sh
. "$(dirname "$0")/lib.sh"

# ready_mail INTRO: email the pending containers with the Upgrade button.
ready_mail() {
  classify
  {
    html_head "Updates ready to apply"
    echo "<p style=\"margin:0 0 8px\">$1</p>"
    if [ -n "$UP" ]; then html_section "Containers to upgrade"; html_chips "$UP" "#dbeafe"
      html_button "${UPDATE_URL:?UPDATE_URL not set}?key=${REPO_UPDATE_KEY:?}" "Review &amp; upgrade"
    fi
    [ -n "$PROT" ] && { html_section "Changed, do by hand (protected)"; html_chips "$PROT" "#fde68a"; }
    [ -n "$STOP" ] && { html_section "Changed but stopped (left alone)"; html_chips "$STOP" "#e5e7eb"; }
    [ -n "$NEWS" ] && { html_section "New, start by hand"; html_chips "$NEWS" "#dcfce7"; }
    [ -n "$REMOVED" ] && { html_section "Removed from the repo, still running (remove by hand)"; html_chips "$REMOVED" "#fee2e2"; }
    [ -s "$COMMITS" ] && { html_section "Commits"; html_commits "$COMMITS"; }
    html_foot
  } | mail "$(echo $UP | wc -w | tr -d ' ') container(s) ready to upgrade"
}

if [ "$1" = --resend ]; then
  [ -s "$PENDING" ] || { echo "nothing pending"; exit 0; }
  ready_mail "Reminder: these are still waiting. Nothing has restarted yet."; exit 0
fi

if ! git fetch -q origin "$BRANCH" 2>>"$LOG"; then
  log "check: git fetch failed"; mail_error "Update check failed" "git fetch failed; see $LOG"; exit 1
fi
[ "$(git rev-list --count "HEAD..origin/$BRANCH")" -gt 0 ] || { log "check: up to date"; exit 0; }

dc config --hash='*' 2>>"$LOG" | sort > "$STATE_DIR/hash-before.txt"
OLD=$(git rev-parse --short HEAD)
if ! OUT=$(git pull -q --ff-only origin "$BRANCH" 2>&1); then
  log "check: pull failed"
  mail_error "Update check: git pull failed" "$OUT
$(git status --short)"
  exit 1
fi
NEW=$(git rev-parse --short HEAD)
git log --format='%h %s' "$OLD..$NEW" > "$STATE_DIR/new-commits.txt"
if ! dc config --hash='*' 2>"$STATE_DIR/config-error.txt" | sort > "$STATE_DIR/hash-after.txt"; then :; fi
if [ ! -s "$STATE_DIR/hash-after.txt" ]; then
  log "check: compose config failed after pull"
  mail_error "Update check: compose config failed" "$(cat "$STATE_DIR/config-error.txt")"; exit 1
fi

# Services whose settings changed, or that are new, in these commits.
CHANGED=$(awk 'NR==FNR {b[$1]=$2; next} !($1 in b) || b[$1]!=$2 {print $1}' \
  "$STATE_DIR/hash-before.txt" "$STATE_DIR/hash-after.txt")
REMOVED=$(awk 'NR==FNR {a[$1]=1; next} !($1 in a) {print $1}' \
  "$STATE_DIR/hash-after.txt" "$STATE_DIR/hash-before.txt")

if [ -z "$CHANGED$REMOVED" ]; then
  log "check: pulled $OLD -> $NEW, no container changes"
  exit 0
fi
cat "$STATE_DIR/new-commits.txt" "$COMMITS" > "$STATE_DIR/c.tmp" && mv "$STATE_DIR/c.tmp" "$COMMITS"
{ cat "$PENDING"; echo "$CHANGED" | tr ' ' '\n'; } | grep -v '^$' | sort -u > "$STATE_DIR/p.tmp" && mv "$STATE_DIR/p.tmp" "$PENDING"
log "check: pulled $OLD -> $NEW, pending:$(echo $(cat "$PENDING"))"

ready_mail "Pulled <b>$OLD &rarr; $NEW</b>. Nothing has restarted yet."
