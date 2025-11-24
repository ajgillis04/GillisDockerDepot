#!/bin/bash

# ------------------------------------------------------------
# Photo Quarantine Script for Nextcloud Uploads
# ------------------------------------------------------------
# Purpose:
#   - Sweep top-level photo directories for files lacking valid EXIF metadata
#   - Legitimate photos (with Make, Model, DateTimeOriginal) are sorted into year/month folders
#   - Non-originals (e.g., Facebook downloads, screenshots) are quarantined by file mtime
#
# Cron Setup (daily at 2:30 AM):
#   Add the following line to root's crontab via `sudo crontab -e`
#   30 2 * * * /share/Scripts/quarantine_photos.sh
#
# Requirements:
#   - exiv2 installed and in PATH
#   - Script must have read/write access to BASE_DIR and QUARANTINE paths
#   - Designed for dry-run safety and audit-friendly logging
# ------------------------------------------------------------

BASE_DIR="/path/to/your/files/Photos"
QUARANTINE="/path/to/put/Quarantine"
mkdir -p "$QUARANTINE"

# Optional: log file for audit
logfile="/share/Temp/quarantine_run_$(date +%F_%T).log"
exec > >(tee -a "$logfile") 2>&1

for yearDir in "$BASE_DIR"/*/; do
  [ -d "$yearDir" ] || continue
  year=$(basename "$yearDir")

  # Only look at files directly inside the year folder (not in month subfolders)
  find "$yearDir" -maxdepth 1 -type f | while read -r file; do
    make=$(exiv2 -pt "$file" | awk '/Exif.Image.Make/{print $4; exit}')
    model=$(exiv2 -pt "$file" | awk '/Exif.Image.Model/{print $4; exit}')
    date=$(exiv2 -pt "$file" | awk '/Exif.Photo.DateTimeOriginal/{print $4; exit}')

    if [ -n "$make" ] && [ -n "$model" ] && [ -n "$date" ]; then
      # Legit photo → move into year/month based on Exif date
      exifYear=$(echo "$date" | cut -d: -f1)
      exifMonth=$(echo "$date" | cut -d: -f2)
      target="$BASE_DIR/$exifYear/$exifMonth"
      mkdir -p "$target"
      mv "$file" "$target/"
      echo "Legit photo moved: $file → $target/"
    else
      # No Exif → quarantine into year/month based on file mtime
      qYear=$(date -r "$file" +%Y)
      qMonth=$(date -r "$file" +%m)
      qTarget="$QUARANTINE/$qYear/$qMonth"
      mkdir -p "$qTarget"
      mv "$file" "$qTarget/"
      echo "Quarantined non-original: $file → $qTarget/"
    fi
  done
done
