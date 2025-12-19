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
  typeset temp_exports_created=1

  get_fullpath_to_logfile LOGFILE
  
  prepare_display_environment
  check_run_command_as_root
  check_run_command_as_admin
  
  # get script user password
  ohai 'Getting password for account currently running this script.'
  get_account_password_aux $SCRIPT_USER
  printf '\n'
  
  get_sudo "${PASSWORDS[$SCRIPT_USER]}"
  
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

  ohai "Checking whether Terminal has Full Disk Access"
  local has_terminal_full_disk_access
  local switch_state
  [[ "$(execute_sudo systemsetup -getremotelogin 2>/dev/null)" == *On* ]] && switch_state="off" || switch_state="on"
  [[ "$(execute_sudo systemsetup -f -setremotelogin $switch_state 2>&1)" == *"requires Full Disk Access privileges"* ]] &&
    has_terminal_full_disk_access=0 || has_terminal_full_disk_access=1

  if (( ! has_terminal_full_disk_access )); then
    ohai "Terminal does not have Full Disk Access."
    ohai "Displaying instructions for enabling Full Disk Access for Terminal."
    open_system_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    # Note: there is often a timing issue and so in order to properly bring System Settings to
    #       the foreground, it must be opened a second time.
    open_system_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/enable_fda_instructions.json"
    osascript -e 'activate application "Terminal"'
  fi

  ohai "Securing System-Wide Settings"

  # Configure Firewall
  ohai "Enabling firewall."
  execute_sudo "/usr/libexec/ApplicationFirewall/socketfilterfw" "--setglobalstate" "on" >/dev/null 2>&1
  
  ohai "Enabling stealth mode."
  execute_sudo "/usr/libexec/ApplicationFirewall/socketfilterfw" "--setstealthmode" "on" >/dev/null 2>&1
  
  ohai "Allowing built-in software to receive incoming connections automatically."
  execute_sudo "/usr/libexec/ApplicationFirewall/socketfilterfw" "--setallowsigned" "on" >/dev/null 2>&1
  
  ohai "Allowing downloaded signed software to receive incoming connections automatically."
  execute_sudo "/usr/libexec/ApplicationFirewall/socketfilterfw" "--setallowsignedapp" "on" >/dev/null 2>&1
  
  # Configure Guest Account
  ohai "Disabling guest access."
  execute_sudo "sysadminctl" "-guestAccount" "off" >/dev/null 2>&1
  
  ohai "Preventing guest user from connecting to shared folders."
  execute_sudo "defaults" "write" "/Library/Preferences/SystemConfiguration/com.apple.smb.server" "AllowGuestAccess" "-bool" "NO"
  
  ohai "Disabling screen sharing."
  execute_sudo "launchctl" "disable" "system/com.apple.screensharing" >/dev/null 2>&1
  
  ohai "Stopping SMB daemon."
  execute_sudo --no-abort "launchctl" "bootout" "system" "/System/Library/LaunchDaemons/com.apple.smbd.plist" >/dev/null 2>&1
  execute_sudo "launchctl" "disable" "system/com.apple.smbd"

  ohai "Disabling SMB in preferences."
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.smb.server" "SharingEnabled" "-bool" "false" >/dev/null 2>&1
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.sharingd.plist" "ServerServices" "-dict-add" "SMB" "-bool" "false" >/dev/null 2>&1

  # Disable NFS
  ohai "Disabling NFS."
  if [[ ! -f /etc/exports ]]; then
    execute_sudo "touch" "/etc/exports"
    temp_exports_created=0
  fi
  execute_sudo "nfsd" "stop" >/dev/null 2>&1
  execute_sudo "nfsd" "disable" >/dev/null 2>&1
  [[ $temp_exports_created -eq 0 ]] && execute_sudo "rm" "-f" "/etc/exports"
  
  ohai "Disabling Internet sharing."
  execute_sudo "defaults" "write" "/Library/Preferences/SystemConfiguration/com.apple.nat" "NAT" "-dict" "Enabled" "-int" "0" >/dev/null 2>&1
 
  ohai "Disabling remote login."
  execute_sudo "systemsetup" "-f" "-setremotelogin" "off" >/dev/null 2>&1

  ohai "Disabling remote management."
  execute_sudo "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart" "-deactivate" "-stop" >/dev/null 2>&1

  ohai "Disabling remote Apple events."
  execute_sudo --no-abort "systemsetup" "-setremoteappleevents" "off" >/dev/null 2>&1

  # Restart sharingd to reload preferenes that have been changed
  ohai "Restarting sharingd."
  execute_sudo "killall" "sharingd"

  ohai "Disbling Touch ID for account unlock."
  execute_sudo --no-abort "bioutil" "-s" "-w" "-u" "0" >/dev/null 2>&1

  ohai "Enabling automatic check for software updates on macOS 11 and later."
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticCheckEnabled" "-bool" "yes"
  
  ohai "Enabling automatic download of software updates."
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.SoftwareUpdate" "AutomaticDownload" "-bool" "yes"
  
  ohai "Enabling installation of critical updates."
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.SoftwareUpdate" "CriticalUpdateInstall" "-bool" "yes"
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.SoftwareUpdate" "ConfigDataInstall" "-bool" "yes"

  ohai "Enabling automatic updates of App Store apps."
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.commerce" "AutoUpdate" "-bool" "yes"

  ohai "Disabling sharing crash and usage data with app developers."
  execute_sudo "defaults" "write" "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" "ThirdPartyDataSubmit" "-int" "0"

  ohai "Disabling Mac Analytics."
  execute_sudo "defaults" "write" "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" "AutoSubmit" "-int" "0"

  ohai "Update System Services Details Settings."
  open_system_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
  /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/system_services_details.json"

  # Note: This setting applies for all accounts so if any user signed in with an Apple ID changes it
  #       the change will apply to all accounts.
  ohai "Disable sharing iCloud Analytics."
  open_system_settings "x-apple.systempreferences:com.apple.preference.security?"
  /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_sharing_of_information.json"

  if (( has_terminal_full_disk_access )); then
    # display a warning about leaving Terminal with Full Disk Access
    if /usr/bin/swift "${SCRIPT_DIR}/swift/fda_warning_prompt.swift"; then
      open_system_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
      /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_fda_instructions.json"
    fi
  else
    open_system_settings "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    /usr/bin/swift "${SCRIPT_DIR}/swift/instructions.swift" "${SCRIPT_DIR}/instructions/disable_fda_instructions.json"
  fi

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
