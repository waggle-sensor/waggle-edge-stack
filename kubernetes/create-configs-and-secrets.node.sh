#!/bin/bash -e

WAGGLE_NODE_ID=$(openssl x509 -in /etc/waggle/cert.pem -text | sed -n -e 's/.*CN.*node-\(.*\),.*/\1/p')
WAGGLE_BEEHIVE_HOST=$(getent hosts beehive | awk '{print $1}')

echo "creating waggle config map"
kubectl create configmap waggle-config \
  --from-literal=WAGGLE_NODE_ID="$WAGGLE_NODE_ID" \
  --from-literal=WAGGLE_BEEHIVE_HOST="$WAGGLE_BEEHIVE_HOST"

echo "creating rabbitmq shovel secret from /etc/waggle"
kubectl create secret generic waggle-shovel-secret \
  --from-file=cacert.pem=/etc/waggle/cacert.pem \
  --from-file=cert.pem=/etc/waggle/cert.pem \
  --from-file=key.pem=/etc/waggle/key.pem
