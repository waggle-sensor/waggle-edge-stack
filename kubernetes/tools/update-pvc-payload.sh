#!/bin/bash -e

remove_pvc_if_needed() {
    if kubectl get pvc data-wes-rabbitmq-0 | grep 50Gi; then
        echo "pvc already updated"
        return 0
    fi

    if ! kubectl exec -it wes-rabbitmq-0 -- rabbitmqctl list_queues > /tmp/rabbitmqctl_list_queues; then
        echo "could not list queues"
        return 1
    fi

    if ! awk '/to-/ && ($2 > 0) {exit 1}' /tmp/rabbitmqctl_list_queues; then
        echo "live messages in rmq - giving up"
        return 1
    fi

    kubectl delete -f wes-rabbitmq.yaml && kubectl delete pvc data-wes-rabbitmq-0
}

cd /opt/waggle-edge-stack/kubernetes
git reset --hard
git pull

if ! remove_pvc_if_needed; then
    echo "could not remove pvc"
    exit 1
fi

./update-stack.sh
