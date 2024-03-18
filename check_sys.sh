function check_sys_(){

  if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then

    # check system version number
    local centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')
    if [[ -z ${centosVersion} ]] && grep </etc/centos-release "release 8"; then
      centosVersion=8
    fi
    release="centos"

  elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then

    # check system version number
    if grep </etc/issue -i "8"; then
      debianVersion=8
    fi
    release="debian"

  elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
    release="ubuntu"
    ubuntuVersion=$(lsb_release -r --short)
  fi

  if [[ -z ${release} ]]; then
    echo "Other system"
  else
    echo "${release}"
  fi
}
