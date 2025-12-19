#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * Ensure all *enabled* login accounts have passwords that meet the
#    complexity requirements for HIGH or EXTREME locations.
#  * Ensure all login accounts have a SECURE TOKEN.
#  * Ensure all login accounts for HIGH locations have access to
#    unlock FileVault.
#  * Ensure a preboot account exists and is configured as the only account that
#    can unlock FileVault for EXTREME locations
#  * Ensure a preboot account is configured to only unlock FileVault for
#    EXTREME locations and is not used as a regular user account.
#  * Provide a smooth transition between HIGH and EXTREME configurations
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
  typeset choice
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
  check_run_command_as_root
  check_run_command_as_admin
  
  printf "%s\n" "A security level choice must be made."
  PS3="Select security level: "
  select_with_default security_levels "EXTREME" choice
  [[ $choice == "EXTREME" ]] && EXTREME=0 || EXTREME=1
  
  [[ $EXTREME -eq 0 ]] && ohai 'Current Security Level: EXTREME' || ohai 'Current Security Level: HIGH'

  # get script user password
  # note: we get this separately because we need to have sudo prior to attempting to verify
  #       the remaining accounts just in case they are currently disabled.
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  get_sudo "${PASSWORDS[$SCRIPT_USER]}"
  
  check_for_security_level_downgrade_attempt

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
  if [[ $EXTREME -eq 0 ]]; then
    log_message 'Checkpoint 27'
    configure_preboot_account
    configure_filevault_extreme $main_username
  else
    log_message 'Checkpoint 28'
    [[ "$filevault_state" == "off" ]] && enable_filevault $main_username
    log_message 'Checkpoint 29'
    enable_filevault_access_for_all_accounts $main_username
    is_account_exist "preboot" && remove_account "preboot" && ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#preboot}")
    show_others_option_from_login_screen
  fi

  log_message 'Checkpoint 30'
  log_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  disable_accounts_without_provided_password

  if [[ "$filevault_state" == "off" ]]; then
    # FileVault was initially disabled so it must have just been enabled.
    printf '\n'
    display_warning "A FileVault recovery key has been generatered and stored in the same folder as this script. The filename begins with this device's serial # "$(get_serial_number)"."
    printf '\n'
    display_message "Copy this file to a safe location (e.g. Google Drive) before proceeding."

    printf '\n'
    read -s -k '?Press any key to continue.'
    printf '\n'
  fi
}

main "$@"

printf '\n'
display_message "The script has completed running."
printf '\n'

if [[ $EXTREME -eq 0 ]]; then
  display_message 'It is strongly recommended that you reboot the computer and practice unlocking the disk encryption by using the new "Pre-Boot Authentication" account to authenticate'
else
  display_message 'It is strongly recommended that you reboot the computer and practice unlocking the disk encryption.'
fi
printf "\n"

ask_yes_no "Reboot now? (y/n)"
if [[ $? -eq 0 ]]; then
  clear
  printf '\n'
  display_message "Restarting computer in 5 seconds..."
  printf '\n'
  display_message "If a dialog appears stating '"'"Terminal" wants access to control "System Events". Allowing control will provide access to documents and data in "System Events", and to perform actions within that app.'"' Please click 'OK'."
  printf '\n'
  display_message "If a dialog appears stating '"'"System Events" would like to access files in your Desktop folder.'"' Please click 'OK'."

  # deploy temporary script to run at next login that will close the Terminal window
  # and remove all traces of itself from the system.
  cat > "${SCRIPT_DIR}/close-terminal.command" << EOF
#!/usr/bin/env zsh
osascript -e 'tell application "System Events" to delete login item "close-terminal.command"'
rm "${SCRIPT_DIR}/close-terminal.command"
kill \$(ps -A | grep -w Terminal.app | grep -v grep | awk '{print \$1}')
EOF
  chmod +x "${SCRIPT_DIR}/close-terminal.command"
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"'${SCRIPT_DIR}'/close-terminal.command", hidden:false}' >/dev/null 2>&1
  sleep 5
  execute_sudo "reboot"
fi

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
