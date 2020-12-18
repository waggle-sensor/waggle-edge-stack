#!/bin/bash -e

fatal() {
  echo $*
  exit 1
}

if [ -z "$1" ]; then
  echo "usage: $0 plugin-image"
  echo "example: "
  exit 1
fi

plugin_image="$1"

# if no namespace provided, assume docker.io/waggle
case $(dirname $plugin_image) in
.) plugin_image="docker.io/waggle/${plugin_image}" ;;
esac

if ! echo "$plugin_image" | grep -q ":"; then
  fatal "plugin image tag is required"
fi

plugin_name=$(basename $1 | sed -e 's/:.*//')
if [ -z "$plugin_name" ]; then
  fatal "plugin name is required"
fi

plugin_version=$(basename $1 | sed -e 's/.*://')
if [ -z "$plugin_version" ]; then
  fatal "plugin version is required"
fi

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

# ensure plugin network policy is in place
kubectl apply -f plugin-network-policy.yaml

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
        role: plugin
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
