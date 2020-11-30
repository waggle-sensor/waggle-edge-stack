#!/bin/bash -e

plugin_name="$1"
plugin_version="$2"
plugin_image="docker.io/waggle/${plugin_name}:${plugin_version}"
plugin_username="${plugin_name}-${plugin_version}"
plugin_password="averysecurepassword"

# apply rabbitmq server config
kubectl exec --stdin service/rabbitmq-server -- bash -s <<EOF
if ! rabbitmqctl authenticate_user ${plugin_username} ${plugin_password}; then
  rabbitmqctl add_user ${plugin_username} ${plugin_password} || \
  rabbitmqctl change_password ${plugin_username} ${plugin_password}
fi
rabbitmqctl set_permissions ${plugin_username} '.*' '.*' '.*'
EOF

# apply deployment config
cat <<EOF | kubectl apply -f -
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
      volumes:
      - name: uploads
        hostPath:
          path: /media/plugin-data/uploads/${plugin_name}/${plugin_version}
          type: DirectoryOrCreate
EOF
