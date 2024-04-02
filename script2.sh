#!/bin/bash


CONFIG_FILE=/home/uvm1/Desktop/tmp.conf


function os_type()
{
	
	local release=''
	
	if [ -n "${OSTYPE}" ]; then
		if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
			release="linux"
		elif [[ "${OSTYPE}" == "bsd"* ]]; then 
			release="bsd"
		elif [[ "${OSTYPE}" == "freebsd"* ]]; then 
			release="freebsd"
		elif [[ "${OSTYPE}" == "darwin"* ]]; then 
			release="osx"
		elif [[ "${OSTYPE}" == "solaris"* ]]; then 
			release="solaris"
		elif [[ "${OSTYPE}" == "cygwin" ]]; then 
			# POSIX compatibility layer and Linux environment emulation for Windows 
			release="cygwin"
		elif [[ "${OSTYPE}" == "msys" ]]; then 
			# Lightweight shell and GNU utilities compiled for Windows (part of MinGW) 
			release="msys"
		elif [[ "${OSTYPE}" == "win32" ]]; then 
			# I'm not sure this can happen. 
			release="windows"
		else 
			release="unknown"
		fi
	else
		
		# $OSTAYPE not recognized by the older shells (such as Bourne shell).
		# Use `uname` instead
		
		case $(uname | tr '[:upper:]' '[:lower:]') in
			linux*)
				release='linux'
			;;
			freebsd*)
				release='freebsd'
			;;
			darwin*)
				release="osx"
			;;
			SunOS*)
				release="solaris"
			;;
			msys*)
				release="msys"
			;;
			windows*)
				release="windows"
			;;
			*)
				release="unknown"
			;;
		esac
	fi
	

	echo "${release}"
}

function linux_type()
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "should run with root"
		exit 1
    fi

    local release=
	if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
		if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
			release="centos"
		elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
			release="debian"
		elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
			release="ubuntu"
		else
			release="linux"
		fi
	else
	    release="unknown"
	fi

    echo "${release}"
}


function _sed_escape() {
	sed -e 's/[]\/$*.^[]/\\&/g'
}


function has_cfg_haskey()
{
	local key=$1
	if [ -z ${key} ]; then
		echo 'key is empty'
		exit 1
	fi
	
	local fixkey=$(echo "${key}" | _sed_escape)
	test -f "${CONFIG_FILE}" && grep -Eq "^\s*${fixkey}\s*=\s*.*$" "${CONFIG_FILE}" 
}

function read_cfg_key()
{
	local key=$1
	if [ -z ${key} ]; then
		echo 'key is empty'
		exit 1
	fi
	
	local fixkey=$(echo "${key}" | _sed_escape)
	test -f "${CONFIG_FILE}" && grep -E "^\s*${fixkey}\s*=\s*" "${CONFIG_FILE}" | sed -e  "s/[[:space:]]*${fixkey}[[:space:]]*=[[:space:]]*//g" | grep -o "[^ ]\+\( \+[^ ]\+\)*"
}

function delete_cfg_key()
{ # key
	local key=$1
	if [ -z ${key} ]; then
		echo 'key is empty'
		exit 1
	fi

	local fixkey=$(echo "${key}" | _sed_escape)
	if [[ $(os_type) == 'osx' ]]; then
		test -f "${CONFIG_FILE}" && sed -i "" "/^[[:space:]]*${fixkey}[[:space:]]*=.*$/d" "${CONFIG_FILE}"
	else
		test -f "${CONFIG_FILE}" && sed -i "/^[[:space:]]*${fixkey}[[:space:]]*=.*$/d" "${CONFIG_FILE}"
	fi
}

function commentout_cfg_key()
{ # key
	local key=$1
	if [ -z ${key} ]; then
		echo 'key is empty'
		exit 1
	fi
	
	local fixkey=$(echo "${key}" | _sed_escape)
	if [[ $(os_type) == 'osx' ]]; then
		test -f "${CONFIG_FILE}" && sed -i "" "s/^[[:space:]]*\(${fixkey}[[:space:]]*=.*\)$/#\1/g" "${CONFIG_FILE}"
	else
		test -f "${CONFIG_FILE}" && sed -i "s/^[[:space:]]*\(${fixkey}[[:space:]]*=.*\)$/#\1/g" "${CONFIG_FILE}"
	fi
}

function wite_cfg_key()
{ # key
	local key=$1
	if [ -z ${key} ]; then
		echo 'key is empty'
		exit 1
	fi
	
	local val=$2
	if [ -z ${val} ]; then
		echo 'value is empty'
		exit 1
	fi
	
	local fixkey=$(echo "${key}" | _sed_escape)
	if 	test -f "${CONFIG_FILE}" && grep -Eq "^\s*#?\s*${fixkey}\s*=.*$" "${CONFIG_FILE}"; then
		if 	test -f "${CONFIG_FILE}" && grep -Eq "^\s*#?\s*${fixkey}\s*=\s*${val}\s*$" "${CONFIG_FILE}"; then
			if [[ $(os_type) == 'osx' ]]; then
				sed -i "" "s/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/${fixkey} = ${val}/g" "${CONFIG_FILE}"
			else
				sed -i "s/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/${fixkey} = ${val}/g" "${CONFIG_FILE}"
			fi
		else
			if [[ $(os_type) == 'osx' ]]; then
				sed -i "" "/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/ a\\
				${fixkey} = ${val}\\
				" "${CONFIG_FILE}"
			else
				sed -i "/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/ a ${fixkey} = ${val}" "${CONFIG_FILE}"
			fi
		fi
	else
		echo "${key} = ${val}" >> ${CONFIG_FILE}
	fi	
}



#if has_cfg_haskey gg; then
#	echo 'has key'
#else
#	echo 'not has key'
#fi


#read_cfg_key ff[18]

#delete_cfg_key gg

#commentout_cfg_key gg

#wite_cfg_key cc[13] 44

linux_type


