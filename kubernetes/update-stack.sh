#!/bin/bash
set -e

WAGGLE_CONFIG_DIR="${WAGGLE_CONFIG_DIR:-/etc/waggle}"
WAGGLE_BIN_DIR="${WAGGLE_BIN_DIR:-/usr/bin}"
SES_VERSION="${SES_VERSION:-0.28.0}"
SES_TOOLS="${SES_TOOLS:-runplugin pluginctl sesctl}"
NODE_MANIFEST_V2="${NODE_MANIFEST_V2:-node-manifest-v2.json}"

fatal() {
    echo $*
    exit 1
}

# waggle_log logs important messages to the journal so they can fetched using the waggle identifier:
# journalctl -t waggle
waggle_log() {
    level="$1"
    shift
    systemd-cat -t waggle -p "$level" echo $*
}

getarch() {
    case $(uname -s) in
    [Dd]arwin) os=darwin ;;
    [Ll]inux) os=linux ;;
    *) return 1 ;;
    esac

    case $(uname -m) in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    amd64) arch=amd64 ;;
    arm64) arch=arm64 ;;
    *) return 1 ;;
    esac

    echo "${os}-${arch}"
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

    # download checksum file
    if ! wget -q --timeout 10 "https://github.com/waggle-sensor/edge-scheduler/releases/download/${SES_VERSION}/sha256sum.txt" -O /tmp/sestools-sha256sum.txt; then
        fatal "failed to fetch checksum file"
    fi

    # extract checksums for current arch
    grep "${arch}" /tmp/sestools-sha256sum.txt > "/tmp/sestools-sha256sum-${arch}.txt"

    # collect files which fail checksum (or do not exist) and download
    files_to_download=$(cd "${WAGGLE_BIN_DIR}" && shasum -a 256 -c "/tmp/sestools-sha256sum-${arch}.txt" | awk -F: '/FAILED/ {print $1}')

    for name in $files_to_download; do
        echo "downloading ${name}..."
        url="https://github.com/waggle-sensor/edge-scheduler/releases/download/${SES_VERSION}/${name}"
        wget --quiet --continue --timeout 900 "${url}" -O "${WAGGLE_BIN_DIR}/${name}.download"
        mv "${WAGGLE_BIN_DIR}/${name}.download" "${WAGGLE_BIN_DIR}/${name}"
    done

    # ensure permissions and links are correct
    for name in $SES_TOOLS; do
        chmod +x "${WAGGLE_BIN_DIR}/${name}-${arch}"
        ln -f "${WAGGLE_BIN_DIR}/${name}-${arch}" "${WAGGLE_BIN_DIR}/${name}"
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

# NOTE (Yongho): this cleans up the old iio/raingauge plugins to ensure
#                the new ones can use the serial device
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
      --force-to-update \
      waggle/plugin-iio:0.7.0 -- \
      --filter bme680 \
      --node-publish-interval 30 \
      --beehive-publish-interval 30 \
      --cache-seconds 30

    echo "running iio plugin for bme280..."
    pluginctl deploy --name wes-iio-bme280 \
      --type daemonset \
      --privileged \
      --selector resource.bme280=true \
      --resource request.cpu=50m,request.memory=30Mi,limit.memory=30Mi \
      --force-to-update \
      waggle/plugin-iio:0.6.0 -- \
      --filter bme280
    
    echo "running iio plugin for raingauge"
    pluginctl deploy --name wes-raingauge \
      --type daemonset \
      --privileged \
      --selector resource.raingauge=true \
      --resource request.cpu=50m,request.memory=30Mi,limit.memory=30Mi \
      --force-to-update \
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

