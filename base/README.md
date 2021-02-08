
## Create new base image waggle/waggle-node

```bash

./create_release.sh <VERSION>

```


## Upload


Automated upload like below did not work for me. Unless you figure out how to make it work, please upload the box manually via browser to vagrant cloud.

```bash

# option 1) CLI
vagrant cloud provider upload waggle/waggle-node virtualbox 1.0.1 ./waggle-node.box

# option 2) curl

# get upload_path
export VERSION=1.0.0
export VAGRANT_TOKEN=    # get token from https://app.vagrantup.com/session/refresh
curl "https://vagrantcloud.com/api/v1/box/waggle/waggle-node/version/${VERSION}/provider/virtualbox/upload?access_token=${VAGRANT_TOKEN}"

curl -X PUT --upload-file foo.box ${UPLOAD_PATH}


```


reference: https://www.vagrantup.com/vagrant-cloud/boxes/create

