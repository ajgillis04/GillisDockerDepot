#!/bin/sh

# Adjust these paths and email before using in production
LOG="/path/to/logs/UserPhotosBackToMainPhotos.log"
MAILTO="your_email@example.com"
ERRORS=0

# Reset log at start of run and add timestamp header
echo "=== Run started $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LOG"

sync_photos() {
  USER=$1
  SRC="/path/to/nextcloud/$USER/Photos/"
  DEST="/path/to/media/Photos/"

  if [ -d "$SRC" ]; then
    rsync -av --ignore-existing --exclude='*/.@__thumb/' "$SRC" "$DEST"

    if [ $? -ne 0 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR during rsync for $SRC" >> "$LOG"
      ERRORS=1
    fi

    # Scan for files older than 3 years not present in DEST
    find "$SRC" -type f -mtime +1095 ! -path "*/.@__thumb/*" 2>/dev/null | while read FILE; do
      RELPATH=$(realpath --relative-to="$SRC" "$FILE")
      if [ -f "$DEST/$RELPATH" ]; then
        rm "$FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') Deleted old file: $FILE" >> "$LOG"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') OLD file not in DEST: $FILE" >> "$LOG"
        ERRORS=1
      fi
    done

    # Clean up empty year/month dirs
    find "$SRC" -type d -empty ! -path "*/.@__thumb/*" -exec rmdir {} \; -print 2>/dev/null >> "$LOG"

  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') Skipped $SRC (no photos dir)" >> "$LOG"
  fi
}

# Enabled users (replace with actual usernames)
sync_photos user1
# sync_photos user2
# sync_photos user3
# sync_photos user4

echo "=== Run completed $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

# Send one email at the end if any errors or unmatched old files were found
if [ $ERRORS -ne 0 ]; then
  mail -s "Photo Sync Issues Detected" "$MAILTO" < "$LOG"
fi