# determine_rabbitmq_upgrade_path: Determines the upgrade path between two RabbitMQ versions
# Returns a space-separated list of intermediate versions, or empty string if direct upgrade
determine_rabbitmq_upgrade_path() {
    echo "DEBUG: ENTERING determine_rabbitmq_upgrade_path function"
    local current_ver="$1"
    local target_ver="$2"
    
    echo "DEBUG: determine_rabbitmq_upgrade_path called with current_ver=$current_ver, target_ver=$target_ver"
    
    # Define supported upgrade paths based on RabbitMQ documentation
    # https://www.rabbitmq.com/docs/upgrade
    # From -> To (only one hop is supported)
    declare -A supported_paths
    supported_paths["3.7.18"]="3.8.x"
    supported_paths["3.8.x"]="3.9.x"
    supported_paths["3.9.x"]="3.10.x"
    supported_paths["3.10.x"]="3.11.x"
    supported_paths["3.11.18"]="3.12.x"
    supported_paths["3.12.x"]="3.13.x"
    supported_paths["3.13.x"]="4.0.x"
    supported_paths["3.13.x"]="4.1.x"
    supported_paths["4.0.x"]="4.1.x"
    
    # Determine current version pattern
    local current_pattern=""
    if [[ "$current_ver" =~ ^3\.7\. ]]; then
        current_pattern="3.7.18"
    elif [[ "$current_ver" =~ ^3\.8\. ]]; then
        current_pattern="3.8.x"
    elif [[ "$current_ver" =~ ^3\.9\. ]]; then
        current_pattern="3.9.x"
    elif [[ "$current_ver" =~ ^3\.10\. ]]; then
        current_pattern="3.10.x"
    elif [[ "$current_ver" =~ ^3\.11\. ]]; then
        current_pattern="3.11.18"
    elif [[ "$current_ver" =~ ^3\.12\. ]]; then
        current_pattern="3.12.x"
    elif [[ "$current_ver" =~ ^3\.13\. ]]; then
        current_pattern="3.13.x"
    elif [[ "$current_ver" =~ ^4\.0\. ]]; then
        current_pattern="4.0.x"
    fi
    
    echo "DEBUG: current_pattern determined as: $current_pattern"
    
    # Check if direct upgrade is supported
    if [ -n "$current_pattern" ] && [ -n "${supported_paths[$current_pattern]}" ]; then
        local target_pattern="${supported_paths[$current_pattern]}"
        echo "DEBUG: target_pattern from supported_paths: $target_pattern"
        
        # Check if target version matches the supported upgrade path
        if [[ "$target_ver" =~ ^${target_pattern//x/} ]]; then
            # Direct upgrade is supported
            echo "DEBUG: Direct upgrade supported from $current_pattern to $target_pattern"
            echo ""
            return 0
        fi
        
        # Need to find intermediate path
        local intermediate_versions=""
        local current_step="$current_pattern"
        echo "DEBUG: Starting path building from current_step: $current_step"
        
        while [ -n "$current_step" ]; do
            echo "DEBUG: Loop iteration - current_step: $current_step"
            local next_step="${supported_paths[$current_step]}"
            echo "DEBUG: next_step from supported_paths: $next_step"
            if [ -n "$next_step" ]; then
                # Convert pattern to major.minor version for intermediate step
                if [[ "$next_step" =~ ^3\. ]]; then
                    case "$next_step" in
                        "3.8.x") intermediate_versions="$intermediate_versions 3.8" ;;
                        "3.9.x") intermediate_versions="$intermediate_versions 3.9" ;;
                        "3.10.x") intermediate_versions="$intermediate_versions 3.10" ;;
                        "3.11.x") intermediate_versions="$intermediate_versions 3.11" ;;
                        "3.12.x") intermediate_versions="$intermediate_versions 3.12" ;;
                        "3.13.x") intermediate_versions="$intermediate_versions 3.13" ;;
                    esac
                elif [[ "$next_step" =~ ^4\. ]]; then
                    case "$next_step" in
                        "4.0.x") intermediate_versions="$intermediate_versions 4.0" ;;
                        "4.1.x") intermediate_versions="$intermediate_versions 4.1" ;;
                    esac
                fi
                
                # Check if we've reached the target pattern
                if [[ "$target_ver" =~ ^${next_step//x/} ]]; then
                    # We've found the target pattern, stop here
                    # Don't add this step to intermediate versions since it's the target
                    break
                fi
                
                current_step="$next_step"
            else
                break
            fi
        done
        
        # Return intermediate versions (trimmed)
        local final_result=$(echo "$intermediate_versions" | sed 's/^ *//;s/ *$//')
        echo "DEBUG: Final intermediate_versions result: '$final_result'"
        echo "$final_result"
        return 0
    fi
    
    # No supported path found
    echo "DEBUG: No supported path found for current_ver=$current_ver, target_ver=$target_ver"
    return 1
}

# upgrade_rabbitmq_to_version: Upgrades RabbitMQ to a specific version
upgrade_rabbitmq_to_version() {
    local target_ver="$1"
    
    echo "Upgrading to version $target_ver..."
    waggle_log info "RabbitMQ upgrading to version $target_ver"
    
    kubectl set image statefulset/wes-rabbitmq wes-rabbitmq="rabbitmq:${target_ver}-management-alpine"
    echo "Waiting for $target_ver rollout to complete..."
    
    if ! kubectl rollout status statefulset/wes-rabbitmq; then
        echo "Error: $target_ver rollout failed"
        waggle_log err "RabbitMQ $target_ver rollout failed"
        return 1
    fi
    
    # Wait for RabbitMQ to be running
    echo "Waiting for RabbitMQ to be running after $target_ver upgrade..."
    if ! kubectl wait --for=condition=Ready pod/wes-rabbitmq-0 --timeout=600s; then
        echo "Error: RabbitMQ not ready after $target_ver upgrade"
        waggle_log err "RabbitMQ not ready after $target_ver upgrade"
        return 1
    fi
    
    # Enable feature flags for next upgrade
    sleep 1m
    echo "Enabling feature flags for next upgrade..."
    kubectl exec wes-rabbitmq-0 -- rabbitmqctl enable_feature_flag all || true
    
    echo "Successfully upgraded to $target_ver"
    return 0
}

# update_rabbitmq_version: Main function to handle RabbitMQ version upgrades
# This function handles:
# - Upgrades following RabbitMQ's official supported upgrade paths
# - Only one-hop upgrades (e.g., 3.8.x -> 3.9.x, 3.13.x -> 4.0.x)
# - Automatic backup creation before major upgrades
# - Feature flag enabling for compatibility
# - Rollout verification and health checks
# - Comprehensive logging via waggle_log
update_rabbitmq_version() {
    echo "checking if RabbitMQ version upgrade is needed..."
    waggle_log info "starting RabbitMQ version upgrade check"
    
    # Get current running version
    if ! current_version=$(kubectl get statefulset wes-rabbitmq -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null); then
        echo "RabbitMQ StatefulSet not found, skipping version upgrade"
        waggle_log info "RabbitMQ StatefulSet not found, skipping version upgrade"
        return 0
    fi
    
    # Extract version from image (e.g., "rabbitmq:3.8.11-management-alpine" -> "3.8.11")
    current_ver=$(echo "$current_version" | sed 's/rabbitmq://' | sed 's/-management-alpine//')
    
    # Validate current version format
    if ! echo "$current_ver" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
        echo "Error: Invalid current version format: $current_ver"
        waggle_log err "Invalid RabbitMQ current version format: $current_ver"
        return 1
    fi
    
    # Get target version from the YAML file
    target_ver=$(grep "image: rabbitmq:" wes-rabbitmq.yaml | sed 's/.*rabbitmq://' | sed 's/-management-alpine//')
    
    # Validate target version format
    if ! echo "$target_ver" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
        echo "Error: Invalid target version format: $target_ver"
        waggle_log err "Invalid RabbitMQ target version format: $target_ver"
        return 1
    fi
    
    if [ "$current_ver" = "$target_ver" ]; then
        echo "RabbitMQ is already at target version $target_ver"
        waggle_log info "RabbitMQ already at target version $target_ver"
        return 0
    fi
    
    echo "RabbitMQ version upgrade needed: $current_ver -> $target_ver"
    waggle_log info "RabbitMQ version upgrade needed: $current_ver -> $target_ver"
    
    # Check if this is a downgrade (not supported)
    local current_major=$(echo "$current_ver" | cut -d. -f1)
    local current_minor=$(echo "$current_ver" | cut -d. -f2)
    local target_major=$(echo "$target_ver" | cut -d. -f1)
    local target_minor=$(echo "$target_ver" | cut -d. -f2)
    
    if [ "$current_major" -gt "$target_major" ] || ([ "$current_major" -eq "$target_major" ] && [ "$current_minor" -gt "$target_minor" ]); then
        echo "Error: Downgrading RabbitMQ from $current_ver to $target_ver is not supported"
        waggle_log err "RabbitMQ downgrade not supported: $current_ver -> $target_ver"
        return 1
    fi
    
    # Ensure RabbitMQ is running before attempting upgrade
    echo "Ensuring RabbitMQ is running..."
    if ! kubectl wait --for=condition=ready pod/wes-rabbitmq-0 --timeout=60s; then
        echo "Error: RabbitMQ is not ready, cannot proceed with upgrade"
        waggle_log err "RabbitMQ is not ready, cannot proceed with upgrade"
        return 1
    fi
    
    # Backup data before major upgrades
    echo "Creating backup of RabbitMQ data..."
    waggle_log info "Creating backup of RabbitMQ data"
    
    # Check available disk space (need at least 1GB free)
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # 1GB in KB
        echo "Warning: Low disk space available (${available_space}KB), backup may fail"
        waggle_log warn "Low disk space for RabbitMQ backup: ${available_space}KB"
    fi
    
    backup_file="/var/backups/rabbitmq-data-$(date +%F).tar.gz"
    if ! kubectl exec wes-rabbitmq-0 -- tar czf /tmp/rabbitmq-data.tar.gz /var/lib/rabbitmq/mnesia; then
        echo "Error: Failed to create backup, stopping upgrade..."
        waggle_log err "Failed to create RabbitMQ backup, stopping upgrade"
        return 1
    fi
    
    if ! kubectl cp wes-rabbitmq-0:/tmp/rabbitmq-data.tar.gz "$backup_file"; then
        echo "Error: Failed to copy backup to host, stopping upgrade..."
        waggle_log err "Failed to copy RabbitMQ backup to host, stopping upgrade"
        return 1
    fi
    
    echo "Backup created: $backup_file"
    waggle_log info "RabbitMQ backup created: $backup_file"
    
    # Enable feature flags for upgrade
    echo "Enabling feature flags for upgrade..."
    if ! kubectl exec wes-rabbitmq-0 -- rabbitmqctl enable_feature_flag all; then
        echo "Warning: Failed to enable feature flags, continuing with upgrade..."
        waggle_log warn "Failed to enable RabbitMQ feature flags, continuing with upgrade"
    fi
    
    # Verify feature flags are enabled
    echo "Verifying feature flags..."
    kubectl exec wes-rabbitmq-0 -- rabbitmqctl -q --formatter pretty_table list_feature_flags || true
    echo "DEBUG: Feature flags verification completed"
    
    # Determine upgrade path
    echo "Determining upgrade path..."
    echo "DEBUG: About to call determine_rabbitmq_upgrade_path with current_ver=$current_ver, target_ver=$target_ver"
    upgrade_path=$(determine_rabbitmq_upgrade_path "$current_ver" "$target_ver")
    echo "DEBUG: determine_rabbitmq_upgrade_path returned: $upgrade_path"
    
    local exit_code=$?
    echo "DEBUG: determine_rabbitmq_upgrade_path exit code: $exit_code"
    if [ $exit_code -ne 0 ]; then
        echo "Error: No supported upgrade path found from $current_ver to $target_ver"
        waggle_log err "No supported RabbitMQ upgrade path found: $current_ver -> $target_ver"
        return 1
    fi
    
    # Execute upgrades
    if [ -n "$upgrade_path" ]; then
        echo "Will upgrade through intermediate versions: $upgrade_path"
        waggle_log info "RabbitMQ will upgrade through intermediate versions: $upgrade_path"
        
        # Upgrade through intermediate versions
        for version in $upgrade_path; do
            if ! upgrade_rabbitmq_to_version "$version"; then
                echo "Error: Failed to upgrade to intermediate version $version"
                return 1
            fi
        done
    else
        echo "Direct upgrade path available"
        waggle_log info "RabbitMQ direct upgrade path available"
    fi
    
    # Finally upgrade to target version
    if ! upgrade_rabbitmq_to_version "$target_ver"; then
        echo "Error: Failed to upgrade to target version $target_ver"
        return 1
    fi
    
    # Verify the upgrade was successful
    echo "Verifying upgrade was successful..."
    if ! new_version=$(kubectl get statefulset wes-rabbitmq -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null); then
        echo "Warning: Could not verify new version"
        waggle_log warn "Could not verify RabbitMQ new version"
    else
        new_ver=$(echo "$new_version" | sed 's/rabbitmq://' | sed 's/-management-alpine//')
        if [ "$new_ver" = "$target_ver" ]; then
            echo "Upgrade verification successful: RabbitMQ is now running version $new_ver"
            waggle_log info "RabbitMQ upgrade verification successful: now running version $new_ver"
        else
            echo "Warning: Upgrade verification failed. Expected: $target_ver, Got: $new_ver"
            waggle_log warn "RabbitMQ upgrade verification failed. Expected: $target_ver, Got: $new_ver"
        fi
    fi
    
    echo "RabbitMQ version upgrade completed successfully"
    waggle_log info "RabbitMQ version upgrade completed successfully: $current_ver -> $target_ver"
}

update_wes() {
    echo "updating wes"

    echo "generating wes configs"

    mkdir -p configs configs/rabbitmq configs/upload-agent
    # make all config directories private
    find configs -type d | xargs -r chmod 700

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
    # TODO unify how this is done for various node settings rather than it being a one off for the shovel.
    if [ -e configs/no-rabbitmq-shovel ]; then
        echo "rabbitmq shovel is disabled"
        cat > configs/rabbitmq/enabled_plugins <<EOF
[rabbitmq_prometheus,rabbitmq_management,rabbitmq_management_agent,rabbitmq_auth_mechanism_ssl,rabbitmq_mqtt].
EOF
    else
        echo "rabbitmq shovel is enabled"
        cat > configs/rabbitmq/enabled_plugins <<EOF
[rabbitmq_prometheus,rabbitmq_management,rabbitmq_management_agent,rabbitmq_auth_mechanism_ssl,rabbitmq_shovel,rabbitmq_shovel_management,rabbitmq_mqtt].
EOF
    fi

    cat > configs/rabbitmq/rabbitmq.conf <<EOF
# server config
listeners.tcp.default = 5672

# management config
management.load_definitions = /etc/rabbitmq/definitions.json
management.tcp.ip   = 0.0.0.0
management.tcp.port = 15672

# disable logging to file to prevent runaway disk usage and log to console instead
log.file = false
log.console = true

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
                "reconnect-delay": 60,
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

    # NOTE(YK) This ensures the namespace exists before the wes-plugin-account creates the account
    # under the namespace
    echo "creating ses namespace for scheduler"
    kubectl apply -f wes-plugin-k3s-namespace.yaml

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
#   - cadvisor-exporter.yaml
  - jetson-exporter.yaml
#   - dcgm-exporter.yaml
#   - nvidia-device-plugin.yaml
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
  - wes-update-waggle-ssh-keys.yaml
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

    echo "performing one-time operation - cleaning up performance measurements"
    # NOTE(Yongho) the performance exporters seem to stress the wes-node-influxdb too much
    # we disable them until we know how to configure them properly
    kubectl delete -f cadvisor-exporter.yaml || true
    kubectl delete -f jetson-exporter.yaml || true
    kubectl delete -f dcgm-exporter.yaml || true
    kubectl delete -f nvidia-device-plugin.yaml || true

    echo "deploying wes stack"
    # NOTE(sean) this is split as its own thing as the version of kubectl (v1.20.2+k3s1) we were using
    # when this was added didn't seem to support nesting other kustomization dirs as resources.
    # i'm deploying this first, to ensure to influxdb pvc issue doesn't stop this from running
    kubectl apply -k wes-app-meta-cache
    # NOTE(Joe) this is a work-around until all nodes are upgraded to v1.25.x
    # see: https://kubernetes.io/docs/reference/using-api/deprecation-guide/#v1-25
    k3s_minor_version=$(kubectl version -o json | jq -r .serverVersion.minor)
    if [[ $k3s_minor_version -ge 25 ]]; then
        kubectl apply -k .
    else
        echo "perform backwards compatible changes - support old kubectl (v1.20.x)"
        kubectl kustomize | sed -e 's:batch/v1:batch/v1beta1:' | kubectl apply -f -
    fi

    # manage chirpstack deployment based on node manifest
    if jq -e '.sensors[] | select(.name == "lorawan")' /etc/waggle/node-manifest-v2.json > /dev/null; then
        kubectl apply -k wes-chirpstack
    else
        kubectl delete -k wes-chirpstack 2> /dev/null || true
    fi

    echo "cleaning untagged / broken images"
    # wait a moment before checking for images
    sleep 10
    k3s crictl images | awk '$2 ~ /<none>/ {print $3}' | xargs -r k3s crictl rmi || true
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

update_influxdb_retention() {
    echo "updating influxdb retention..."
    if ./debug/update-influxdb-retention.py 2d; then
        echo "successfully updated influxdb retention"
    else
        echo "failed to update influxdb retention"
    fi
}

delete_stuck_pods() {
    # sean: I'm temporarily putting a general fix to clean up and restart pods which aren't
    # working correctly. we should make the specific recovery more precise later.
    #
    # As some examples, I've seen things like wes-app-meta-cache-0 stuck in Completed and the
    # IIO daemonsets stuck until their pod was restarted.
    # 
    # I also clean up kube-system as I've seen cases where coredns or local-path-provisioner
    # are stuck and this prevents other pods from starting.
    echo "cleaning up stuck pods."
    delete_stuck_pods_ns kube-system
    delete_stuck_pods_ns default
    echo "finished cleaning up stuck pods."

    echo "cleaning up stuck terminating pods."
    delete_stuck_terminating_pods_ns kube-system
    delete_stuck_terminating_pods_ns default
    echo "finished cleaning up stuck terminating pods."
}

delete_stuck_pods_ns() {
    ns="${1}"

    echo "cleaning up pods in namespace ${ns}"
    if kubectl -n "${ns}" get pod | awk 'NR > 1 && !/Running/ && !/Pending/ && !/ContainerCreating/ && !/Terminating/ {print $1}' | timeout 90 xargs -r kubectl -n "${ns}" delete pod; then
        echo "finished cleaning up pods in namespace ${ns}"
    else
        echo "error when cleaning up pods in namespace ${ns}"
    fi
}

# HACK(sean) This is a temporary hack to clean up pods which are stuck in Terminating for a
# long time (~1h intervals between when this script is run). It also assumes we don't run this
# more often than every minute, in order to allow to 60s termination grace period to finish.
#
# The plan is to move this and much of the general self healing logic into a node agent.
delete_stuck_terminating_pods_ns() {
    ns="${1}"
    f="/tmp/terminating-pods-${ns}"
    flast="/tmp/terminating-pods-last-${ns}"

    kubectl -n "${ns}" get pod | awk '/Terminating/ {print $1}' > "${f}"

    if [ -f "${flast}" ]; then
        echo "force cleaning up stuck terminating pods in namespace ${ns}."
        if sort "${f}" "${flast}" | uniq -d | xargs -r kubectl -n "${ns}" delete pod --force; then
            echo "finished force cleaning up stuck terminating pods in namespace ${ns}."
        else
            echo "error force cleaning up stuck terminating pods in namespace ${ns}."
        fi
    fi

    mv "${f}" "${flast}"
}

restart_bad_meta_init_pods() {
    # sean: For some reason, the IIO and raingauge pods (maybe more?) seem to end up starting even when their init container
    # which should block until they register them with the app meta cache. We should look into what's happening.
    #
    # In the mean time, I'm simply checking the logs for rejected messages and restarting the required services.
    if ! logs=$(kubectl logs --since=300s -l app=wes-data-sharing-service); then
        echo "failed to get wes-data-sharing-service logs"
        return
    fi
    if grep -q -m1 'reject.*bme280' <<< "${logs}"; then
        kubectl delete pod -l app=wes-iio-bme280
    fi
    if grep -q -m1 'reject.*bme680' <<< "${logs}"; then
        kubectl delete pod -l app=wes-iio-bme680
    fi
    if grep -q -m1 'reject.*raingauge' <<< "${logs}"; then
        kubectl delete pod -l app=wes-raingauge
    fi
}

clean_manifestv2_cm() {
    echo "cleaning up waggle-node-manifest-v2 configmaps"
    kubectl get cm -o name | grep waggle-node-manifest-v2- | head -n -3 | xargs -r kubectl delete
}

# clean_slash_run_tempfs removes the cache entries in /run/udev/data.
# Those entries are Kubernetes slices by cgroup, for example,
# '+cgroup:anon_vma_chain(1884686:kubepods-burstable-podacfe9bf7_3e09_451b_ab91_e6205e525966.slice:cri-containerd:0c087b2c26f6167d348aeb5d59e922cf07c5bf3cb4189099645e45105c97d115)'
# TODO (Yongho): If the node has additional devices such as NXagent or RPi, we will need to 
#                run this command on the devices as well.
clean_slash_run_tempfs() {
    echo "cleaning /run/udev/data by udevadm info -c"
    udevadm info -c
    echo "attempting to perform the same on NXagent if exists"
    ssh ws-nxagent -x "udevadm info -c"
}

waggle_log info "started updating wes"
cd $(dirname $0)

# Perform k3s health check and recovery
if ! output=$(kubectl get nodes 2>&1); then
    waggle_log err "k3s is stuck with error: ${output}"
    waggle_log info "attempting to restart k3s..."
    if systemctl restart k3s; then
        waggle_log info "k3s restarted sucessfully!"
    else
        waggle_log err "k3s failed to restart!"
    fi
fi

# Scrape system metrics.
waggle_log info "starting scraping system metrics..."
if timeout 300 ./debug/scrape-system-metrics.py; then
    waggle_log info "finished scraping system metrics!"
else
    waggle_log err "failed to scrape system metrics!"
fi

# Prune old RabbitMQ and Upload Agent configs.
kubectl get secret | grep wes-rabbitmq-config | head -n -3 | awk '{print $1}' | xargs --no-run-if-empty kubectl delete secret
kubectl get secret | grep wes-upload-agent-config | head -n -3 | awk '{print $1}' | xargs --no-run-if-empty kubectl delete secret

delete_stuck_pods
restart_bad_meta_init_pods
cleanup_old_iio_raingauge
update_wes_tools
update_node_secrets
update_node_manifest_v2
update_data_config
update_rabbitmq_version
update_wes_plugins
update_wes
update_influxdb_retention
clean_manifestv2_cm
clean_slash_run_tempfs
waggle_log info "finished updating wes"
