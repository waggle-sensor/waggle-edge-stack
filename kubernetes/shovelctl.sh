#!/bin/bash -e

enable_shovels() {
    nodeID=$(kubectl get cm waggle-config --template={{.data.WAGGLE_NODE_ID}})
    beehive_host=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_HOST}})
    beehive_port=$(kubectl get cm waggle-config --template={{.data.WAGGLE_BEEHIVE_RABBITMQ_PORT}})
    username=$(kubectl get secret rabbitmq-service-account-secret --template={{.data.USERNAME}} | base64 -d)
    password=$(kubectl get secret rabbitmq-service-account-secret --template={{.data.PASSWORD}} | base64 -d)

    kubectl exec -i svc/rabbitmq -- rabbitmqctl set_parameter shovel push-messages "{
  \"src-uri\": \"amqp://${username}:${password}@rabbitmq\",
  \"src-queue\": \"to-beehive\",
  \"dest-uri\": \"amqps://${beehive_host}:${beehive_port}?auth_mechanism=external&cacertfile=/etc/waggle/cacert.pem&certfile=/etc/waggle/cert.pem&keyfile=/etc/waggle/key.pem\",
  \"dest-exchange\": \"waggle.msg\",
  \"dest-publish-properties\": {
    \"delivery_mode\": 2,
    \"user_id\": \"node-$nodeID\"
  }
}
"
}

disable_shovels() {
    kubectl exec -i svc/rabbitmq -- rabbitmqctl clear_parameter shovel push-messages
}

case "$1" in
enable) enable_shovels ;;
disable) disable_shovels ;;
*) echo "usage: $0 (enable|disable)"; exit 1 ;;
esac
