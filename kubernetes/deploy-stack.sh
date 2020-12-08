#!/bin/bash -e

# defines made up credentials for testing. this includes:
# * Node ID
# * Upload server hostname
# * CA pubkey
# * Node SSH key pair
# * Signed Node SSH cert

export WAGGLE_NODE_ID=${WAGGLE_NODE_ID:-0000000000000001}
echo "WAGGLE_NODE_ID: $WAGGLE_NODE_ID"

export WAGGLE_BEEHIVE_HOST=${WAGGLE_BEEHIVE_HOST:-beehive1.mcs.anl.gov}
echo "WAGGLE_BEEHIVE_HOST: $WAGGLE_BEEHIVE_HOST"

(
echo "generating test ssh credentials"
tempdir=$(mktemp -d)
cd "$tempdir"
echo "working in $(pwd)"

# generate node configmap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: waggle-config
data:
  WAGGLE_NODE_ID: "$WAGGLE_NODE_ID"
  WAGGLE_BEEHIVE_HOST: "WAGGLE_BEEHIVE_HOST"
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
)

echo "creating rabbitmq server"
kubectl apply -f rabbitmq-server

echo "generating rabbitmq service account credentials"
username=service
password=$(openssl rand -hex 12)

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-service-account-secret
type: Opaque
stringData:
    USERNAME: "$username"
    PASSWORD: "$password"
EOF

# TODO this may not be secure over the network. check this later.
echo "updating rabbitmq service account"
while ! kubectl exec --stdin service/rabbitmq-server -- true; do
  echo "waiting for rabbitmq server"
  sleep 3
done

kubectl exec --stdin service/rabbitmq-server -- sh -s <<EOF
while ! rabbitmqctl -q authenticate_user "$username" "$password"; do
  echo "refreshing credentials for \"$username\""
  rabbitmqctl -q add_user "$username" "$password" || \
  rabbitmqctl -q change_password "$username" "$password"
done
EOF

# setup shovel using credentials.
echo "enabling shovels for $WAGGLE_NODE_ID to $WAGGLE_BEEHIVE_HOST"
while ! WAGGLE_NODE_ID="$WAGGLE_NODE_ID" WAGGLE_BEEHIVE_HOST="$WAGGLE_BEEHIVE_HOST" NODE_RABBITMQ_USERNAME="$username" NODE_RABBITMQ_PASSWORD="$password" python3 shovelctl.py enable; do
  echo "failed to update shovel"
  sleep 3
done
