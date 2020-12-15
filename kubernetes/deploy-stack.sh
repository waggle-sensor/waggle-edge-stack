#!/bin/bash -e

create_waggle_config() {
  echo "creating waggle config"
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: waggle-config
data:
  WAGGLE_NODE_ID: "$WAGGLE_NODE_ID"
  WAGGLE_BEEHIVE_HOST: "WAGGLE_BEEHIVE_HOST"
EOF
}

create_waggle_data_config() {
  echo "creating waggle data config"
  (kubectl delete configmap waggle-data-config || true) &>/dev/null
  kubectl create configmap waggle-data-config --from-file=data-config.json=data-config.json
}

export WAGGLE_NODE_ID=${WAGGLE_NODE_ID:-0000000000000001}
echo "WAGGLE_NODE_ID=$WAGGLE_NODE_ID"

export WAGGLE_BEEHIVE_HOST=${WAGGLE_BEEHIVE_HOST:-beehive1.mcs.anl.gov}
echo "WAGGLE_BEEHIVE_HOST=$WAGGLE_BEEHIVE_HOST"

create_waggle_config
create_waggle_data_config

(
echo "generating test ssh credentials"

# ensure temp dir exists and is empty
mkdir -p .tmp
rm -f .tmp/*
cd .tmp

# generate test ca key pair
ssh-keygen -C "Beekeeper CA Key" -N "" -f ca

# generate and sign node ssh key
# do we need different access between beekeeper and the upload server??
ssh-keygen -C "Node SSH Key" -N "" -f node-ssh-key
ssh-keygen \
    -s ca \
    -t rsa-sha2-256 \
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
ssh-keygen \
    -s ca \
    -t rsa-sha2-256 \
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

(kubectl delete secret waggle-shovel-secret || true) &>/dev/null
if ls /etc/waggle/cacert.pem /etc/waggle/cert.pem /etc/waggle/key.pem; then
  echo "adding rabbitmq shovel credentials in /etc/waggle to secret"
  kubectl create secret generic waggle-shovel-secret \
    --from-file=cacert.pem=/etc/waggle/cacert.pem \
    --from-file=cert.pem=/etc/waggle/cert.pem \
    --from-file=key.pem=/etc/waggle/key.pem
else
  echo "rabbitmq shovel credentials not found - will run in local mode only"
fi

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
while ! kubectl exec --stdin service/rabbitmq-server -- rabbitmqctl list_users; do
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

echo "deploying rest of node stack"
kubectl apply -f node-upload-agent.yaml
kubectl apply -f playback-server
kubectl apply -f data-sharing-service.yaml
kubectl apply -f node-exporter.yaml

# upload server deployment - should be moved into a "deploy-beehive" script
echo "deploying upload server"
kubectl apply -f beehive-upload-server

add_user_to_upload_server() {
  username="$1"
  kubectl exec --stdin deployment/beehive-upload-server -- sh -s <<EOF
adduser -D -g "" "$username"
passwd -u "$username"
true
EOF
}

echo "adding user to upload server"
while ! add_user_to_upload_server "node$WAGGLE_NODE_ID"; do
  sleep 3
done
