#!/usr/bin/env sh
#
# radarr_sonarr_cleanup.sh
#
# Purpose:
#   Automatically remove movies or series from Radarr/Sonarr when all video
#   files have been deleted from disk (typically by Maintainerr).
#
# How it works:
#   - Sonarr/Radarr fire "EpisodeFileDelete" or "MovieFileDelete" events
#     whenever they detect a missing video file.
#   - This script runs on those events and checks the remaining files for
#     the affected movie/series.
#   - Only true video files are counted (mkv, mp4, avi, etc).
#   - If *no* video files remain, the script removes the movie/series from
#     Radarr/Sonarr via their API.
#   - Non‑video files (srt, txt, nfo, jpg, etc) are ignored and do NOT block
#     deletion.
#
# Safety:
#   - The script will NOT delete anything if at least one video file remains.
#   - Manual deletions behave the same as Maintainerr deletions.
#   - API keys are loaded securely from /secrets and not stored in this file.
#
# Requirements:
#   - Script must be mounted into the container at /scripts
#   - Secrets folder must be mounted at /secrets (read‑only)
#   - jq must be available in the container
#
# Logging:
#   - All output is sent to Sonarr/Radarr logs via stdout.
#   - Optional file logging can be added if needed.
#
# Test Events:
#   - Sonarr/Radarr "Test" events include no IDs.
#   - These are safely ignored and exit cleanly.


# Ignore Test events
if [ "$sonarr_eventtype" = "Test" ] || [ "$radarr_eventtype" = "Test" ]; then
    echo "[INFO] radarr_sonarr_cleanup.sh — Test event received, exiting cleanly"
    exit 0
fi



###############################################
# LOAD API KEYS FROM SECRETS FOLDER
###############################################
RADARR_API=$(cat /secrets/radarr_api_key)
SONARR_API=$(cat /secrets/sonarr_api_key)

RADARR_URL="http://radarr:7878"
SONARR_URL="http://sonarr:8989"

# Video extensions to consider as "real media"
VIDEO_EXTENSIONS="mkv mp4 avi mov wmv flv m4v ts mpeg mpg"

is_video_file() {
    file="$1"
    ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    for vext in $VIDEO_EXTENSIONS; do
        if [ "$ext" = "$vext" ]; then
            return 0
        fi
    done

    return 1
}


###############################################
# RADARR — Movie File Delete Event
###############################################
if [ "$radarr_eventtype" = "MovieFileDelete" ] && [ -n "$radarr_movie_id" ]; then
    echo "[INFO] radarr_sonarr_cleanup.sh — delete event for movie ID: $radarr_movie_id"

    MOVIE_JSON=$(curl -s -H "X-Api-Key: $RADARR_API" "$RADARR_URL/api/v3/movie/$radarr_movie_id")
    FILES=$(echo "$MOVIE_JSON" | jq -r '.movieFile.relativePath')

    VIDEO_COUNT=0
    for f in $FILES; do
        if is_video_file "$f"; then
            VIDEO_COUNT=$((VIDEO_COUNT+1))
        fi
    done

    if [ "$VIDEO_COUNT" -eq 0 ]; then
        echo "[INFO] radarr_sonarr_cleanup.sh — No video files remain — deleting movie from Radarr"
        curl -s -X DELETE \
            "$RADARR_URL/api/v3/movie/$radarr_movie_id?deleteFiles=false&addExclusion=false" \
            -H "X-Api-Key: $RADARR_API"
    else
        echo "[INFO] radarr_sonarr_cleanup.sh — Movie still has $VIDEO_COUNT video files — not deleting"
    fi
fi

###############################################
# SONARR — Episode File Delete Event
###############################################
if [ "$sonarr_eventtype" = "EpisodeFileDelete" ] && [ -n "$sonarr_series_id" ]; then
    echo "[INFO] radarr_sonarr_cleanup.sh — delete event for series ID: $sonarr_series_id"

    EP_JSON=$(curl -s -H "X-Api-Key: $SONARR_API" \
        "$SONARR_URL/api/v3/episodefile?seriesId=$sonarr_series_id")

    FILES=$(echo "$EP_JSON" | jq -r '.[].relativePath')

    VIDEO_COUNT=0
    for f in $FILES; do
        if is_video_file "$f"; then
            VIDEO_COUNT=$((VIDEO_COUNT+1))
        fi
    done

    if [ "$VIDEO_COUNT" -eq 0 ]; then
        echo "[INFO] radarr_sonarr_cleanup.sh — No video files remain — deleting series from Sonarr"
        curl -s -X DELETE \
            "$SONARR_URL/api/v3/series/$sonarr_series_id?deleteFiles=false&addExclusion=false" \
            -H "X-Api-Key: $SONARR_API"
    else
        echo "[INFO] radarr_sonarr_cleanup.sh — Series still has $VIDEO_COUNT video files — not deleting"
    fi
fi