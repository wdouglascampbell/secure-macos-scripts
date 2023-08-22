#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * 
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

# don't log to file
LOGFILE=/dev/null

TRAPEXIT() {
  [[ $SUDO_INVALIDATE_ON_EXIT -eq 0 ]] && /usr/bin/sudo -k
}

main () {
  get_fullpath_to_logfile LOGFILE
  
  prepare_display_environment
  check_run_command_as_root
  
  # get script user password
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  # Get major OS version (uses uname -r and zsh parameter substitution)
  # osvers is 20 for 11.0, 21 for 12.0, 22 for 13.0, etc.
  osversionlong=$(uname -r)
  osvers=${osversionlong/.*/}
  (( true_os_version=osvers-9 ))
  true_os_version_long=${osversionlong/#${osvers}/${true_os_version}}
  ohai "OS Version is $true_os_version_long"
  
  ohai "Securing User-Specific Settings"

  ohai "Configuring screensaver to activate after 10 minutes of inactivity."
  defaults -currentHost write com.apple.screensaver idleTime -int 600

  ohai "Requiring password to unlock once sleep or screensaver has been active for 5 seconds."
  sysadminctl -screenLock 5 -password "${PASSWORDS[$username]}"

  ohai "Disabling notifications on lock screen, at sleep and while sharing/mirroring screen."
  enable_do_not_disturb "$username"

  ohai "Disabling Bluetooth sharing."
  defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool no

  ohai "Enabling automatic empty of trash after 30 days."
  defaults write com.apple.finder FXRemoveOldTrashItems -int 1

  ohai "Disabling collection of Siri & Dictation data."
  defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 0

  ohai "Disabling personalized ads."
  defaults write com.apple.AdLib allowApplePersonalizedAdvertising -int 0

  # Prevent the creation of .DS_Store files on network volumes
  # Note: This setting will not take effect until after logout
  ohai "Preventing creation of .DS_Store files."
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool yes

  ohai "Disable Siri."
  defaults write com.apple.Siri StatusMenuVisible -bool NO
  defaults write com.apple.Siri VoiceTriggerUserEnabled -bool NO
  defaults write com.apple.assistant.support "Assistant Enabled" -bool NO
  launchctl unload /System/Library/LaunchAgents/com.apple.Siri.agent.plist

  # macOS 13 (Ventura) and later
  if [[ $true_os_version -ge 13 ]]; then
    display_message 'System Settings (System Preferences) will be opened.'
    display_message 'Please perform the following manual steps.'
    display_message '1.  Select "No One" from the "Air Drop" drop-down list.'
    display_message '2.  Quit System Settings (System Preferences).'

    printf '\n'
    display_message 'Once you are done, return to this screen to continue.'

    open "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"

    printf '\n'
    read -s -k '?Press any key to continue.'
    printf '\n'
  fi
}

main "$@"

printf '\n'
display_message "The script has completed running."
printf '\n'
read -s -k '?Press any key to continue.'

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
