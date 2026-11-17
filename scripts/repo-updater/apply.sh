#!/bin/sh
# Pull, let Compose recreate whatever's settings changed, then email the result.
# Only running, unprotected services are passed to "up"; Compose itself decides which
# of those need recreating (unchanged ones just report "Running"). What actually changed
# is found by comparing container IDs before and after.
# Run by hand: docker exec repo-updater.<host> sh /share/.../scripts/repo-updater/apply.sh
# Dry run (pulls, recreates nothing, lists what Compose would do):
#   docker exec -e DRY_RUN=1 repo-updater.<host> sh .../apply.sh
. "$(dirname "$0")/lib.sh"
LOCK="$STATE_DIR/apply.lock"
mkdir "$LOCK" 2>/dev/null || { log "apply: already running"; exit 0; }
trap 'rmdir "$LOCK"' EXIT
OUT="$STATE_DIR/last-apply.txt"
exec >"$OUT" 2>&1
log "apply: start"

ps_all() {
  docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
    --format '{{.Label "com.docker.compose.service"}} {{.ID}} {{.State}} {{.Label "com.docker.compose.config-hash"}}'
}
ps_all > "$STATE_DIR/before.txt"

OLD=$(git rev-parse --short HEAD)
if ! git pull -q --ff-only origin "$BRANCH"; then
  echo "git pull --ff-only failed; nothing was changed."
  git status --short
  log "apply: pull failed"; mail "Update FAILED (git pull)" < "$OUT"; exit 1
fi
NEW=$(git rev-parse --short HEAD)
echo "Pulled $OLD -> $NEW"
git log --format='  %h %s' "$OLD..$NEW"
echo

if ! dc config --hash='*' > "$STATE_DIR/after.txt"; then
  echo "compose config failed; nothing was recreated."
  log "apply: compose config failed"; mail "Update FAILED (compose config)" < "$OUT"; exit 1
fi

TARGETS=""; PROTECTED=""; STOPPED=""; NEWSVC=""
while read -r svc hash; do
  line=$(awk -v s="$svc" '$1==s' "$STATE_DIR/before.txt" | head -1)
  if [ -z "$line" ]; then NEWSVC="$NEWSVC $svc"; continue; fi
  # shellcheck disable=SC2086
  set -- $line
  if skipped "$svc"; then
    # Can't ask Compose without touching it, so the hash is only a hint here.
    [ "$4" = "$hash" ] || PROTECTED="$PROTECTED $svc"
    continue
  fi
  if [ "$3" != running ]; then
    [ "$4" = "$hash" ] || STOPPED="$STOPPED $svc"
    continue
  fi
  TARGETS="$TARGETS $svc"
done < "$STATE_DIR/after.txt"

REMOVED=$(awk '{print $1}' "$STATE_DIR/before.txt" | sort -u | while read -r s; do
  grep -q "^$s " "$STATE_DIR/after.txt" || printf '%s ' "$s"; done)

if [ -n "$DRY_RUN" ]; then
  echo "DRY RUN, nothing recreated. Compose would do:"
  # shellcheck disable=SC2086
  [ -n "$TARGETS" ] && dc up -d --no-deps --dry-run $TARGETS 2>&1 | grep -viE ' (running|started)$' | sed 's/^/  /'
elif [ -n "$TARGETS" ]; then
  # shellcheck disable=SC2086
  dc up -d --no-deps $TARGETS 2>&1 | grep -viE ' running$'
fi
ps_all > "$STATE_DIR/now.txt"

# Which containers really changed (new container ID).
CHANGED=""
for svc in $TARGETS; do
  a=$(awk -v s="$svc" '$1==s{print $2}' "$STATE_DIR/before.txt" | head -1)
  b=$(awk -v s="$svc" '$1==s{print $2}' "$STATE_DIR/now.txt" | head -1)
  [ "$a" = "$b" ] || CHANGED="$CHANGED $svc"
done

# Containers sharing a recreated container's network (network_mode: service:X) lose
# that network, so recreate them too.
FOLLOW=""
for svc in $CHANGED; do
  id=$(awk -v s="$svc" '$1==s{print $2}' "$STATE_DIR/before.txt" | head -1)
  for c in $(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT"); do
    case "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$c")" in
      container:"$id"*)
        f=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$c")
        case " $CHANGED $FOLLOW " in *" $f "*) ;; *) FOLLOW="$FOLLOW $f" ;; esac ;;
    esac
  done
done
if [ -n "$FOLLOW" ]; then
  echo "Recreating (shared a recreated container's network):$FOLLOW"
  # shellcheck disable=SC2086
  dc up -d --no-deps --force-recreate $FOLLOW 2>&1 | grep -viE ' running$'
fi

echo
if [ -z "$DRY_RUN" ]; then
  if [ -n "$CHANGED$FOLLOW" ]; then
    echo "Recreated:$CHANGED$FOLLOW"
    echo "Status after 60 s:"
    sleep 60
    for svc in $CHANGED $FOLLOW; do
      docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
        --filter "label=com.docker.compose.service=$svc" --format '  {{.Names}}: {{.Status}}'
    done
  else
    echo "No container needed recreating."
  fi
fi
[ -n "$PROTECTED" ] && { echo; echo "May have changed but NOT applied (protected, do by hand):$PROTECTED"; }
[ -n "$STOPPED" ]   && { echo; echo "May have changed but stopped, left stopped:$STOPPED"; }
[ -n "$NEWSVC" ]    && { echo; echo "New in the repo, not started (start by hand):$NEWSVC"; }
[ -n "$REMOVED" ]   && { echo; echo "No longer in the repo but still exist (remove by hand): $REMOVED"; }

STATUS="done"
[ -n "$DRY_RUN" ] && STATUS="dry run"
docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} {{.Status}}' \
  | grep -E 'Exited|Restarting|unhealthy' > "$STATE_DIR/bad.txt"
if [ -s "$STATE_DIR/bad.txt" ]; then
  STATUS="$STATUS, with problems"
  echo; echo "Containers not running or unhealthy:"; sed 's/^/  /' "$STATE_DIR/bad.txt"
fi
log "apply: $OLD -> $NEW, recreated:${CHANGED:- none}${FOLLOW:+ +$FOLLOW}; $STATUS"
mail "Update $STATUS ($OLD -> $NEW)" < "$OUT"
