#!/bin/bash

# Function to display usage
function display_usage() {
    echo "Usage: "
    echo "./generate-service-yaml.sh -s <service_name> -o <output_directory> [-c <compose_file_path>]"
    echo
    echo "Parameters:"
    echo "  -s <service_name>         The name of the service to be created."
    echo "  -o <output_directory>     The directory where the generated YAML file will be saved."
    echo "  -c <compose_file_path>    The path to the Docker Compose file where the generated service YAML will be added (optional)."
    echo
    echo "Example:"
    echo "./generate-service-yaml.sh -s dozzle -o /path/to/output/directory -c /path/to/docker-compose.yml"
    exit 1
}

# Check if no arguments or --help is passed
if [ $# -eq 0 ] || [[ "$*" == *"--help"* ]]; then
    display_usage
fi

# Parse command line arguments
while getopts ":s:o:c:" opt; do
    case ${opt} in
        s) SERVICE_NAME=${OPTARG} ;;
        o) OUTPUT_DIR=${OPTARG} ;;
        c) COMPOSE_FILE=${OPTARG} ;;
        \?) echo "Invalid option: -${OPTARG}" >&2; display_usage ;;
        :) echo "Option -${OPTARG} requires an argument." >&2; display_usage ;;
    esac
done

# Check if required parameters are provided
if [ -z "$SERVICE_NAME" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Error: Service name and output directory are required."
    display_usage
fi

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Define the template
TEMPLATE=$(cat <<EOF
services:
  ${SERVICE_NAME}:
    container_name: ${SERVICE_NAME}.\${HOST_NAME}
    hostname: ${SERVICE_NAME}.\${HOST_NAME}.local
    image: # Replace with the Docker image name, e.g., amir20/dozzle
    environment:
      TZ: \${TZ}
      PUID: \${PUID}
      PGID: \${PGID}
    networks:
      - mediaserver
    ports:
      - \${SERVICE_PORT}:80  # Replace SERVICE_PORT with the actual port you want to expose. Add SERVICE_PORT to your .env file.
    volumes:
      # Uncomment if needed
      # - /var/run/docker.sock:/var/run/docker.sock
      - \${DOCKERDIR}/${SERVICE_NAME}/config:/config
      - \${DOCKERDIR}/logs/${SERVICE_NAME}:/var/log
    restart: always
    security_opt:
      - no-new-privileges:true
    labels:
      - "traefik.enable=true"
      ## HTTP Routers
      - "traefik.http.routers.${SERVICE_NAME}-rtr.entrypoints=https"
      ## Middlewares
      - "traefik.http.routers.${SERVICE_NAME}-rtr.rule=Host(${SERVICE_NAME}\${HOST_SUFFIX}.\${DOMAINNAME})"
      - "traefik.http.routers.${SERVICE_NAME}-rtr.middlewares=chain-oauth@file"
      ## Docker Network
      - "traefik.docker.network=mediaserver"
      ## HTTP Services
      - "traefik.http.routers.${SERVICE_NAME}-rtr.service=${SERVICE_NAME}-svc"
      - "traefik.http.services.${SERVICE_NAME}-svc.loadbalancer.server.port=80"
      ## Watchtower enabled?
      - "com.centurylinklabs.watchtower.enable=true"
EOF
)

# Save the template to a file
TEMPLATE_FILE_PATH="${OUTPUT_DIR}/${SERVICE_NAME}.yaml"
echo "$TEMPLATE" > "$TEMPLATE_FILE_PATH"
echo "File ${SERVICE_NAME}.yaml created in ${OUTPUT_DIR}"

# Ask if the user wants to add it to a Docker Compose file
if [ -n "$COMPOSE_FILE" ]; then
    read -p "Do you want to add this service to the Docker Compose file (${COMPOSE_FILE})? (yes/no) " ADD_TO_COMPOSE
    if [ "$ADD_TO_COMPOSE" == "yes" ]; then
        echo "$TEMPLATE_FILE_PATH" >> "$COMPOSE_FILE"
        echo "Added ${TEMPLATE_FILE_PATH} to ${COMPOSE_FILE}"
    else
        echo "Did not add ${TEMPLATE_FILE_PATH} to ${COMPOSE_FILE}"
    fi
fi
