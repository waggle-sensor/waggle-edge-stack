#!/bin/bash

# deploy quickly using:
# xargs -L1 -P4 ./deploy-update.sh < nodes
#
# where nodes is a list of node IDs like:
# 000048B02D15BC77
# 000048B02D15BDC7
# ...
#
# results are logged under results/nodeID

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
