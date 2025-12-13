#!/bin/sh

# Adjust these paths and email before using in production
LOGFILE="/var/log/nextcloud_fix.log"
MAILTO="your_email@example.com"

fix_perms() {
  USERNAME=$1
  USERID=$2
  DIR="/path/to/nextcloud/$USERNAME"

  echo "$(date '+%Y-%m-%d %H:%M:%S') Fixing perms for $DIR" >> "$LOGFILE"

  # Note: replace '33' with the appropriate group ID for your environment
  if chown -R "$USERID":33 "$DIR" && chmod -R 770 "$DIR"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Success for $DIR" >> "$LOGFILE"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR fixing $DIR" >> "$LOGFILE"
    echo "Permission fix failed for $DIR on $(date)" | mail -s "Nextcloud Fix Failed" "$MAILTO"
  fi
}

# Run for each user (replace with actual usernames and IDs)
fix_perms user1 1001
fix_perms user2 1002
fix_perms user3 1003
fix_perms user4 1004
fix_perms user5 1005
fix_perms user6 1006
