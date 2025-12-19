#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

get_fullpath_to_logfile () {
  typeset _logfile=$1
  typeset logfile_basename
  typeset -i prev_run_iteration
  typeset serial_num

  serial_num=$(get_serial_number)
  logfile_basename="$(date +"%Y-%m-%d")-${serial_num}-script-1--"

  # generate logfile name
  prev_run_iteration=$(ls "${SCRIPT_DIR}/log/${logfile_basename}"* | sort -rV | head -n 1 | sed -E "s/.*--([[:digit:]]*)/\1/") 2>/dev/null
  prev_run_iteration=${prev_run_iteration:-0}

  : ${(P)_logfile::="${SCRIPT_DIR}/log/${logfile_basename}$((++prev_run_iteration))"}
}

log_message () {
  typeset msg

  text=("${(@f)$(printf "%s" "$(shell_join "$@")" | fold -sw 70)}")
  printf "$(date +"%H:%M:%S") | %s\n" "${text[1]}" >>"$LOGFILE"

  text=("${text[@]:1}")
  for msg in "${text[@]}"
  do
    printf "           %s\n" "$msg" >>"$LOGFILE"
  done
}

log_variable_state () {
  log_message 'Variable State'
  log_message '  LOGIN_ACCOUNTS: '${LOGIN_ACCOUNTS[@]}
  log_message '  FILEVAULT_ENABLED_ACCOUNTS: '${FILEVAULT_ENABLED_ACCOUNTS[@]}
  log_message '  Usernames of PASSWORDS provided: '${(k)PASSWORDS[@]}
  log_message '  ADMINS: '${ADMINS[@]}
  log_message '  DISABLED_ACCOUNTS: '${DISABLED_ACCOUNTS[@]}
  log_message '  SECURE_TOKEN_HOLDERS: '${SECURE_TOKEN_HOLDERS[@]}
  log_message '  ACCOUNTS_TO_DISABLE: '${ACCOUNTS_TO_DISABLE[@]}
  log_message '  ACCOUNTS_WITH_PROBLEM_PASSWORDS: '${ACCOUNTS_WITH_PROBLEM_PASSWORDS[@]}
  log_message '  main_username: '$1
  log_message '  fv_username: '$2
  log_message '  secure_token_user_username: '$3
}


