#!/bin/bash

# extract and import credentials bundle for node
tar xzvf node-0000000000000001.tar.gz
mv *.pem ca.pub ssh-key* /etc/waggle

# define beehive endpoints
export WAGGLE_NODE_ID=0000000000000001
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_HOST=beehive.honeyhouse.one
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_RABBITMQ_HOST=rabbitmq.honeyhouse.one
export WAGGLE_BEEHIVE_RABBITMQ_PORT=30000
# not actually using subdomain - just as a standin
export WAGGLE_BEEHIVE_UPLOAD_HOST=upload.honeyhouse.one
export WAGGLE_BEEHIVE_UPLOAD_PORT=30002

# deploy everything!!
./deploy-stack.sh