#!/usr/bin/env bash



CMD=yxfirewall


source yxlogger
source yxsafecmd

####################################################################################################
# command
####################################################################################################

function cmd_install()
{
  local script_path=$(pwd)
  local bin_path=
  local lib_path=
  local command=

  while [ $# -gt 0 ]; do
		case $1 in

      --bin-path )
        shift
        bin_path=$1
      ;;

      --lib-path )
        shift
        lib_path=$1
      ;;

      --command )
        shift
        command=$1
      ;;


      *)
        yx_fatal "unknown params $1."
      ;;
    esac
    shift
  done


  if [[ -z "${command}" ]]; then
    yx_fatal "command is empty"
  fi
  if [[ "${command}" != "${CMD}" ]]; then
    yx_fatal "unknown command ${CMD}"
  fi

  if [ -z "${bin_path}" ]; then
    yx_fatal "bin path is empty"
  fi
  if ! [[ -d "${bin_path}" ]]; then
    yx_fatal "target directory not exist:${bin_path}"
  fi

  if [ -z "${lib_path}" ]; then
    yx_fatal "failed to get library path"
  fi

  # verify the pwd
  if ! [ -f "${script_path}/.yxct.setup.sh" ]; then
    yx_fatal "Current working directory not correct:${script_path}"
  fi


  # remove old libpath if exist
  local cmd_lib_path="${lib_path%\/}/${command}"
  if [ -d "${cmd_lib_path}" ]; then
    if ! yx_verbcmd "${RM} -rf ${cmd_lib_path}"; then
      yx_fatal "failed to remove old lib"
    fi
  fi


  # create lib dir
  yx_verbcmd "${MKDIR} -p ${cmd_lib_path}"
  if ! [ -d "${cmd_lib_path}" ]; then
    yx_fatal "failed to make dir:${cmd_lib_path}"
  fi


  # copy whole dir to lib
  yx_verbcmd "${CP} -R ${PWD}/. ${cmd_lib_path}"
  if [[ $? != 0 ]]; then
    yx_fatal "failed to copy yxlib to ${cmd_lib_path}"
  fi
  yx_verbcmd "${CHMOD} -R 755 ${cmd_lib_path}"
  if [[ $? != 0 ]]; then
    yx_fatal "faild to change yxlib's authorization"
  fi


  # link command to bin path
  if ! yx_verbcmd "${LN} -sf ${cmd_lib_path}/${CMD} ${bin_path%/}/${command}"; then
    yx_fatal "faild to link command to ${bin_path}"
  fi


  return 0
}

function cmd_uninstall()
{

  local script_path=$(pwd)
  local command=
  local bin_path=
  local lib_path=

  while [ $# -gt 0 ]; do
		case $1 in

      --bin-path )
        shift
        bin_path=$1
      ;;

      --lib-path )
        shift
        lib_path=$1
      ;;

      --command )
        shift
        command=$1
      ;;

      *)
        yx_fatal "Unknown params $1"
      ;;
    esac
    shift
  done



  if [[ -z "${command}" ]]; then
    yx_fatal "Command is empty"
  fi
  if [[ "${command}" != "${CMD}" ]]; then
    yx_fatal "Unknown command ${command}"
  fi

  if [ -z "${bin_path}" ]; then
    yx_fatal "bin path is empty"
  fi
  if ! [[ -d "${bin_path}" ]]; then
    yx_fatal "target directory not exist:${bin_path}"
  fi

  if [ -z "${lib_path}" ]; then
    yx_fatal "failed to get library path"
  fi


  # verify the pwd
  if ! [ -f "${script_path}/.yxct.setup.sh" ]; then
    yx_fatal "Current working directory not correct:${script_path}"
  fi


  local has_err=false

  # remove ${CMD} from bin-path
  local execute_file="${bin_path}/${command}"
  if [ -x "${execute_file}" ]; then
    
    if ! yx_verbcmd "${RM} -f ${execute_file}"; then
      yx_err "failed to remove ${execute_file}"
      has_err=true
    fi
  else
    yx_err "Can not found ${CMD} on path:${execute_file}"
    has_err=true
  fi


  # remove library
  local cmd_lib_path="${lib_path%\/}/${command}"
  if ! yx_verbcmd "${RM} -rf ${cmd_lib_path}"; then
    has_err=true
    yx_err "failed to remove library:${cmd_lib_path}"
  fi


  ${has_err} && return 1 || return 0

}



####################################################################################################
# Entry
####################################################################################################


# Force root
if [ "$(id -u)" -ne 0 ]; then
  yx_fatal "'${CMD} should run with root"
fi


sub_cmd=$1
shift
if [[ -z ${sub_cmd} ]]; then
  yx_fatal "param error."
fi



if [[ ${sub_cmd} == 'install' ]]; then
  cmd_install $@
elif [[ ${sub_cmd} == 'uninstall' ]]; then
  cmd_uninstall $@
else
  yx_fatal "unknown sub command:'${sub_cmd}'."
fi

