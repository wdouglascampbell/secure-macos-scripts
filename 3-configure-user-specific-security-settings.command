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
  check_run_command_as_admin
  
  # get script user password
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  get_sudo "${PASSWORDS[${SCRIPT_USER}]}"

  # Get major OS version (uses uname -r and zsh parameter substitution)
  # osvers is 20 for 11.0, 21 for 12.0, 22 for 13.0, etc.
  osversionlong=$(uname -r)
  osvers=${osversionlong/.*/}
  (( true_os_version=osvers-9 ))
  true_os_version_long=${osversionlong/#${osvers}/${true_os_version}}
  ohai "OS Version is $true_os_version_long"
  
  if ! xcode-select -p &>/dev/null; then
    ohai "Installing Command Line Tools…"

    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    CLT=$(softwareupdate -l 2>/dev/null | \
      awk -F': ' '/Command Line Tools for Xcode/ {print $2; exit}')

    if [[ -z "$CLT" ]]; then
      echo "ERROR: Could not find Command Line Tools label"
      exit 1
    fi

    execute_sudo "softwareupdate" "-i" "$CLT" "--verbose"

    rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    ohai "\"Warming Up Swift\". This can take up to 2 minutes. Please wait..."
    swift - <<'EOF' >/dev/null
import Cocoa
print("warming Cocoa...")
EOF
  fi

  ohai "Securing User-Specific Settings"

  ohai "Configuring screensaver to activate after 10 minutes of inactivity."
  defaults -currentHost write com.apple.screensaver idleTime -int 600

  ohai "Requiring password to unlock once sleep or screensaver has been active for 5 seconds."
  sysadminctl -screenLock 5 -adminUser "${SCRIPT_USER}" -adminPassword "${PASSWORDS[${SCRIPT_USER}]}" -password "${PASSWORDS[${SCRIPT_USER}]}"

  ohai "Disabling notifications on lock screen, at sleep and while sharing/mirroring screen."
  # macOS 15 (Sequoia) and earlier
  if [[ $true_os_version -lt 16 ]]; then
    enable_do_not_disturb "${SCRIPT_USER}"
  else
    open_system_settings "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    # Note: there is often a timing issue and so in order to properly bring System Settings to
    #       the foreground, it must be opened a second time.
    open_system_settings "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/restrict_notification_display.json"
    osascript -e 'activate application "Terminal"'
  fi

  ohai "Disabling Bluetooth sharing."
  defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool no

  ohai "Enabling automatic empty of trash after 30 days."
  defaults write com.apple.finder FXRemoveOldTrashItems -int 1

  ohai "Disabling collection of Siri & Dictation data."
  defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 0

  # macOS 15 (Sonoma) and later
  if [[ $true_os_version -ge 15 ]]; then
    ohai "Disable Improve Assistive Voice Features"
    open_system_settings "x-apple.systempreferences:com.apple.preference.security"
    /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_sharing_of_information_per_user.json"
    osascript -e 'activate application "Terminal"'
  fi

  ohai "Disabling personalized ads."
  defaults write com.apple.AdLib allowApplePersonalizedAdvertising -int 0

  # Prevent the creation of .DS_Store files on network volumes
  # Note: This setting will not take effect until after logout
  ohai "Preventing creation of .DS_Store files."
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool yes

  ohai "Disable Siri."
  if [[ $true_os_version -lt 16 ]]; then
    defaults write com.apple.Siri StatusMenuVisible -bool NO
    defaults write com.apple.Siri VoiceTriggerUserEnabled -bool NO
    defaults write com.apple.assistant.support "Assistant Enabled" -bool NO
    launchctl unload /System/Library/LaunchAgents/com.apple.Siri.agent.plist 1>&2 2>/dev/null | true
    killall SystemUIServer
  else
    # macOS 26 (Tahoe) and later
    open "x-apple.systempreferences:com.apple.preference"
    /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_siri.json"
  fi

  ohai "Disable Air Drop."
  open "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"
  /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_air_drop.json"

  osascript -e 'tell application "System Settings" to quit'
  osascript -e 'activate application "Terminal"'
}

main "$@"

printf '\n'
display_message "The script has completed running."
printf '\n'
read -s -k '?Press any key to continue.'

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
