#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * prompt user for Preboot Authentication password
#  * prompt user for new Preboot Authentication password
#  * change Preboot Authentication password
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
  typeset new_password

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
    ohai 'Getting password for Preboot Authentication account.'
    get_account_password_aux "preboot"
    printf "\n"

    ohai 'Getting new password for Preboot Authentication account.'
    printf "%s\n" 'Please provide new password for `preboot`.'
    get_password_and_confirm "preboot" new_password
    printf "\n"

    ohai 'Changing `preboot` password.'
    change_preboot_password "${PASSWORDS[preboot]}" "$new_password"

    printf "\n"
    display_message "Done."
    printf "\n"
  else
    display_error 'The `preboot` account does not exist!  Exiting...'
    exit 1
  fi
}

main "$@"

exit 0
