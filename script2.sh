#!/bin/bash


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

	local file=
	local key=

	while [ $# -gt 0 ]; do
		case $1 in
		--file )
			shift
			file=$1
		;;

		--key )
			shift
			key=$1
		;;

		*)
			echo "Invalid optional ${1}"
			exit 1
		;;
		esac
		shift
	done


	if [ -z "${key}" ]; then
		echo 'key is empty'
		exit 1
	fi

	if [ -z "${file}" ]; then
		echo 'file is empty'
		exit 1
	fi

	
	local fixkey=$(echo "${key}" | _sed_escape)
	test -f "${file}" && grep -Eq "^\s*${fixkey}\s*=\s*.*$" "${file}" 
}

function read_cfg_key()
{

	local file=
	local key=

	while [ $# -gt 0 ]; do
		case $1 in
		--file )
			shift
			file=$1
		;;

		--key )
			shift
			key=$1
		;;

		*)
			echo "Invalid optional ${1}"
			exit 1
		;;
		esac
		shift
	done

	if [ -z "${key}" ]; then
		echo 'key is empty'
		exit 1
	fi

	if [ -z "${file}" ]; then
		echo 'file is empty'
		exit 1
	fi


	local fixkey=$(echo "${key}" | _sed_escape)
	test -f "${file}" && grep -E "^\s*${fixkey}\s*=\s*" "${file}" | sed -e  "s/[[:space:]]*${fixkey}[[:space:]]*=[[:space:]]*//g" | grep -o "[^ ]\+\( \+[^ ]\+\)*"
}

function delete_cfg_key()
{

	local file=
	local key=

	while [ $# -gt 0 ]; do
		case $1 in
		--file )
			shift
			file=$1
		;;

		--key )
			shift
			key=$1
		;;

		*)
			echo "Invalid optional ${1}"
			exit 1
		;;
		esac
		shift
	done


	if [ -z "${key}" ]; then
		echo 'key is empty'
		exit 1
	fi

	if [ -z "${file}" ]; then
		echo 'file is empty'
		exit 1
	fi


	local fixkey=$(echo "${key}" | _sed_escape)
	if [[ $(os_type) == 'osx' ]]; then
		test -f "${file}" && sed -i "" "/^[[:space:]]*${fixkey}[[:space:]]*=.*$/d" "${file}"
	else
		test -f "${file}" && sed -i "/^[[:space:]]*${fixkey}[[:space:]]*=.*$/d" "${file}"
	fi
}

function commentout_cfg_key()
{
    
	local file=
	local key=

	while [ $# -gt 0 ]; do
		case $1 in
		--file )
			shift
			file=$1
		;;

		--key )
			shift
			key=$1
		;;

		*)
			echo "Invalid optional ${1}"
			exit 1
		;;
		esac
		shift
	done


	if [ -z "${key}" ]; then
		echo 'key is empty'
		exit 1
	fi

	if [ -z "${file}" ]; then
		echo 'file is empty'
		exit 1
	fi

	
	local fixkey=$(echo "${key}" | _sed_escape)
	if [[ $(os_type) == 'osx' ]]; then
		test -f "${file}" && sed -i "" "s/^[[:space:]]*\(${fixkey}[[:space:]]*=.*\)$/#\1/g" "${file}"
	else
		test -f "${file}" && sed -i "s/^[[:space:]]*\(${fixkey}[[:space:]]*=.*\)$/#\1/g" "${file}"
	fi
}

function wite_cfg_key()
{

	local file=
	local key=
	local val=

	while [ $# -gt 0 ]; do
		case $1 in
		--file )
			shift
			file=$1
        ;;

		--key )
			shift
			key=$1
        ;;

		--val )
			shift
			val=$1
        ;;

        *)
			echo "Invalid optional ${1}"
			exit 1
        ;;
		esac
		shift
	done


    if [ -z "${key}" ]; then
	    echo 'key is empty'
		exit 1
	fi

	if [ -z "${val}" ]; then
	    echo 'val is empty'
		exit 1
	fi

	if [ -z "${file}" ]; then
		echo 'file is empty'
		exit 1
	fi


	local fixkey=$(echo "${key}" | _sed_escape)
	if test -f "${file}" &&  grep -Eq "^\s*${fixkey}\s*=\s*${val}\s*$" "${file}"; then # Testfile exist and text 'key = val' exist, do nothing ...
		:
	elif test -f "${file}" && grep -Eq "^\s*#\s*${fixkey}\s*=.*$" "${file}"; then #Test file exist and text '# key = xxx' exist
		if 	grep -Eq "^\s*#\s*${fixkey}\s*=\s*${val}\s*$" "${file}"; then #Test exist '# key = val', remove '#' and format line.
			if [[ $(os_type) == 'osx' ]]; then
				sed -i "" "s/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/${fixkey} = ${val}/g" "${file}"
			else
				sed -i "s/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/${fixkey} = ${val}/g" "${file}"
			fi
		else # Text '# key=???' exist, append 'key = val' below.
			if [[ $(os_type) == 'osx' ]]; then
			    # 因为sed在OSX上的问题，这里不得不换行!!!
				sed -i "" "/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/ a\\
				${fixkey} = ${val}\\
				" "${file}"
			else
				sed -i "/^[[:space:]]*#*[[:space:]]*${fixkey}[[:space:]]*=.*/ a ${fixkey} = ${val}" "${file}"
			fi
		fi
	else
		echo "${key} = ${val}" >> "${file}"
	fi	
}



CONFIG_FILE=/home/uvm1/Desktop/tmp.conf


# if has_cfg_haskey --key gg --file "${CONFIG_FILE}" ; then
# 	echo 'has key'
# else
# 	echo 'not has key'
# fi


# read_cfg_key --key gg --file "${CONFIG_FILE}"

# delete_cfg_key --key aa[11] --file "${CONFIG_FILE}"

# commentout_cfg_key --key "aa[11]" --file "${CONFIG_FILE}"

# wite_cfg_key  --key "cc[143]" --val 33 --file "${CONFIG_FILE}"

# linux_type


