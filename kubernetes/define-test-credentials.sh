#!/bin/bash -e

# defines made up credentials for testing. this includes:
# * Node ID
# * Upload server hostname
# * CA pubkey
# * Node SSH key pair
# * Signed Node SSH cert

tempdir=$(mktemp -d)
cd "$tempdir"
echo "working in $(pwd)"

WAGGLE_NODE_ID="0000000000000001"

# generate node configmap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: waggle-config
data:
  WAGGLE_NODE_ID: "$WAGGLE_NODE_ID"
EOF

# generate test ca key pair
ssh-keygen -C "Beekeeper CA Key" -N "" -f ca

# generate and sign node ssh key
# do we need different access between beekeeper and the upload server??
ssh-keygen -C "Node SSH Key" -N "" -f node-ssh-key
ssh-keygen -s ca \
    -I "Waggle Upload Key" \
    -n "node$WAGGLE_NODE_ID" \
    -V "-5m:+365d" \
    node-ssh-key
(kubectl delete secret waggle-secret || true) &>/dev/null
kubectl create secret generic waggle-secret \
  --from-file=ca.pub=ca.pub \
  --from-file=ssh-key=node-ssh-key \
  --from-file=ssh-key.pub=node-ssh-key.pub \
  --from-file=ssh-key-cert.pub=node-ssh-key-cert.pub

# generate and sign upload server host key
ssh-keygen -C "Upload Server Key" -N "" -f upload-server-host-key
ssh-keygen -s ca \
    -I "Upload Server Key" \
    -n "beehive-upload-server" \
    -V "-5m:+365d" \
    -h \
    upload-server-host-key
(kubectl delete secret beehive-upload-server-secret || true) &>/dev/null
kubectl create secret generic beehive-upload-server-secret \
  --from-file=ca.pub=ca.pub \
  --from-file=ssh-host-key=upload-server-host-key \
  --from-file=ssh-host-key.pub=upload-server-host-key.pub \
  --from-file=ssh-host-key-cert.pub=upload-server-host-key-cert.pub
