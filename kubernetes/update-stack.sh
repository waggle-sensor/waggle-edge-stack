#!/bin/bash
set -e

WAGGLE_CONFIG_DIR="${WAGGLE_CONFIG_DIR:-/etc/waggle}"
WAGGLE_BIN_DIR="${WAGGLE_BIN_DIR:-/usr/bin}"
SES_VERSION="${SES_VERSION:-0.19.0}"
SES_TOOLS="${SES_TOOLS:-runplugin pluginctl sesctl}"
NODE_MANIFEST_V2="${NODE_MANIFEST_V2:-node-manifest-v2.json}"

fatal() {
    echo $*
    exit 1
}

getarch() {
    case $(uname -m) in
    x86_64) echo linux-amd64 ;;
    aarch64) echo linux-arm64 ;;
    amd64) echo linux-amd64 ;;
    arm64) echo linux-arm64 ;;
    * ) return 1 ;;
    esac
}

node_id() {
    echo $(awk '{print tolower($0)}' "${WAGGLE_CONFIG_DIR}/node-id")
}

node_vsn() {
    echo $(awk '{print toupper($0)}' "${WAGGLE_CONFIG_DIR}/vsn")
}

update_wes_tools() {
    echo "updating wes tools"

    if ! arch=$(getarch); then
        fatal "failed to get arch"
    fi

    for name in $SES_TOOLS; do
        url="https://github.com/waggle-sensor/edge-scheduler/releases/download/${SES_VERSION}/${name}-${arch}"

        echo "downloading ${url}"
        wget --timeout 300 -q -N -P "${WAGGLE_BIN_DIR}" "${url}"
        basename=$(basename ${url})

        echo "updating ${name} to ${url}"
        chmod +x "${WAGGLE_BIN_DIR}/${basename}"
        ln -f "${WAGGLE_BIN_DIR}/${basename}" "${WAGGLE_BIN_DIR}/${name}"
    done
}

update_node_secrets() {
    (
    if [ -e /root/.ssh/node-private-git-repo-key ] ; then
        export GIT_SSH_COMMAND='ssh -i /root/.ssh/node-private-git-repo-key -o StrictHostKeyChecking=no -o IdentitiesOnly=yes'
        if [ -e /opt/node-config-private ] ; then
            git -C /opt/node-config-private pull
        else
            git clone git@github.com:waggle-sensor/node-config-private.git /opt/node-config-private
        fi
        kubectl apply -f /opt/node-config-private/secrets
    else
        echo "/root/ssh/node-private-git-repo-key not found, skipping..."
    fi
    )
}

update_node_manifest_v2() {
    local filepath="${WAGGLE_CONFIG_DIR}/${NODE_MANIFEST_V2}"
    local tmppath="/tmp/${NODE_MANIFEST_V2}"
    local url="https://auth.sagecontinuum.org/manifests/$(node_vsn)/"

    echo "syncing manifest (${filepath} from ${url}"

    # download the latest manifest file
    if wget -q -O ${tmppath} ${url}; then
        echo "online manifest (${url}) found, updating ${filepath}"
        # create the local host "pretty" manifest
        cat ${tmppath} | jq . > ${filepath}
    else
        echo "failed to download manifest (${url})"
    fi
}

update_data_config() {
    echo "updating waggle-data-config"

    # This is a 1 time operation only if the CM doesn't exist already
    if output=$(kubectl create configmap waggle-data-config --from-file=data-config.json=data-config.json 2>&1); then
        echo "waggle-data-config created"
    elif echo "$output" | grep -q "already exists"; then
        echo "waggle-data-config already exists"
    else
        fatal "error when setting up waggle-data-config"
    fi
}

delete_influxdb_pvc() {
    echo "WARNING: deleting influxDB data volume"
    kubectl delete -f wes-node-influxdb.yaml || true
    echo "sleep for 3 seconds"
    sleep 3
    echo "deleting Kubernetes pvc: data-wes-node-influxdb-0 and config-wes-node-influxdb-0"
    kubectl delete pvc data-wes-node-influxdb-0 config-wes-node-influxdb-0 || true
}

# NOTE (Yongho): This will get eventually removed as all nodes do not have the plugins anymore
cleanup_old_iio_raingauge() {
    echo "attempting to remove old iio/rainguage plugins"
    kubectl delete deployment iio-nx iio-rpi raingauge iio-enclosure || true
}

