#!/bin/bash -e

enable_shovels() {
    nodeID=$(kubectl get cm waggle-config --template={{.data.WAGGLE_NODE_ID}})
    beehive_host=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_HOST}})
    beehive_port=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_PORT}})
    kubectl exec -i svc/wes-rabbitmq -- rabbitmqctl set_parameter shovel push-messages "{
  \"src-uri\": \"amqp://shovel:shovel@wes-rabbitmq\",
  \"src-queue\": \"to-beehive\",
  \"dest-uri\": \"amqps://${beehive_host}:${beehive_port}?auth_mechanism=external&cacertfile=/etc/ca/cacert.pem&certfile=/etc/tls/cert.pem&keyfile=/etc/tls/key.pem\",
  \"dest-exchange\": \"waggle.msg\",
  \"dest-publish-properties\": {
    \"delivery_mode\": 2,
    \"user_id\": \"node-$nodeID\"
  }
}
"
}

disable_shovels() {
    kubectl exec -i svc/wes-rabbitmq -- rabbitmqctl clear_parameter shovel push-messages
}

case "$1" in
enable) enable_shovels ;;
disable) disable_shovels ;;
*) echo "usage: $0 (enable|disable)"; exit 1 ;;
esac
