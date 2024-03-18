#!/bin/bash

CMD=$(basename $0)
LAN='enp0s8'
WAN='enp0s17'
RULE_DIR='/etc/myrule'
FILENAME_NAT='iptables'
FILENAME_NAT6='iptables6'



function check_sys(){

  local release=''

  if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
    release="centos"
  elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
    release="debian"
  elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
    release="ubuntu"
  fi

  if [[ -z ${release} ]]; then
    echo "unknown system"
  else
    echo "${release}"
  fi
}



function echo_msg() { (>&1 echo "${1}") }
function echo_warn() { local yellow=$(tput setaf 3); local reset=$(tput sgr0); (>&2 echo "${yellow}${1}${reset}") }
function echo_err() { local magenta=$(tput setaf 5); local reset=$(tput sgr0); (>&2 echo "${magenta}${1}${reset}") }
function echo_fatal() { local red=$(tput setaf 1); local reset=$(tput sgr0); (>&2 echo "${red}Fatal: ${1}${reset}"); exit 1; }

function usage() {
cat <<EOF
	usage: ${CMD} [nat|] <optional>

  nat : nat 

EOF
}

function usage_nat() {
cat <<EOF
	usage: ${CMD} nat <optional>

  --lan|-l  
  --wan|-w

EOF
}


function iptables_start() {
  local system=$(check_sys)
  if [[ ${system} == "centos" || ${system} == "debian" ]]; then
    systemctl start iptables.service
    systemctl enable iptables.service
  elif [[ ${system} == "ubuntu" ]]; then
    :
  else
    :
  fi
}

function iptables_save() {
  local system=$(check_sys)
  if [[ ${system} == "centos" || ${system} == "debian" ]]; then
    service iptables save
    service iptables stop
    service iptables start
  elif [[ ${system} == "ubuntu" ]]; then

    if [ ! -d  "${RULE_DIR}" ]; then
        echo_err "DIR ${RULE_DIR} not exist, try create one"
        mkdir -p "${RULE_DIR}"
        if [ ! -d  "${RULE_DIR}" ]; then
          echo_fatal "mkdir ${RULE_DIR} ..."
        fi
    fi

    # save current config
    RULE_FILE="${RULE_DIR}/${FILENAME_NAT}".rules
    local script_file_v4="/etc/network/if-pre-up.d/${FILENAME_NAT}"

    RULE6_FILE="${RULE_DIR}/${FILENAME_NAT6}".rules
    local script_file_v6="/etc/network/if-pre-up.d/${FILENAME_NAT6}"

    echo_msg "Create iptables rule file: ${RULE_FILE}"
    iptables-save > "${RULE_FILE}"

    echo_msg "Create iptables rule file: ${RULE6_FILE}"
    ip6tables-save > "${RULE6_FILE}"

    # add script
    echo_msg "Create launch script: ${script_file_v4}"
    echo -e "#!/bin/bash\niptables-restore < ${RULE_FILE}" > "${script_file_v4}\n "

    echo_msg "Create launch script: ${script_file_v6}"
    echo -e "#!/bin/bash\niptables-restore < ${RULE6_FILE}" > "${script6_file_v6}\n "

  else
    :
  fi
}

function iptables_clear() {
  iptables -F
  iptables -t nat -F
  iptables -X
  iptables -t nat -X
  iptables -Z
  iptables -t nat -Z

  ip6tables -F
  ip6tables -t nat -F
  ip6tables -X
  ip6tables -t nat -X
  ip6tables -Z
  ip6tables -t nat -Z
}

function iptables_set_default() {

  local option=$1
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  iptables -P INPUT ${option}
  iptables -P OUTPUT ${option}
  iptables -P FORWARD ${option}

  # ipv6 always drop
  ip6tables -P INPUT DROP
  ip6tables -P OUTPUT DROP
  ip6tables -P FORWARD DROP
}

function iptables_ping() {

  local option=$1
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  iptables -A INPUT -p icmp --icmp-type echo-request -j ${option}
  iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ${option}
}


function iptables_cmd_nat() {

  local lan=
  local wan=
  local log=false
  local ping=false
	
	while [ $# -gt 0 ]; do
		case $1 in
			--lan )
				shift
				lan=$1
			;;

			--wan )
				shift
				wan=$1
			;;

			--log )
				log=true
			;;

			--ping )
				ping=true
			;;

			*)
        usage_nat
				exit
				;;
		esac
		shift
	done

  if [[ -z ${lan} ]]; then
    yx_fatal "Invalid --lan params"
  fi

  if [[ -z ${wan} ]]; then
    yx_fatal "Invalid --wan params"
  fi

  if [ $(id -u) -ne 0 ]; then
    yx_fatal "Script should run with root"
  fi

  # enable sysctl ip_forward
  echo_msg 'set sysctl ip_forward=1'
  sysctl net.ipv4.ip_forward=1 > /dev/null

  # launch iptables and set iptables service start on launch
  echo_msg "Start iptable service ..."
  iptables_start

  # clear
  echo_msg 'Clear all settings ...'
  iptables_clear


  # base setting
  echo_msg 'Set Default link to DROP ...'
  iptables_set_default DROP

  if ${ping}; then
    echo_msg 'Enable ping ...'
    iptables_ping ACCEPT
  fi
  
  # set dns
  # 这个不需要设置
  # 如果设置，客户端DNS的IP好像必须设置成一样的
  # sudo iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to 1.1.1.1

  # set nat
  echo_msg 'Set nat rule ...'
  # 允许初始网络包
  iptables -A FORWARD -o "${wan}" -i "${lan}" -m conntrack --ctstate NEW -j ACCEPT
  # 允许已经建立链接的网络包
  #sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -o "${wan}" -i "${lan}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -o "${lan}" -i "${wan}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  # 设置NAT
  iptables -t nat -A POSTROUTING -o "${wan}" -j MASQUERADE


  # log
  if ${log}; then
    echo_msg 'Add a log record droped INPUT package ...'
    iptables -N LOGGING
    iptables -A INPUT -j LOGGING
    iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables INPUT Packet Dropped:" --log-level 7
    iptables -A LOGGING -j DROP
  fi

  iptables_save
}

sub_cmd=$1
if [[ -z ${sub_cmd} ]]; then
  yx_fatal "param error. use ${cmd} help to show document"
fi

if [[ ${sub_cmd} == "nat" ]]; then
  shift
  iptables_cmd_nat $@
  exit 0
else
  echo_fatal "Unknown sub command:${sub_cmd}. use ${sub_cmd} to show document"
fi



