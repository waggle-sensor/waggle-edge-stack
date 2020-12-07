#!/bin/bash -e

username=service
password=$(openssl rand -hex 12)

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-service-account-secret
type: Opaque
stringData:
    USERNAME: "${username}"
    PASSWORD: "${password}"
EOF

# TODO this may not be secure over the network. check this later.
kubectl exec --stdin service/rabbitmq-server -- sh -s <<EOF
while ! rabbitmqctl -q authenticate_user ${username} ${password}; do
  echo "refreshing credentials for \"${username}\""
  rabbitmqctl -q add_user ${username} ${password} || \
  rabbitmqctl -q change_password ${username} ${password}
done
EOF

while ! NODE_RABBITMQ_USERNAME="${username}" NODE_RABBITMQ_PASSWORD="${password}" python3 shovelctl.py; do
  echo "failed to update shovel"
  sleep 1
done

# can we do something generic to spin up an api config? for example, just using curl?
