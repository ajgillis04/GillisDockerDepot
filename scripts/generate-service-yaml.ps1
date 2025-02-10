<#
.SYNOPSIS
    This script generates a Docker service YAML template.

.DESCRIPTION
    The script accepts a service name and output directory as parameters. It generates a Docker service YAML template with placeholders for environment variables. The user is prompted to add the generated YAML to a specified Docker Compose file if desired.

.PARAMETER ServiceName
    The name of the service to be created.

.PARAMETER OutputDir
    The directory where the generated YAML file will be saved.

.PARAMETER ComposeFilePath
    The path to the Docker Compose file where the generated service YAML will be added (optional).

.EXAMPLE
    ./generate-service-yaml.ps1 -ServiceName "dozzle" -OutputDir "C:\path\to\output\directory" -ComposeFilePath "C:\path\to\docker-compose.yml"

.NOTES
    Author: Andy Gillis
    Date: Jan 28-25
#>

param (
    [string]$ServiceName,
    [string]$OutputDir,
    [string]$ComposeFilePath
)

# Display help if --help is passed
if ($args.Contains('--help')) {
    Write-Host @"
Usage: 
    ./generate-service-yaml.ps1 -ServiceName <service_name> -OutputDir <output_directory> -ComposeFilePath <docker_compose_file_path>

Parameters:
    -ServiceName       The name of the service to be created.
    -OutputDir         The directory where the generated YAML file will be saved.
    -ComposeFilePath   The path to the Docker Compose file where the generated service YAML will be added (optional).

Examples:
    ./generate-service-yaml.ps1 -ServiceName "dozzle" -OutputDir "C:\path\to\output\directory" -ComposeFilePath "C:\path\to\docker-compose.yml"
    ./generate-service-yaml.ps1 -ServiceName "dozzle" -OutputDir ".\temp" -ComposeFilePath ".\docker-compose.yml"

"@
    exit
}

# Check if required parameters are provided
if (-not $ServiceName -or -not $OutputDir) {
    Write-Host "Error: ServiceName and OutputDir parameters are required."
    Write-Host @"
Usage: 
    ./generate-service-yaml.ps1 -ServiceName <service_name> -OutputDir <output_directory> -ComposeFilePath <docker_compose_file_path>

Parameters:
    -ServiceName       The name of the service to be created.
    -OutputDir         The directory where the generated YAML file will be saved.
    -ComposeFilePath   The path to the Docker Compose file where the generated service YAML will be added (optional).

Examples:
    ./generate-service-yaml.ps1 -ServiceName "dozzle" -OutputDir "C:\path\to\output\directory" -ComposeFilePath "C:\path\to\docker-compose.yml"
    ./generate-service-yaml.ps1 -ServiceName "dozzle" -OutputDir ".\temp" -ComposeFilePath ".\docker-compose.yml"

"@
    exit
}

# Resolve the paths to handle both full and relative paths
$resolvedOutputDir = Resolve-Path -Path $OutputDir
$resolvedComposeFilePath = $null
if ($ComposeFilePath) {
    $resolvedComposeFilePath = Resolve-Path -Path $ComposeFilePath -ErrorAction SilentlyContinue
}

if (-Not (Test-Path -Path $resolvedOutputDir)) {
    New-Item -ItemType Directory -Path $resolvedOutputDir -Force
}

# Define the template using here-string
$template = @'
services:
  SERVICE_NAME:
    container_name: SERVICE_NAME.${HOST_NAME}
    hostname: SERVICE_NAME.${HOST_NAME}.local
    image: # Replace with the Docker image name, e.g., amir20/dozzle
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
      DOMAINNAME: ${DOMAINNAME}
    networks:
      - mediaserver
    ports:
      - ${SERVICE_PORT}:80  # Replace SERVICE_PORT with the actual port you want to expose. Add SERVICE_PORT to your .env file.
    volumes:
      # Uncomment if needed
      # - /var/run/docker.sock:/var/run/docker.sock
      - ${DOCKERDIR}/SERVICE_NAME/config:/config
      - ${DOCKERDIR}/logs/SERVICE_NAME:/var/log
    restart: always
    security_opt:
      - no-new-privileges:true
    labels:
      - "traefik.enable=true"
      ## HTTP Routers
      - "traefik.http.routers.SERVICE_NAME-rtr.entrypoints=https"
      ## Middlewares
      - "traefik.http.routers.SERVICE_NAME-rtr.rule=Host(SERVICE_NAME${HOST_SUFFIX}.${DOMAINNAME})"
      - "traefik.http.routers.SERVICE_NAME-rtr.middlewares=chain-oauth@file"
      ## Docker Network
      - "traefik.docker.network=mediaserver"
      ## HTTP Services
      - "traefik.http.routers.SERVICE_NAME-rtr.service=SERVICE_NAME-svc"
      - "traefik.http.services.SERVICE_NAME-svc.loadbalancer.server.port=80"
      ## Watchtower enabled?
      - "com.centurylinklabs.watchtower.enable=true"
'@

# Replace the placeholders with the actual service name
$template = $template -replace 'SERVICE_NAME', $ServiceName

# Save the template to a file
$templateFilePath = "$resolvedOutputDir\$ServiceName.yaml"
$template | Out-File -FilePath $templateFilePath -Encoding utf8
Write-Host "File ${ServiceName}.yaml created in $resolvedOutputDir"

# Ask if the user wants to add it to a Docker Compose file
if ($resolvedComposeFilePath) {
    $addToCompose = Read-Host "Do you want to add this service to the Docker Compose file ($resolvedComposeFilePath)? (yes/no)"
    if ($addToCompose -eq "yes") {
        "`$$ServiceName.yaml" >> $resolvedComposeFilePath
        Write-Host "Added $templateFilePath to $resolvedComposeFilePath"
    } else {
        Write-Host "Did not add $templateFilePath to $resolvedComposeFilePath"
    }
} else {
    Write-Host "Compose file path is not valid or not provided. Skipping addition to Docker Compose file."
}
