# -------------------------------------------------------------------------
# Script Name: CheckAndCleanFile.ps1
# Author: Your Name
# Date: January 26, 2025
# Description: This script checks a file for null bytes and trailing 
#              whitespace, then cleans the file while creating a backup.
# 
# Usage:
#   1. To run the script with a file path argument:
#      .\CheckAndCleanFile.ps1 -filePath "path\to\your\file"
#
#   2. To run the script without a file path argument:
#      .\CheckAndCleanFile.ps1
# -------------------------------------------------------------------------

param(
    [string]$filePath
)

# If the file path is not provided as an argument, prompt the user to input it
if (-not $filePath) {
    $filePath = Read-Host "Enter the path to the file you want to check and clean"
}

# Read the content of the file
$content = Get-Content $filePath -Raw

# Create a backup of the original file
$backupFilePath = "$filePath.bak"
Copy-Item $filePath -Destination $backupFilePath
Write-Host "Backup created at: $backupFilePath"

# Check for null bytes
if ($content -match "\x00") {
    Write-Host "Null bytes found in the file."
} else {
    Write-Host "No null bytes found in the file."
}

# Split the content into lines
$lines = $content -split "`n"

# Check for trailing whitespace and display the lines with issues
foreach ($line in $lines) {
    if ($line -match "\s+$") {
        Write-Host "Trailing whitespace found in line: '$line'"
    }
}

# Remove null bytes and trailing whitespace from each line
$cleanedLines = $lines | ForEach-Object { $_.TrimEnd().Replace("`0", "") }

# Combine the cleaned lines back into a single string
$cleanedContent = $cleanedLines -join "`n"

# Write the cleaned content back to the file
Set-Content $filePath -Value $cleanedContent

Write-Host "The file has been cleaned and saved."
Write-Host "Original file backed up at: $backupFilePath"
