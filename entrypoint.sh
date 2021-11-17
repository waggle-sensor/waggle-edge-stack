#!/bin/bash

# This entrypoint.sh is only used for the docker image waggle/wes-minimal


set -x
set -e


# create fake kubectl for debugging
echo -e '#!/bin/bash\necho "(this is a dummy) created"' > /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl


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

# start sshd  (usually via systemd)
mkdir -p /var/run/sshd
/usr/sbin/sshd

# registration  (usually via systemd)
waggle-bk-registration.py

# reverse ssh tunnel  (usually via systemd)
waggle-bk-reverse-tunnel.sh