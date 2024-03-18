#!/bin/bash

CMD=$(basename $0)
LAN='enp0s8'
WAN='enp0s17'
RULE_DIR='/etc/myrule'
FILENAME_NAT='iptables'
FILENAME_NAT6='iptables6'

DEBUG=true

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
		return 1
	fi
	
	return 0
}


function echo_msg() { (>&1 echo "${1}") }
function echo_warn() { local yellow=$(tput setaf 3); local reset=$(tput sgr0); (>&2 echo "${yellow}${1}${reset}") }
function echo_err() { local magenta=$(tput setaf 5); local reset=$(tput sgr0); (>&2 echo "${magenta}${1}${reset}") }
function echo_fatal() { local red=$(tput setaf 1); local reset=$(tput sgr0); (>&2 echo "${red}Fatal:${1}${reset}"); exit 1; }
function echo_cmd()
{
  if $DEBUG; then
    echo "$@"
  fi
  "$@"
}

function analysis_cmd()
{
  echo "##############################################################################"
  echo "Run command:\"$@\""
  echo "------------------------------------------------------------------------------"
  local start=$(date +%s)
	$@
	local exit_code=$?
  echo "------------------------------------------------------------------------------"
	echo "took $(($(date +%s)-${start})) seconds. exited with ${exit_code}"
  echo "##############################################################################"
	return $exit_code
}



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
function iptables_wrap() {

  local interface=
  local not_interface=

  local inports=
  local outports=

  local protocol=
  local inflag=
  local outflag=

  local times=
  local frequency=

  local ip_from=
  local ip_not_from=
  local ip_to=
  local ip_not_to=

  local mac=
  local not_mac=

  local option=$1
  shift


	while [ $# -gt 0 ]; do
		case $1 in
			--interface )
				shift
				interface=$1
			;;

			--not-interface )
				shift
				not_interface=$1
			;;

			--in-flag )
				shift
				inflag=$1
			;;

			--out-flag )
				shift
				outflag=$1
			;;

			--in-port )
				shift
				inports=$1
			;;

			--out-port )
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
        freq=$1
      ;;

      --ip-from )
				shift
        ip_from=$1
      ;;

      --ip-notfrom )
				shift
        ip_not_from=$1
      ;;

      --ip-to )
				shift
        ip_to=$1
      ;;

      --ip-notto )
				shift
        ip_not_to=$1
      ;;

      --mac )
				shift
        mac=$1
      ;;

      --not-mac )
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


  local optional_params=''
  if [[ ${option} == 'enable' ]]; then
    optional_params="ACCEPT"
  elif [[ ${option} == 'disable' ]]; then
    optional_params="DROP"
  else
    echo_fatal "unknown optional \"${option}\""
  fi


  # interface
  local output_interface_param=''
  local input_interface_param=''
  if [[ -n ${interface} ]]; then
    output_interface_param=" -o ${interface}"
    input_interface_param=" -i ${interface}"
  elif [[ -n ${not_interface} ]]; then 
    output_interface_param=" ! -o ${not_interface}"
    input_interface_param=" ! -i ${not_interface}"
  fi

  # protocol
  local protocol_params=''
  if [[ -n ${protocol} ]]; then
    protocol_params=" -p ${protocol}"
  fi

  # protocol flag
  local inflag_params=''
  local outflag_params=''
  if [[ ${protocol} == "icmp" ]]; then
    if [[ -n ${inflag} ]]; then
      inflag_params=" --icmp-type ${inflag}"
    fi
    if [[ -n ${outflag} ]]; then
      outflag_params=" --icmp-type ${outflag}"
    fi
  else
    if [[ -n ${inflag} ]]; then
      echo_fatal "unknown --in-flag ${inflag} for protocol ${protocol}"
    fi
    if [[ -n ${outflag} ]]; then
      echo_fatal "unknown --out-flag ${outflag} for protocol ${protocol}"
    fi
  fi

  # Test -m limit params
  # --limit [6/second | 6/min | xx/s]
  local limit_params=''
  if [[ -n ${times} ]] || [[ -n ${frequency} ]]; then
    limit_params=' -m limit'

    # --limit
    if [[ -n ${freq} ]]; then
      if yx_str_checkfmt '^([0-9])+/(s|min|second)$' "${freq}"; then
        limit_params="${limit_params} --limit ${freq}"
      else
        echo_fatal "\"${freq}\" is not a valid params for --freq"
      fi
    fi
    
    # --limit-burst
    if [[ -n ${times} ]]; then
      if yx_str_checkfmt '^([0-9])+$' "${times}"; then
        limit_params="${limit_params} --limit-burst ${times}"
      else
        echo_fatal "\"${times}\" is not a valid params for --times"
      fi
    fi

  fi


  #indicate from ip-address or net-segment
  local ip_from_params=''
  if [[ -n ${ip_from} ]]; then
      if yx_str_checkfmt '^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}(/[0-3]?[0-9])?$' "${ip_from}"; then
        ip_from_params=" -s ${ip_from}"
      elif yx_str_checkfmt '^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$' "${ip_from}"; then
        ip_from_params=" -m iprange --src-range ${ip_from}"
      else
        echo_fatal "\"${ip_from}\" is not a valid ip-address or net-setment"
      fi
  elif [[ -n ${ip_not_from} ]]; then
      if yx_str_checkfmt '^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}(/[0-3]?[0-9])?$' "${ip_not_from}"; then
        ip_from_params=" !-s ${ip_not_from}"
      elif yx_str_checkfmt '^([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}-([0-2]?[0-9]{1,2}\.){3}[0-2]?[0-9]{1,2}$' "${ip_not_from}"; then
        ip_from_params=" -m iprange ! --src-range ${ip_not_from}"
      else
        echo_fatal "\"${ip_not_from}\" is not a valid ip-address or net-setment"
      fi
  fi

  #indicate target ip-address or net-segment
  local ip_to_params=''
  if [[ -n ${ip_to} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_to}"; then
        ip_to_params=" -d ${ip_to}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_to}"; then
        ip_from_params=" -m iprange --dst-range ${ip_to}"
      else
        echo_fatal "\"${ip_to}\" is not a valid ip-address or net-setment"
      fi
  elif [[ -n ${ip_not_to} ]]; then
      if yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}(/\d{1,3})?' "${ip_not_to}"; then
        ip_to_params=" ! -d ${ip_not_to}"
      elif yx_str_checkfmt '(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}' "${ip_not_to}"; then
        ip_from_params=" -m iprange ! --dst-range ${ip_not_to}"
      else
        echo_fatal "\"${ip_not_to}\" is not a valid ip-address or net-setment"
      fi
  fi

  local mac_params=''
  if [[ -n ${mac} ]]; then
    mac_params=" -m mac --mac-source ${mac}"
  elif [[ -n ${not_mac} ]]; then
    mac_params=" -m mac ! --mac-source ${not_mac}"
  fi



  if [[ -z ${inports} ]]  &&  [[ -z ${outports} ]]; then
      echo_cmd "iptables -A INPUT${input_interface_param}${protocol_params}${inflag_params}${mac_params}${ip_from_params}${ip_to_params}${limit_params} -j ${optional_params}"
      echo_cmd "iptables -A OUTPUT${output_interface_param}${protocol_params}${outflag_params}${mac_params}${ip_from_params}${ip_to_params}${limit_params} -j ${optional_params}"
  else
    if [[ -n ${inports} ]]; then
      echo_cmd "iptables -A INPUT${input_interface_param}${protocol_params}${inflag_params}${mac_params} -m multiport${limit_params} --dports ${inports}${ip_from_params}${ip_to_params} -m state --state NEW,ESTABLISHED -j ${optional_params}"
      echo_cmd "iptables -A OUTPUT${output_interface_param}${protocol_params}${outflag_params}${mac_params} -m multiport${limit_params} --sports ${inports}${ip_from_params}${ip_to_params} -m state --state ESTABLISHED -j ${optional_params}"
    fi

    if [[ -n ${outports} ]]; then
      echo_cmd "iptables -A OUTPUT${output_interface_param}${protocol_params}${inflag_params}${mac_params} -m multiport${limit_params} --dports ${outports}${ip_from_params}${ip_to_params} -m state --state NEW,ESTABLISHED -j ${optional_params}"
      echo_cmd "iptables -A INPUT${input_interface_param}${protocol_params}${outflag_params}${mac_params} -m multiport${limit_params} --sports ${outports}${ip_from_params}${ip_to_params} -m state --state ESTABLISHED -j ${optional_params}"
    fi
  fi

}


