#!/bin/bash

# Get ChirpStack version
chirpstack_version=$(chirpstack --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# Check if version is >= 4.7.0 before running migration
if [ "$chirpstack_version" != "" ] && [ "$(printf '%s\n' "4.7.0" "$chirpstack_version" | sort -V | head -1)" = "4.7.0" ]; then
    echo "[POST-START] ChirpStack version $chirpstack_version >= 4.7.0, running device sessions migration..."
    chirpstack -c /etc/chirpstack-waggle migrate-device-sessions-to-postgres
else
    echo "[POST-START] ChirpStack version $chirpstack_version < 4.7.0, skipping device sessions migration"
fi

# Always import the legacy LoRaWAN devices repository
echo "[POST-START] Importing legacy LoRaWAN devices repository..."
#TODO: uncomment for production
# chirpstack -c /etc/chirpstack-waggle import-legacy-lorawan-devices-repository -d /opt/lorawan-devices
