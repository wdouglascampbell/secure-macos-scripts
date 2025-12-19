#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

unset HAVE_SUDO_ACCESS # unset this from the environment

abort () {
  printf "%s\n" "$@" >&2
  exit 1
}

check_run_command_as_admin () {
  if [[ $(id -p | grep "^groups" | grep -E " admin | admin$" | wc -l) -ne 1 ]]; then
    display_error 'The current user `'$(id -un)'` is not an administrator. This script must be run from an administrator account.'
    read -s -k '?Press any key to continue.'
    printf "\n"
    exit 1
  fi
}

check_run_command_as_root() {
  [[ "${EUID:-${UID}}" == "0" ]] || return

  abort "Don't run this as root!"
}

have_sudo_access () {
  if [[ ! -x "/usr/bin/sudo" ]]
  then
    return 1
  fi

  local -a SUDO=("/usr/bin/sudo")
  if [[ -n "${SUDO_ASKPASS-}" ]]
  then
    SUDO+=("-A")
  elif [[ -n "${NONINTERACTIVE-}" ]]
  then
    SUDO+=("-n")
  fi

  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]
  then
    if [[ -n "${NONINTERACTIVE-}" ]]
    then
      "${SUDO[@]}" -l mkdir &>/dev/null
    else
      "${SUDO[@]}" -v && "${SUDO[@]}" -l mkdir &>/dev/null
    fi
    HAVE_SUDO_ACCESS="$?"
  fi

  if [[ "${HAVE_SUDO_ACCESS}" -ne 0 ]]
  then
    abort "Need sudo access (e.g. the user ${USER} needs to be an Administrator)!"
  fi

  return "${HAVE_SUDO_ACCESS}"
}

execute () {
  local abort_on_fail=1

  # check if first argument is --no-abort
  if [[ "$1" == "--no-abort" ]]; then
    abort_on_fail=0
    shift
  fi

  if ! "$@"; then
    if (( abort_on_fail )); then
      abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
    else
      # just return non-zero, but continue
      return 1
    fi
  fi
}

execute_sudo () {
  local -a args=("$@")
  local abort_on_fail=1

  if [[ "$1" == "--no-abort" ]]; then
    abort_on_fail=0
    shift
    args=("$@")
  fi

  if have_sudo_access
  then
    if [[ -n "${SUDO_ASKPASS-}" ]]
    then
      args=("-A" "${args[@]}")
    fi
    #ohai "/usr/bin/sudo" "${args[@]}"
    execute $( ((abort_on_fail)) && echo "" || echo "--no-abort" ) "/usr/bin/sudo" "${args[@]}"
  else
    #ohai "${args[@]}"
    execute $( ((abort_on_fail)) && echo "" || echo "--no-abort" ) "${args[@]}"
  fi
}

shell_join () {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

