#!/bin/bash

mkdir -p update-logs
mkdir -p update-fail

for nodeID in $*; do
    # clear old fail status
    rm -f "update-fail/${nodeID}" > /dev/null

    if ! ssh "node-$nodeID" true &> /dev/null; then
        echo "${nodeID} is down"
        echo "${nodeID}" > "update-fail/${nodeID}"
        continue
    fi

    if ! ssh "node-$nodeID" bash -s < deploy-update-payload.sh &> "update-logs/$nodeID"; then
        echo "${nodeID} deploy failed"
        echo "${nodeID}" > "update-fail/${nodeID}"
    fi
done

true
