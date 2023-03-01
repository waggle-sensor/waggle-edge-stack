#!/bin/bash

if ! kubectl get pod | grep -q 'wes-node-influxdb-0.*CrashLoopBackOff'; then
    echo "influxdb doesn't seem to be stuck in crash loop"
    exit 0
fi

# temporarily up memory limit so influxdb can run 
kubectl set resources statefulset/wes-node-influxdb --limits=memory=2Gi
kubectl delete pod wes-node-influxdb-0

# lower influxdb data retention time to reduce memory usage
while ! /opt/waggle-edge-stack/kubernetes/debug/update-influxdb-retention.py 2d; do
    sleep 10
done
