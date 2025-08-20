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

# Check if version is >= 4.7.0 before running migration
echo "Checking if version >= 4.7.0..."
if [ "$chirpstack_version" != "" ] && [ "$(printf '%s\n' "4.7.0" "$chirpstack_version" | sort -V | head -1)" = "4.7.0" ]; then
    echo "ChirpStack version $chirpstack_version >= 4.7.0, running device sessions migration..."
    echo "Executing: chirpstack -c $CONFIG_PATH migrate-device-sessions-to-postgres"
    if chirpstack -c "$CONFIG_PATH" migrate-device-sessions-to-postgres; then
        echo "Device sessions migration completed successfully"
    else
        echo "ERROR: Device sessions migration failed with exit code $?"
    fi
else
    echo "ChirpStack version $chirpstack_version < 4.7.0, skipping device sessions migration"
fi

# import the legacy LoRaWAN devices repository
echo "Importing legacy LoRaWAN devices repository..."
echo "Executing: chirpstack -c $CONFIG_PATH import-legacy-lorawan-devices-repository -d /opt/lorawan-devices"
#TODO: uncomment for production
# if chirpstack -c "$CONFIG_PATH" import-legacy-lorawan-devices-repository -d /opt/lorawan-devices; then
#     echo "Legacy LoRaWAN devices repository import completed successfully"
# else
#     echo "ERROR: Legacy LoRaWAN devices repository import failed with exit code $?"
# fi

echo ""
echo "=== POST-START SCRIPT COMPLETED $(date) ==="
echo "Log file location: /tmp/post-start.log"
