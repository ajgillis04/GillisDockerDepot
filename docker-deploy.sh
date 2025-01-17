#!/bin/bash
#***********************************************************************************
# Created: Andy Gillis
# Date:      Jan 17, 2025
# Purpose:   A script to start the proper docker config depending on the hostname
# Clone:     git clone https://github.com/ajgillis04/GillisDockerDepot.git
# Prereqs:   Docker 
#			 Windows: wsl & ubuntu, or git bash
#			 Linux: should just work
# Prereqs 1: chmod +x /mnt/d/Docker/GillisDockerDepot/docker-deploy.sh
# Prereqs 2: https://github.com/ajgillis04/GillisDockerDepot.git
#
# Note: 	 first time run these commands for windows
# Commands : wsl --install -d ubuntu
# Commands : sudo apt-get update
# Commands : sudo apt-get install bash
# Commands : start, search, ubuntu and open it
# cd /mnt/d/Docker/GillisDockerDepot
# Usage:     ./docker-deploy.sh
# **********************************************************************************

# Check if .env file exists
if [ ! -f .env ]; then
  echo ".env file not found! Please create and configure the .env file."
  exit 1
fi

echo ".env file found. Loading environment variables..."

# Load environment variables from .env file
while IFS='=' read -r key value; do
  # Ignore lines that are comments or empty
  if [[ $key =~ ^# ]] || [[ -z $key ]]; then
    continue
  fi
  # Export valid environment variables
  export "$key=$value"
done < .env

echo "Environment variables loaded."

# Determine the server name based on hostname using environment variables
case $HOSTNAME in
  $SERVER1_NAME)
    export SERVER_NAME=server1
    ;;
  $SERVER2_NAME)
    export SERVER_NAME=server2
    ;;
  $SERVER3_NAME)
    export SERVER_NAME=server3
    ;;
  *)
    echo "Unknown hostname: $HOSTNAME"
    exit 1
    ;;
esac

echo "Server name determined: $SERVER_NAME"

# Check if the docker-compose file exists
DOCKER_COMPOSE_FILE="docker-compose${SERVER_NAME}.yml"
if [ ! -f $DOCKER_COMPOSE_FILE ]; then
  echo "$DOCKER_COMPOSE_FILE not found! Please ensure the Docker Compose file exists."
  exit 1
fi

echo "Docker Compose file found. Running Docker Compose..."

# Run Docker Compose using the dynamic file name
docker compose -p mediaserver -f $DOCKER_COMPOSE_FILE up --detach
