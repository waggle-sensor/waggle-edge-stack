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
  WAGGLE_UPLOAD_HOST: "beehive-upload-server"
EOF

# TODO split ca.pub into its own thing and then just use generic signed ssh key resource?

# generate test ca key pair
ssh-keygen -C "Beekeeper CA Key" -N "" -f ca

# generate and sign node ssh key
# do we need different access between beekeeper and the upload server??
ssh-keygen -C "Node SSH Key" -N "" -f node-ssh-key

ssh-keygen -s ca \
    -I "Waggle Upload Key" \
    -n "node$WAGGLE_NODE_ID" \
    -V "-5m:+7d" \
    node-ssh-key

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: waggle-secret
data:
  ca.pub: $(base64 -w 0 ca.pub)
  ssh-key: $(base64 -w 0 node-ssh-key)
  ssh-key.pub: $(base64 -w 0 node-ssh-key.pub)
  ssh-key-cert.pub: $(base64 -w 0 node-ssh-key-cert.pub)
EOF

# generate and sign
ssh-keygen -C "Upload Server Key" -N "" -f upload-server-host-key

ssh-keygen -s ca \
    -I "Upload Server Key" \
    -n "upload-server" \
    -V "-5m:+7d" \
    -h \
    upload-server-host-key

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: beehive-upload-server-secret
data:
  ca.pub: $(base64 -w 0 ca.pub)
  upload-server-key: $(base64 -w 0 upload-server-host-key)
  upload-server-key.pub: $(base64 -w 0 upload-server-host-key.pub)
  upload-server-key-cert.pub: $(base64 -w 0 upload-server-host-key-cert.pub)
EOF
