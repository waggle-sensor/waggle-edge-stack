#!/bin/bash -e

mkdir -p pvc-logs

for nodeID in $*; do
    host="node-${nodeID}"
    (
    echo "#run ${nodeID} $(date)"
    scp update-pvc-payload.sh "${host}":/tmp/update-pvc-payload.sh
    ssh "${host}" /tmp/update-pvc-payload.sh
    echo "#exit $?"
    ) &> "pvc-logs/${nodeID}"
done

true
