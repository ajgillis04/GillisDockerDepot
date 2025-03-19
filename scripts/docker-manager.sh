#!/bin/bash
#***********************************************************************************
# Enhanced Script with Pre-checks and Service Status Reporting
# Created: Andy Gillis
# Purpose:  Manage Docker stack/services and report running services/ports
# Commands: ./docker-manager.sh [start|stop|restart|start-service|stop-service <service_name>|remove-service <service_name>|--help]
#**********************************************************************************
# Load environment variables from .env file
if [ -f ../.env ]; then
    source ../.env
else
    echo ".env file not found! Please create and configure the .env file."
    exit 1
fi

# Function to display help message
show_help() {
  echo "Usage: $0 [start|stop|restart|start-service|stop-service <service_name>|remove-service <service_name>|--help]"
  echo ""
  echo "Commands:"
  echo "  start              Starts the Docker stack"
  echo "  stop               Stops the Docker stack without removing containers"
  echo "  restart            Restarts the Docker stack"
  echo "  start-service      Starts an individual service"
  echo "  stop-service       Stops an individual service"
  echo "  remove-service     Stops and removes an individual service"
  echo "  --help             Displays this help message"
}

# Function to check if a command is installed
check_command() {
  if ! command -v $1 &> /dev/null; then
    echo "Error: $1 is not installed."
    echo "To install $1:"
    case "$1" in
      jq)
        echo "For Ubuntu: sudo apt-get update && sudo apt-get install jq -y"
        echo "For Fedora: sudo dnf install jq -y"
        ;;
    esac
    exit 1
  fi
}

# Pre-checks
check_command jq

echo "Environment variables loaded."

# Check hostname
HOSTNAME=$(hostname)

# Determine the server name based on hostname using environment variables
case "$HOSTNAME" in
  "$SERVER1_NAME")
    export SERVER_NAME="server1"
    ;;
  "$SERVER2_NAME")
    export SERVER_NAME="server2"
    ;;
  "$SERVER3_NAME")
    export SERVER_NAME="server3"
    ;;
  "$SERVER4_NAME")
    export SERVER_NAME="server4"
    ;;
  *)
    echo "Unknown hostname: $HOSTNAME"
    exit 1
    ;;
esac

# Check if the docker-compose file exists
DOCKER_COMPOSE_FILE="${BASE_DIR}/docker-compose-${SERVER_NAME}.yaml"
if [ ! -f $DOCKER_COMPOSE_FILE ]; then
  echo "$DOCKER_COMPOSE_FILE not found! Please ensure the docker-compose file exists."
  exit 1
fi

echo "docker-compose file found."

# Function to start the stack
start_stack() {
  echo "Starting the Docker stack..."
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE up --detach
  #docker-compose --verbose -p mediaserver -f $DOCKER_COMPOSE_FILE up --detach
}

# Function to stop the stack without removing containers
stop_stack() {
  echo "Stopping the Docker stack..."
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE stop
}

# Function to restart the stack
restart_stack() {
  echo "Restarting the Docker stack..."
  stop_stack
  start_stack
}

# Function to start an individual service
start_service() {
  local service_name=$1
  if [ -z $service_name ]; then
    echo "Service name not provided!"
    exit 1
  fi
  echo "Starting service: $service_name..."
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE up -d $service_name                  
}

# Function to stop an individual service
stop_service() {
  local service_name=$1
  if [ -z $service_name ]; then
    echo "Service name not provided!"
    exit 1
  fi
  echo "Stopping service: $service_name..."
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE stop $service_name
}

# Function to remove an individual service
remove_service() {
  local service_name=$1
  if [ -z $service_name ]; then
    echo "Service name not provided!"
    exit 1
  fi
  echo "Stopping and removing service: $service_name..."
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE stop $service_name
  docker-compose -p mediaserver -f $DOCKER_COMPOSE_FILE rm -f $service_name
}

# Main script logic
command=$1
service_name=$2

if [ -z "$command" ]; then
  show_help
  exit 0
fi

case $command in
  start)
    start_stack
    ;;
  stop)
    stop_stack
    ;;
  restart)
    restart_stack
    ;;
  start-service)
    start_service $service_name
    ;;
  stop-service)
    stop_service $service_name
    ;;
  remove-service)
    remove_service $service_name
    ;;
  --help)
    show_help
    ;;
  *)
    echo "Invalid command!"
    show_help
    exit 1
    ;;
esac

# Only show running services if the stop command and help command are not used
if [ "$command" != "stop" ] && [ "$command" != "--help" ]; then
    # Function to output running services and their external IP/Ports
    show_running_services() {
        echo
        echo -e "Service\t\t\tInternal IP\t\t\tExternal IP\t\t\tExternal Port\t\t"
        
        # Source the .env file to get the server IP
        if [ -f ../.env ]; then
            source ../.env
            SERVER_IP=${SERVER_IP}
        else
            echo ".env file not found! Please create and configure the .env file."
            exit 1
        fi

        # Create a temporary file to track running services
        running_services=$(mktemp)

        # List the running containers and their status
        docker ps --format "{{.Names}} {{.Ports}}" | while IFS= read -r line; do
            name=$(echo "$line" | awk '{print $1}')
            internal_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
            ports=$(echo "$line" | awk '{print $2}')
            status="Running"

            if [ -n "$ports" ]; then
                echo "$ports" | sed "s/0.0.0.0/$SERVER_IP/g" | grep -oP "$SERVER_IP:\d+" | while IFS= read -r port; do
                    external_ip="${port%:*}"
                    external_port="${port##*:}"
                    printf "%-23s %-31s %-31s %-21s\n" "$name" "$internal_ip" "$external_ip" "$external_port"
                    echo "$name" >> "$running_services"
                done
            else
                status="No mapped ports"
                printf "%-23s %-31s %-23s %-31s %-20s\n" "$name" "$internal_ip" "N/A" "N/A" "$status"
                echo "$name" >> "$running_services"
            fi
        done

        # Check for non-running services, avoiding duplicates
        docker-compose -p mediaserver -f "$DOCKER_COMPOSE_FILE" ps --services | while IFS= read -r service; do
            if ! grep -q "$service" "$running_services"; then
                printf "%-23s %-31s %-23s %-31s %-20s\n" "$service" "N/A" "N/A" "N/A" "Not running"
            fi
        done

        # Clean up the temporary file
        rm "$running_services"
    }

    # Show running services
    show_running_services
fi
