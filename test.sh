#!/bin/bash


###########################################################
# IP 定义
# 根据需要定义。 它不必被定义就可以工作。
###########################################################

# 无条件丢弃的列表（array）
DENY_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+)
)

# 允许的内网范围 (Array)
LOCAL_NET=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+)
#    \*
#    lo+
)

# 可信主机 (Array）
ALLOW_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+)
)

# 限制信任主机 (Array)
LIMITED_LOCAL_NET=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+)
)


###########################################################
# SNAT 定义
# 根据需要定义。 它不必被定义就可以工作。
###########################################################

SNAT_WAN=enp0s3

# (Array)
SNAT_LAN_LIST=( 
    enp0s8
)


###########################################################
# 端口定义
###########################################################

SSH=22
FTP=20,21
DNS=53
SMTP=25,465,587
POP3=110,995
IMAP=143,993
HTTP=80,443
IDENT=113
NTP=123
MYSQL=3306
NET_BIOS=135,137,138,139,445
DHCP=67,68



###########################################################
# 设置调试日志级别为 Debug, 并保存之前的配置
###########################################################
info_level_buckup=$(sudo ./firewall config --read --key info.level)
sudo ./firewall config --write --key info.level --val debug


###########################################################
# 初始化 Iptables
###########################################################
sudo ./firewall start  # 启动服务
sudo ./firewall clear  # 清空所有规则
sudo ./firewall default DROP --all  # 设置所有规则的默认行为是Drop


###########################################################
# 攻击防护：bad package
###########################################################
sudo ./firewall Server DROP --rule "PKG_SRV" --proto wall-pkg --log  firewall_invalid_package:-

###########################################################
# 攻击防护：stealth scan
###########################################################
sudo ./firewall Server DROP  --rule "PKG_SCAN" --proto wall-scan --log firewall_stealth_scan:-


###########################################################
# 攻击防护：SSH 暴力破解
# 为使用密码认证的服务器准备密码暴力攻击。
# 如果 SSH 服务器开启了密码认证，请取消注释掉以下内容。
#
# TODO 添加禁止SSH-client 的命令。 这个不能用 firewall Client, 会冲突
# TODO 测试 SSH WALL
# TODO ICMP ping 的命令
##################################################
sudo ./firewall Server ACCEPT --proto ssh --rule "SSH_SRV" --ip 10.12.13.2 --log ssh_brute_force:-


###########################################################
# 攻击防护：Ping of Death
###########################################################
#sudo ./firewall Server --proto icmp --rule "ICMP_SRV"

sudo ./firewall filter --list

# sudo iptables -F; sudo iptables -X; sudo iptables -Z
# sudo iptables -F
# sudo iptables -X
# sudo iptables -Z
# sudo iptables -F
# sudo iptables -X
# sudo iptables -Z
# sudo iptables -F
# sudo iptables -X
# sudo iptables -Z


exit 0


###########################################################
# 放弃来自 $DENY_HOSTS 的访问
###########################################################
if [ "${DENY_HOSTS}" ]
then
	for host in "${DENY_HOSTS[@]}";
	do
      sudo ./firewall incoming drop --net "${host}" --log deny_host:limit:1/s
	done
fi

###########################################################
# 攻击防护：隐身扫描
###########################################################
sudo ./firewall filter DROP --rule STEALTH_SCAN --log 'stealth_scan_attack'

# 看似隐身扫描的数据包会跳转到“STEALTH_SCAN”链
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag SYN,ACK SYN,ACK --state NEW
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag ALL NONE

sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag SYN,FIN SYN,FIN
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag SYN,RST SYN,RST
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag ALL SYN,RST,ACK,FIN,URG

sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag FIN,RST FIN,RST
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag ACK,FIN FIN #TODO 这个好像有问题
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag ACK,PSH PSH
sudo ./firewall filter STEALTH_SCAN --rule INPUT --proto tcp --proto-flag ACK,URG URG

###########################################################
# 攻击防护：端口扫描碎片报文、DOS 攻击
# namap -v -sF 等度量
# TODO 这里抛弃了所有碎片, 
###########################################################
# sudo ./firewall incoming ACCEPT --fragment --limit 1000/s
sudo ./firewall incoming DROP --fragment --log 'fragment_packet'

###########################################################
# 攻击防护：Ping of Death
###########################################################
# 10 次 ping 超过每秒 1 次后丢弃
sudo ./firewall filter RETURN --rule PING_OF_DEATH --proto icmp --proto-flag echo-request --limit limit-upto:t_PING_OF_DEATH:1/s:10:srcip:::3000


# # 丢弃超出限制的ICMP
sudo ./firewall filter DROP --rule PING_OF_DEATH --log ping_of_death_attack


# # ICMP跳转到“PING_OF_DEATH”链
sudo ./firewall incoming PING_OF_DEATH --proto icmp --proto-flag echo-request


###########################################################
# 攻击防护：SYN Flood 攻击
# 除了此措施外，您还应该启用 Syn cookie。
###########################################################
# sudo ./firewall rule create --rule 'SYN_FLOOD'
sudo ./firewall filter RETURN --rule SYN_FLOOD --proto tcp --syn --limit limit-upto:t_SYN_FLOOD:200/s:3:srcip:::3000

# 丢弃超过限制的 SYN 报文
sudo ./firewall filter DROP --rule SYN_FLOOD --log syn_flood_attack

