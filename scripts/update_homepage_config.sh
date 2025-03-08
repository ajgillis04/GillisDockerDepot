#!/bin/bash

# Load environment variables from .env file
set -a
source .env
set +a

SERVICES_CONFIG_FILE="${DOCKERDIR}/homepage/config/services.yaml"
WIDGETS_CONFIG_FILE="${DOCKERDIR}/homepage/config/widgets.yaml"
LABEL="traefik.http.routers.homepage-rtr.rule"
WARNING_MESSAGE="Warning: Only running containers with the Traefik label will be added."

echo $WARNING_MESSAGE

NOT_ADDED=()

declare -A groups
groups=(
    [Media]="Sonarr.GillisNAS Radarr.GillisNAS Bazarr.GillisNAS Lidarr.GillisNAS Overseerr.GillisNAS Tautulli.GillisNAS Plex.GillisNAS Tdarr.GillisNAS Sabnzbd.GillisNAS Prowlarr.GillisNAS"
    [Infrastructure]="Traefik.GillisNAS Php-Apache-Gillisonline.GillisNAS Php-Apache-Awl.GillisNAS Portainer.GillisNAS Guacamole.GillisNAS"
    [Network]="Pihole.GillisNAS"
    [Utility]="Dozzle.GillisNAS Vaultwarden.GillisNAS"
    [Other]="Chowdown.GillisNAS Transmission-Openvpn.GillisNAS Nextcloud.GillisNAS"
)

echo "---" > $SERVICES_CONFIG_FILE

for group in "${!groups[@]}"; do
    echo "- $group:" >> $SERVICES_CONFIG_FILE
    for container_name in ${groups[$group]}; do
        if docker inspect $container_name | grep -q "$LABEL"; then
            container_url=$(docker inspect --format='{{(index (index .Config.Labels "'"$LABEL"'") 0)}}' $container_name)
            container_url=$(echo $container_url | sed "s/Host('//; s/')//")
            echo "    - name: \"$container_name\"" >> $SERVICES_CONFIG_FILE
            echo "      href: \"http://$container_url\"" >> $SERVICES_CONFIG_FILE
            echo "      icon: \"/path/to/icon\"" >> $SERVICES_CONFIG_FILE
            echo "      description: \"Description for $container_name\"" >> $SERVICES_CONFIG_FILE
        else
            NOT_ADDED+=($container_name)
        fi
    done
done

echo "Containers added to $SERVICES_CONFIG_FILE"

if [ ${#NOT_ADDED[@]} -ne 0 ]; then
    echo "These containers were not added because they do not have the required Traefik label:"
    for container in "${NOT_ADDED[@]}"; do
        echo "- $container"
    done
fi

# Add Google search widget to widgets.yaml
echo "- name: \"Google Search\"" > $WIDGETS_CONFIG_FILE
echo "  widget: html" >> $WIDGETS_CONFIG_FILE
echo "  refresh_interval: 60000" >> $WIDGETS_CONFIG_FILE
echo "  settings:" >> $WIDGETS_CONFIG_FILE
echo "    html: |" >> $WIDGETS_CONFIG_FILE
echo "      <div style=\"text-align: center;\">" >> $WIDGETS_CONFIG_FILE
echo "        <form action=\"https://www.google.com/search\" method=\"get\">" >> $WIDGETS_CONFIG_FILE
echo "          <input type=\"text\" name=\"q\" placeholder=\"Search Google\" style=\"width: 300px; padding: 5px;\" />" >> $WIDGETS_CONFIG_FILE
echo "          <input type=\"submit\" value=\"Search\" style=\"padding: 5px 10px;\" />" >> $WIDGETS_CONFIG_FILE
echo "        </form>" >> $WIDGETS_CONFIG_FILE
echo "      </div>" >> $WIDGETS_CONFIG_FILE

echo "Google search widget added to $WIDGETS_CONFIG_FILE"
