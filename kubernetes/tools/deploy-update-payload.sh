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

# # restart plugins (hack until we understand occasional problem in some cases where plugin stops sending data)
# kubectl get deployment -o name | grep -E 'iio|raingauge|sampler|test-pipeline|objectcounter|cloudcover|yamnet' | xargs -L1 kubectl rollout restart

# # manually deploy hses stuff, if it exists
# if test -e /root/ses/plugins; then
#     for f in /root/ses/plugins/*; do
#         $f
#     done
# fi

# cleanup
rm /root/runplugin-arm64 || true
rm /root/runplugin-amd64 || true
rm -rf /root/waggle-edge-stack || true