# SYN 数据包跳转到 “SYN_FLOOD” 链
sudo ./firewall incoming SYN_FLOOD --proto tcp --syn 


###########################################################
# 攻击防护：IDENT 端口探测
# 标识，以帮助攻击者为未来的攻击做好准备，或使用用户的
# 进行端口勘测，查看系统是否容易受到攻击
# 可能。
# DROP 会减少邮件服务器等的响应，所以 REJECT
###########################################################
sudo ./firewall incoming REJECT --proto tcp --port "${IDENT}" --reject-with tcp-reset


###########################################################
# 攻击防护：SSH 暴力破解
# SSH为使用密码认证的服务器准备密码暴力攻击。
# 每分钟只允许 5 次连接尝试。
# REJECT 而不是 DROP 以防止 SSH 客户端重复重新连接。
# 如果 SSH 服务器开启了密码认证，请取消注释掉以下内容。
###########################################################
sudo ./firewall incoming --proto tcp --syn --port "${SSH}" --limit recent-set:ssh_attack2
sudo ./firewall incoming REJECT-WITH tcp-reset --proto tcp --syn --port "${SSH}" --limit recent-check:ssh_attack:60:5 --log ssh_brute_force:-



###########################################################
# 攻击防护：FTP 暴力破解
# FTP用于密码认证，因此为密码暴力攻击做好了准备。
# 每分钟只允许 5 次连接尝试。
# REJECT 代替 DROP 以防止 FTP 客户端重复重新连接。
# 如果您运行的是 FTP 服务器，请取消注释以下内容。
###########################################################
sudo ./firewall incoming --proto tcp --syn --port "${FTP}" --limit recent-set:ftp_attack
sudo ./firewall incoming REJECT-WITH tcp-reset --proto tcp --syn --port "${FTP}" --limit recent-check:ftp_attack:60:5 --log ftp_brute_force:-


###########################################################
# 发往所有主机（广播地址、组播地址）的数据包将被丢弃。
###########################################################

BROAD_HOSTS=( # "xxx.xxx.xxx.xxx"
    192.168.1.255
    255.255.255.255
    224.0.0.1
)

if [ "${BROAD_HOSTS}" ]
then
    for ip in "${BROAD_HOSTS[@]}"; do
    sudo ./firewall incoming DROP --ip "${ip}" --log drop_broadcast
    done
fi


###########################################################
# SNAT设置
###########################################################

if [ -n "${SNAT_WAN}" ]  && [ "${SNAT_LAN_LIST}" ]
then
  for lan in "${SNAT_LAN_LIST[@]}"
  do
    sudo ./firewall nat --snat --from-inter "${lan}" --to-inter "${SNAT_WAN}" --log firewall-forward:
  done
fi


###########################################################
# 允许的受信任主机
###########################################################

# 本地网络
# 如果设置了 $LOCAL_NET，则允许与局域网上的其他服务器通信
if [ "${LOCAL_NET}" ];
then
    for net in "${LOCAL_NET[@]}";
    do
        sudo ./firewall incoming ACCEPT --net "${net}"
    done
fi


# 可信主机
# 如果设置了 $ALLOW_HOSTS，则允许与该主机交互
if [ "${ALLOW_HOSTS}" ]
then
    for host in "${ALLOW_HOSTS[@]}";
    do
      sudo ./firewall incoming ACCEPT --net "${host}"
    done
fi

###########################################################
# 来自所有主机的输入 （ANY）
###########################################################

# ICMP：配置 Ping 响应
# iptables -A INPUT -p icmp -j ACCEPT # ANY -> SELF

# HTTP, HTTPS
# iptables -A INPUT -p tcp -m multiport --dports $HTTP -j ACCEPT # ANY -> SELF

# SSH：如果要限制主机，请将受信任的主机写入TRUST_HOSTS并注释掉以下内容。
# iptables -A INPUT -p tcp -m multiport --dports $SSH -j ACCEPT # ANY -> SEL

# FTP
# iptables -A INPUT -p tcp -m multiport --dports $FTP -j ACCEPT # ANY -> SELF

# DNS
# iptables -A INPUT -p tcp -m multiport --sports $DNS -j ACCEPT # ANY -> SELF
# iptables -A INPUT -p udp -m multiport --sports $DNS -j ACCEPT # ANY -> SELF

# SMTP
# iptables -A INPUT -p tcp -m multiport --sports $SMTP -j ACCEPT # ANY -> SELF

# POP3
# iptables -A INPUT -p tcp -m multiport --sports $POP3 -j ACCEPT # ANY -> SELF

# IMAP
# iptables -A INPUT -p tcp -m multiport --sports $IMAP -j ACCEPT # ANY -> SELF



###########################################################
# 其他
# 如果上述规则不适用，则记录并丢弃
###########################################################
sudo ./firewall incoming DROP --log drop



###########################################################
# 恢复之前的配置
###########################################################
if [ -n "${info_level_buckup}" ]; then
    sudo ./firewall config --write --key info.level --val "${info_level_buckup}"
else
    sudo ./firewall config --remove --key info.level
fi

###########################################################
# 保存 Iptables
###########################################################
sudo ./firewall save --log-input firewall-input-drop:


###########################################################
# 显示配置信息
###########################################################
echo -ne "\n\n"
echo "####################################################################################################"
sudo ./firewall filter --list
echo -ne "\n\n"
sudo ./firewall nat --list

