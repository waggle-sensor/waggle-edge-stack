#!/bin/bash

kubectl run -it --rm --restart=Never -l role=plugin --image=busybox plugin-network-policy-test -- sh -c '
echo "checking for internet connectivity"

while wget http://google.com -O /dev/null; do
    echo "WARNING able to each internet. waiting for network policy to become active..."
    sleep 1
done

echo "network policy ready"
'
