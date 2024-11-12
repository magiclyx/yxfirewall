#!/bin/bash


###########################################################
# 配置
###########################################################

# 回环
LOOP_BACK=false

# 仅支持https
HTTPS_ONLY=true

# 日志级别(SILENT, FATAL, ERROR, VERBOSE, 或可直接使用0-99数字), 不更改可以留空
LOG_Level=VERBOSE

# 备份路径
BUCKUP_PATH=~/Desktop/test/buckup

###########################################################
# Host 定义
###########################################################

# 无条件丢弃的列表
DENY_HOSTS=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

# 允许进入的列表
INCOMING_HOST=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

# 允许出去的列表
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
# Function
###########################################################
function echo_noti() {(>&1 echo "$(tput setaf 4)"${*}"$(tput sgr0)") }
function echo_info() {(>&1 echo "$(tput setaf 2)"${*}"$(tput sgr0)") }
function echo_warn() {(>&2 echo "$(tput setaf 3)"${*}"$(tput sgr0)") }

###########################################################
# 提示:测试脚本，不要用于生产环境
###########################################################
echo_warn "============================================================"
echo_warn "!!!! Test script, do not use in a production environment !!!!"
echo_warn "============================================================"


###########################################################
# 设置调试日志级别, 并保存之前的配置
###########################################################
if [ -n "${LOG_Level}" ]; then
    echo_noti "========================================================================================================================"
    echo_noti "Change output level to '${LOG_Level}'..."
    echo_noti "========================================================================================================================"
    # 先备份之前的配置
    info_level_buckup=$(sudo ./yxfirewall config --read --key info.level)
    # 更改全局日志配置, 这里使用了`--info-level`参数，确保当前命令也有正确的日志输出
    sudo ./yxfirewall config --write --key info.level --val "${LOG_Level}" --info-level "${LOG_Level}"
fi


###########################################################
# 执行前，备份当前防火墙配置
###########################################################
if [ -n "${BUCKUP_PATH}" ]; then
  # 备份
  echo_noti "========================================================================================================================"
  echo_noti "Buckup current network configuration ..."
  echo_noti "========================================================================================================================"
  sudo ./yxfirewall buckup --path "${BUCKUP_PATH}"
fi


###########################################################
# 初始化 Iptables
###########################################################
echo_noti "========================================================================================================================"
echo_noti "Initialize..."
echo_noti "========================================================================================================================"

sudo ./yxfirewall start  # 启动服务
echo_info "Clear all rule..."
sudo ./yxfirewall clear  # 清空所有规则
echo_info "Set default policy..."
sudo ./yxfirewall default DROP --all  # 设置所有规则的默认行为是Drop


###########################################################
# 放弃来自 $DENY_HOSTS 的访问
###########################################################

if [ "${DENY_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set deny hosts..."
  echo_noti "========================================================================================================================"
	for host in "${DENY_HOSTS[@]}"; do
      sudo ./yxfirewall incoming drop --net "${host}" --log firewall-denyhost:limit:1/s
	done
fi


###########################################################
# 通用防护
###########################################################
echo_noti "========================================================================================================================"
echo_noti "Set Common guard rule..."
echo_noti "========================================================================================================================"

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
echo_noti "========================================================================================================================"
echo_noti "Set Loopback"
echo_noti "========================================================================================================================"

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
if [ "${ICMP_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set ICMP host rule..."
  echo_noti "========================================================================================================================"
  for net in "${ICMP_HOSTS[@]}"; do
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
if [ "${SSH_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set SSH host rule..."
  echo_noti "========================================================================================================================"
  for net in "${SSH_HOSTS[@]}"; do
    ip_params=''
    if [[ ${net} != '*' ]]; then
      ip_params="--net ${net}"
    fi
      sudo ./yxfirewall Server ACCEPT --proto ssh --chain "FW_SSH" ${ip_params} --log firewall-ssh:-
  done
fi


# 攻击防护：HTTP/HTTPS 
if [ "${WEB_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set Web host rule..."
  echo_noti "========================================================================================================================"
  for net in "${WEB_HOSTS[@]}"; do
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
if [ "${FTP_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set FTP host rule..."
  echo_noti "========================================================================================================================"
  for net in "${FTP_HOSTS[@]}"; do
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

if [ -n "${SNAT_WAN}" ]  && [ "${SNAT_LAN_LIST}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set SNAT..."
  echo_noti "========================================================================================================================"
  for lan in "${SNAT_LAN_LIST[@]}"; do
    sudo ./yxfirewall nat --snat --from-inter "${lan}" --to-inter "${SNAT_WAN}" --log firewall-forward:
  done
fi


###########################################################
# 受信主机
###########################################################

if [ "${INCOMING_HOST}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set incoming host..."
  echo_noti "========================================================================================================================"
  for host in "${INCOMING_HOST[@]}"; do
    sudo ./yxfirewall Server ACCEPT --net "${host}"
  done
fi

if [ "${OUTGOING_HOST}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set outgoing host..."
  echo_noti "========================================================================================================================"
  for host in "${OUTGOING_HOST[@]}";
  do
    sudo ./yxfirewall Client ACCEPT --net "${host}"
  done
fi

if [ "${FULL_TRUST_HOSTS}" ]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set full-trust host..."
  echo_noti "========================================================================================================================"
  for host in "${FULL_TRUST_HOSTS[@]}"; do
    sudo ./yxfirewall incoming ACCEPT --net "${host}"
    sudo ./yxfirewall outgoing ACCEPT --net "${host}"
  done
fi


###########################################################
# 其他
# 如果上述规则不适用，则记录并丢弃
###########################################################
echo_noti "========================================================================================================================"
echo_noti "Drop any other connect..."
echo_noti "========================================================================================================================"
sudo ./yxfirewall incoming DROP --log firewall-drop


###########################################################
# 保存 Iptables
###########################################################
echo_noti "========================================================================================================================"
echo_noti "Save changes..."
echo_noti "========================================================================================================================"
# sudo ./yxfirewall save --memsize 3G
sudo ./yxfirewall save --memsize 3G


###########################################################
# 重置Info.level
###########################################################
echo_noti "========================================================================================================================"
echo_noti "Reset Info.level..."
echo_noti "========================================================================================================================"
if [ -n "${info_level_buckup}" ]; then
    sudo ./yxfirewall config --write --key info.level --val "${info_level_buckup}"
else
    sudo ./yxfirewall config --remove --key info.level
fi


###########################################################
# 显示配置信息
###########################################################
echo_noti "========================================================================================================================"
echo_noti "List all chains...."
echo_noti "========================================================================================================================"
# echo "Test list"
for chain in $(sudo ./yxfirewall chain list --custom-only --chain-io); do
  fixed_chain=$(echo "${chain}" | sed -e "s/^\(.*\)(.*)$/\1/g")
  echo_info '------------------------------------------------------------'
  echo_info "list ${fixed_chain} ..."
  sudo ./yxfirewall list "${fixed_chain}" --chain-io --reference
done

echo -ne "\n\n"

###########################################################
# 显示Nat信息
###########################################################
echo_noti "========================================================================================================================"
echo_noti "List Nat information ...."
echo_noti "========================================================================================================================"
if [ -n "${SNAT_WAN}" ]  && [ "${SNAT_LAN_LIST}" ]; then
  sudo ./yxfirewall list FORWARD
fi

# ###########################################################
# # 显示配置信息
# ###########################################################
# echo -ne "\n\n"
# echo "####################################################################################################"
# sudo ./yxfirewall list
# echo -ne "\n\n"
# sudo ./yxfirewall list --table nat

