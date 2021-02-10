#!/bin/bash

# delete services
kubectl delete -f playback-server.yaml
kubectl delete -f data-shovel-push.yaml
kubectl delete -f node-upload-agent.yaml
kubectl delete -f data-sharing-service.yaml
kubectl delete -f rabbitmq.yaml
kubectl delete -f node-exporter.yaml
kubectl delete -f beehive-upload-server

# delete config and secrets
kubectl delete configmap waggle-config
kubectl delete secret waggle-secret
kubectl delete secret rabbitmq-service-account-secret
kubectl delete secret beehive-upload-server-secret
