#!/bin/bash -e

if ! id "waggle" &>/dev/null; then
    echo "No waggle user found. Skip making dev account"
    exit 1
fi
kubectl apply -k .

mkdir -p /home/waggle/.kube

cat <<EOF > /home/waggle/.kube/config
apiVersion: v1
clusters:
contexts:
current-context:
kind: Config
preferences: {}
EOF

chown waggle:waggle -R /home/waggle/.kube

server=$(kubectl config view -o json | jq -r '.clusters[0].cluster.server')
account_secret_name=$(kubectl get serviceaccount node-dev-svc-account -n dev -o json | jq -r '.secrets[0].name')
ca=$(kubectl get secret -n dev $account_secret_name -o json | jq -r '.data."ca.crt"')
token=$(kubectl get secret -n dev $account_secret_name -o json | jq -r '.data.token' | base64 -d)
(
    export KUBECONFIG=/home/waggle/.kube/config
    kubectl config set-cluster cluster-dev --server=$server
    kubectl config set clusters.cluster-dev.certificate-authority-data "$ca"
    kubectl config set-credentials node-dev-svc-account --token=$token
    kubectl config set-context context-dev --cluster=cluster-dev --user=node-dev-svc-account --namespace dev
    kubectl config use-context context-dev
)