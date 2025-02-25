#!/bin/bash

# Script: create_photosdir_nextcloud.sh
# Purpose: This script creates a 'Photos' directory for each user in the '/share/homes' directory and sets appropriate permissions.
# Reason: Ensures that the Nextcloud service, running under the 'www-data' user, can access and upload photos for each user.
# Usage: Run this script on the NAS to automatically set up 'Photos' directories with the correct permissions for each user.
# Pre-requisites: chmod +x /path/to/create_photosdir_nextcloud.sh
# Note: If the script was edited on a Windows system, use 'dos2unix' to convert it before running on the NAS.

# Base directory for user homes
BASE_DIR="/share/homes"

# Get a list of all users on the NAS
users=$(getent passwd | awk -F: '{ if ($6 ~ /^\/share\/homes\//) print $1 }')

# Loop through each user
for username in $users; do
  user_dir="$BASE_DIR/$username"
  
  # Create Photos directory if it doesn't exist
  if [ ! -d "$user_dir/Photos" ]; then
    mkdir -p "$user_dir/Photos"
    echo "Created Photos directory for user: $username"
  fi
  
  # Set permissions for Photos directory
  chown -R www-data:www-data "$user_dir/Photos"
  chmod -R 775 "$user_dir/Photos"
  echo "Set permissions for Photos directory for user: $username"
done

echo "Script completed successfully."
