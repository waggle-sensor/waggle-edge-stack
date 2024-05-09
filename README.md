# Waggle Edge Stack

The Waggle Edge Stack provides the core services which support running AI@Edge.

The bulk of this repo consists of the [Kubernetes files](./kubernetes/) and scripts required to deploy the stack.
_We are actively working on simplifying the steps required to deploy the stack. In the next couple months, we plan to make this easy to deploy in a standalone mode on a generic Linux machine, Jetson Nano, Raspberry Pi 4, etc._

## Common Tasks

* Update WES on a node: `/opt/waggle-edge-stack/kubernetes/update-stack.sh`
* Delete WES on a node: `/opt/waggle-edge-stack/kubernetes/delete-stack.sh`
