#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * prompt for current user password
#  * prompt user for Pre-Boot Authentication password
#  * grant current user privileges to unlock FileVault
#
# Copyright (c) 2025 Doug Campbell. All rights reserved.

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

TRAPEXIT() {
  [[ $SUDO_INVALIDATE_ON_EXIT -eq 0 ]] && /usr/bin/sudo -k
}

main () {
  prepare_display_environment
  check_run_command_as_root
  check_run_command_as_admin
  
  # get script user password
  # note: we get this separately because we need to have sudo prior to attempting to verify
  #       the remaining accounts just in case they are currently disabled.
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  get_sudo "${PASSWORDS[$SCRIPT_USER]}"
  
  if is_account_exist "preboot"; then
    ohai 'Getting password for Pre-Boot Authentication account.'
    get_account_password_aux "preboot"
    printf "\n"

    # add current user to FileVault (temporarily)
    enable_account "preboot"
    grant_account_filevault_access "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}" "preboot" "${PASSWORDS[preboot]}"
    enable_secure_token_for_account "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}" "preboot" "${PASSWORDS[preboot]}"
    disable_account "preboot"
  fi

  generate_new_filevault_recovery_key "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}"

  if is_account_exist "preboot"; then
    # remove current user from FileVault
    get_sudo "${PASSWORDS[$SCRIPT_USER]}"
    remove_filevault_unlock_for_other_users
  fi

  printf '\n'
  display_warning "A FileVault recovery key has been generatered and stored in the same folder as this script. The filename begins with this device's serial # "$(get_serial_number)"."
  printf '\n'
  display_message "Copy this file to a safe location (e.g. Google Drive) before proceeding."

  printf '\n'
  read -s -k '?Press any key to continue.'
  printf '\n'

  kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`
}

main "$@"

exit 0
