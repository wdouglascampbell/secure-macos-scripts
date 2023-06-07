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

display_message "The script has completed running."
printf "\n"

display_message "It is strongly recommended that you reboot the computer and practice unlocking the disk encryption by using the new "Pre-Boot Authentication" account to authenticate"
printf "\n"

ask_yes_no "Reboot now? (y/n)"
if [[ $? -eq 0 ]]; then
  clear
  printf "\n"
  display_message "Restarting computer in 5 seconds..."
  printf "\n"
  sleep 5

  # deploy temporary script to run at next login that will close the Terminal window
  # and remove all traces of itself from the system.
  cat > "${SCRIPT_DIR}/close-terminal.command" << EOF
#!/usr/bin/env zsh
osascript -e 'tell application "System Events" to delete login item "close-terminal.command"'
rm "${SCRIPT_DIR}/close-terminal.command"
kill \$(ps -A | grep -w Terminal.app | grep -v grep | awk '{print \$1}')
EOF
  chmod +x "${SCRIPT_DIR}/close-terminal.command"
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"'${SCRIPT_DIR}'/close-terminal.command", hidden:false}'
  execute_sudo "reboot"
fi

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
