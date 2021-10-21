#!/bin/sh

cd $(dirname $0)

fatal() {
    echo $*
    exit 1
}

getarch() {
    case $(uname -m) in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    * ) return 1 ;;
    esac
}

for node in $(kubectl get node | awk '/ws-nxcore/ {print $1}'); do
    kubectl label nodes "$node" resource.bme280=true || true
    kubectl label nodes "$node" resource.gps=true || true
done
for node in $(kubectl get node | awk '/ws-rpi/ {print $1}'); do
    kubectl label nodes "$node" resource.microphone=true || true
    kubectl label nodes "$node" resource.raingauge=true || true
    kubectl label nodes "$node" resource.bme680=true || true
done

# pull latest compatible version of runplugin
if ! arch=$(getarch); then
    fatal "failed to get arch"
fi

(
    cd /root && \
    wget -N "https://github.com/sagecontinuum/ses/releases/download/0.6.4/runplugin-${arch}" && \
    chmod +x runplugin-*
)

# update / prune kubernetes resources that are part of waggle-edge-stack
kubectl apply -k . #--prune --selector app.kubernetes.io/part-of=waggle-edge-stack
