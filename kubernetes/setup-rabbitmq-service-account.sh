#!/bin/bash -e

# TODO see if we can clean this up. basically, this is just making the configmap stuff available inside this
# admin tool.
export WAGGLE_NODE_ID=$(kubectl get configmap waggle-config -o "jsonpath={.data['WAGGLE_NODE_ID']}")
export WAGGLE_BEEHIVE_HOST=$(kubectl get configmap waggle-config -o "jsonpath={.data['WAGGLE_BEEHIVE_HOST']}")

username=$(kubectl get secret rabbitmq-service-account-secret -o "jsonpath={.data['USERNAME']}" | base64 -d)
password=$(kubectl get secret rabbitmq-service-account-secret -o "jsonpath={.data['PASSWORD']}" | base64 -d)

# TODO this may not be secure over the network. check this later.
kubectl exec --stdin service/rabbitmq-server -- sh -s <<EOF
while ! rabbitmqctl -q authenticate_user ${username} ${password}; do
  echo "refreshing credentials for \"${username}\""
  rabbitmqctl -q add_user ${username} ${password} || \
  rabbitmqctl -q change_password ${username} ${password}
done
EOF

# setup shovel using credentials.
while ! NODE_RABBITMQ_USERNAME="${username}" NODE_RABBITMQ_PASSWORD="${password}" python3 shovelctl.py enable; do
  echo "failed to update shovel"
  sleep 1
done
