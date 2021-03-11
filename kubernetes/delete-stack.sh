#!/bin/bash

# delete services
kubectl delete -f wes-playback-server.yaml
kubectl delete -f data-shovel-push.yaml
kubectl delete -f node-upload-agent.yaml
kubectl delete -f data-sharing-service.yaml
kubectl delete -f wes-rabbitmq.yaml
kubectl delete -f node-exporter.yaml

# delete config and secrets
kubectl delete configmap waggle-config
kubectl delete secret waggle-secret
kubectl delete secret wes-rabbitmq-service-account-secret
