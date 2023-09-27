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
  execute_sudo "launchctl" "unload" "-w" "/System/Library/LaunchDaemons/com.apple.screensharing.plist" >/dev/null 2>&1
  
  ohai "Disabling file sharing."
  execute_sudo "launchctl" "unload" "-w" "/System/Library/LaunchDaemons/com.apple.smbd.plist" >/dev/null 2>&1
  
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
  execute_sudo "launchctl" "unload" "-w" "/System/Library/LaunchDaemons/ssh.plist" >/dev/null 2>&1
  
  ohai "Disabling remote management."
  execute_sudo "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart" "-deactivate" "-stop" >/dev/null 2>&1
  
  ohai "Disabling remote Apple events."
  execute_sudo "launchctl" "unload" "-w" "/System/Library/LaunchDaemons/com.apple.eppc.plist" >/dev/null 2>&1
  
  ohai "Disbling Touch ID for account unlock."
  execute_sudo "bioutil" "-s" "-w" "-u" "0" >/dev/null 2>&1

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

  display_message 'System Settings (System Preferences) will be opened.'
  display_message 'Please perform the following manual steps.'
  display_message '1.  Click the lock icon and enter your password. (macOS 12 Monterey only)'
  display_message '2.  Click the "System Services" Details button.'
  display_message '3.  Move the slider for "Location-based alerts" to the off position. (macOS 12 Monterey and macOS 13 Ventura)'
  display_message '4.  Move the slider for "Location-based suggestions" to the off position. (macOS 12 Monterey and macOS 13 Ventura)'
  display_message '5.  Move the slider for "Significant Locations" to the off position.'
  display_message '6.  Move the slider for "Mac Analytics" to the off position. (macOS 13 Ventura and later)'
  display_message '7.  Click Done.'
  display_message '8.  Quit System Settings (System Preferences).'
  printf '\n'
  display_message 'Once you are done, return to this screen to continue.'

  open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"

  printf '\n'
  read -s -k '?Press any key to continue.'

  # macOS 13 (Ventura) and later
  if [[ $true_os_version -ge 13 ]]; then
    # Note: This setting applies for all accounts so if any user signed in with an Apple ID changes it
    #       the change will apply to all accounts.
    display_message 'System Settings (System Preferences) will be opened.'
    display_message 'Please perform the following manual steps.'
    display_message '1.  Click "Analytics & Improvements".'
    display_message '2.  If a slider is present for "Share iCloud Analytics", move it to the off positions.'
    display_message '3.  Quit System Settings (System Preferences).'

    printf '\n'
    display_message 'Once you are done, return to this screen to continue.'

    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"

    printf '\n'
    read -s -k '?Press any key to continue.'
  fi
}

main "$@"

printf '\n'
display_message "The script has completed running."
printf '\n'
read -s -k '?Press any key to continue.'

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
