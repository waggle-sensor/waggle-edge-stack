#!/bin/bash -eu

WAGGLE_CONFIG_DIR="${WAGGLE_CONFIG_DIR:-/etc/waggle}"

node_vsn() {
    echo $(awk '{print toupper($0)}' "${WAGGLE_CONFIG_DIR}/vsn")
}

vsn=$(node_vsn)

echo "updating waggle user authorized keys"

if curl --silent --fail "https://auth.sagecontinuum.org/nodes/${vsn}/authorized_keys" > /home/waggle/.ssh/authorized_keys2.update; then
    chown waggle:waggle /home/waggle/.ssh/authorized_keys2.update
    chmod 600 /home/waggle/.ssh/authorized_keys2.update
    mv /home/waggle/.ssh/authorized_keys2.update /home/waggle/.ssh/authorized_keys2
    echo "updated waggle user authorized keys"
else
    echo "failed to update waggle user authorized keys"
fi
