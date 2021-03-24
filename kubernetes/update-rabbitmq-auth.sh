#!/bin/bash

rmqctl() {
    kubectl exec svc/wes-rabbitmq -- rabbitmqctl "$@"
}

secretname="$1"
username="$2"
confperm="$3"
writeperm="$4"
readperm="$5"
tags="$6"
password="$(openssl rand -hex 20)"

echo "updating kubernetes config ${secretname}..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secretname}
type: kubernetes.io/basic-auth
stringData:
  username: ${username}
  password: ${password}
EOF

echo "updating rabbitmq user ${username}..."
(
while ! rmqctl authenticate_user "$username" "$password"; do
    while ! (rmqctl add_user "$username" "$password" || rmqctl change_password "$username" "$password"); do
      sleep 3
    done
done

while ! rmqctl set_permissions "$username" "$confperm" "$writeperm" "$readperm"; do
  sleep 3
done

while ! rmqctl set_user_tags "$username" "$tags"; do
  sleep 3
done
) &> /dev/null
echo "done"
