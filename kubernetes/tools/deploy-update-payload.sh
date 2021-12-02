#!/bin/bash -e

git clone https://github.com/waggle-sensor/waggle-edge-stack /opt/waggle-edge-stack || true
cd /opt/waggle-edge-stack/kubernetes/

# remove generated kustomization.yaml file
rm kustomization.yaml

# change to latest main branch
git reset --hard
git pull
git checkout main
git pull

# deploy stack
./deploy-stack.sh
