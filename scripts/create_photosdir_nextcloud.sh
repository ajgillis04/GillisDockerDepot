#!/bin/bash

# Script: create_photosdir_nextcloud.sh
# Purpose: This script creates a 'Photos' directory for each user in the '/share/homes' directory and sets appropriate permissions.
# Reason: Ensures that the Nextcloud service, running under the 'www-data' user within the container, can access and upload photos for each user.
# Prerequisites: chmod +x /path/to/create_photosdir_nextcloud.sh
# Usage: Run this script on the NAS to automatically set up 'Photos' directories with the correct permissions for each user.
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
  
  # Set permissions for Photos directory on the host
  sudo chown -R www-data:www-data "$user_dir/Photos"
  sudo chmod -R 775 "$user_dir/Photos"
  echo "Set permissions for Photos directory for user: $username"
done

# Set permissions within the Nextcloud container
#docker exec -it nextcloud-aio-nextcloud bash -c 'for user_dir in /share/homes/*; do if [ -d "$user_dir/Photos" ]; then chown -R www-data:www-data "$user_dir/Photos"; chmod -R 775 "$user_dir/Photos"; echo "Set permissions for Photos directory in $user_dir"; fi; done'
docker exec -it nextcloud.GillisNAS bash -c 'for user_dir in /share/homes/*; do if [ -d "$user_dir/Photos" ]; then chown -R www-data:www-data "$user_dir/Photos"; chmod -R 775 "$user_dir/Photos"; echo "Set permissions for Photos directory in $user_dir"; fi; done'

echo "Script completed successfully."
