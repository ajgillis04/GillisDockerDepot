#!/bin/bash

# This script generates a services.yaml file for the homepage app
# based on the running containers and their environment variables.
# It groups services into categories and sets the appropriate
# icon, href, widget, and siteMonitor values for each service.

# Load environment variables
set -a
source .env
set +a

# Set config file paths. Adjust these if needed.
SERVICES_CONFIG_FILE="${DOCKERDIR}/homepage/app/config/services.yaml"

# Define your service groups
media_list=("sonarr" "radarr" "bazarr" "lidarr" "overseerr" "tautulli" "plex" "tdarr" "sabnzbd" "prowlarr")
infrastructure_list=("traefik" "php-apache-gillisonline" "php-apache-awl" "portainer" "guacamole")
network_list=("pihole")
utility_list=("dozzle" "vaultwarden")

# Extract SERVER_IP from .env or default to localhost
SERVER_IP="${SERVER_IP:-127.0.0.1}"

# Initialize group variables
media_services="- media:\n"
infrastructure_services="- infrastructure:\n"
network_services="- network:\n"
utility_services="- utility:\n"
other_services="- other:\n"

# Added, skipped, and missing services for logging
added_services=()
skipped_services=()
missing_port_services=()

# Get the names of all running containers
running_containers=$(docker ps --format "{{.Names}}")

# Loop over each running container
for container in $running_containers; do
  # Standardize the container name
  cn_clean=$(echo "$container" | tr '[:upper:]' '[:lower:]' | sed 's/\.gillisnas//')

  # Extract API key and port for the application from .env
  api_key_var=$(env | grep -i "^${cn_clean}_API_KEY=" | awk -F'=' '{print $2}')
  port_var=$(env | grep -i "^${cn_clean}_PORT=" | awk -F'=' '{print $2}')

  # Log services with missing PORT
  if [ -z "$port_var" ]; then
    missing_port_services+=("$container")
    site_monitor_url="http://${SERVER_IP}" # Default to SERVER_IP without port
  else
    site_monitor_url="http://${SERVER_IP}:${port_var}"
  fi

  # Construct default href using SERVER_IP and PORT
  href_url="http://${SERVER_IP}"
  if [ -n "$port_var" ]; then
    href_url="${href_url}:${port_var}"
  fi

  # Extract container labels
  container_labels=$(docker inspect --format='{{json .Config.Labels}}' "$container" 2>/dev/null)

  # Extract the first valid Host(...) label to avoid duplicates
  if [ -n "$container_labels" ]; then
    container_url=$(echo "$container_labels" | grep -o 'Host(`[^`]*`)' | head -n 1 | sed 's/Host(`//; s/`)//' | tr -d '[:space:]')
    if [ -n "$container_url" ]; then
      href_url="http://${container_url}"
    fi
  fi

  added_services+=("$container")

  # Build the service entry
  service_entry="      - $container:\n"
  service_entry+="          icon: ${cn_clean}.png\n"
  service_entry+="          href: $href_url\n"

  # Add the widget if API_KEY is available
  if [ -n "$api_key_var" ]; then
    service_entry+="          widget:\n"
    service_entry+="            type: $cn_clean\n"
    service_entry+="            url: $site_monitor_url\n"
    service_entry+="            key: $api_key_var\n"
  fi

  # Add the siteMonitor field
  service_entry+="          siteMonitor: $site_monitor_url\n"

  # Determine which group the service belongs to
  group_name="other"
  for g in "${media_list[@]}"; do
    if [ "$cn_clean" = "$g" ]; then
      group_name="media"
      break
    fi
  done
  if [ "$group_name" = "other" ]; then
    for g in "${infrastructure_list[@]}"; do
      if [ "$cn_clean" = "$g" ]; then
        group_name="infrastructure"
        break
      fi
    done
  fi
  if [ "$group_name" = "other" ]; then
    for g in "${network_list[@]}"; do
      if [ "$cn_clean" = "$g" ]; then
        group_name="network"
        break
      fi
    done
  fi
  if [ "$group_name" = "other" ]; then
    for g in "${utility_list[@]}"; do
      if [ "$cn_clean" = "$g" ]; then
        group_name="utility"
        break
      fi
    done
  fi

  # Append the service entry to the appropriate group
  case $group_name in
    media)
      media_services+="$service_entry"
      ;;
    infrastructure)
      infrastructure_services+="$service_entry"
      ;;
    network)
      network_services+="$service_entry"
      ;;
    utility)
      utility_services+="$service_entry"
      ;;
    other)
      other_services+="$service_entry"
      ;;
  esac
done

# Write services.yaml file with nested structure
{
  echo -e "$media_services"
  echo -e "$infrastructure_services"
  echo -e "$network_services"
  echo -e "$utility_services"
  echo -e "$other_services"
} > "$SERVICES_CONFIG_FILE"

# Display summary with better separation
echo -e "\n========= SUMMARY ========="

echo -e "\n[ADDED SERVICES]"
for added in "${added_services[@]}"; do
  echo " - $added"
done

echo -e "\n[SKIPPED SERVICES]"
for skipped in "${skipped_services[@]}"; do
  echo " - $skipped"
done

echo -e "\n[MISSING PORT SERVICES (please add PORT manually)]"
for missing in "${missing_port_services[@]}"; do
  echo " - $missing"
done

echo -e "\nServices configuration written to $SERVICES_CONFIG_FILE"
