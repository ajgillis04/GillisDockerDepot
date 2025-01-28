#!/bin/bash

# Define your Docker Compose project and file
PROJECT="mediaserver"
COMPOSE_FILE="docker-compose.yml"
LOG_FILE="update-containers.log"

# Function to log messages
log_message() {
  local message=$1
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a $LOG_FILE
}

# Function to update a specific service
update_service() {
  local service=$1
  log_message "Checking for updates: $service"

  # Pull the latest image
  docker-compose -p $PROJECT -f $COMPOSE_FILE pull $service

  # Get current and new image digests
  current_digest=$(docker inspect --format='{{index .RepoDigests 0}}' $service)
  new_digest=$(docker-compose -p $PROJECT -f $COMPOSE_FILE images --quiet $service | xargs docker inspect --format='{{index .RepoDigests 0}}')

  # Compare digests and update if necessary
  if [ "$current_digest" != "$new_digest" ]; then
    log_message "Updating $service: $current_digest -> $new_digest"
    docker-compose -p $PROJECT -f $COMPOSE_FILE up --no-deps --detach $service
  else
    log_message "$service is up-to-date."
  fi
}

# Retrieve the list of services from docker-compose.yml
SERVICES=$(yq e '.services | keys | .[]' $COMPOSE_FILE)

# Loop through each service
for service in $SERVICES; do
  # Check if the service has the watchtower.enable label set to true
  label=$(docker-compose -p $PROJECT -f $COMPOSE_FILE config --services $service | xargs docker inspect --format '{{ index .Config.Labels "com.centurylinklabs.watchtower.enable" }}')

  if [ "$label" == "true" ]; then
    update_service $service
  else
    log_message "Skipping update for $service as watchtower.enable