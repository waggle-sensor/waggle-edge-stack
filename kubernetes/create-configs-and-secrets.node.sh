#!/bin/bash -e

WAGGLE_NODE_ID=$(openssl x509 -in /etc/waggle/cert.pem -text | sed -n -e 's/.*CN.*node-\(.*\),.*/\1/p')
WAGGLE_BEEHIVE_HOST=$(getent hosts beehive | awk '{print $1}')

echo "creating configmap waggle-config"
kubectl create configmap waggle-config --dry-run=client -o yaml \
  --from-literal=WAGGLE_NODE_ID="$WAGGLE_NODE_ID" \
  --from-literal=WAGGLE_BEEHIVE_HOST="$WAGGLE_BEEHIVE_HOST" | kubectl apply -f -

echo "adding rabbitmq shovel credentials in /etc/waggle to secret"
kubectl create secret generic waggle-shovel-secret --dry-run=client -o yaml \
  --from-file=cacert.pem=/etc/waggle/cacert.pem \
  --from-file=cert.pem=/etc/waggle/cert.pem \
  --from-file=key.pem=/etc/waggle/key.pem | kubectl apply -f -
