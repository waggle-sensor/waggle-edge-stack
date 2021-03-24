#!/bin/bash

kubectl apply -f node-0000000000000001.yaml

# define beehive endpoints
export WAGGLE_NODE_ID=0000000000000001
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_HOST=beehive.honeyhouse.one
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_RABBITMQ_HOST=rabbitmq.honeyhouse.one
export WAGGLE_BEEHIVE_RABBITMQ_PORT=49191
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_UPLOAD_HOST=upload.honeyhouse.one
export WAGGLE_BEEHIVE_UPLOAD_PORT=49192

# deploy everything!!
./deploy-stack.sh
