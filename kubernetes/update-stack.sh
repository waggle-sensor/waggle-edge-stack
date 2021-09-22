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

# deploy stack
# TODO clean up bits with different version
kubectl apply -k .

# pull latest compatible version of runplugin
if ! arch=$(getarch); then
    fatal "failed to get arch"
fi

(
    cd /root && \
    wget -N "https://github.com/sagecontinuum/ses/releases/download/0.6.3/runplugin-${arch}" && \
    chmod +x runplugin-*
)
