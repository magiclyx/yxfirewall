#!/bin/bash

INTRA='enp0s8'
INTER='enp0s17'

if [ $(id -u) -ne 0 ]; then
  echo "Must run in root"
  exit 1
fi

function yx_noti() {
    local blue=$(tput setaf 4)
    local reset=$(tput sgr0)
    
    (>&1 echo "${blue}${1}${reset}")
}

function yx_logcmd()
{
  local start=$(date +%s)
	$@
	local exit_code=$?
	echo >&2 "took ~$(($(date +%s)-${start})) seconds. exited with ${exit_code}"
	return $exit_code
}


yx_noti 'li -l'

exit 0

# check sysctl option
echo 'check sysctl setting...'
sudo sysctl -p

# launch iptables and set iptables service start on launch
#echo '[iptable] Setup iptables service...'
#systemctl start iptables.service
#systemctl enable iptables.service

# clear
echo 'Clear all settings ....'
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X
iptables -Z
iptables -t nat -Z

# base setting
echo 'DROP input ...'
iptables -P INPUT DROP
echo 'DROP output ...'
iptables -P OUTPUT DROP
echo 'Drop forward ...'
iptables -P FORWARD DROP


# disable ping
# 因为INPUT 和 OUTPUT 的Default都是DROP
# 如果没添加其他规则的情况下，不用设置
echo 'disable ping ...'
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
iptables -A OUTPUT -p icmp --icmp-type echo-reply -j DROP


# set dns
# 这个不需要设置
# 如果设置，客户端DNS的IP好像必须设置成一样的
# sudo iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to 1.1.1.1

# set nat
echo 'Set nat rule ...'
# 允许初始网络包
iptables -A FORWARD -o enp0s17 -i enp0s8 -m conntrack --ctstate NEW -j ACCEPT
# 允许已经建立链接的网络包
#sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o enp0s17 -i enp0s8 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o enp0s8 -i enp0s17 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# 设置NAT
iptables -t nat -A POSTROUTING -o enp0s17 -j MASQUERADE


# debug
echo 'Add a log record droped INPUT package'
iptables -N LOGGING
iptables -A INPUT -j LOGGING
iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables INPUT Packet Dropped:" --log-level 7
iptables -A LOGGING -j DROP


if [ ! -d /etc/myrule ]; then
  mkdir -p /etc/myrule
fi

# save current config
iptables-save > /etc/myrule/iptables.rules

# add script
echo "#!/bin/bash\niptables-restore < /etc/myrule/iptables.rules" > /etc/network/if-pre-up.d/nat.sh

