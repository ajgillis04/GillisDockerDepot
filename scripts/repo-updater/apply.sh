#!/bin/sh
# Pull, recreate only the containers whose compose settings changed, then email the result.
# Run by hand: docker exec repo-updater.<host> sh /share/.../scripts/repo-updater/apply.sh
. "$(dirname "$0")/lib.sh"
LOCK="$STATE_DIR/apply.lock"
mkdir "$LOCK" 2>/dev/null || { log "apply: already running"; exit 0; }
trap 'rmdir "$LOCK"' EXIT
OUT="$STATE_DIR/last-apply.txt"
exec >"$OUT" 2>&1
log "apply: start"

# Each existing container's settings hash, from the labels Compose put on it.
docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
  --format '{{.Label "com.docker.compose.service"}} {{.Label "com.docker.compose.config-hash"}} {{.State}} {{.ID}}' \
  > "$STATE_DIR/before.txt"

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

RECREATE=""; SKIPPED=""; STOPPED=""; NEWSVC=""
while read -r svc hash; do
  line=$(awk -v s="$svc" '$1==s' "$STATE_DIR/before.txt" | head -1)
  if [ -z "$line" ]; then NEWSVC="$NEWSVC $svc"; continue; fi
  # shellcheck disable=SC2086
  set -- $line
  [ "$2" = "$hash" ] && continue
  if skipped "$svc"; then SKIPPED="$SKIPPED $svc"; continue; fi
  [ "$3" = running ] || { STOPPED="$STOPPED $svc"; continue; }
  RECREATE="$RECREATE $svc"
done < "$STATE_DIR/after.txt"

# Containers that share a recreated container's network (network_mode: service:X)
# lose their network when it is recreated, so they are recreated with it.
FOLLOW=""
for svc in $RECREATE; do
  id=$(awk -v s="$svc" '$1==s{print $4}' "$STATE_DIR/before.txt" | head -1)
  for c in $(docker ps -q --filter "label=com.docker.compose.project=$PROJECT"); do
    case "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$c")" in
      container:"$id"*)
        f=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$c")
        case " $RECREATE $FOLLOW " in *" $f "*) ;; *) FOLLOW="$FOLLOW $f" ;; esac ;;
    esac
  done
done

REMOVED=$(awk '{print $1}' "$STATE_DIR/before.txt" | sort -u | while read -r s; do
  grep -q "^$s " "$STATE_DIR/after.txt" || printf '%s ' "$s"; done)

if [ -n "$RECREATE" ]; then
  echo "Recreating:$RECREATE"
  # shellcheck disable=SC2086
  dc up -d --no-deps $RECREATE
  if [ -n "$FOLLOW" ]; then
    echo "Recreating (shares a recreated container's network):$FOLLOW"
    # shellcheck disable=SC2086
    dc up -d --no-deps --force-recreate $FOLLOW
  fi
  echo
  echo "Status after 60 s:"
  sleep 60
  for svc in $RECREATE $FOLLOW; do
    docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
      --filter "label=com.docker.compose.service=$svc" --format '  {{.Names}}: {{.Status}}'
  done
else
  echo "No running container's settings changed."
fi
[ -n "$SKIPPED" ] && { echo; echo "Changed but NOT applied (protected, do by hand):$SKIPPED"; }
[ -n "$STOPPED" ] && { echo; echo "Changed but stopped, left stopped:$STOPPED"; }
[ -n "$NEWSVC" ]  && { echo; echo "New in the repo, not started (start by hand):$NEWSVC"; }
[ -n "$REMOVED" ] && { echo; echo "No longer in the repo but still exist (remove by hand): $REMOVED"; }

STATUS="done"
docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} {{.Status}}' \
  | grep -E 'Exited|Restarting|unhealthy' > "$STATE_DIR/bad.txt"
if [ -s "$STATE_DIR/bad.txt" ]; then
  STATUS="done, with problems"
  echo; echo "Containers not running or unhealthy:"; sed 's/^/  /' "$STATE_DIR/bad.txt"
fi
log "apply: $OLD -> $NEW, recreated:${RECREATE:- none}${FOLLOW:+ +$FOLLOW}; $STATUS"
mail "Update $STATUS ($OLD -> $NEW)" < "$OUT"
