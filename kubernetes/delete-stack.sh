#!/bin/bash

cd $(dirname $0)
kubectl delete -k wes-app-meta-cache
kubectl delete -k wes-chirpstack
kubectl delete -k .
