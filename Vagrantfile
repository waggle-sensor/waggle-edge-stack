# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  #config.vm.box = "hashicorp/bionic64"
  config.vm.box = "ubuntu/focal64"
  config.vm.hostname = "waggle-node"
  config.vm.network "private_network", ip: "10.31.81.10"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    # enable usb passthrough (optional)
    # vb.customize ["modifyvm", :id, "--usb", "on"]
    # vb.customize ["modifyvm", :id, "--usbxhci", "on"]
    # VBoxManage controlvm :id webcam attach
  end

  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "playbook.yml"
  end

  
end
