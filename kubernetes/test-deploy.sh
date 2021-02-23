#!/bin/bash

# cp ~/waggle/waggle-beehive-v2/pki-tools/node-0000000000000001.tar.gz .
tar xzvf node-0000000000000001.tar.gz
mv *.pem ca.pub ssh-key* /etc/waggle

export WAGGLE_NODE_ID=0000000000000001
export WAGGLE_BEEHIVE_HOST=10.31.81.200
export WAGGLE_BEEHIVE_RABBITMQ_HOST=10.31.81.200
export WAGGLE_BEEHIVE_RABBITMQ_PORT=30000
export WAGGLE_BEEHIVE_UPLOAD_HOST=10.31.81.200
export WAGGLE_BEEHIVE_UPLOAD_PORT=30002

./deploy-stack.sh

./run-plugin.sh waggle/plugin-test-pipeline:0.0.3
