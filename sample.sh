#!/bin/bash


###########################################################
# 配置
###########################################################

# 回环
LOOP_BACK=false

# 仅支持https
HTTPS_ONLY=true

# 调试
DEBUG=true

###########################################################
# Host 定义
###########################################################

# 无条件丢弃的列表
DENY_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

INCOMING_HOST=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

OUTGOING_HOST=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

# 无条件信任列表 (谨慎使用)
FULL_TRUST_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

###########################################################
# 协议相关Host
###########################################################

SSH_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
    10.12.13.2
)

ICMP_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
    10.12.13.2
)

WEB_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
    \*
)

FTP_PORTS_RANGE='5000:5100'
FTP_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
    10.12.13.2
)

# 可通过配置文件，修改port号。 
# 也可在命令中直接指定 --port 参数
# sudo ./yxfirewall config rule.ssh --remove --key port

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


function echo_noti()
{
  local str=
	if (( $# == 0 )) ; then
		read -r -t 5 -d $'\0' str
#		num=`cat < /dev/stdin`
	else
		str="$*"
	fi

  local blue=$(tput setaf 4);
  local reset=$(tput sgr0);
  
  (>&1 echo "${blue}${str}${reset}")
}

function echo_info()
{
  local str=
	if (( $# == 0 )) ; then
		read -r -t 5 -d $'\0' str
#		num=`cat < /dev/stdin`
	else
		str="$*"
	fi

  local green=$(tput setaf 2);
  local reset=$(tput sgr0);
  (>&1 echo "${green}${str}${reset}")
}

###########################################################
# 设置调试日志级别为 Debug, 并保存之前的配置
###########################################################
if ${DEBUG}; then
    echo_noti "Change output level to 'DEBUG'..."

    info_level_buckup=$(sudo ./yxfirewall config --read --key info.level)
    sudo ./yxfirewall config --write --key info.level --val verbose 
fi


###########################################################
# 初始化 Iptables
###########################################################
echo_noti "Initialize..."

sudo ./yxfirewall start  # 启动服务
echo_info "Clear all rule..."
sudo ./yxfirewall clear  # 清空所有规则
echo_info "Set default policy..."
sudo ./yxfirewall default DROP --all  # 设置所有规则的默认行为是Drop


###########################################################
# 放弃来自 $DENY_HOSTS 的访问
###########################################################

if [ "${DENY_HOSTS}" ]
then
  echo_noti "Set deny hosts..."
	for host in "${DENY_HOSTS[@]}";
	do
      sudo ./yxfirewall incoming drop --net "${host}" --log firewall-denyhost:limit:1/s
	done
fi


###########################################################
# 通用防护
###########################################################
echo_noti "Set Common guard rule..."

# 攻击防护：broadcast
echo_info "Block broadcast package..."
sudo ./yxfirewall Server Block --proto wall-broadcast --chain "FW_BROADCAST" --log firewall-broadcast:-
# 攻击防护：bad package
echo_info "Block bad package..."
sudo ./yxfirewall Server Block --proto wall-pkg --chain "FW_PKG" --log firewall-invalid-package:-
# 攻击防护：syn flood
echo_info "Block syn-flood attack..."
sudo ./yxfirewall Server Block --proto wall-synflood --chain "FW_SYNFLOOD" --log firewall-synflood:-
# 攻击防护：stealth scan
echo_info "Block steal-scan..."
sudo ./yxfirewall Server Block --proto wall-scan --chain "FW_STEALTHSCAN" --log firewall-stealthscan:-


###########################################################
# loopback
###########################################################
echo_noti "Set Loopback"

if ${LOOP_BACK}; then
 sudo ./yxfirewall loopback Enable
else
  sudo ./yxfirewall loopback Disable
fi

###########################################################
# 常用的协议
###########################################################

# 攻击防护：icmp
# 默认地,所有丢弃的 ICMP 包都不记录日志. "冲击波" 以及 "蠕虫" 会导致系统发起大量
# 这里了还是记了日志，因为只对特定ip开放
if [ "${ICMP_HOSTS}" ];
then
  echo_noti "Set ICMP host rule..."
  for net in "${ICMP_HOSTS[@]}";
  do
    ip_params=''
    if [[ ${net} != '*' ]]; then
      ip_params="--net ${net}"
    fi
      sudo ./yxfirewall Server ACCEPT --proto icmp --chain "FW_ICMP" ${ip_params} --log firewall-icmp:-
  done
fi


# 攻击防护：SSH 暴力破解
# 为使用密码认证的服务器准备密码暴力攻击。
# 如果 SSH 服务器开启了密码认证，请取消注释掉以下内容。
if [ "${SSH_HOSTS}" ];
then
  echo_noti "Set SSH host rule..."
  for net in "${SSH_HOSTS[@]}";
  do
    ip_params=''
    if [[ ${net} != '*' ]]; then
      ip_params="--net ${net}"
    fi
      sudo ./yxfirewall Server ACCEPT --proto ssh --chain "FW_SSH" ${ip_params} --log firewall-ssh:-
  done
fi


# 攻击防护：HTTP/HTTPS 
if [ "${WEB_HOSTS}" ];
then
  echo_noti "Set Web host rule..."
  for net in "${WEB_HOSTS[@]}";
  do
    ip_params=''
    if [[ ${net} != '*' ]]; then
      ip_params="--net ${net}"
    fi
      sudo ./yxfirewall Server ACCEPT --proto https --chain "FW_HTTPS" ${ip_params} --log firewall-https:-
      if ! ${HTTPS_ONLY}; then
          sudo ./yxfirewall Server ACCEPT --proto http --chain "FW_HTTP" ${ip_params} --log firewall-http:-
      fi
  done
fi


# 攻击防护：FTP
# FTP, 一定要设置一个端口范围，否则会开放全部端口
if [ "${FTP_HOSTS}" ];
then
  echo_noti "Set FTP host rule..."
  for net in "${FTP_HOSTS[@]}";
  do
    ip_params=''
    if [[ ${net} != '*' ]]; then
      ip_params="--net ${net}"
    fi

    port_params=''
    if [ -n ${FTP_PORTS_RANGE} ]; then
      port_params="--port ${FTP_PORTS_RANGE}"
    fi
      sudo ./yxfirewall Server ACCEPT --proto ftp ${port_params} --chain "FTP_SRV" ${ip_params}
  done
fi


###########################################################
# SNAT设置
###########################################################

if [ -n "${SNAT_WAN}" ]  && [ "${SNAT_LAN_LIST}" ]
then
  echo_noti "Set SNAT..."
  for lan in "${SNAT_LAN_LIST[@]}"
  do
    sudo ./yxfirewall nat --snat --from-inter "${lan}" --to-inter "${SNAT_WAN}" --log firewall-forward:
  done
fi


###########################################################
# 受信主机
###########################################################

if [ "${INCOMING_HOST}" ]
then
  echo_noti "Set incoming host..."
  for host in "${INCOMING_HOST[@]}";
  do
    sudo ./yxfirewall Server ACCEPT --net "${host}"
  done
fi

if [ "${OUTGOING_HOST}" ]
then
  echo_noti "Set outgoing host..."
  for host in "${OUTGOING_HOST[@]}";
  do
    sudo ./yxfirewall Client ACCEPT --net "${host}"
  done
fi

if [ "${FULL_TRUST_HOSTS}" ]
then
  echo_noti "Set full-trust host..."
  for host in "${FULL_TRUST_HOSTS[@]}";
  do
    sudo ./yxfirewall incoming ACCEPT --net "${host}"
    sudo ./yxfirewall outgoing ACCEPT --net "${host}"
  done
fi

###########################################################
# 来自所有主机的输入 （ANY）
###########################################################

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
echo_noti "Drop any other connect..."
sudo ./yxfirewall incoming DROP --log firewall-drop


###########################################################
# 保存 Iptables
###########################################################
#:~TODO 去除 save 命令 三个log相关参数
echo_noti "Save changes..."
# sudo ./yxfirewall save --memsize 3G
sudo ./yxfirewall save --memsize 3G


###########################################################
# 恢复之前的配置
###########################################################
echo_noti "Reset Info.level..."
if [ -n "${info_level_buckup}" ]; then
    sudo ./yxfirewall config --write --key info.level --val "${info_level_buckup}"
else
    sudo ./yxfirewall config --remove --key info.level
fi


###########################################################
# 显示配置信息
###########################################################
echo -ne "\n\n"
echo "####################################################################################################"
sudo ./yxfirewall list
echo -ne "\n\n"
sudo ./yxfirewall list --table nat

