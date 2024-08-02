#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * prompt for current user password
#  * prompt user for Pre-Boot Authentication password
#  * grant current user privileges to unlock FileVault
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

    display_message 'The Software Update preference pane in System Settings (System Preferences) needs to be opened to proceed with performing updates.'
    printf "\n"
    display_message 'Once the Software Update pane is displayed follow the on-screen prompts to perform any updates.'
    printf "\n"
    display_message 'Restart the computer if prompted once updates have finished installing.  Note that you may be presented with the option with authenticate using either the current user account or the Pre-Boot Authentication; you should use the current user account to authenticate.'
    printf "\n"
    display_message 'After the updates have completed and the computer has been restarted (if prompted), you need to restore the computer'"'"'s security by running the u2b-post-update-clean.command script by double-clicking it in Finder and following the on-screen instructions.' 
    printf "\n"
    read -s -k '?Press any key to continue.'
    printf "\n\n"

    # Open System Settings (System Preferences) to the Software Update pane
    open -b com.apple.systempreferences /System/Library/PreferencePanes/SoftwareUpdate.prefPane

    kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`
  else
    display_error 'The `preboot` account does not exist!  Exiting...'
    exit 1
  fi
}

main "$@"

exit 0
