#!/bin/bash

# Check if domain name is passed as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <domain-name>"
    exit 1
fi

DOMAIN=$1

# Function to check CORS
check_cors() {
    RESPONSE=$(curl -s -I "https://$DOMAIN")
    CORS_HEADER=$(echo "$RESPONSE" | grep -i "access-control-allow-origin")
    
    if [ -z "$CORS_HEADER" ]; then
        echo "No CORS headers found in the response from $DOMAIN."
    else
        echo "CORS headers from $DOMAIN:"
        echo "$CORS_HEADER"
    fi
}

# Call the function to check CORS
check_cors
