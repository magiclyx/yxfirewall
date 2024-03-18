iptables -t nat -A POSTROUTING -s 192.168.56.0/24 -o enp0s8 -j SNAT --to-source 10.0.2.15

sudo ./nat2.sh nat --lan enp0s8 --wan enp0s17 --log --ping
