#!/bin/bash


######################################################################################################################
# 配置
######################################################################################################################

# 回环
LOOP_BACK=true

# 仅支持https
HTTPS_ONLY=false

# 日志级别(SILENT, FATAL, ERROR, VERBOSE, 或可直接使用0-99数字), 默认ERROR, 不更改可以留空
# 慎用权局设置VERBOSE, 会产生非常多无用输出
LOG_Level=VERBOSE

# 备份路径
BUCKUP_PATH=

######################################################################################################################
# Host 定义
######################################################################################################################

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

######################################################################################################################
# 协议相关
######################################################################################################################

######################
### SSH ###
SSH_SRV=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)
SSH_CLT=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

######################
### ICMP ###
ICMP_SRV=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)
ICMP_CLT=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
  \*
)

######################
### DNS ###
DNS_SRV=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)
DNS_CLT=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
  \*
)

######################
### WEB ###
WEB_SRV=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)
WEB_CLT=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
  \*
)

######################
### FTP ###
FTP_PORTS_RANGE='5000:5100'
FTP_SRV=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)
FTP_CLT=( # interface or ip (ip, ip/mask, ip_from-ip_to) or lo(lo, lo+) or \*
)

# 可通过配置文件，修改port号。 
# 也可在命令中直接指定 --port 参数
# sudo yxfirewall config rule.ssh --remove --key port

######################################################################################################################
# SNAT 定义
# 根据需要定义。 它不必被定义就可以工作。
######################################################################################################################

#SNAT_WAN=enp0s3
SNAT_WAN=

# (Array)
SNAT_LAN_LIST=( 
#    enp0s8
)





######################################################################################################################
#**********************************************************************************************************************
######################################################################################################################
#**********************************************************************************************************************
######################################################################################################################
#**********************************************************************************************************************
######################################################################################################################
#**********************************************************************************************************************
######################################################################################################################





######################################################################################################################
# Function
######################################################################################################################
function echo_verb() {(>&1 echo "${*}")}
function echo_noti() {(>&1 echo "$(tput setaf 4)${*}$(tput sgr0)") }
function echo_info() {(>&1 echo "$(tput setaf 2)${*}$(tput sgr0)") }
function echo_warn() {(>&2 echo "$(tput setaf 3)${*}$(tput sgr0)") }


# 将 ip 地址 或 接口 转换为 参数
# net_params net_or_ip
# 1.1.1.1 -> --net 1.1.1.1
# !1.1.1.1 -> --not-net 1.1.1.1
# en0 -> --net en0
# !en0 -> --not-net en0
function net_params()
{
  local net=$1
  local net_params=
  
  if [[ "${net}" != '*' ]] && [[ "${net}" != '\*' ]]; then
    if echo "${net}" | grep -Eq "^\s*!.*$"; then
      net=$(echo "${net}" | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed -e "s/^[[:space:]]*![[:space:]]*//g")
      if [ -n "${net}" ]; then
        net_params="--not-net ${net}"
      fi
    else
      net_params="--net ${net}"
    fi
  fi
  
  echo "${net_params}"
}

# 判断数组中是否有 '*' 或 '\*'
function ip_range_hasstar()
{
  local -n test_list=$1
  local has_flag=false
  for test_item in "${test_list[@]}"; do
    if [[ ${test_item} == '*' ]]  ||  [[ ${test_item} == '\*' ]]; then
      has_flag=true
      break
    fi
  done
  
  return "$(${has_flag} && echo 0 || echo 1)"
}

# 求数组或网络接口取反
# ip_range_not '1.1.1.1'
#
# 1.1.1.1 -> !1.1.1.1
# !1.1.1.1 -> 1.1.1.1
# en0 -> !en0
# !en0 -> en0
function ip_range_not()
{
  local net=$1
  local result=
  
  if [ -z "${net}" ]; then
    echo_fatal "no ip found"
  fi
  
  if [[ ${net} != '*' ]] && [[ ${net} != '\*' ]]; then
    if echo "${net}" | grep -Eq "^\s*!.*$"; then
      result=$(echo "${net}" | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed -e "s/^[[:space:]]*![[:space:]]*//g")
      if [ -z "${result}" ]; then
        echo_fatal "invalid ip:${net}"
      fi
    else
      result="!${net}"
    fi
  else
    result=
  fi
  
  echo "${result}"
}

