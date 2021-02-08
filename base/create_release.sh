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

set -x

vagrant up

vagrant package --output waggle-node-${VERSION}.box
vagrant destroy --force



export BOXPATH=`pwd`
sed -e "s/{{VERSION}}/${VERSION}/" -e "s'{{BOXPATH}}'${BOXPATH}'" ./metadata.json_template > ./metadata-${VERSION}.json


vagrant box add waggle/waggle-node ./metadata-${VERSION}.json

vagrant box list

