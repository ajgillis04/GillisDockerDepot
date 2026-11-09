#!/bin/sh
# Copies the console output (docker logs) of containers that don't write their own log files into
# appdata/logs/<app>/<app>.log, so every app has its logs in one place and they survive a container
# being recreated (Docker drops a container's logs when Watchtower or compose replaces it).
#
# Run from cron every 15 minutes, e.g. on a QNAP in /etc/config/crontab:
#   */15 * * * * /share/Docker/GillisDockerDepot/scripts/export-container-logs.sh
# then: crontab /etc/config/crontab && /etc/init.d/crond.sh restart
#
# Each run appends only what was logged since the last run (state in <app>/.last_export).
# A log over MAX_KB is rotated to <app>.log.1 ... <app>.log.$KEEP.
#
# Usage: export-container-logs.sh [app ...]   (default: the APPS list below)
# Container names are <app>.<HOST_NAME>, as in the compose files.

DOCKERDIR="${DOCKERDIR:-/share/Docker/GillisDockerDepot/appdata}"
HOST_NAME="${HOST_NAME:-$(hostname)}"
MAX_KB="${MAX_KB:-10240}"
KEEP="${KEEP:-5}"
# Apps that only log to the console. Apps that write their own files (the *arrs, Plex,
# Tautulli, Traefik and so on) are left out.
APPS="${APPS:-chowdown cloudflare-ddns cloudflared guacamole guacd homeassistant mariadb mosquitto portainer retroassembly sbs-app-dev sbs-mysql8 vaultwarden watchtower}"

export PATH="$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin"
export DOCKER_CONFIG="${DOCKER_CONFIG:-/tmp/.none}"

[ "$#" -gt 0 ] && APPS="$*"
now=$(date +%s)

for app in $APPS; do
    container="$app.$HOST_NAME"
    docker inspect "$container" >/dev/null 2>&1 || continue

    dir="$DOCKERDIR/logs/$app"
    log="$dir/$app.log"
    state="$dir/.last_export"
    mkdir -p "$dir"

    # First run: start from the last 24 hours rather than everything Docker still has.
    since=$(cat "$state" 2>/dev/null)
    case "$since" in ''|*[!0-9]*) since=$((now - 86400)) ;; esac

    # The marker only moves forward when lines were written: a run that got nothing (a quiet app,
    # or a docker hiccup) is covered again by the next run, so nothing is skipped or doubled.
    tmp="$dir/.export.tmp"
    if docker logs --timestamps --since "$since" --until "$now" "$container" >"$tmp" 2>&1 && [ -s "$tmp" ]; then
        cat "$tmp" >>"$log"
        echo "$now" >"$state"
    fi
    rm -f "$tmp"
    touch "$log"
    chmod 644 "$log" 2>/dev/null

    size=$(du -k "$log" 2>/dev/null | cut -f1)
    if [ "${size:-0}" -gt "$MAX_KB" ]; then
        i=$KEEP
        while [ "$i" -gt 1 ]; do
            [ -f "$log.$((i - 1))" ] && mv -f "$log.$((i - 1))" "$log.$i"
            i=$((i - 1))
        done
        mv -f "$log" "$log.1"
        : >"$log"
    fi
done
