#!/bin/bash

# -------------------------------------------------------------------------
# Script Name: CheckAndCleanFile.sh
# Author: Your Name
# Date: January 26, 2025
# Description: This script checks a file for null bytes and trailing 
#              whitespace, then cleans the file while creating a backup.
# 
# Usage:
#   1. To run the script with a file path argument:
#      ./CheckAndCleanFile.sh path/to/your/file
#
#   2. To run the script without a file path argument:
#      ./CheckAndCleanFile.sh
# -------------------------------------------------------------------------

# Function to check and clean file
check_and_clean_file() {
    local filePath=$1

    # Read the content of the file
    content=$(<"$filePath")

    # Create a backup of the original file
    backupFilePath="${filePath}.bak"
    cp "$filePath" "$backupFilePath"
    echo "Backup created at: $backupFilePath"

    # Check for null bytes
    if grep -qP '\x00' "$filePath"; then
        echo "Null bytes found in the file."
    else
        echo "No null bytes found in the file."
    fi

    # Split the content into lines
    IFS=$'\n' read -d '' -r -a lines <<< "$content"

    # Check for trailing whitespace and display the lines with issues
    for line in "${lines[@]}"; do
        if [[ $line =~ [[:space:]]+$ ]]; then
            echo "Trailing whitespace found in line: '${line%[[:space:]]*}'"
        fi
    done

    # Remove null bytes and trailing whitespace from each line
    cleanedLines=()
    for line in "${lines[@]}"; do
        cleanedLines+=("${line%[[:space:]]*//[\x00]/}")
    done

    # Combine the cleaned lines back into a single string
    cleanedContent=$(printf "%s\n" "${cleanedLines[@]}")

    # Write the cleaned content back to the file
    echo -n "$cleanedContent" > "$filePath"

    echo "The file has been cleaned and saved."
    echo "Original file backed up at: $backupFilePath"
}

# Check if file path is provided as an argument
if [ -z "$1" ]; then
    read -p "Enter the path to the file you want to check and clean: " filePath
else
    filePath="$1"
fi

check_and_clean_file "$filePath"