function iptables_port() {

  local option=$1
  shift
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  local ports=
  local default_ports=
  local must_proto=
  local service=false
  local client=false
  local additional=''

  # ignore params
  local protocol=

	while [ $# -gt 0 ]; do
		case $1 in
			--service )
				service=true
			;;

			--client )
        client=true
			;;

			--default-port )
				shift
				default_ports=$1
			;;

			--must-proto )
				shift
				must_proto=$1
			;;

			--port )
				shift
				ports=$1
			;;

			--in-port )
				shift
				ports=$1
			;;

			--out-port )
				shift
				ports=$1
			;;

			--proto )
				shift
				protocol=$1
			;;

			*)
        additional="${additional} $1"
      ;;
		esac
		shift
	done



  if [[ -n ${protocol} ]]; then
    if [[ -n ${must_proto} ]] && [[ ${protocol} != ${must_proto} ]]; then
        echo_fatal "${FUNCNAME} can not allow \"${protocol}\" protocol"
    fi
  else
    protocol=${must_proto}
    if [[ -z ${protocol} ]]; then
        echo_fatal "${FUNCNAME} must provide \"--proto\" or \"--must-proto\" params"
    fi
  fi


  if [[ -z ${ports} ]]; then
    ports=${default_ports}
    if [[ -z ${ports} ]]; then
      echo_fatal "${FUNCNAME} must provide --ports params"
    fi
  fi


  if ${service}; then
    iptables_wrap ${option} --proto ${protocol} --in-port ${ports}
  fi

  if ${client}; then
    iptables_wrap ${option} --proto ${protocol} --out-port ${ports}
  fi

}




