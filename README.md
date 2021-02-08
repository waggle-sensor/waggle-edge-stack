# waggle-edge-stack


This repository contains:

- kubernetes resource files for the waggle edge stack
- ansible playbooks for provisioning of k3s and the waggle edge stack
- a Vagrantfile that uses ansible to deploy the full waggle edge stack onto an ubuntu VM


# Ansible files

Ansible playbooks are used to a) create an waggle-node image with all required software and, b) to configure the image after the first boot. The playbooks used in the vagrant environment are the same as used later in production deployments of waggle nodes in the field.


# Vagrant deployment

The vagrant deployment mechanism is intended mainly for creation of a local testing environment.


Requirements:
  - [Vagrant](https://www.vagrantup.com/downloads)
  - [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
  - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-ansible-with-pip)


Useful commands:
```bash
vagrant up

vagrant ssh


vagrant provison # e.g. to test changes to playbooks
```


Optionally: vagrant scp
```bash
vagrant plugin install vagrant-scp
vagrant scp <some_local_file_or_dir> [vm_name]:<somewhere_on_the_vm>
```

## Accessing sensor hardware


For access to USB devices from within the VirtualBox VM please install the VirtualBox Extension Pack:

[VirtualBox](https://www.virtualbox.org/wiki/Downloads)

Also modify the Vagrantfile to enable usb passthrough.



# Advanced: Run beekeeper and connect vagrant waggle node

```bash
cd ~/git/
git clone https://github.com/waggle-sensor/waggle-edge-stack.git
git clone https://github.com/waggle-sensor/beekeeper.git
cd beekeeper

./init-keys.sh new # or ./init-keys.sh test

# start beekeeper
docker-compose up -d

# create registration key (1500 minutes valid)
cd bk-config
./create_client_files.sh 10.0.2.2 20022 +1500m

# copy registration key
cp known_hosts register.pem register.pem-cert.pub ~/git/waggle-edge-stack/ansible/private/

# start vagrant waggle node
cd ~/git/waggle-edge-stack
vagrant up
vagrant ssh
sudo -i
waggle-list-services
```


## Reverse ssh tunnel

To access vagrant via reverse ssh tunnel from within beekeeper:

```bash
docker exec -it beekeeper_bk-sshd_1 /bin/bash
ssh -o 'ProxyCommand=socat UNIX:/home_dirs/ep-0000000000000001/rtun.sock -' vagrant@foo
#password: vagrant
```
