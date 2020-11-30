#!/bin/bash

username=node0000000000000001

# add user with no password and unlock account.
# TODO ensure this doesn't introduce any security issues
kubectl exec --stdin deployment/beehive-upload-server -- sh -s <<EOF
adduser -D -g "" "${username}"
passwd -u "${username}"
EOF
