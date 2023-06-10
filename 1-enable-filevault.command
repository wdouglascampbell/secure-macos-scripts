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
  local i
  local preboot_password
  local current_username current_password new_current_password
  local selected_username selected_password new_selected_password
  declare -a fv_account_list
  declare -a local_account_list
  declare -a secure_token_enabled_account_list
  typeset -A passwords

  prepare_display_environment

  [[ $EXTREME -eq 0 ]] && ohai 'Current Security Level: EXTREME' || ohai 'Current Security Level: HIGH'

  # Make sure current user is admin
  check_run_command_as_admin

  # Invalidate sudo timestamp before exiting (if it wasn't active before).
  if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
  then
    trap '/usr/bin/sudo -k' EXIT
  fi

  ohai 'Checking for `sudo` access (which may request your password)...'
  have_sudo_access
  echo

  is_account_exist "preboot"; PREBOOT_ACCOUNT_EXISTS=$?

  # HIGH security -- check for preboot account existence
  if [[ $EXTREME -eq 1 ]]; then
    if [[ $PREBOOT_ACCOUNT_EXISTS -eq 0 ]]; then
      display_warning 'The selected security level is HIGH but it appears this computer may have been configured at least partially at the EXTREME security level. We recommend that you not lower the security protection of this device and instead retain the security level at EXTREME.'
      ask_yes_no "Should the security level be retained at EXTREME? (y/n)"
      if [[ $? -eq 0 ]]; then
        EXTREME=0
        printf "\n"
        ohai 'Updated Security Level: EXTREME'
      fi
    fi
  fi

  if [[ $EXTREME -eq 0 ]]; then
    ohai 'Configure Preboot account.'
    configure_preboot_account preboot_password
    echo
  
    ohai 'Configure FileVault'
    configure_filevault_extreme "$preboot_password"
    echo
  else
    current_username=$(logname)

    get_filevault_state filevault_state
  
    case "$filevault_state" in
  
      "off")
        # *** maybe do not try to do this here ***
        # if filevault is not enabled, remove preboot account if it exists
        ;;

      "decrypting")
        ohai 'FileVault is currently decrypting the drive. Re-run this script once the drive has been fully decrypted in order to re-enable encryption.'
        ;;

      "on")
        printf "\n"
        ohai 'The password for the current account, `'$current_username'`, is required.'
        ohai 'Please enter the password at the prompt.'
        get_account_password "admin" "$current_username" current_password "verify"
        passwords[$current_username]=$current_password

        if ! is_account_secure_token_enabled "$current_username"; then
          printf "\n"
          ohai 'The current account, `'$current_username'`, does not have a secure token.'
          ohai "An account with a secure token is required."
          get_local_account_list local_account_list
          secure_token_enabled_account_list=()
          for i in "${local_account_list[@]}"
          do
            if is_account_secure_token_enabled "$i"; then
              secure_token_enabled_account_list+=("$i")
            fi
          done
          printf "\n"
          printf "%s\n" "Accounts with a secure token"
          PS3="Select account: "
          select_with_default secure_token_enabled_account_list "" selected_username
          [[ $selected_username == "preboot" ]] && enable_account "preboot"
          printf "\n"
          printf "%s\n" 'Please provide password for `'$selected_username'`.'
          get_account_password "admin" "$selected_username" selected_password "verify"
          passwords[$selected_username]=$selected_password
          is_account_admin "$selected_username"
          selected_is_admin=$?
          add_user_to_admin_group "$selected_username"
          enable_secure_token_for_account "$current_username" "$current_password" "$selected_username" "$selected_password"
          [[ $selected_is_admin -ne 0 ]] && remove_user_from_admin_group "$selected_username"
          [[ $selected_username == "preboot" ]] && disable_account "preboot"
        fi

        get_filevault_account_list fv_account_list
        if ! [[ "${fv_account_list[@]}" =~ "${current_username}" ]]; then
          printf "\n"
          ohai "An account with FileVault access is required."
          printf "\n"
          printf "%s\n" "Accounts with a FileVault access"
          PS3="Select account: "
          select_with_default fv_account_list "" selected_username
          [[ $selected_username == "preboot" ]] && enable_account "preboot"
          if [[ -z $passwords[$selected_username] ]]; then
            printf "\n"
            printf "%s\n" 'Please provide password for `'$selected_username'`.'
            get_account_password "admin" "$selected_username" selected_password "verify"
            passwords[$selected_username]=$selected_password
          else
            selected_password=$passwords[$selected_username]
          fi
          is_account_admin "$selected_username"
          selected_is_admin=$?
          add_user_to_admin_group "$selected_username"
          grant_account_filevault_access "$current_username" "$current_password" "$selected_username" "$selected_password"
          [[ $selected_is_admin -ne 0 ]] && remove_user_from_admin_group "$selected_username"
          [[ $selected_username == "preboot" ]] && disable_account "preboot"
        fi

        ohai 'Enable secure token for all local accounts.'
        ohai 'Check that all local accounts on this computer meet password requirements.'
        unset i
        for i in "${local_account_list[@]}"
        do
          [[ $i == "preboot" ]] && continue
          if [[ -z $passwords[$i] ]]; then
            printf "\n"
            printf "%s\n" 'Please provide password for `'$i'`.'
            get_account_password "admin" "$i" i_password "verify"
            passwords[$i]=$i_password
          else
            i_password=$passwords[$i]
          fi

          if ! is_account_secure_token_enabled "$i"; then 
            ohai 'Enabling secure token for account, `'$i'`'
            enable_secure_token_for_account "$current_username" "$current_password" "$i" "$i_password"
          fi

          if ! check_password_complexity "$i_password"; then
            display_error 'The password is correct but it does not meet our requirements. It will need to be changed. Please enter a new password.'
            get_password_and_confirm "admin" "$i" new_i_password

            printf "\n"
            ohai 'Changing `'$i'` account password.'
            change_user_password "$i" "$i_password" "$new_i_password"
            passwords[$i]=$new_i_password
          fi
        done

        ohai 'Enable FileVault access for all local accounts.'
        unset i
        for i in "${local_account_list[@]}"
        do
          [[ $i == "preboot" ]] && continue
          i_password=$passwords[$i]
          
          if ! [[ "${fv_account_list[@]}" =~ "$i{}" ]]; then
            ohai 'Granting FileVault access for account, `'$i'`'
            grant_account_filevault_access "$i" "$i_password" "$current_username" "$current_password"
          fi
        done
        ;;
    esac

    echo "${(kv)passwords[@]}"
    exit

    # if preboot account exists, remove it
    is_account_exist "preboot" && remove_account "preboot"
  fi
}

EXTREME=0

usage=(
  "usage:"
  " $(basename ${(%):-%x}) [-h|--help]"
  " $(basename ${(%):-%x}) [--extreme]"
  " $(basename ${(%):-%x}) [--high]"
)

opterr() { echo >&2 "$(basename ${(%):-%x}): Unknown option '$1'" }

case $# in
  0)
    EXTREME=0
    ;;
  1)
    case $1 in
      -h|--help)  printf "%s\n" $usage && exit 0 ;;
      --extreme)  EXTREME=0                      ;;
      --high)     EXTREME=1                      ;;
      -*)         opterr $1 && exit 1            ;;
    esac
    ;;
  *)
    printf "%s\n" "$(basename ${(%):-%x}): too many arguments"
    exit 1
    ;;
esac

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
