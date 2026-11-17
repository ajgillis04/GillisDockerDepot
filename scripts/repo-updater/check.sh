#!/bin/sh
# Weekly check: fetch, and if this server is behind, email what's new with a link to apply it.
# If nothing new affects this server, just fast-forward the checkout quietly.
# Run by hand: docker exec repo-updater.<host> sh /share/.../scripts/repo-updater/check.sh
. "$(dirname "$0")/lib.sh"

if ! git fetch -q origin "$BRANCH" 2>>"$LOG"; then
  log "check: git fetch failed"
  echo "git fetch failed on $HOST_NAME; see $LOG" | mail "Update check failed"
  exit 1
fi
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH")
[ "$BEHIND" -gt 0 ] || { log "check: up to date"; exit 0; }

FILES=$(relevant_files HEAD "origin/$BRANCH")
if [ -z "$FILES" ]; then
  if git merge -q --ff-only "origin/$BRANCH" >>"$LOG" 2>&1; then
    log "check: $BEHIND commit(s), none for $SERVER; fast-forwarded"
  else
    log "check: fast-forward failed"
    echo "git merge --ff-only failed on $HOST_NAME; see $LOG" | mail "Update check failed"
  fi
  exit 0
fi

LOCAL=$(git status --porcelain --untracked-files=no)
log "check: $BEHIND commit(s) behind, emailing"
{
  echo "$HOST_NAME is $BEHIND commit(s) behind $BRANCH."
  echo
  echo "Review and apply:"
  echo "  ${UPDATE_URL:?UPDATE_URL not set}?key=${REPO_UPDATE_KEY:?REPO_UPDATE_KEY not set}"
  echo
  echo "New commits:"
  git log --format='  %h %s' "HEAD..origin/$BRANCH"
  echo
  echo "Files that affect this server:"
  echo "$FILES" | sed 's/^/  /'
  if [ -n "$LOCAL" ]; then
    echo
    echo "WARNING: local changes to tracked files; the pull may refuse to run:"
    echo "$LOCAL" | sed 's/^/  /'
  fi
  echo
  echo "Applying recreates only containers whose settings changed. Never touched:$SKIP"
} | mail "$BEHIND update(s) waiting"
