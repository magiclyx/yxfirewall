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

function yx_str_checkfmt()
{
	local reg=$1
	local str=$2
	
	if [[ -z ${str} ]]; then
		str=''
	fi
	
	if [[ -z ${reg} ]]; then
		reg='^\s*[^\s]+\s*$'
	fi
	
	if ! [[ ${str} =~ ${reg} ]] ; then
		return -1
	fi
	
	return 0
}


function echo_msg() { (>&1 echo "${1}") }
function echo_warn() { local yellow=$(tput setaf 3); local reset=$(tput sgr0); (>&2 echo "${yellow}${1}${reset}") }
function echo_err() { local magenta=$(tput setaf 5); local reset=$(tput sgr0); (>&2 echo "${magenta}${1}${reset}") }
function echo_fatal() { local red=$(tput setaf 1); local reset=$(tput sgr0); (>&2 echo "${red}Fatal:${1}${reset}"); exit 1; }


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


## TODO help info
## TODO support log

# ip format: 192.168.0.1 | 192.168.0.1/24 | 192.168.0.1-192.168.0.99
function iptables_enable_port() {

  local interface=
  local not_interface=
  local inports=
  local outports=
  local times=
  local frequency=
  local protocol='tcp'
  local ip_from=
  local ip_not_from=
  local ip_to=
  local ip_not_to=
  local mac=
  local not_mac=


	while [ $# -gt 0 ]; do
		case $1 in
			--interface )
				shift
				interface=$1
			;;

			--not_interface )
				shift
				not_interface=$1
			;;

			--in )
				shift
				inports=$1
			;;

			--out )
				shift
				outports=$1
			;;

			--proto )
				shift
				protocol=$1
			;;

      --times )
				shift
        times=$1
      ;;

      --freq )
				shift
        frequency=$1
      ;;

      --ip_from )
				shift
        ip_from=$1
      ;;

      --ip_not_from )
				shift
        ip_not_from=$1
      ;;

      --ip_to )
				shift
        ip_to=$1
      ;;

      --ip_not_to )
				shift
        ip_not_to=$1
      ;;

      --mac )
				shift
        mac=$1
      ;;

      --not_mac )
				shift
        not_mac=$1
      ;;

			*)
        usage
				exit
				;;
		esac
		shift
	done



  if [[ -z ${inports} ]]  &&  [[ -z ${outports} ]]; then
    echo_fatal "$FUNCNAME must provide at least one of --inports and --outports params"
  fi


  # interface
  local output_interface_param=
  local input_interface_param=
  if [[ -n ${interface} ]]; then
    output_interface_param="-o ${interface}"
    input_interface_param="-i ${interface}"
  elif [[ -n ${not_interface} ]]; then 
    output_interface_param="! -o ${not_interface}"
    input_interface_param="! -i ${not_interface}"
  fi


  # Test -m limit params
  # --limit [6/second | 6/min | xx/s]
  local limit_params=
  if [[ -n ${times} ]] || [[ -n ${frequency} ]]; then
    limit_params='-m limit'

    # --limit
    if [[ -n ${freq} ]]; then
      if yx_str_checkfmt '^([0-9])+$' "${freq}"; then
        limit_params="${limit_params} --limit ${freq}"
      else
        echo_fatal "\"${freq}\" is not a valid params for --freq"
      fi
    fi
    
    # --limit-burst
    if [[ -n ${times} ]]; then
      if yx_str_checkfmt '^([0-9])+$' "${freq}"; then
        limit_params="${limit_params} --limit-burst ${times}"
      else
        echo_fatal "\"${times}\" is not a valid params for --times"
      fi
    fi

  fi


  #indicate from ip-address or net-segment
  local ip_from_params=
  if [[ -n ${ip_from} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_from}"; then
        ip_from_params="-s ${ip_from}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_from}"; then
        ip_from_params="-m iprange --src-range ${ip_from}"
      else
        echo_fatal "\"${ip_from}\" is not a valid ip-address or net-setment"
      fi
  elif [[ -n ${ip_not_from} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_not_from}"; then
        ip_from_params="!-s ${ip_not_from}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_not_from}"; then
        ip_from_params="-m iprange ! --src-range ${ip_not_from}"
      else
        echo_fatal "\"${ip_not_from}\" is not a valid ip-address or net-setment"
      fi
  fi

  #indicate target ip-address or net-segment
  local ip_to_params=
  if [[ -n ${ip_to} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_to}"; then
        ip_to_params="-d ${ip_to}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_to}"; then
        ip_from_params="-m iprange --dst-range ${ip_to}"
      else
        echo_fatal "\"${ip_to}\" is not a valid ip-address or net-setment"
      fi
  elif [[ -n ${ip_not_to} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_not_to}"; then
        ip_to_params="! -d ${ip_not_to}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_not_to}"; then
        ip_from_params="-m iprange ! --dst-range ${ip_not_to}"
      else
        echo_fatal "\"${ip_not_to}\" is not a valid ip-address or net-setment"
      fi
  fi

  local mac_params=
  if [[ -n ${mac} ]]; then
    mac_params="-m mac --mac-source ${mac}"
  elif [[ -n ${not_mac} ]]; then
    mac_params="-m mac ! --mac-source ${not_mac}"
  fi



  if [[ -z ${inports} ]]; then
    iptables -A INPUT ${input_interface_param} -p ${protocol} ${mac_params} -m multiport ${limit_params} --dports ${inports} ${ip_from_params} ${ip_to_params} -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A OUTPUT ${output_interface_param} -p ${protocol} tcp ${mac_params} -m multiport ${limit_params} --sports ${inports} ${ip_from_params} ${ip_to_params} -m state --state ESTABLISHED -j ACCEPT
  fi

  if [[ -z ${outports} ]]; then
    iptables -A OUTPUT ${output_interface_param} -p ${protocol} ${mac_params} -m multiport ${limit_params} --dports ${inports} ${ip_from_params} ${ip_to_params} -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT ${input_interface_param} -p ${protocol} ${mac_params} -m multiport ${limit_params} --dports ${inports} ${ip_from_params} ${ip_to_params} -m state --state ESTABLISHED -j ACCEPT
     
  fi

}

function iptables_enable_icmp() {

  local interface=
  local in_type=
  local out_type=
  local times=
  local frequency=
  local ip=

	while [ $# -gt 0 ]; do
		case $1 in
			--interface )
				shift
				interface=$1
			;;

			--in-type )
				shift
				in_type=$1
			;;

			--out-type )
				shift
				out_type=$1
			;;

			--proto )
				shift
				protocol=$1
			;;

      --times )
				shift
        times=$1
      ;;

      --freq )
				shift
        frequency=$1
      ;;

      --ip )
				shift
        ip=$1
      ;;

			*)
        usage
				exit
				;;
		esac
		shift
	done



  # Test -m limit params
  # --limit [6/second | 6/min]
  local limit_params=
  if [[ -n ${times} ]] || [[ -n ${frequency} ]]; then
    limit_params='-m limit'

    # --limit
    if [[ -n ${freq} ]]; then
      if yx_str_checkfmt '^([0-9])+$' "${freq}"; then
        limit_params="${limit_params} --limit ${freq}"
      else
        echo_fatal "\"${freq}\" is not a valid params for --freq"
      fi
    fi
    
    # --limit-burst
    if [[ -n ${times} ]]; then
      if yx_str_checkfmt '^([0-9])+$' "${freq}"; then
        limit_params="${limit_params} --limit-burst ${times}"
      else
        echo_fatal "\"${times}\" is not a valid params for --times"
      fi
    fi

  fi


  # ip-address or net-segment
  local ip_params=
  if [[ -n ${ip} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip}"; then
        ip_params="-d ${ip}"
      else
        echo_fatal "\"${ip}\" is not a valid ip-address or net-setment"
      fi
  fi


  if [ -n ${in_type} ]; then

    local interface_params=
    if [ -n ${interface} ]; then
      interface_params="-i ${interface}"
    fi

    local icmp_type_params=
    if [[ "${in_type}" != '*' ]]; then
      icmp_type_params="--icmp-type ${in_type}"
    fi

    iptables -A INPUT "${interface_params}" -p icmp "${icmp_type_params}" "${limit_params}" "${ip_params}" -j ACCEPT
  fi

  if [ -n ${out_type} ]; then

    local interface_params=
    if [ -n ${interface} ]; then
      interface_params="-o ${interface}"
    fi

    local icmp_type_params=
    if [[ "${out_type}" != '*' ]]; then
      icmp_type_params="--icmp-type ${out_type}"
    fi

    iptables -A OUTPUT "${interface_params}" -p icmp "${icmp_type_params}" "${limit_params}" "${ip_params}" -j ACCEPT
  fi

}

