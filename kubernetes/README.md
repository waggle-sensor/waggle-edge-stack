# Waggle Edge Stack Deployment Guide

This guide shows you how to deploy the Waggle Edge Stack (WES) and configure to work with a Beehive.

## 1. Install Dependencies

We assume you're working on an Ubuntu 18 or 20 based system with a Kubernetes cluster running.

If you're new to Kubernetes and would like to get started quickly, we recommend using [k3s](https://k3s.io).

## 2. Beehive Config and Credential Files

Before running the deploy script, we need to configure WES to talk to the right Beehive endpoints. Please tweak the following configuration to match your Beehive's setup.

```sh
export WAGGLE_NODE_ID=0000000000000001
export WAGGLE_BEEHIVE_HOST=10.31.81.200
export WAGGLE_BEEHIVE_RABBITMQ_HOST=10.31.81.200
export WAGGLE_BEEHIVE_RABBITMQ_PORT=30000
export WAGGLE_BEEHIVE_UPLOAD_HOST=10.31.81.200
export WAGGLE_BEEHIVE_UPLOAD_PORT=30002
```

Next, you'll need to place your credential files in `/etc/waggle`. These should consist of:
* `cacert.pem`
* `cert.pem`
* `key.pem`
* `ca.pub`
* `ssh-key`
* `ssh-key.pub`
* `ssh-key-cert.pub`

*ToDo: Add reference to how to generates or get these from Beehive / Beekeeper.*

## 3. Deploy Stack

Now run `./deploy-stack.sh`. This will automatically set up all your Kubernetes resources.
