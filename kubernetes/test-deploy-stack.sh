#!/bin/bash -e

# this is intended to help test wes in a docker desktop environment

export WAGGLE_CONFIG_DIR=$PWD/waggle
export WAGGLE_BIN_DIR=$PWD/root

mkdir -p ${WAGGLE_CONFIG_DIR}
echo 0000000000000001 > "${WAGGLE_CONFIG_DIR}/node-id"
echo TEST > "${WAGGLE_CONFIG_DIR}/vsn"

(
kubectl label node docker-desktop --overwrite node-role.kubernetes.io/master="true" || true

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: waggle-config
data:
  WAGGLE_BEEHIVE_RABBITMQ_HOST: some.rabbitmq.host
  WAGGLE_BEEHIVE_RABBITMQ_PORT: "49191"
  WAGGLE_BEEHIVE_UPLOAD_HOST: some.upload.host
  WAGGLE_BEEHIVE_UPLOAD_PORT: "49192"
EOF
) &> /dev/null

./deploy-stack.sh
