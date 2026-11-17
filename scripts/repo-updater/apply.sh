#!/bin/sh
# Upgrade the containers that pulled commits changed (pending.txt, written by check.sh):
# only running, unprotected ones; nothing else is passed to Compose. Then email the result.
# Run by hand: docker exec repo-updater.<host> sh <BASE_DIR>/scripts/repo-updater/apply.sh
. "$(dirname "$0")/lib.sh"
LOCK="$STATE_DIR/apply.lock"
mkdir "$LOCK" 2>/dev/null || { log "apply: already running"; exit 0; }
trap 'rmdir "$LOCK"' EXIT
OUT="$STATE_DIR/last-apply.txt"
exec >"$OUT" 2>&1
classify
log "apply: start, upgrading:${UP:- none}"
[ -n "$UP" ] || { log "apply: nothing to do"; exit 0; }

ids() { for s in $1; do printf '%s %s\n' "$s" "$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$s" | head -1)"; done; }
ids "$UP" > "$STATE_DIR/ids-before.txt"

# shellcheck disable=SC2086
dc up -d --no-deps $UP

# Containers that share an upgraded container's network (network_mode: service:X) lose
# it when that container is recreated, so they are recreated too.
FOLLOW=""
while read -r svc id; do
  for c in $(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT"); do
    case "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$c")" in
      container:"$id"*)
        f=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$c")
        case " $UP $FOLLOW " in *" $f "*) ;; *) FOLLOW="$FOLLOW $f" ;; esac ;;
    esac
  done
done < "$STATE_DIR/ids-before.txt"
# shellcheck disable=SC2086
[ -n "$FOLLOW" ] && dc up -d --no-deps --force-recreate $FOLLOW

sleep 60
OK=""; BAD=""
for svc in $UP $FOLLOW; do
  st=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=$svc" --format '{{.Status}}' | head -1)
  case "$st" in Up*unhealthy*|Exited*|Restarting*|"") BAD="$BAD $svc" ;; *) OK="$OK $svc" ;; esac
done

# Upgraded ones leave the pending list; protected/stopped/new stay until done by hand.
for s in $UP; do sed -i "/^$s\$/d" "$PENDING"; done
[ -s "$PENDING" ] || : > "$COMMITS"
log "apply: upgraded:$UP${FOLLOW:+ +$FOLLOW}; ok:${OK:- none}; problems:${BAD:- none}"

TITLE="Upgrade done"; [ -n "$BAD" ] && TITLE="Upgrade done, with problems"
{
  html_head "$TITLE"
  [ -n "$OK" ]  && { html_section "Running"; html_chips "$OK" "#dcfce7"; }
  [ -n "$BAD" ] && { html_section "Not running or unhealthy"; html_chips "$BAD" "#fee2e2"; }
  [ -n "$FOLLOW" ] && echo "<p style=\"font-size:14px;color:#6b7280\">Also recreated because they share a network:$FOLLOW</p>"
  classify
  [ -n "$PROT$STOP$NEWS" ] && { html_section "Still waiting for you"; html_chips "$PROT $STOP $NEWS" "#fde68a"; }
  html_section "Details"; html_pre < "$OUT"
  html_foot
} | mail "$TITLE"