# 求两个IP数组的交集
# ip_range_intersection 'array1_name' 'array2_name'
function ip_range_intersection()
{
  local -n test_list1=$1
  local -n test_list2=$2
  local -a result

  if ip_range_hasstar $1 && ip_range_hasstar $2; then
    result=(\\*)
  else
    if ip_range_hasstar $1; then
      result=("${test_list2[@]}")
    elif ip_range_hasstar $2; then
      result=("${test_list1[@]}")
    else
      local -A record
      for test_item in "${test_list1[@]}"; do
        if [[ ${test_item} =~ ^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$ ]]; then
          # ip 范围  192.168.10.1-192.169.10.10
          echo_warn "当ip-range(${test_item})与任何IP地址有交集时，可能会出现错误"
        fi
        record["${test_item}"]=1
      done
      for test_item in "${test_list2[@]}"; do
        if [[ -n ${record[${test_item}]} ]]; then
          result=("${result[@]}" "${test_item}")
        fi
      done
    fi
  fi
  
  echo "${result[@]}"
}


# array1 去除 array2 的内容
# ip_range_subtraction 'array1_name' 'array2_name'
# IFS=" " read -r -a result_array <<< "$(ip_range_intersection 'array1_name' 'array2_name')"
function ip_range_subtraction()
{
  local -n test_list1=$1
  local -n test_list2=$2
  local -a result
  
  
  if ip_range_hasstar $1 && ip_range_hasstar $2; then
    result=()
  else
    if ip_range_hasstar $1; then
      if [[ ${test_list2[0]} ]]; then
        for test_item in "${test_list2[@]}"; do
          if [[ ${test_item} =~ ^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$ ]]; then
            echo_warn "当ip-range(${test_item})与任何IP地址有交集时，可能会出现错误"
          fi
          result=("${result[@]}" $(ip_range_not "${test_item}"))
        done
      else
        result="${test_list1}"
      fi
    elif ip_range_hasstar $2; then
      result=()
    else
      local -A record
      for test_item in "${test_list2[@]}"; do
        if [[ ${test_item} =~ ^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$ ]]; then
          # ip 范围  192.168.10.1-192.169.10.10
          echo_warn "当ip-range(${test_item})与任何IP地址有交集时，可能会出现错误"
        fi
        record["${test_item}"]='1'
      done
      
      for test_item in "${test_list1[@]}"; do
        if [[ ${test_item} =~ ^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$ ]]; then
          # ip 范围  192.168.10.1-192.169.10.10
          echo_warn "当ip-range(${test_item})与任何IP地址有交集时，可能会出现错误"
        fi
        if [[ -z ${record["${test_item}"]} ]]; then
          result=("${result[@]}" "${test_item}")
        fi
      done
    fi
  fi
  
  echo "${result[*]}"
}


######################################################################################################################
# trap
######################################################################################################################
trap "exit 1;" INT EXIT TERM

######################################################################################################################
# 设置调试日志级别, 并保存之前的配置
######################################################################################################################
if [ -n "${LOG_Level}" ]; then
    echo_noti "========================================================================================================================"
    echo_noti "Change output level to '${LOG_Level}'..."
    echo_noti "========================================================================================================================"
    # 先备份之前的配置
    # 注意: 平时不要设置全局的 info.level 为 VERBOSE, 而是对单条命令使用 --info-level 参数
    info_level_buckup=$(sudo yxfirewall config --read --key info.level)
    # 更改全局日志配置, 这里使用了`--info-level`参数，确保当前命令也有正确的日志输出
    sudo yxfirewall config --write --key info.level --val "${LOG_Level}" --info-level "${LOG_Level}"
fi


######################################################################################################################
# 执行前，备份当前防火墙配置
######################################################################################################################
if [ -n "${BUCKUP_PATH}" ]; then
  # 备份
  echo_noti "========================================================================================================================"
  echo_noti "Buckup current network configuration ..."
  echo_noti "========================================================================================================================"
  sudo yxfirewall buckup --path "${BUCKUP_PATH}"
fi


######################################################################################################################
# 初始化 Iptables
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Initialize..."
echo_noti "========================================================================================================================"

sudo yxfirewall start  # 启动服务
echo_info "Clear all rule..."
sudo yxfirewall clear  # 清空所有规则
echo_info "Set default policy..."
sudo yxfirewall default DROP --all  # 设置所有规则的默认行为是Drop


