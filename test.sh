#!/bin/bash
sudo ./firewall start 
sudo ./firewall clear
sudo ./firewall default DROP --all
#sudo ./firewall nat --snat --lan enp0s8 --wan enp0s3
sudo ./firewall nat --snat --from-inter enp0s8 --to-inter enp0s3
sudo ./firewall save

sudo iptables -nvL
sudo iptables -t nat -nvL

#TODO
# log
# DEBUG output 