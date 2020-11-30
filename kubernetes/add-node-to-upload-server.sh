#!/bin/bash

username=node0000000000000001

# add user with no password and unlock account.
# TODO ensure this doesn't introduce any security issues
kubectl exec --stdin --tty deployment/beehive-upload-server -- adduser -D -g "" "$username"
kubectl exec --stdin --tty deployment/beehive-upload-server -- passwd -u "$username"
