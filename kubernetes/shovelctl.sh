#!/bin/bash -e

rmqctl() {
  kubectl exec svc/wes-rabbitmq -- rabbitmqctl -q "$@"
}

enable_shovels() {
    nodeID=$(kubectl get cm waggle-config --template={{.data.WAGGLE_NODE_ID}})
    beehive_host=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_HOST}})
    beehive_port=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_PORT}})
    username=$(kubectl get secret wes-rabbitmq-shovel-account-secret --template={{.data.username}} | base64 -d)
    password=$(kubectl get secret wes-rabbitmq-shovel-account-secret --template={{.data.password}} | base64 -d)

    while ! rmqctl set_parameter shovel push-messages "{
  \"src-uri\": \"amqp://${username}:${password}@wes-rabbitmq\",
  \"src-queue\": \"to-beehive\",
  \"dest-uri\": \"amqps://${beehive_host}:${beehive_port}?auth_mechanism=external&cacertfile=/etc/ca/cacert.pem&certfile=/etc/tls/cert.pem&keyfile=/etc/tls/key.pem\",
  \"dest-exchange\": \"waggle.msg\",
  \"dest-publish-properties\": {
    \"delivery_mode\": 2,
    \"user_id\": \"node-$nodeID\"
  }
}
"; do
    sleep 3
  done
}

disable_shovels() {
    while ! rmqctl clear_parameter shovel push-messages; do
      sleep 3
    done
}

case "$1" in
start|enable) enable_shovels ;;
stop|disable) disable_shovels ;;
*) echo "usage: $0 (enable|disable)"; exit 1 ;;
esac
