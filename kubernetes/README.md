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

Now run `./deploy-stack.sh`. This will automatically set up all your Kubernetes resources

## 4. Running a Test Plugin

We can use the `run-plugin.sh` command to start a plugin in WES. As an example, we'll run version 0.0.3 of this [test plugin](https://github.com/waggle-sensor/plugin-test-pipeline):

```sh
./run-plugin.sh waggle/plugin-test-pipeline:0.0.3
```

The `run-plugin.sh` accepts a reference to any container image of the form `registry/namespace/image:version`. If not specified, it assumes a container image is in Dockerhub under the `waggle` namespace.
