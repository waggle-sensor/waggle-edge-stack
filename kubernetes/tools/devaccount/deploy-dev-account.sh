#!/bin/bash -e

mkdir -p devaccount-logs

for nodeID in $*; do
    host="nodex-${nodeID}"
    (
    echo "#run ${nodeID} $(date)"
    scp *.yaml deploy-dev-account-payload.sh "${host}":/tmp/
    ssh "${host}" -x "
        cd /tmp; \
        ./deploy-dev-account-payload.sh"
    echo "#exit $?"
    ) &> "devaccount-logs/${nodeID}"
done

true