update_wes_plugins() {
    echo "running iio plugin for bme680..."
    pluginctl deploy --name wes-iio-bme680 \
      --type daemonset \
      --privileged \
      --selector resource.bme680=true \
      --resource request.cpu=50m,request.memory=30Mi,limit.memory=30Mi \
      waggle/plugin-iio:0.6.0 -- \
      --filter bme680
    
    echo "running iio plugin for bme280..."
    pluginctl deploy --name wes-iio-bme280 \
      --type daemonset \
      --privileged \
      --selector resource.bme280=true \
      --resource request.cpu=50m,request.memory=30Mi,limit.memory=30Mi \
      waggle/plugin-iio:0.6.0 -- \
      --filter bme280
    
    echo "running iio plugin for raingauge"
    pluginctl deploy --name wes-raingauge \
      --type daemonset \
      --privileged \
      --selector resource.raingauge=true \
      --resource request.cpu=50m,request.memory=30Mi,limit.memory=30Mi \
      waggle/plugin-raingauge:0.4.1 -- \
      --device /dev/ttyUSB0
}

# NOTE the following section is really just a big reshaping of various configs and secrets
# into bits that will be managed by kustomize. they're arguably simpler than before and we
# could consider eventually just shipping the files as a tar / zip in rather than this:
# 1. load source configs / secret into kubernetes from beekeeper
# 2. extract and reshape relevant parts into generated configs
# 3. load generated configs / secrets using kustomize
# if we buy into just using kustomize from the get go, then mostly only need step 3.
update_wes() {
    echo "updating wes"

    echo "generating wes configs"

    mkdir -p configs configs/rabbitmq configs/upload-agent
    # make all config directories private
    find configs -type d | xargs chmod 700

    # generate identity config for kustomize
    # NOTE we are ignoring the WAGGLE_NODE_ID in waggle-config and creating from local file
    WAGGLE_NODE_ID=$(node_id)
    WAGGLE_NODE_VSN=$(node_vsn)
    cat > configs/wes-identity.env <<EOF
WAGGLE_NODE_ID=${WAGGLE_NODE_ID}
WAGGLE_NODE_VSN=${WAGGLE_NODE_VSN}
EOF

    # copy over the (potentially) updated node manifest
    cp ${WAGGLE_CONFIG_DIR}/${NODE_MANIFEST_V2} configs/${NODE_MANIFEST_V2}

    # generate rabbitmq configs / secrets for kustomize
    cat > configs/rabbitmq/enabled_plugins <<EOF
[rabbitmq_prometheus,rabbitmq_management,rabbitmq_management_agent,rabbitmq_auth_mechanism_ssl,rabbitmq_shovel,rabbitmq_shovel_management,rabbitmq_mqtt].
EOF

    cat > configs/rabbitmq/rabbitmq.conf <<EOF
# server config
listeners.tcp.default = 5672

# management config
management.load_definitions = /etc/rabbitmq/definitions.json
management.tcp.ip   = 0.0.0.0
management.tcp.port = 15672

# disable logging to file to prevent runaway disk usage
log.file = false

# mqtt config for lorawan
mqtt.default_user = service
mqtt.default_pass = service
EOF

    WAGGLE_BEEHIVE_RABBITMQ_HOST=$(get_configmap_field waggle-config WAGGLE_BEEHIVE_RABBITMQ_HOST)
    WAGGLE_BEEHIVE_RABBITMQ_PORT=$(get_configmap_field waggle-config WAGGLE_BEEHIVE_RABBITMQ_PORT)
    cat > configs/rabbitmq/definitions.json <<EOF
{
    "users": [
        {
            "name": "admin",
            "password": "admin",
            "tags": "administrator"
        },
        {
            "name": "service",
            "password": "service",
            "tags": ""
        },
        {
            "name": "shovel",
            "password": "shovel",
            "tags": ""
        },
        {
            "name": "plugin",
            "password": "plugin",
            "tags": ""
        }
    ],
    "vhosts": [
        {
            "name": "/"
        }
    ],
    "permissions": [
        {
            "user": "admin",
            "vhost": "/",
            "configure": ".*",
            "write": ".*",
            "read": ".*"
        },
        {
            "user": "service",
            "vhost": "/",
            "configure": ".*",
            "write": ".*",
            "read": ".*"
        },
        {
            "user": "shovel",
            "vhost": "/",
            "configure": ".*",
            "write": ".*",
            "read": ".*"
        },
        {
            "user": "plugin",
            "vhost": "/",
            "configure": ".*",
            "write": ".*",
            "read": ".*"
        }
    ],
    "queues": [
        {
            "name": "data",
            "vhost": "/",
            "durable": true,
            "auto_delete": false,
            "arguments": {}
        },
        {
            "name": "messages",
            "vhost": "/",
            "durable": true,
            "auto_delete": false,
            "arguments": {}
        },
        {
            "name": "to-beehive",
            "vhost": "/",
            "durable": true,
            "auto_delete": false,
            "arguments": {}
        },
        {
            "name": "to-beekeeper",
            "vhost": "/",
            "durable": true,
            "auto_delete": false,
            "arguments": {}
        },
        {
            "name": "resource-manager",
            "vhost": "/",
            "durable": true,
            "auto_delete": false,
            "arguments": {}
        }
    ],
    "exchanges": [
        {
            "name": "data.topic",
            "vhost": "/",
            "type": "topic",
            "durable": true,
            "auto_delete": false,
            "internal": false,
            "arguments": {}
        },
        {
            "name": "data.fanout",
            "vhost": "/",
            "type": "fanout",
            "durable": true,
            "auto_delete": false,
            "internal": false,
            "arguments": {}
        },
        {
            "name": "messages",
            "vhost": "/",
            "type": "fanout",
            "durable": true,
            "auto_delete": false,
            "internal": false,
            "arguments": {}
        },
        {
            "name": "to-node",
            "vhost": "/",
            "type": "topic",
            "durable": true,
            "auto_delete": false,
            "internal": false,
            "arguments": {}
        }
    ],
    "bindings": [
        {
            "source": "data.fanout",
            "vhost": "/",
            "destination": "data",
            "destination_type": "queue",
            "routing_key": "",
            "arguments": {}
        },
        {
            "source": "messages",
            "vhost": "/",
            "destination": "messages",
            "destination_type": "queue",
            "routing_key": "messages",
            "arguments": {}
        },
        {
            "source": "to-node",
            "vhost": "/",
            "destination": "resource-manager",
            "destination_type": "queue",
            "routing_key": "*.resource-manager",
            "arguments": {}
        },
        {
            "source": "to-node",
            "vhost": "/",
            "destination": "ansible",
            "destination_type": "queue",
            "routing_key": "*.ansible",
            "arguments": {}
        }
    ],
    "parameters": [
        {
            "value": {
            "dest-exchange": "waggle.msg",
            "dest-publish-properties": {
                "delivery_mode": 2,
                "user_id": "node-${WAGGLE_NODE_ID}"
            },
            "dest-uri": "amqps://${WAGGLE_BEEHIVE_RABBITMQ_HOST}:${WAGGLE_BEEHIVE_RABBITMQ_PORT}?auth_mechanism=external&cacertfile=/etc/rabbitmq/cacert.pem&certfile=/etc/rabbitmq/cert.pem&keyfile=/etc/rabbitmq/key.pem",
            "src-queue": "to-beehive",
            "src-uri": "amqp://shovel:shovel@wes-rabbitmq"
            },
            "vhost": "/",
            "component": "shovel",
            "name": "push-messages"
        }
    ]
}
EOF

    # generate rabbitmq configs / secrets for kustomize
    get_configmap_field beehive-ca-certificate cacert.pem > configs/rabbitmq/cacert.pem
    get_secret_field wes-beehive-rabbitmq-tls cert.pem > configs/rabbitmq/cert.pem
    get_secret_field wes-beehive-rabbitmq-tls key.pem > configs/rabbitmq/key.pem

    # generate upload agent configs / secrets for kustomize
    WAGGLE_BEEHIVE_UPLOAD_HOST=$(get_configmap_field waggle-config WAGGLE_BEEHIVE_UPLOAD_HOST)
    WAGGLE_BEEHIVE_UPLOAD_PORT=$(get_configmap_field waggle-config WAGGLE_BEEHIVE_UPLOAD_PORT)
    cat > configs/upload-agent/wes-upload-agent.env <<EOF
WAGGLE_BEEHIVE_UPLOAD_HOST=${WAGGLE_BEEHIVE_UPLOAD_HOST}
WAGGLE_BEEHIVE_UPLOAD_PORT=${WAGGLE_BEEHIVE_UPLOAD_PORT}
SSH_CA_PUBKEY=/etc/upload-agent/ca.pub
SSH_KEY=/etc/upload-agent/ssh-key
SSH_CERT=/etc/upload-agent/ssh-key-cert.pub
EOF

    get_configmap_field beehive-ssh-ca ca.pub > configs/upload-agent/ca.pub
    get_configmap_field beehive-ssh-ca ca-cert.pub > configs/upload-agent/ca-cert.pub
    get_secret_field wes-beehive-upload-ssh-key ssh-key > configs/upload-agent/ssh-key
    get_secret_field wes-beehive-upload-ssh-key ssh-key-cert.pub > configs/upload-agent/ssh-key-cert.pub
    get_secret_field wes-beehive-upload-ssh-key ssh-key.pub > configs/upload-agent/ssh-key.pub

    # create or pull influxdb token
    echo "setting influxdb..."
    # it is assumed that the commands below may fail.
    set +e
    TOKEN_NAME="waggle-read-write-bucket"
    INFLUXDB_UNAUTHORIZED=$(kubectl exec svc/wes-node-influxdb -- influx auth ls 2>&1 | grep "Unauthorized")
    if [ ! -z "${INFLUXDB_UNAUTHORIZED}" ]; then
        echo "failed to check influxDB auth. Access token is missing"
        echo "influxDB and its PVCs will be deleted to reset them"
        delete_influxdb_pvc
    fi
    # NOTE(sean) there have been nodes with multiple tokens named 'waggle-read-write-bucket', so we simply accept the first match.
    WAGGLE_INFLUXDB_TOKEN=$(kubectl exec svc/wes-node-influxdb -- influx auth ls | awk -v name="${TOKEN_NAME}" '$2 ~ name {print $3; exit}')
    if [ -z "${WAGGLE_INFLUXDB_TOKEN}" ]; then
        echo "creating influxdb read-write token..."
        WAGGLE_INFLUXDB_TOKEN=$(kubectl exec svc/wes-node-influxdb -- influx auth create -u waggle -o waggle --hide-headers --read-buckets --write-buckets -d $TOKEN_NAME | awk '{print $3}')
    else
        echo "token found. skipping creating influxdb read-write token"
    fi
    # NOTE(YK) This token is used for "pluginctl profile" to access wes-node-influxDB from host
    TOKEN_NAME="waggle-read-bucket"
    PLUGINCTL_INFLUXDB_TOKEN=$(kubectl exec svc/wes-node-influxdb -- influx auth ls | awk -v name="${TOKEN_NAME}" '$2 ~ name {print $3; exit}')
    if [ -z "${PLUGINCTL_INFLUXDB_TOKEN}" ]; then
        echo "creating influxdb read-only token..."
        PLUGINCTL_INFLUXDB_TOKEN=$(kubectl exec svc/wes-node-influxdb -- influx auth create -u waggle -o waggle --hide-headers --read-buckets -d $TOKEN_NAME | awk '{print $3}')
    else
        echo "token found. skipping creating influxdb read-only token"
    fi
    mkdir -p /root/.influxdb2
    echo ${PLUGINCTL_INFLUXDB_TOKEN} > /root/.influxdb2/token
    mkdir -p /home/waggle/.influxdb2
    echo ${PLUGINCTL_INFLUXDB_TOKEN} > /home/waggle/.influxdb2/token
    set -e

    echo "creating/updating wes-plugin-account"
    kubectl apply -f wes-plugin-account.yaml

    # HACK(sean) we add a "plain" wes-identity for plugins. kustomize will add a hash to wes-identity
    # causing the name to be unpredictable. we'll keep both, as the hash allows kustomize to restart
    # parts of wes that depend on an updated config.
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: wes-identity
data:
  WAGGLE_NODE_ID: "${WAGGLE_NODE_ID}"
  WAGGLE_NODE_VSN: "${WAGGLE_NODE_VSN}"
EOF

    # HACK(sean) at some point, kustomize deprecated env: for envs: in the configmap / secret generators.
    # i'm generating the kustomization.yaml file just to use literals instead of envs which are
    # backwards compatible...
    # you'll see this as the error:
    # error: json: unknown field "envs"
    cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
  - name: wes-identity
    literals:
      - WAGGLE_NODE_ID=${WAGGLE_NODE_ID}
      - WAGGLE_NODE_VSN=${WAGGLE_NODE_VSN}
  - name: wes-upload-agent-env
    literals:
      - WAGGLE_BEEHIVE_UPLOAD_HOST=${WAGGLE_BEEHIVE_UPLOAD_HOST}
      - WAGGLE_BEEHIVE_UPLOAD_PORT=${WAGGLE_BEEHIVE_UPLOAD_PORT}
      - SSH_CA_PUBKEY=/etc/upload-agent/ca.pub
      - SSH_KEY=/etc/upload-agent/ssh-key
      - SSH_CERT=/etc/upload-agent/ssh-key-cert.pub
  - name: waggle-node-manifest-v2
    files:
      - configs/${NODE_MANIFEST_V2}
secretGenerator:
  - name: wes-rabbitmq-config
    files:
      - configs/rabbitmq/rabbitmq.conf
      - configs/rabbitmq/definitions.json
      - configs/rabbitmq/enabled_plugins
      - configs/rabbitmq/cacert.pem
      - configs/rabbitmq/cert.pem
      - configs/rabbitmq/key.pem
  - name: wes-upload-agent-config
    files:
      - configs/upload-agent/ca.pub
      - configs/upload-agent/ca-cert.pub
      - configs/upload-agent/ssh-key
      - configs/upload-agent/ssh-key-cert.pub
      - configs/upload-agent/ssh-key.pub
  - name: wes-node-influxdb-waggle-token
    literals:
      - token=${WAGGLE_INFLUXDB_TOKEN}
resources:
  # common constraints and limits
  - wes-default-limits.yaml
  - wes-priority-classes.yaml
  - wes-plugin-network-policy.yaml
  # main components
  - cadvisor-exporter.yaml
  - jetson-exporter.yaml
  - dcgm-exporter.yaml
  - nvidia-device-plugin.yaml
  - node-exporter.yaml
  - wes-device-labeler.yaml
  - wes-audio-server.yaml
  - wes-data-sharing-service.yaml
  - wes-rabbitmq.yaml
  - wes-upload-agent.yaml
  - wes-metrics-agent.yaml
  - wes-plugin-scheduler.yaml
  - wes-sciencerule-checker.yaml
  - wes-gps-server.yaml
  - wes-scoreboard.yaml
  - wes-camera-provisioner.yaml
  - wes-node-influxdb.yaml
  - wes-node-influxdb-loader.yaml
EOF

    echo "patching coredns to always run on nxcore"
    kubectl -n kube-system patch deployment coredns -p '
{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "node-role.kubernetes.io/master": "true"
        }
      }
    }
  }
}
'

    echo "performing one-time operation - clean old chirpstack"
    # NOTE(Joe) this is a work-around to remove old deployments when converting to statefulsets
    # this can safely be removed after all nodes have moved to the "statefulset" postgresql and redis setups
    kubectl delete deployment wes-chirpstack-postgresql || true
    kubectl delete deployment wes-chirpstack-redis || true
    kubectl delete cm wes-chirpstack-postgresql-configmap || true
    kubectl delete pvc wes-chirpstack-postgresql-data || true
    kubectl delete pvc wes-chirpstack-redis-data || true

    echo "deploying wes stack"
    # NOTE(sean) this is split as its own thing as the version of kubectl (v1.20.2+k3s1) we were using
    # when this was added didn't seem to support nesting other kustomization dirs as resources.
    # i'm deploying this first, to ensure to influxdb pvc issue doesn't stop this from running
    kubectl apply -k wes-app-meta-cache
    kubectl apply -k .
    kubectl apply -k wes-chirpstack

    echo "cleaning untagged / broken images"
    # wait a moment before checking for images
    sleep 10
    k3s crictl images | awk '$2 ~ /<none>/ {print $3}' | xargs k3s crictl rmi || true
}

get_configmap_field() {
    name="${1}"
    escaped_field="${2//./\\.}"
    kubectl get configmap "${name}" -o jsonpath="{.data.${escaped_field}}"
}

get_secret_field() {
    name="${1}"
    escaped_field="${2//./\\.}"
    if ! output=$(kubectl get secret "${name}" -o jsonpath="{.data.${escaped_field}}"); then
        return 1
    fi
    echo "${output}" | base64 -d
}

cd $(dirname $0)
# NOTE (Yongho): this cleans up the old iio/raingauge plugins to ensure
#                the new ones can use the serial device
cleanup_old_iio_raingauge
update_wes_tools
update_node_secrets
update_node_manifest_v2
update_data_config
update_wes_plugins
update_wes
