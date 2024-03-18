# check sysctl option
echo 'check sysctl setting...'
sysctl -p

# launch iptables and set iptables service start on launch
#echo '[iptable] Setup iptables service...'
#systemctl start iptables.service
#systemctl enable iptables.service

# clear
echo '[iptable] Clear old setting ....'
iptables -F
iptables -X
iptables -Z

# allow ssh
#echo '[iptable] ACCEPT ssh ...'
#iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# base setting
#echo '[iptable] Drop input ...'
#iptables -P INPUT DROP
#echo '[iptable] Accept output ...'
#iptables -P OUTPUT ACCEPT
#echo '[iptable] Drop forward ...'
#iptables -P FORWARD DROP

# allow ping
#echo '[iptable] Accept icmp ...'
#iptables -A INPUT -p icmp -j ACCEPT
# 允许进入的数据包只能是刚刚发出去的数据包的回应
#echo '[iptable] Accept Related package ...'
#iptables -A INPUT -m state -state ESTABLISHED,RELATED -j ACCEPT


# add nat
# 地址转换
echo '[iptable] Set nat ...'
#iptables -t nat -A POSTROUTING -o enp0s8 -s 192.168.56.0/24 -j SNAT --to-source 10.0.2.15
# 动态IP的情况
iptables -t nat -A POSTROUTING -o enp0s8 -s 192.168.56.0/24 -j MASQUERADE
# ADSL的的情况
#iptables -t nat -A POSTROUTING -o ppp0 -s 192.168.56.0/24 -j MASQUERADE


# add forward between interface
iptables -A FORWARD -i enp0s8 -o enp0s17 -j ACCEPT
iptables -A FORWARD -i enp0s17 -o enp0s8 -j ACCEPT


# 保存防火墙规则并重启
#echo '[iptable] Save change ...'
#service iptables save
#echo '[iptable] Restart iptable ...'
#systemctl restart iptables.service






































































































