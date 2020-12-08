#!/bin/bash

# delete services
kubectl delete -f node-upload-agent.yaml
kubectl delete -f playback-server
kubectl delete -f rabbitmq-server
kubectl delete -f beehive-upload-server
kubectl delete -f data-sharing-service.yaml

# delete config and secrets
kubectl delete configmap waggle-config
kubectl delete secret waggle-secret
kubectl delete secret rabbitmq-service-account-secret
kubectl delete secret beehive-upload-server-secret
