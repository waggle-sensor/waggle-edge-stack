#!/bin/bash

set -eu

cd /opt/waggle-edge-stack/kubernetes

echo "removing rabbitmq"
kubectl delete -f wes-rabbitmq.yaml

echo "removing rabbitmq pvc"
kubectl delete pvc data-wes-rabbitmq-0

echo "removing data sharing service"
kubectl delete -f wes-data-sharing-service.yaml

echo "waiting for 60s to allow kubernetes to clean up..."
sleep 60

echo "redeploying wes"
./update-stack.sh