function iptables_loopback(){

  local option=$1
  shift
  if [ -z ${option} ]; then
    echo_fatal "${FUNCNAME} need at least one params [DROP , ACCEPT]"
  fi


  local additional=''

  # ignore params
  local interface=
  local not_interface=

	while [ $# -gt 0 ]; do
		case $1 in

			--proto )
				shift
				interface=$1
			;;

			--not-interface )
				shift
				not_interface=$1
			;;

			*)
        additional="${additional} $1"
      ;;
		esac
		shift
	done


  if [[ -n ${interface} ]]  &&  [[ ${interface} != 'icmp' ]]; then
    echo_fatal "${FUNCNAME} can not allow \"${interface}\" interface"
  fi

  if [[ -n ${not_interface} ]]; then
    echo_fatal "${FUNCNAME} can not support --not-interface params"
  fi


  # iptables -A INPUT -i lo -j ACCEPT
  # iptables -A OUTPUT -o lo -j ACCEPT
  iptables_wrap ${option} --interface lo
}

function iptables_ping() {

  local option=$1
  shift
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  local service=false
  local client=false
  local additional=''

  # ignore params
  local protocol=

	while [ $# -gt 0 ]; do
		case $1 in
			--service )
				service=true
			;;

			--client )
        client=true
			;;

			--proto )
				shift
				protocol=$1
			;;

			*)
        additional="${additional} $1"
      ;;
		esac
		shift
	done


  if [[ -n ${protocol} ]]  &&  [[ ${protocol} != 'icmp' ]]; then
    echo_fatal "${FUNCNAME} can not allow \"${protocol}\" protocol"
  fi


  if ${service}; then
    iptables_wrap ${option} --proto icmp --in-flag echo-request --out-flag echo-reply ${additional}
  fi

  if ${client}; then
    iptables_wrap ${option} --proto icmp --out-flag echo-request --in-flag echo-reply ${additional}
  fi

}


#TODO merge ping to iptables_port
#TODO additional params not valid

function iptables_ssh2() {
  local option=$1
  shift
  if [ -z ${option} ]; then
    echo_fatal 'iptables_set_default need at least one params [DROP , ACCEPT]'
  fi

  iptables_port ${option} --must-proto tcp --default-port 22 $@
}

function iptables_ssh() {

  local ports=22
  local service=false
  local client=false
  local additional=''

  # ignore params
  local protocol=

	while [ $# -gt 0 ]; do
		case $1 in
			--service )
				service=true
			;;

			--client )
        client=true
			;;

			--port )
				shift
				ports=$1
			;;

			--in-port )
				shift
				ports=$1
			;;

			--out-port )
				shift
				ports=$1
			;;

			--proto )
				shift
				protocol=$1
			;;

			*)
        additional="${additional} $1"
      ;;
		esac
		shift
	done


  if [[ -n ${protocol} ]]  &&  [[ ${protocol} != 'tcp' ]]; then
    echo_fatal "${FUNCNAME} can not allow \"${protocol}\" protocol"
  fi


  if ${service}; then
    iptables_wrap ${option} --proto tcp --in-port ${ports}
  fi

  if ${client}; then
    iptables_wrap ${option} --proto tcp --out-port ${ports}
  fi

}

# TODO implement iptable_port
#iptable_loopback enable
#iptables_ping enable --service --ip-from "192.168.1.1/24" --times 3 --freq 2/second
#iptables_ping disable --service
iptables_ssh2 enable --service --ip-from "192.168.1.1/24" --times 3 --freq 2/second
iptables_ssh2 enable --client

#exit 0


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



