#!/bin/bash

# Redirect all output to a log file for debugging
exec > /tmp/post-start.log 2>&1

echo "=== POST-START SCRIPT STARTED $(date) ==="
echo "Script: $0"
echo "PID: $$"
echo "User: $(whoami)"
echo "Working directory: $(pwd)"
echo ""

# Check if config path argument is provided
if [ $# -eq 0 ]; then
    echo "ERROR: Config path argument is required"
    echo "Usage: $0 <config-path>"
    echo "Example: $0 /etc/chirpstack-waggle"
    exit 1
fi
CONFIG_PATH="$1"

# Get ChirpStack version
echo "Getting ChirpStack version..."
chirpstack_version=$(chirpstack --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Detected ChirpStack version: '$chirpstack_version'"

# Run device session migration with retry mechanism, check if version is >= 4.7.0 before running migration
echo "Checking if version >= 4.7.0..."
if [ "$chirpstack_version" != "" ] && [ "$(printf '%s\n' "4.7.0" "$chirpstack_version" | sort -V | head -1)" = "4.7.0" ]; then
    echo "ChirpStack version $chirpstack_version >= 4.7.0, running device sessions migration..."
    
    MAX_RETRIES=5
    RETRY_DELAY=2
    retry_count=0
    success=false
    while [ $retry_count -lt $MAX_RETRIES ] && [ "$success" = false ]; do
        retry_count=$((retry_count + 1))
        
        # Exponential backoff
        if [ $retry_count -gt 1 ]; then
            echo "Retry attempt $retry_count of $MAX_RETRIES (waiting ${RETRY_DELAY}s before retry)..."
            sleep $RETRY_DELAY
            RETRY_DELAY=$((RETRY_DELAY * 2))
        fi
        
        # Run migration
        echo "Executing: chirpstack -c $CONFIG_PATH migrate-device-sessions-to-postgres (attempt $retry_count)"
        if chirpstack -c "$CONFIG_PATH" migrate-device-sessions-to-postgres; then
            echo "Device sessions migration completed successfully on attempt $retry_count"
            success=true
        else
            exit_code=$?
            echo "ERROR: Device sessions migration failed on attempt $retry_count with exit code $exit_code"
            
            if [ $retry_count -eq $MAX_RETRIES ]; then
                echo "ERROR: Device sessions migration failed after $MAX_RETRIES attempts. Giving up."
            fi
        fi
    done
else
    echo "ChirpStack version $chirpstack_version < 4.7.0, skipping device sessions migration"
fi

echo ""
echo "=== POST-START SCRIPT COMPLETED $(date) ==="
echo "Log file location: /tmp/post-start.log"
