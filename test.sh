#!/bin/bash
sudo ./firewall.sh nat --lan enp0s8 --wan enp0s3

sudo iptables -nvL
sudo iptables -t nat -nvL
