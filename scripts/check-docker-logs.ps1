<#
.SYNOPSIS
    Docker Logs Checker Script

.DESCRIPTION
    This script checks Docker container logs for specific keywords and records unique error messages, filtering duplicates and displaying only the latest message for each issue.

.PARAMETER ContainerName
    (Optional) The name of the container to filter the logs by.

.NOTES
    Author: Your Name
    Date Written: 2025-01-26
    Usage: Run this script to check Docker container logs and filter out specific keywords. It creates a log file with the results.
#>

param (
    [string]$ContainerName = $null
)

# Define the log file path
$logFilePath = "Logs\docker_logs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create or clear the log file
New-Item -Path $logFilePath -ItemType File -Force | Out-Null

# Function to write to both console and log file
function Write-Log {
    param (
        [string]$message
    )
    $message | Tee-Object -FilePath $logFilePath -Append
}

# Add a header to the log file
$header = @"
Script Name: Docker Logs Checker
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Usage: This script checks Docker container logs for specific keywords and records unique error messages, filtering duplicates and displaying only the latest message for each issue.
------------------------------------------------------------
"@
Write-Log $header

# Get the list of containers (filtered by name if provided)
if ($ContainerName) {
    $containers = docker ps -q -f "name=$ContainerName"
    if (-not $containers) {
        Write-Log "No container found with the name '$ContainerName'."
        exit
    }
} else {
    $containers = docker ps -q
}

# Keywords to search for
$keywords = @('error', 'warn', 'failed', 'critical', 'exception', 'traceback', 'timeout', 'unavailable', 'fatal', 'could not resolve host', 'unknown user/group', 'no available indexers', 'skipping "/var/log/acpid.log"', 'connection reset by peer')

# Initialize a hash table to store unique error messages
$uniqueMessages = @{}

# Function to extract core message by removing timestamp and other varying parts
function Get-CoreMessage {
    param (
        [string]$logMessage
    )
    # Remove timestamp and other non-static parts
    $coreMessage = $logMessage -replace 'time=".*?" ', ''         # Remove timestamps
    $coreMessage = $coreMessage -replace '

\[.*?\]

', ''            # Remove content within square brackets
    $coreMessage = $coreMessage -replace '\d{2,}:\d{2}:\d{2}.\d+', '' # Remove specific time formats like HH:MM:SS.mmm
    $coreMessage = $coreMessage -replace '\d{4}-\d{2}-\d{2}', ''  # Remove specific date formats like YYYY-MM-DD
    return $coreMessage.Trim()                                    # Return trimmed core message
}

# Check logs for each container and search for keywords
foreach ($container in $containers) {
    $containerName = docker inspect --format '{{.Name}}' $container | ForEach-Object { $_ -replace "/", "" }
    Write-Log "Container: $containerName ($container)"
    
    $hasIssues = $false

    foreach ($keyword in $keywords) {
        $logs = docker logs $container 2>&1 | Select-String -Pattern $keyword -CaseSensitive:$false
        foreach ($log in $logs) {
            $coreMessage = Get-CoreMessage -logMessage $log.ToString()
            # Filter out specific log messages and store the latest message
            if ($coreMessage -notmatch 'Failed=0' -and $coreMessage -notmatch 'Migrating data source=.*' -and $coreMessage -notmatch 'Logging to .*/mariadb-error.log.*' -and $coreMessage -notmatch 'PHP_ERROR_LOG.*') {
                $uniqueMessages[$coreMessage] = $log.ToString()
                $hasIssues = $true
            }
        }
    }
    
    if ($hasIssues) {
        Write-Log "Problems found in container: $containerName"
        foreach ($coreMessage in $uniqueMessages.Keys) {
            Write-Log $uniqueMessages[$coreMessage]
        }
    } else {
        Write-Log "No issues found."
    }
    
    Write-Log "--------------------------"
    Write-Log ""  # Add a blank line for readability
    Write-Log ""  # Add another blank line for readability

    # Reset the hash table for the next container
    $uniqueMessages.Clear()
}

Write-Log "Log file created at: $logFilePath"
