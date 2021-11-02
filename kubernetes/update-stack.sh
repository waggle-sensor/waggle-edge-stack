#!/bin/bash -e

WAGGLE_CONFIG_DIR=${WAGGLE_CONFIG_DIR:-/etc/waggle}
WAGGLE_BIN_DIR=${WAGGLE_BIN_DIR:-/usr/bin}

fatal() {
    echo $*
    exit 1
}

getarch() {
    case $(uname -m) in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    * ) return 1 ;;
    esac
}

update_runplugin() {
    echo "updating runplugin"

    if ! arch=$(getarch); then
        fatal "failed to get arch"
    fi

    wget -q -N -P "${WAGGLE_BIN_DIR}" "https://github.com/sagecontinuum/ses/releases/download/0.7.0/runplugin-${arch}"
    chmod +x "${WAGGLE_BIN_DIR}/runplugin-${arch}"
    ln -f "${WAGGLE_BIN_DIR}/runplugin-${arch}" "${WAGGLE_BIN_DIR}/runplugin"
}

update_data_config() {
    echo "updating waggle-data-config"

    if output=$(kubectl create configmap waggle-data-config --from-file=data-config.json=data-config.json 2>&1); then
        echo "waggle-data-config created"
    elif echo "$output" | grep -q "already exists"; then
        echo "waggle-data-config already exists"
    else
        fatal "error when setting up waggle-data-config"
    fi
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
    WAGGLE_NODE_ID=$(awk '{print tolower($0)}' "${WAGGLE_CONFIG_DIR}/node-id")
    WAGGLE_NODE_VSN=$(awk '{print toupper($0)}' "${WAGGLE_CONFIG_DIR}/vsn")
    cat > configs/wes-identity.env <<EOF
WAGGLE_NODE_ID=${WAGGLE_NODE_ID}
WAGGLE_NODE_VSN=${WAGGLE_NODE_VSN}
EOF

    # generate rabbitmq configs / secrets for kustomize
    cat > configs/rabbitmq/enabled_plugins <<EOF
[rabbitmq_prometheus,rabbitmq_management,rabbitmq_management_agent,rabbitmq_auth_mechanism_ssl,rabbitmq_shovel,rabbitmq_shovel_management].
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
EOF

    WAGGLE_BEEHIVE_RABBITMQ_HOST=$(kubectl get cm waggle-config -o jsonpath='{.data.WAGGLE_BEEHIVE_RABBITMQ_HOST}')
    WAGGLE_BEEHIVE_RABBITMQ_PORT=$(kubectl get cm waggle-config -o jsonpath='{.data.WAGGLE_BEEHIVE_RABBITMQ_PORT}')
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

    kubectl get cm beehive-ca-certificate -o jsonpath="{.data.cacert\.pem}" > configs/rabbitmq/cacert.pem
    kubectl get secret wes-beehive-rabbitmq-tls -o jsonpath='{.data.cert\.pem}' | base64 -d > configs/rabbitmq/cert.pem
    kubectl get secret wes-beehive-rabbitmq-tls -o jsonpath='{.data.key\.pem}' | base64 -d > configs/rabbitmq/key.pem

    # generate upload agent configs / secrets for kustomize
    WAGGLE_BEEHIVE_UPLOAD_HOST=$(kubectl get cm waggle-config -o jsonpath='{.data.WAGGLE_BEEHIVE_UPLOAD_HOST}')
    WAGGLE_BEEHIVE_UPLOAD_PORT=$(kubectl get cm waggle-config -o jsonpath='{.data.WAGGLE_BEEHIVE_UPLOAD_PORT}')
    cat > configs/upload-agent/wes-upload-agent.env <<EOF
WAGGLE_BEEHIVE_UPLOAD_HOST=${WAGGLE_BEEHIVE_UPLOAD_HOST}
WAGGLE_BEEHIVE_UPLOAD_PORT=${WAGGLE_BEEHIVE_UPLOAD_PORT}
SSH_CA_PUBKEY=/etc/upload-agent/ca.pub
SSH_KEY=/etc/upload-agent/ssh-key
SSH_CERT=/etc/upload-agent/ssh-key-cert.pub
EOF

    kubectl get cm beehive-ssh-ca -o jsonpath="{.data.ca\.pub}" > configs/upload-agent/ca.pub
    kubectl get cm beehive-ssh-ca -o jsonpath="{.data.ca-cert\.pub}" > configs/upload-agent/ca-cert.pub
    kubectl get secret wes-beehive-upload-ssh-key -o jsonpath='{.data.ssh-key}' | base64 -d > configs/upload-agent/ssh-key
    kubectl get secret wes-beehive-upload-ssh-key -o jsonpath='{.data.ssh-key-cert\.pub}' | base64 -d > configs/upload-agent/ssh-key-cert.pub
    kubectl get secret wes-beehive-upload-ssh-key -o jsonpath='{.data.ssh-key\.pub}' | base64 -d > configs/upload-agent/ssh-key.pub

    # HACK at some point, kustomize deprecated env: for envs: in the configmap / secret generators.
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
resources:
  # common constraints and limits
  - wes-default-limits.yaml
  - wes-priority-classes.yaml
  - wes-plugin-network-policy.yaml
  # main components
  - node-exporter.yaml
  - wes-device-labeler.yaml
  - wes-audio-server.yaml
  - wes-data-sharing-service.yaml
  - wes-rabbitmq.yaml
  - wes-upload-agent.yaml
  - wes-metrics-agent.yaml
  - wes-gps-server.yaml
EOF

    echo "deploying wes stack"
    kubectl apply -k .
}

cd $(dirname $0)
update_runplugin
update_data_config
update_wes
