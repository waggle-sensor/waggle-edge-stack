#!/usr/bin/env python3
import argparse
import json
import re
import os
import time
import logging
import subprocess

# TODO this should be deprecated and handled as part of our proper declarative config. something like:
# ...
# shovel:
#   host: beehive.nu.edu
#   port: 5671
#

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s', datefmt='%Y/%m/%d %H:%M:%S')

WAGGLE_NODE_ID = os.environ['WAGGLE_NODE_ID']
WAGGLE_BEEHIVE_HOST = os.environ['WAGGLE_BEEHIVE_HOST']

NODE_RABBITMQ_HOST = os.environ.get('NODE_RABBITMQ_HOST', 'rabbitmq-server')
NODE_RABBITMQ_PORT = int(os.environ.get('NODE_RABBITMQ_PORT', 15672))
NODE_RABBITMQ_USERNAME = os.environ.get('NODE_RABBITMQ_USERNAME', 'service')
NODE_RABBITMQ_PASSWORD = os.environ.get('NODE_RABBITMQ_PASSWORD', 'service')

node_uri = (
    f'amqp://{NODE_RABBITMQ_USERNAME}:{NODE_RABBITMQ_PASSWORD}@{NODE_RABBITMQ_HOST}'
)

beehive_username = f'node{WAGGLE_NODE_ID}'

beehive_uri = (
    f'amqps://{beehive_username}@{WAGGLE_BEEHIVE_HOST}:23181'
    '?auth_mechanism=external'
    '&cacertfile=/etc/waggle/cacert.pem'
    '&certfile=/etc/waggle/cert.pem'
    '&keyfile=/etc/waggle/key.pem'
    '&verify=verify_peer'
    '&connect_timeout=60000'
    '&server_name_indication=disable'
    # '&heartbeat=60'
)

configs = {
    'push-to-beehive': {
        'src-uri': node_uri,
        'src-queue': 'to-beehive',
        'dest-uri': beehive_uri,
        'dest-exchange': 'messages',
        'publish-properties': {
            'delivery_mode': 2,
            'user_id': beehive_username,
        },
        'reconnect-delay': 60,
    },
    'pull-from-beehive': {
        'src-uri': beehive_uri,
        'src-queue': f'to-{beehive_username}',
        'dest-uri': node_uri,
        'dest-exchange': 'to-node',
        'publish-properties': {
            'delivery_mode': 2,
        },
        'reconnect-delay': 60,
    },
}

def enable_shovels():
    logging.info('enabling shovels for %s to %s', WAGGLE_NODE_ID, WAGGLE_BEEHIVE_HOST)

    for name, config in configs.items():
        logging.info('enabling shovel %s', name)
        subprocess.check_output([
            'kubectl', 'exec', 'service/rabbitmq-server', '--',
            'rabbitmqctl', 'set_parameter', 'shovel', name, json.dumps(config)
        ])

    logging.info('enabled all shovels')

def disable_shovels():
    logging.info('disabling shovels for %s', WAGGLE_NODE_ID)

    for name in configs.keys():
        logging.info('disabling shovel %s', name)
        subprocess.check_output([
            'kubectl', 'exec', 'service/rabbitmq-server', '--',
            'rabbitmqctl', 'clear_parameter', 'shovel', name
        ])
    logging.info('disabled all shovels')

def status():
    subprocess.check_call(['kubectl', 'exec', 'service/rabbitmq-server', '--', 'rabbitmqctl', 'shovel_status'])

actions = {
    'enable': enable_shovels,
    'disable': disable_shovels,
    'status': status,
}

parser = argparse.ArgumentParser()
parser.add_argument('action', choices=actions.keys())
args = parser.parse_args()
actions[args.action]()
