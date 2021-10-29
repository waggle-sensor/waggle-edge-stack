#!/bin/bash -e
git clone https://github.com/waggle-sensor/waggle-edge-stack /opt/waggle-edge-stack || true
cd /opt/waggle-edge-stack/kubernetes/

# remove generated kustomization.yaml file
rm kustomization.yaml

# change to latest main branch
git pull
git checkout main
git pull

# attempt to deploy stack. this should work in the steady state.
if ! ./deploy-stack.sh; then
    # hack for now to wipe and retry on changes to immutable things like service labels
    kubectl delete -k .
    ./deploy-stack.sh
fi

# restart plugins (hack until we understand occasional problem in some cases where plugin stops sending data)
kubectl get deployment -o name | grep -E 'iio|raingauge|sampler|test-pipeline|objectcounter' | xargs -L1 kubectl rollout restart
