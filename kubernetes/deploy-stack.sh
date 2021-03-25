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
  WAGGLE_BEEHIVE_HOST: "$WAGGLE_BEEHIVE_HOST"
  WAGGLE_BEEHIVE_RABBITMQ_HOST: "$WAGGLE_BEEHIVE_RABBITMQ_HOST"
  WAGGLE_BEEHIVE_RABBITMQ_PORT: "$WAGGLE_BEEHIVE_RABBITMQ_PORT"
  WAGGLE_BEEHIVE_UPLOAD_HOST: "$WAGGLE_BEEHIVE_UPLOAD_HOST"
  WAGGLE_BEEHIVE_UPLOAD_PORT: "$WAGGLE_BEEHIVE_UPLOAD_PORT"
EOF
}

create_waggle_data_config() {
  echo "creating waggle data config"
  (kubectl delete configmap waggle-data-config || true) &>/dev/null
  kubectl create configmap waggle-data-config --from-file=data-config.json=data-config.json
}

# TODO clean up defining this initial config

export WAGGLE_NODE_ID=${WAGGLE_NODE_ID:-0000000000000001}
echo "WAGGLE_NODE_ID=$WAGGLE_NODE_ID"

export WAGGLE_BEEHIVE_HOST=${WAGGLE_BEEHIVE_HOST:-beehive1.mcs.anl.gov}
echo "WAGGLE_BEEHIVE_HOST=$WAGGLE_BEEHIVE_HOST"

# TODO clean this up! for now, we just assume that "beehive" and rabbitmq are on the same host
export WAGGLE_BEEHIVE_RABBITMQ_HOST=${WAGGLE_BEEHIVE_RABBITMQ_HOST:-$WAGGLE_BEEHIVE_HOST}
export WAGGLE_BEEHIVE_RABBITMQ_PORT=${WAGGLE_BEEHIVE_RABBITMQ_PORT:-15671}
echo "WAGGLE_BEEHIVE_RABBITMQ $WAGGLE_BEEHIVE_RABBITMQ_HOST:$WAGGLE_BEEHIVE_RABBITMQ_PORT"

export WAGGLE_BEEHIVE_UPLOAD_HOST=${WAGGLE_BEEHIVE_UPLOAD_HOST:-$WAGGLE_BEEHIVE_HOST}
export WAGGLE_BEEHIVE_UPLOAD_PORT=${WAGGLE_BEEHIVE_UPLOAD_PORT:-20022}
echo "WAGGLE_BEEHIVE_UPLOAD $WAGGLE_BEEHIVE_UPLOAD_HOST:$WAGGLE_BEEHIVE_UPLOAD_PORT"

create_waggle_config
create_waggle_data_config

(kubectl delete secret waggle-shovel-secret || true) &>/dev/null
if ls /etc/waggle/cacert.pem /etc/waggle/cert.pem /etc/waggle/key.pem; then
  echo "adding rabbitmq shovel credentials in /etc/waggle to secret"
  kubectl create secret generic waggle-shovel-secret \
    --from-file=cacert.pem=/etc/waggle/cacert.pem \
    --from-file=cert.pem=/etc/waggle/cert.pem \
    --from-file=key.pem=/etc/waggle/key.pem
else
  echo "warning: rabbitmq shovel credentials not found! rabbitmq shovel will fail!"
fi

echo "creating rabbitmq server"
kubectl apply -f wes-rabbitmq.yaml

echo "generating rabbitmq service account credentials"
./update-rabbitmq-auth.sh wes-rabbitmq-service-account-secret service '.*' '.*' '.*'
./update-rabbitmq-auth.sh wes-rabbitmq-shovel-account-secret shovel '^$' '^$' '^to-beehive|to-beekeeper$'

(kubectl delete secret waggle-ssh-key-secret || true) &>/dev/null
if ls /etc/waggle/ssh-key /etc/waggle/ssh-key.pub /etc/waggle/ssh-key-cert.pub; then
  echo "adding ssh keys /etc/waggle to secret"
  kubectl create secret generic waggle-ssh-key-secret \
    --from-file=ca.pub=/etc/waggle/ca.pub \
    --from-file=ssh-key=/etc/waggle/ssh-key \
    --from-file=ssh-key.pub=/etc/waggle/ssh-key.pub \
    --from-file=ssh-key-cert.pub=/etc/waggle/ssh-key-cert.pub
else
  echo "warning: ssh keys not found! upload agent will fail."
fi

echo "deploying rest of node stack"
kubectl apply -f node-upload-agent.yaml
kubectl apply -f wes-audio-server.yaml
kubectl apply -f wes-playback-server.yaml
kubectl apply -f data-sharing-service.yaml
kubectl apply -f node-exporter.yaml
kubectl apply -f wes-metrics-agent.yaml

echo "enabling data shovel"
./shovelctl.sh enable
