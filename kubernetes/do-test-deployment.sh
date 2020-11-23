#!/bin/bash

WAGGLE_NODE_ID="0000000000000001"

# generate keys. remember, we will only have presigned keys and only ca.pub!
ssh-keygen -C "Waggle CA Key" -N '' -f ca
ssh-keygen -C "Waggle SSH Key" -N '' -f ssh-key

ssh-keygen -s ca \
    -I "Waggle Upload Key" \
    -n "node$WAGGLE_NODE_ID" \
    -V "-5m:+7d" \
    ssh-key

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: waggle-secret
data:
  ca.pub: $(base64 -w 0 ca.pub)
  ssh-key: $(base64 -w 0 ssh-key)
  ssh-key.pub: $(base64 -w 0 ssh-key.pub)
  ssh-key-cert.pub: $(base64 -w 0 ssh-key-cert.pub)
EOF

# clean up test key files. (they are copied into the secret)
rm ca ca.pub ssh-key ssh-key.pub ssh-key-cert.pub

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: waggle-config
data:
  WAGGLE_NODE_ID: "$WAGGLE_NODE_ID"
  WAGGLE_UPLOAD_HOST: "upload-server"
EOF

kubectl apply -f rabbitmq-server
kubectl apply -f node-upload-agent.yaml
kubectl apply -f plugin-test.yaml
