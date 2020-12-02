# -*- mode: ruby -*-
# vi: set ft=ruby :


# Env variable TZ is optional
timezone = ENV["TZ"]


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

    
    ansible.compatibility_mode = "2.0"
    ansible.playbook = "playbook.yml"
    ansible.extra_vars = {
      node_id: "0000000000000001" , 
      beekeeper_registration_host: "10.0.2.2" ,  # used in /etc/waggle/config.ini
      beekeeper_registration_port: "20022" ,  # used in /etc/waggle/config.ini
      timezone: timezone   
    }
  end

   
end
