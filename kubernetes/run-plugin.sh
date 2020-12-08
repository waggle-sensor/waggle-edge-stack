#!/bin/bash -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: $0 plugin-name plugin-version"
  echo "example: $0 plugin-test-pipeline 0.0.2"
  echo
  echo "note: assumes image follows \"docker.io/waggle/plugin-name:plugin-version\" for now"
  exit 1
fi

plugin_name="$1"
plugin_version="$2"
plugin_image="docker.io/waggle/${plugin_name}:${plugin_version}"
plugin_username="${plugin_name}-${plugin_version}"
plugin_password="averysecurepassword"

# apply rabbitmq server config
# TODO make permissions more strict
kubectl exec --stdin service/rabbitmq-server -- sh -s <<EOF
while ! rabbitmqctl -q authenticate_user ${plugin_username} ${plugin_password}; do
  echo "adding user ${plugin_username} to rabbitmq"
  rabbitmqctl -q add_user ${plugin_username} ${plugin_password} || \
  rabbitmqctl -q change_password ${plugin_username} ${plugin_password}
done

rabbitmqctl set_permissions ${plugin_username} ".*" ".*" ".*"
EOF

# apply deployment config
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${plugin_name}
spec:
  selector:
    matchLabels:
      app: ${plugin_name}
  template:
    metadata:
      labels:
        app: ${plugin_name}
    spec:
      containers:
      - image: ${plugin_image}
        name: ${plugin_name}
        env:
        - name: WAGGLE_PLUGIN_NAME
          value: "${plugin_name}"
        - name: WAGGLE_PLUGIN_VERSION
          value: "${plugin_version}"
        - name: WAGGLE_PLUGIN_USERNAME
          value: "${plugin_username}"
        - name: WAGGLE_PLUGIN_PASSWORD
          value: "${plugin_password}"
        - name: WAGGLE_PLUGIN_HOST
          value: "rabbitmq-server"
        - name: WAGGLE_PLUGIN_PORT
          value: "5672"
        envFrom:
          - configMapRef:
              name: waggle-config
        resources:
          limits:
            cpu: 200m
            memory: 20Mi
          requests:
            cpu: 100m
            memory: 10Mi
        volumeMounts:
          - name: uploads
            mountPath: /run/waggle/uploads
          - name: waggle-data-config
            mountPath: /run/waggle/data-config.json
            subPath: data-config.json
      volumes:
      - name: uploads
        hostPath:
          path: /media/plugin-data/uploads/${plugin_name}/${plugin_version}
          type: DirectoryOrCreate
      - name: waggle-data-config
        configMap:
          name: waggle-data-config
EOF
