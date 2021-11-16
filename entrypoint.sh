#!/bin/bash

# This entrypoint.sh is only used for the docker image waggle/wes-minimal


set -x
set -e


cd /etc/waggle

# copy files in place so they can be deleted afterwards
cp ./sage_registration-cert.pub_readonly sage_registration-cert.pub
cp ./sage_registration_readonly sage_registration

# prepare ssh_known_hosts
echo '@cert-authority' bk-api $(cat /etc/waggle/beekeeper_ca_key.pub | cut -f 1,2 -d ' ') > /etc/ssh/ssh_known_hosts

# wait for the ssh sever
while ! nc -z bk-sshd 2201; do
  sleep 1
done

# cert-authority above did not work for some reason, thus we add the host server directly:
ssh-keyscan -H -p 2201 bk-sshd >> /etc/ssh/ssh_known_hosts

waggle-bk-registration.py

waggle-bk-reverse-tunnel.sh