#!/bin/sh
# ------------------------------------------------------------------------------
# sort_user_photos.sh - sort a family member's phone uploads (Nextcloud auto-upload)
#
# iPhones upload everything from one camera roll, so real photos arrive mixed with
# screenshots, WhatsApp images, Facebook downloads and saved memes. This script:
#   1. Camera photos/videos (camera Make + a capture date)  -> <user>/Photos/YYYY/MM
#   2. iPhone screenshots (EXIF UserComment "Screenshot")   -> <user>/Photos-NotCamera/Screenshots/YYYY/MM
#   3. Everything else (no camera info: WhatsApp, FB, ...)  -> <user>/Photos-NotCamera/Other/YYYY/MM
# Photos-NotCamera sits beside Photos, so the user can still see and rescue things in
# Nextcloud, and UserPhotosBackToMainPhotos.sh (which copies Photos/) never picks it up.
#
# Only files not already in a YYYY/MM folder are touched. Nothing is deleted. Name clashes
# get a -1, -2 ... suffix. Videos are handled (iPhone .mov keeps its date in QuickTime tags).
#
# Uses exiftool from the PhotoPrism image already on the host (no host install needed).
#
# Usage:
#   sort_user_photos.sh <nextcloud-user>                 dry run: prints what would move
#   sort_user_photos.sh <nextcloud-user> run             moves files
#   sort_user_photos.sh <nextcloud-user> run <extra-dir> also sweep another folder
#                                                        recursively (e.g. an old quarantine)
# Cron (daily 02:30, before the weekly copy to the main library):
#   30 2 * * * /share/Docker/GillisDockerDepot/scripts/sort_user_photos.sh <user> run
# ------------------------------------------------------------------------------

USER_NAME="$1"
MODE="${2:-dryrun}"
EXTRA="$3"
[ -n "$USER_NAME" ] || { echo "usage: $0 <nextcloud-user> [dryrun|run] [extra-dir]"; exit 1; }

NC_ROOT="/share/nextcloud"
SRC="$NC_ROOT/$USER_NAME/Photos"
JUNK="$NC_ROOT/$USER_NAME/Photos-NotCamera"
IMAGE="photoprism/photoprism:261029"   # any image with exiftool works
RUN_UID=1000
RUN_GID=33                            # www-data, so Nextcloud keeps write access
TZ_LOCAL="America/Toronto"
NC_CONTAINER="nextcloud.GillisNAS"
NC_HOME_MOUNT="Documents"             # Nextcloud external mount that maps /homes/$user
LOGDIR="/share/homes/GilAdmin/logs"
LOG="$LOGDIR/sort_photos_${USER_NAME}.log"
EXTS="-ext jpg -ext jpeg -ext png -ext heic -ext heif -ext gif -ext webp -ext mov -ext mp4 -ext m4v"

export PATH="$PATH:/share/CACHEDEV1_DATA/.qpkg/container-station/bin"
export DOCKER_CONFIG=/tmp/.none

[ -d "$SRC" ] || { echo "no such folder: $SRC"; exit 1; }
mkdir -p "$LOGDIR" "$JUNK"
chgrp $RUN_GID "$JUNK" 2>/dev/null; chmod 2770 "$JUNK" 2>/dev/null

if [ "$MODE" = "run" ]; then NAMETAG="FileName"; else NAMETAG="TestName"; fi

# Nextcloud's iOS upload names files "YY-MM-DD HH-MM-SS NNNN.ext" using the date the photo
# entered the phone's library. For non-camera files that beats the upload (modify) date.
# Later assignments win when they produce a value, so this overrides FileModifyDate.
NAMEDATE='$_ = m/^(\d\d)-(\d\d)-\d\d \d\d-\d\d-\d\d/ ? "20$1/$2" : undef'

# Inputs (container paths): the Photos root and each year folder, not recursive,
# so files already in YYYY/MM are left alone.
INPUTS="/src"
for d in "$SRC"/[12][0-9][0-9][0-9]; do
  [ -d "$d" ] && INPUTS="$INPUTS /src/$(basename "$d")"
done
EXTRA_MOUNT=""
if [ -n "$EXTRA" ]; then
  [ -d "$EXTRA" ] || { echo "no such folder: $EXTRA"; exit 1; }
  EXTRA_MOUNT="-v $EXTRA:/extra"
fi

exiftool_run() {
  # $1 = extra args for recursion; rest = exiftool args
  docker run --rm -u $RUN_UID:$RUN_GID -e TZ="$TZ_LOCAL" \
    -v "$SRC":/src -v "$JUNK":/junk $EXTRA_MOUNT \
    --entrypoint sh "$IMAGE" -c 'umask 002; exec exiftool "$@"' sh "$@"
}

sweep() {
  # $@ = input folders (plus -r if recursive)
  echo "--- camera photos and videos"
  exiftool_run -q -q $EXTS -api QuickTimeUTC -d %Y/%m \
    -if '$Make and ($DateTimeOriginal or $CreateDate or $ContentCreateDate) and not ($SpecialInstructions and $SpecialInstructions =~ /^FBMD/)' \
    "-$NAMETAG</src/\${CreateDate}/%f%-c.%e" \
    "-$NAMETAG</src/\${ContentCreateDate}/%f%-c.%e" \
    "-$NAMETAG</src/\${DateTimeOriginal}/%f%-c.%e" \
    "$@"

  echo "--- screenshots"
  exiftool_run -q -q $EXTS -d %Y/%m \
    -if '$UserComment and $UserComment eq "Screenshot" and not $Make' \
    "-$NAMETAG</junk/Screenshots/\${FileModifyDate}/%f%-c.%e" \
    "-$NAMETAG</junk/Screenshots/\${FileName;$NAMEDATE}/%f%-c.%e" \
    "-$NAMETAG</junk/Screenshots/\${DateTimeOriginal}/%f%-c.%e" \
    "$@"

  # In a dry run nothing moved, so skip files the first two passes would have taken.
  echo "--- not from a camera (WhatsApp, Facebook, saved images)"
  exiftool_run -q -q $EXTS -d %Y/%m \
    -if 'not ($Make and ($DateTimeOriginal or $CreateDate or $ContentCreateDate) and not ($SpecialInstructions and $SpecialInstructions =~ /^FBMD/)) and not ($UserComment and $UserComment eq "Screenshot" and not $Make)' \
    "-$NAMETAG</junk/Other/\${FileModifyDate}/%f%-c.%e" \
    "-$NAMETAG</junk/Other/\${FileName;$NAMEDATE}/%f%-c.%e" \
    "$@"
}

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') $USER_NAME mode=$MODE ${EXTRA:+extra=$EXTRA}"
  # shellcheck disable=SC2086
  sweep $INPUTS
  [ -n "$EXTRA" ] && sweep -r /extra
  if [ "$MODE" = "run" ]; then
    # Remove folders left empty. BusyBox find has no -empty; rmdir refuses non-empty ones.
    find "$SRC" -mindepth 1 -maxdepth 1 -type d -exec rmdir {} \; 2>/dev/null
    [ -n "$EXTRA" ] && find "$EXTRA" -mindepth 1 -depth -type d -exec rmdir {} \; 2>/dev/null
    # Tell Nextcloud about the moves (user homes are the external mount /Documents)
    for p in Photos Photos-NotCamera; do
      docker exec -u 33 "$NC_CONTAINER" php occ files:scan --quiet \
        --path="/$USER_NAME/files/$NC_HOME_MOUNT/$p" || echo "nextcloud rescan failed for $p"
    done
  fi
  echo "=== done $(date '+%H:%M:%S')"
} 2>&1 | tee -a "$LOG"