function iptable_enable_loopback(){
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT
}

function iptables_ping() {

  iptables_enable_icmp

  local option=$1
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
}

function iptables_pingd()
{

  iptables -A INPUT -i eth0 -d 192.168.146.3 -p icmp --icmp-type 8 -m limit --limit 2/second --limit-burst 3 -j ACCEPT

  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 2/second --limit-burst 3 -j ACCEPT

  iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
  iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
}

function iptables_ssh() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --outports 22
}

function iptables_sshd() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --inports 22
}

function iptables_http() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --outports 80
}

function iptables_httpd() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --inports 80
}

function iptables_https() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --outports 443
}

function iptables_httpsd() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_enable_port --interface ${interface} --inports 443
}

function iptables_web() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_http
  iptables_https
}

function iptables_webd() {
  local interface=$1
  if [ -z ${interface} ]; then
    echo_fatal "$FUNCNAME must provide --interface xxx params"
  fi

  iptables_httpd
  iptables_httpsd
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
    echo_fatal "Invalid --lan params"
  fi

  if [[ -z ${wan} ]]; then
    echo_fatal "Invalid --wan params"
  fi

  if [ $(id -u) -ne 0 ]; then
    echo_fatal "Script should run with root"
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

echo '1'
sub_cmd=$1
if [[ -z ${sub_cmd} ]]; then
  echo_fatal "param error. use ${cmd} help to show document"
fi


if [[ ${sub_cmd} == "nat" ]]; then
  shift
  iptables_cmd_nat $@
  exit 0
else
  echo_fatal "Unknown sub command:${sub_cmd}. use ${sub_cmd} to show document"
fi