######################################################################################################################
# 放弃来自 $DENY_HOSTS 的访问
######################################################################################################################

if [[ "${DENY_HOSTS[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set deny hosts..."
  echo_noti "========================================================================================================================"
	for host in "${DENY_HOSTS[@]}"; do
      sudo yxfirewall incoming drop --net "${host}" --log firewall-denyhost:limit:1/s
	done
fi


######################################################################################################################
# 通用防护
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Set Common guard rule..."
echo_noti "========================================================================================================================"

# 攻击防护：broadcast
echo_info "Block broadcast package..."
sudo yxfirewall Server Block --proto wall-broadcast --chain "FW_BROADCAST" --log firewall-broadcast:-
# 攻击防护：bad package
echo_info "Block bad package..."
sudo yxfirewall Server Block --proto wall-pkg --chain "FW_PKG" --log firewall-invalid-package:-
# 攻击防护：syn flood
echo_info "Block syn-flood attack..."
sudo yxfirewall Server Block --proto wall-synflood --chain "FW_SYNFLOOD" --log firewall-synflood:-
# 攻击防护：stealth scan
echo_info "Block steal-scan..."
sudo yxfirewall Server Block --proto wall-scan --chain "FW_STEALTHSCAN" --log firewall-stealthscan:-


######################################################################################################################
# loopback
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Set Loopback"
echo_noti "========================================================================================================================"

if ${LOOP_BACK}; then
  sudo yxfirewall loopback Enable
else
  sudo yxfirewall loopback Disable
fi

######################################################################################################################
# 常用的协议
######################################################################################################################

# 攻击防护：icmp
# 默认地,所有丢弃的 ICMP 包都不记录日志. "冲击波" 以及 "蠕虫" 会导致系统发起大量
# 这里了还是记了日志，因为只对特定ip开放
if [[ "${ICMP_SRV[0]}" ]] || [[ "${ICMP_CLT[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set ICMP rule..."
  echo_noti "========================================================================================================================"

  # 1. NODE_LIST = NODE_LIST + (SRV_LIST & CLT_LIST)
  declare -a ICMP_NODE_HOST_LIST
  IFS=" " read -r -a ICMP_NODE_HOST_LIST <<< "$(ip_range_intersection 'ICMP_SRV' 'ICMP_CLT')"

  # 2. SRV_LIST = SRV_LIST - NODE_LIST
  declare -a ICMP_SRV_HOST_LIST
  IFS=" " read -r -a ICMP_SRV_HOST_LIST <<< "$(ip_range_subtraction 'ICMP_SRV' 'ICMP_NODE_HOST_LIST')"

  # 3. CLT_LIST = CLT_LIST - NODE_LIST
  declare -a ICMP_CLT_HOST_LIST
  IFS=" " read -r -a ICMP_CLT_HOST_LIST <<< "$(ip_range_subtraction 'ICMP_CLT' 'ICMP_NODE_HOST_LIST')"


  if [[ ${ICMP_NODE_HOST_LIST[0]} ]]; then
    echo_info "ICMP Node rule..."
    need_space=false
    for net in "${ICMP_NODE_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Node ACCEPT --proto icmp --chain "NODE_ICMP" ${net_params} --log yxfirewall-node-icmp:-
    done
  fi

  if [[ ${ICMP_SRV_HOST_LIST[0]} ]]; then
    echo_info "ICMP Server rule..."
    need_space=false
    for net in "${ICMP_SRV_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Server ACCEPT --proto icmp --chain "SRV_ICMP" ${net_params} --log yxfirewall-server-icmp:-
    done
  fi

  if [[ ${ICMP_CLT_HOST_LIST[0]} ]]; then
    echo_info "ICMP Client rule..."
    need_space=false
    for net in "${ICMP_CLT_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Client ACCEPT --proto icmp --chain "CLT_ICMP" ${net_params} --log yxfirewall-client-icmp:-
    done
  fi

fi


# 协议DNS
if [[ "${DNS_SRV[0]}" ]] || [[ "${DNS_CLT[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set DNS rule..."
  echo_noti "========================================================================================================================"

  # 1. NODE_LIST = NODE_LIST + (SRV_LIST & CLT_LIST)
  declare -a DNS_NODE_HOST_LIST
  IFS=" " read -r -a DNS_NODE_HOST_LIST <<< "$(ip_range_intersection 'DNS_SRV' 'DNS_CLT')"

  # 2. SRV_LIST = SRV_LIST - NODE_LIST
  declare -a DNS_SRV_HOST_LIST
  IFS=" " read -r -a DNS_SRV_HOST_LIST <<< "$(ip_range_subtraction 'DNS_SRV' 'DNS_NODE_HOST_LIST')"

  # 3. CLT_LIST = CLT_LIST - NODE_LIST
  declare -a DNS_CLT_HOST_LIST
  IFS=" " read -r -a DNS_CLT_HOST_LIST <<< "$(ip_range_subtraction 'DNS_CLT' 'DNS_NODE_HOST_LIST')"



  if [[ ${DNS_NODE_HOST_LIST[0]} ]]; then
    echo_info "DNS Node rule..."
    need_space=false
    for net in "${DNS_NODE_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Node ACCEPT --proto dns --chain "NODE_DNS" ${net_params} --log yxfirewall-node-dns:-
    done
  fi

  if [[ ${DNS_SRV_HOST_LIST[0]} ]]; then
    echo_info "DNS Server rule..."
    need_space=false
    for net in "${DNS_SRV_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Server ACCEPT --proto dns --chain "SRV_DNS" ${net_params} --log yxfirewall-server-dns:-
    done
  fi

  if [[ ${DNS_CLT_HOST_LIST[0]} ]]; then
    echo_info "SSH Client rule..."
    need_space=false
    for net in "${DNS_CLT_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Client ACCEPT --proto dns --chain "CLT_DNS" ${net_params} --log yxfirewall-client-dns:-
    done
  fi

fi


# 攻击防护：SSH 暴力破解
# 为使用密码认证的服务器准备密码暴力攻击。
# 如果 SSH 服务器开启了密码认证，请取消注释掉以下内容。
if [[ "${SSH_SRV[0]}" ]] || [[ "${SSH_CLT[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set SSH rule..."
  echo_noti "========================================================================================================================"

  # 1. NODE_LIST = NODE_LIST + (SRV_LIST & CLT_LIST)
  declare -a SSH_NODE_HOST_LIST
  IFS=" " read -r -a SSH_NODE_HOST_LIST <<< "$(ip_range_intersection 'SSH_SRV' 'SSH_CLT')"

  # 2. SRV_LIST = SRV_LIST - NODE_LIST
  declare -a SSH_SRV_HOST_LIST
  IFS=" " read -r -a SSH_SRV_HOST_LIST <<< "$(ip_range_subtraction 'SSH_SRV' 'SSH_NODE_HOST_LIST')"

  # 3. CLT_LIST = CLT_LIST - NODE_LIST
  declare -a SSH_CLT_HOST_LIST
  IFS=" " read -r -a SSH_CLT_HOST_LIST <<< "$(ip_range_subtraction 'SSH_CLT' 'SSH_NODE_HOST_LIST')"



  if [[ ${SSH_NODE_HOST_LIST[0]} ]]; then
    echo_info "SSH Node rule..."
    need_space=false
    for net in "${SSH_NODE_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Node ACCEPT --proto ssh --chain "NODE_SSH" ${net_params} --log yxfirewall-node-ssh:-
    done
  fi

  if [[ ${SSH_SRV_HOST_LIST[0]} ]]; then
    echo_info "SSH Server rule..."
    need_space=false
    for net in "${SSH_SRV_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Server ACCEPT --proto ssh --chain "SRV_SSH" ${net_params} --log yxfirewall-server-ssh:-
    done
  fi

  if [[ ${SSH_CLT_HOST_LIST[0]} ]]; then
    echo_info "SSH Client rule..."
    need_space=false
    for net in "${SSH_CLT_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Client ACCEPT --proto ssh --chain "CLT_SSH" ${net_params} --log yxfirewall-client-ssh:-
    done
  fi

fi


# 攻击防护：HTTP/HTTPS 
if [[ "${WEB_SRV[0]}" ]] || [[ "${WEB_CLT[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set Web rule..."
  echo_noti "========================================================================================================================"

  # 1. NODE_LIST = NODE_LIST + (SRV_LIST & CLT_LIST)
  declare -a WEB_NODE_HOST_LIST
  IFS=" " read -r -a WEB_NODE_HOST_LIST <<< "$(ip_range_intersection 'WEB_SRV' 'WEB_CLT')"
  # WEB_NODE=($(ip_range_intersection 'WEB_SRV' 'WEB_CLT'))

  # 2. SRV_LIST = SRV_LIST - NODE_LIST
  declare -a WEB_SRV_HOST_LIST
  IFS=" " read -r -a WEB_SRV_HOST_LIST <<< "$(ip_range_subtraction 'WEB_SRV' 'WEB_NODE_HOST_LIST')"

  # 3. CLT_LIST = CLT_LIST - NODE_LIST
  declare -a WEB_CLT_HOST_LIST
  IFS=" " read -r -a WEB_CLT_HOST_LIST <<< "$(ip_range_subtraction 'WEB_CLT' 'WEB_NODE_HOST_LIST')"

  
  if [[ ${WEB_NODE_HOST_LIST[0]} ]]; then
    echo_info "Web Node rule..."
    need_space=false
    for net in "${WEB_NODE_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Node ACCEPT --proto https --chain "NODE_HTTPS" ${net_params} --log yxfirewall-node-https:-
      if ! ${HTTPS_ONLY}; then
          sudo yxfirewall Node ACCEPT --proto http --chain "NODE_HTTP" ${net_params} --log yxfirewall-node-http:-
      fi
    done
  fi

  if [[ ${WEB_SRV_HOST_LIST[0]} ]]; then
    echo_info "Web Server rule..."
    need_space=false
    for net in "${WEB_SRV_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Server ACCEPT --proto https --chain "SRV_HTTPS" ${net_params} --log yxfirewall-server-https:-
      if ! ${HTTPS_ONLY}; then
          sudo yxfirewall Server ACCEPT --proto http --chain "SRV_HTTP" ${net_params} --log yxfirewall-server-http:-
      fi
    done
  fi

  if [[ ${WEB_CLT_HOST_LIST[0]} ]]; then
    echo_info "Web Client rule..."
    need_space=false
    for net in "${WEB_CLT_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi
      net_params=$(net_params "${net}")
      sudo yxfirewall Client ACCEPT --proto https --chain "CLT_HTTPS" ${net_params} --log yxfirewall-client-https:-
      if ! ${HTTPS_ONLY}; then
          sudo yxfirewall Client ACCEPT --proto http --chain "CLT_HTTP" ${net_params} --log yxfirewall-client-http:-
      fi
    done
  fi

fi


# 攻击防护：FTP
# FTP, 一定要设置一个端口范围，否则会开放全部端口
if [[ "${FTP_SRV[0]}" ]] || [[ "${FTP_CLT[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set FTP rule..."
  echo_noti "========================================================================================================================"

  # 1. NODE_LIST = NODE_LIST + (SRV_LIST & CLT_LIST)
  declare -a FTP_NODE_HOST_LIST
  IFS=" " read -r -a FTP_NODE_HOST_LIST <<< "$(ip_range_intersection 'FTP_SRV' 'FTP_CLT')"

  # 2. SRV_LIST = SRV_LIST - NODE_LIST
  declare -a FTP_SRV_HOST_LIST
  IFS=" " read -r -a FTP_SRV_HOST_LIST <<< "$(ip_range_subtraction 'FTP_SRV' 'FTP_NODE_HOST_LIST')"

  # 3. CLT_LIST = CLT_LIST - NODE_LIST
  declare -a FTP_CLT_HOST_LIST
  IFS=" " read -r -a FTP_CLT_HOST_LIST <<< "$(ip_range_subtraction 'FTP_CLT' 'FTP_NODE_HOST_LIST')"



  if [[ ${FTP_NODE_HOST_LIST[0]} ]]; then
    echo_info "FTP Node rule..."
    need_space=false
    for net in "${FTP_NODE_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi

      port_params=''
      if [ -n "${FTP_PORTS_RANGE}" ]; then
        port_params="--port ${FTP_PORTS_RANGE}"
      fi

      net_params=$(net_params "${net}")

      sudo yxfirewall Node ACCEPT --proto ftp ${port_params} --chain "NODE_FTP" ${net_params} --log yxfirewall-node-ftp:-
    done
  fi


  if [[ ${FTP_SRV_HOST_LIST[0]} ]]; then
    echo_info "FTP Server rule..."
    need_space=false
    for net in "${FTP_SRV_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi

      port_params=''
      if [ -n "${FTP_PORTS_RANGE}" ]; then
        port_params="--port ${FTP_PORTS_RANGE}"
      fi

      net_params=$(net_params "${net}")

      sudo yxfirewall Server ACCEPT --proto ftp ${port_params} --chain "SRV_FTP" ${net_params} --log yxfirewall-server-ftp:-
    done
  fi


  if [[ ${FTP_CLT_HOST_LIST[0]} ]]; then
    echo_info "FTP Client rule..."
    need_space=false
    for net in "${FTP_CLT_HOST_LIST[@]}"; do
      if ${need_space}; then
        echo_verb ""
      else
        need_space=true
      fi

      port_params=''
      if [ -n "${FTP_PORTS_RANGE}" ]; then
        port_params="--port ${FTP_PORTS_RANGE}"
      fi

      net_params=$(net_params "${net}")

      sudo yxfirewall Client ACCEPT --proto ftp ${port_params} --chain "CLT_FTP" ${net_params} --log yxfirewall-client-ftp:-
    done
  fi

fi


######################################################################################################################
# SNAT设置
######################################################################################################################

if [ -n "${SNAT_WAN}" ]  && [[ "${SNAT_LAN_LIST[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set SNAT..."
  echo_noti "========================================================================================================================"
  for lan in "${SNAT_LAN_LIST[@]}"; do
    sudo yxfirewall nat --snat --from-inter "${lan}" --to-inter "${SNAT_WAN}" --log "yxfirewall-snat-${lan}:"
  done
fi


######################################################################################################################
# 受信主机
######################################################################################################################

if [[ "${INCOMING_HOST[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set incoming host..."
  echo_noti "========================================================================================================================"
  for host in "${INCOMING_HOST[@]}"; do
    sudo yxfirewall Server ACCEPT --net "${host}"
  done
fi

if [[ "${OUTGOING_HOST[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set outgoing host..."
  echo_noti "========================================================================================================================"
  for host in "${OUTGOING_HOST[@]}";
  do
    sudo yxfirewall Client ACCEPT --net "${host}"
  done
fi

if [[ "${FULL_TRUST_HOSTS[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "Set full-trust host..."
  echo_noti "========================================================================================================================"
  for host in "${FULL_TRUST_HOSTS[@]}"; do
    sudo yxfirewall incoming ACCEPT --net "${host}"
    sudo yxfirewall outgoing ACCEPT --net "${host}"
  done
fi


######################################################################################################################
# 其他
# 如果上述规则不适用，则记录并丢弃
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Drop any other connect..."
echo_noti "========================================================================================================================"
sudo yxfirewall incoming DROP --log yxfirewall-drop


######################################################################################################################
# 保存 Iptables
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Save changes..."
echo_noti "========================================================================================================================"
# sudo yxfirewall save --memsize 3G
sudo yxfirewall save


######################################################################################################################
# 重置Info.level
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "Reset Info.level..."
echo_noti "========================================================================================================================"
if [ -n "${info_level_buckup}" ]; then
    sudo yxfirewall config --write --key info.level --val "${info_level_buckup}"
else
    sudo yxfirewall config --remove --key info.level
fi


######################################################################################################################
# 显示配置信息
######################################################################################################################
echo_noti "========================================================================================================================"
echo_noti "List all chains...."
echo_noti "========================================================================================================================"
# echo "Test list"
for chain in $(sudo yxfirewall chain list --custom-only --chain-io); do
  fixed_chain=$(echo "${chain}" | sed -e "s/^\(.*\)(.*)$/\1/g")
  echo_info '------------------------------------------------------------'
  echo_info "list ${fixed_chain} ..."
  sudo yxfirewall list "${fixed_chain}" --chain-io --reference
done

echo -ne "\n\n"

######################################################################################################################
# 显示Nat信息
######################################################################################################################
if [ -n "${SNAT_WAN}" ]  && [[ "${SNAT_LAN_LIST[0]}" ]]; then
  echo_noti "========================================================================================================================"
  echo_noti "List Nat information ...."
  echo_noti "========================================================================================================================"

  sudo yxfirewall list FORWARD
fi

# ###########################################################
# # 显示配置信息
# ###########################################################
# echo -ne "\n\n"
# echo "####################################################################################################"
# sudo yxfirewall list
# echo -ne "\n\n"
# sudo yxfirewall list --table nat

