#!/bin/bash


info_level_buckup=$(sudo ./firewall config --read --key info.level)
sudo ./firewall config --write --key info.level --val debug


sudo ./firewall start
sudo ./firewall clear
sudo ./firewall default DROP --all
sudo ./firewall nat --snat --from-inter enp0s8 --to-inter enp0s3 --log firewall-forward:
sudo ./firewall save --log-input firewall-input-drop:


echo -ne "\n\n"
echo "####################################################################################################"
sudo ./firewall filter --list
echo -ne "\n\n"
sudo ./firewall nat --list


if [ -n "${info_level_buckup}" ]; then
    sudo ./firewall config --write --key info.level --val "${info_level_buckup}"
else
    sudo ./firewall config --remove --key info.level
fi