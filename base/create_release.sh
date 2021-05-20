#!/bin/bash

set -e



if [ $# -eq 0 ] ; then
    echo "Usage: ./create_release.sh <VERSION>"
    exit 1
fi


export VERSION=$1

if [ $(vagrant box list | grep waggle/waggle-node | grep "$VERSION" | wc -l) -ge 1 ] ; then
    echo "Box waggle/waggle-node with version $VERSION already exists"
    exit 1
fi


if [ -e waggle-node-${VERSION}.box ] ; then
    echo "File waggle-node-${VERSION}.box already exists."
    exit 1
fi

set -x

vagrant up

vagrant package --output waggle-node-${VERSION}.box
vagrant destroy --force



export BOXPATH=`pwd`
sed -e "s/{{VERSION}}/${VERSION}/" -e "s'{{BOXPATH}}'${BOXPATH}'" ./metadata.json_template > ./metadata-${VERSION}.json


vagrant box add waggle/waggle-node ./metadata-${VERSION}.json

vagrant box list

set +x

echo ""
echo "Please runs these command:"
echo "vagrant cloud publish --release --force waggle/waggle-node ${VERSION} virtualbox ./metadata-${VERSION}.json"
echo "vagrant cloud provider upload waggle/waggle-node virtualbox ${VERSION} ./waggle-node-${VERSION}.box"
echo ""