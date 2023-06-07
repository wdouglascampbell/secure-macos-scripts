#!/usr/bin/env zsh
#
# Ensures FileVault is enabled and only allows preboot account to perform
# preboot authentication.
#
# Copyright (c) 2023 Doug Campbell. All rights reserved.

PREBOOT_PASS_MIN_LENGTH=30

SCRIPT_DIR=$( cd -- "$( dirname -- "${(%):-%x}" )" &> /dev/null && pwd )

. "${SCRIPT_DIR}/lib/display.sh"
. "${SCRIPT_DIR}/lib/filevault.sh"
. "${SCRIPT_DIR}/lib/input.sh"
. "${SCRIPT_DIR}/lib/preboot.sh"
. "${SCRIPT_DIR}/lib/quoting.sh"
. "${SCRIPT_DIR}/lib/system.sh"
. "${SCRIPT_DIR}/lib/util.sh"

main () {
  local preboot_password

  prepare_display_environment

  # Make sure current user is admin
  check_run_command_as_admin

  ohai 'Checking for `sudo` access (which may request your password)...'
  have_sudo_access
  echo
  
  ohai 'Configure Preboot account.'
  configure_preboot_account preboot_password
  echo
  
  ohai 'Configure FileVault'
  configure_filevault "$preboot_password"
  echo
}

# Invalidate sudo timestamp before exiting (if it wasn't active before).
if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
then
  trap '/usr/bin/sudo -k' EXIT
fi

main "$@"

printf "${tty_cyan}%s${tty_reset}\n\n\n" "The script has completed running.  Press Command-W to close this window."
exit 0
