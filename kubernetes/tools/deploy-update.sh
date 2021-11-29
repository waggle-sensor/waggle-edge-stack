#!/bin/bash

mkdir -p results

for nodeID in $*; do
    host="node-$nodeID"
    (
        echo "#run ${nodeID} $(date)"
        scp deploy-update-payload.sh "${host}:/tmp/deploy-update-payload.sh" && \
        ssh "${host}" /tmp/deploy-update-payload.sh
        echo "#exit $?"
    ) &> "results/${nodeID}"
done

true
