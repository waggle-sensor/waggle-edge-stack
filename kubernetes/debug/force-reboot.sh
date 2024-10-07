#!/bin/bash

# Sometimes "reboot" and "shutdown -r now" do not work and return
# an error in systemd. In this case a force system reboot helps the system reboot.

while true; do
    read -p "Do you really want to force reboot the system?" yn
    case $yn in
        [Yy]* ) systemctl --force --force reboot; break;;
        [Nn]* ) echo "Cancelled"; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

