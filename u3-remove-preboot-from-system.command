#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * if Pre-Boot Authentication account exists, it removes it from the system
#    while granting FileVault privileges to all user accounts for which
#    passwords have been provided.
#
# Copyright (c) 2023 Doug Campbell. All rights reserved.

SCRIPT_DIR=$( cd -- "$( dirname -- "${(%):-%x}" )" &> /dev/null && pwd )

. "${SCRIPT_DIR}/lib/config.sh"
. "${SCRIPT_DIR}/lib/display.sh"
. "${SCRIPT_DIR}/lib/filevault.sh"
. "${SCRIPT_DIR}/lib/globals.sh"
. "${SCRIPT_DIR}/lib/input.sh"
. "${SCRIPT_DIR}/lib/logging.sh"
. "${SCRIPT_DIR}/lib/preboot.sh"
. "${SCRIPT_DIR}/lib/quoting.sh"
. "${SCRIPT_DIR}/lib/system.sh"
. "${SCRIPT_DIR}/lib/util.sh"

SCRIPT_USER=$(logname)

# set LOG_SECRETS to 0 to include some passwords in logs
LOG_SECRETS=1

TRAPEXIT() {
  [[ $SUDO_INVALIDATE_ON_EXIT -eq 0 ]] && /usr/bin/sudo -k
}

main () {
  typeset filevault_state
  typeset fv_username
  typeset main_username
  typeset username
  typeset secure_token_user_username
  typeset -a other_choices_with_password
  typeset -a other_choices_without_password
  typeset -a security_levels=("EXTREME" "HIGH")

  get_fullpath_to_logfile LOGFILE
  
  prepare_display_environment

  # first, check if there is even a preboot account to be rmeoved
  if ! is_account_exist "preboot"; then
    display_error 'This system does not contain a Pre-Boot Authentication account to be removed.'
    return
  fi

  check_run_command_as_root
  check_run_command_as_admin
  
  # get script user password
  # note: we get this separately because we need to have sudo prior to attempting to verify
  #       the remaining accounts just in case they are currently disabled.
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  get_sudo "${PASSWORDS[$SCRIPT_USER]}"

  get_login_account_list
  get_info_all_login_accounts
  get_filevault_account_list
  get_passwords_for_remaining_login_accounts
  get_filevault_state filevault_state
  check_all_login_accounts_for_problem_passwords
  log_variable_state "$main_username" "$fv_username" "$secure_token_user_username"

  get_privileged_accounts "$filevault_state" main_username fv_username secure_token_user_username

  log_message 'Checkpoint 19'
  log_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  [[ $LOG_SECRETS -eq 0 ]] && log_message 'preboot password: '${PASSWORDS[preboot]}
  update_secure_token_holder_list
  enable_secure_token_for_all_accounts $main_username
  confirm_all_login_account_passwords_meet_requirements
  update_secure_token_holder_list
  enable_secure_token_for_all_accounts $main_username

  log_message 'Checkpoint 26'
  log_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  if [[ "$filevault_state" == "on" ]]; then
    log_message 'Checkpoint 27'
    enable_filevault_access_for_all_accounts $main_username
  else
    enable_filevault $main_username
    enable_filevault_access_for_all_accounts $main_username
    disable_filevault "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}"
  fi
  remove_account "preboot" && ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#preboot}")

  log_message 'Checkpoint 28'
  log_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  disable_accounts_without_provided_password
}

main "$@"

printf '\n'
display_message "The script has completed running."
printf "\n"
read -s -k '?Press any key to continue.'

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
