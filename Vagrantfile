# -*- mode: ruby -*-
# vi: set ft=ruby :


# Env variable TZ is optional
timezone = ENV["TZ"]


Vagrant.configure("2") do |config|

  config.vm.box = "waggle/waggle-node"
  config.vm.box_version = "0.0.9"

  config.vm.hostname = "waggle-node"
  config.vm.network "private_network", ip: "10.31.81.10"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    # enable usb passthrough (optional)
    # vb.customize ["modifyvm", :id, "--usb", "on"]
    # vb.customize ["modifyvm", :id, "--usbxhci", "on"]
    # VBoxManage controlvm :id webcam attach
  end


  config.vm.provision "config", type: "ansible" do |ansible|
    ansible.playbook = "ansible/waggle_config.yml"
    ansible.compatibility_mode = "2.0"
    ansible.extra_vars = {
      beekeeper_registration_host: "10.0.2.2" ,  # used in /etc/waggle/config.ini
      beekeeper_registration_port: "20022" ,  # used in /etc/waggle/config.ini
      node_id: "0000000000000001" ,
      timezone: timezone
    }
  end



end
