#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

check_for_security_level_downgrade_attempt () {
  if [[ $EXTREME -eq 1 ]]; then
    # HIGH security -- check for preboot account existence
    if is_account_exist "preboot"; then
      display_warning 'The selected security level is HIGH but it appears this computer may have been configured at least partially at the EXTREME security level. We recommend that you not lower the security protection of this device and instead retain the security level at EXTREME.'
      ask_yes_no "Should the security level be retained at EXTREME? (y/n)"
      if [[ $? -eq 0 ]]; then
        EXTREME=0
        printf '\n'
        printf '\n'
        ohai 'Updated Security Level: EXTREME'
      else
        printf '\n'
        printf '\n'
      fi
    fi
  fi
}

configure_filevault_extreme () {
  local filevault_user=$1
  local filevault_state

  get_filevault_state filevault_state

  ohai 'Configuring FileVault'

  case "$filevault_state" in

  "off")
    log_message 'Checkpoint 23 - FileVault Disabled. Proceeding to encrypt,'
    ohai "FileVault is Disabled. Proceeding with encryption..."
    printf '\n'
    display_message "Click 'OK' button in response to the dialog that appears stating that 'fdesetup would like to enable FileVault.'"
    enable_filevault_extreme
    printf '\n'
    ;;

  "decrypting")
    abort 'FileVault is currently decrypting the drive. Re-run this script once the drive has been fully decrypted in order to re-enable encryption.'
    ;;

  "on")
    log_message 'Checkpoint 24 - FileVault Enabled. Check if preboot account can unlock.'
    ohai 'FileVault is Enabled.' 

    # ensure preboot account can unlock FileVault
    if ! (($FILEVAULT_ENABLED_ACCOUNTS[(Ie)preboot])); then
      log_message 'Checkpoint 25 - Granting preboot account FileVault access.'
      ohai '`preboot` account does not have permissions to unlock FileVault.'

      enable_account "preboot"
      grant_account_filevault_access "preboot" "${PASSWORDS[preboot]}" "$filevault_user" "${PASSWORDS[$filevault_user]}"
      disable_account "preboot"
    fi

    hide_account "preboot"
    hide_others_option_from_login_screen
    remove_filevault_unlock_for_other_users
    ;;

  esac
}

disable_filevault () {
  local password

  quote_string_for_use_within_expect_tcl_script_double_quotes "$2" password

  ohai "Disabling FileVault..."
  printf '\n'

  execute_sudo "expect" >/dev/null << EOF
    spawn fdesetup disable -user $1
    expect {
      -re "Enter the password for (the )?user '$1':" {
        send "$password\r"
      }
      default {
        exit 3
      }
    }
    expect {
      "Error: User authentication failed." {
        exit 1
      }
      "FileVault has been disabled." {
        exit 0
      }
    }
    exit 0
EOF
}

get_filevault_account_list () {
  log_message 'Getting list of accounts with FileVault access.'

  FILEVAULT_ENABLED_ACCOUNTS=$(
    execute_sudo "fdesetup" "list" | \
    awk -F ',' '{ printf "%s ", $1 }'
  )

  FILEVAULT_ENABLED_ACCOUNTS=(${(@s: :)FILEVAULT_ENABLED_ACCOUNTS})
}

get_filevault_state () {
  local _state=$1

  log_message 'Getting FileVault state.'

  if [[ $(fdesetup status | grep "FileVault" | grep "On" | wc -l) -eq 1 ]]; then
    if [[ $(fdesetup status | grep "^Decryption in progress" | wc -l) -eq 1 ]]; then
      : ${(P)_state::="decrypting"}
    else
      : ${(P)_state::="on"}
    fi
  else
    : ${(P)_state::="off"}
  fi
}

enable_filevault () {
  typeset is_account_enabled

  ohai "FileVault is Disabled. Proceeding with encryption..."
  printf '\n'
  display_message "Click 'OK' button in response to the dialog that appears stating that 'fdesetup would like to enable FileVault.'"
  is_account_enabled=$(pwpolicy -u $1 authentication-allowed | grep -c "is disabled")
  enable_account "$1"
  add_user_to_admin_group "$1"
  encrypt_using_fdesetup_with_expect "$1" "${PASSWORDS[$1]}"
  [[ $is_account_enabled -ne 0 ]] && disable_account "$1"
  ! (($ADMINS[(Ie)$1])) && remove_user_from_admin_group "$1"
}

enable_filevault_access_for_all_accounts () {
  typeset username

  ohai 'Enabling FileVault access for all accounts.'

  printf '\n'
  display_message "If a dialog appears stating '"'"Terminal" would like to administer your computer. Administration can include modifying passwords, networking, and system settings.'"'. Please click 'OK'."
  printf '\n'

  for username in "${LOGIN_ACCOUNTS[@]}"
  do
    [[ "$username" == "preboot" ]] && continue
    (($DISABLED_ACCOUNTS[(Ie)$username])) && continue

    if ! (($FILEVAULT_ENABLED_ACCOUNTS[(Ie)$username])); then
      log_message 'Granting FileVault access for account, `'$username'`'
      [[ "$1" == "preboot" ]] && enable_account "preboot"
      grant_account_filevault_access "$username" "${PASSWORDS[$username]}" "$1" "${PASSWORDS[$1]}"
      [[ "$1" == "preboot" ]] && disable_account "preboot"
    fi
  done
}

enable_filevault_extreme () {
  enable_account "preboot"

  # fdesetup complains when a non-admin account is used to enable FileVault
  # even though it will still enable FileVault so temporarily add preboot
  # to admin group.
  add_user_to_admin_group "preboot"

  encrypt_using_fdesetup_with_expect "preboot" "${PASSWORDS[preboot]}"

  hide_others_option_from_login_screen

  remove_user_from_admin_group "preboot"

  disable_account "preboot"

  hide_account "preboot"

  remove_filevault_unlock_for_other_users
}

encrypt_using_fdesetup_with_expect () {
  local output
  local password
  local serial_num

  quote_string_for_use_within_expect_tcl_script_double_quotes "$2" password

  output=$(execute_sudo "expect" << EOF
    #since we use expect inside a bash-script, we have to escape tcl-$.
    set timeout 180
    spawn fdesetup enable -user $1
    expect {
      -re "Enter the password for (the )?user '$1':" {
        send "$password\r"
      }
      default {
        exit 2
      }
    }
    expect {
      "Error: User authentication failed." {
        exit 1
      }
      "Please reboot to complete the process." {
        exit 0
      }
    }
    exit 0
EOF
  )

  if [[ $? -eq 0 ]]; then
    # retrieve and store recovery key
    serial_num=$(ioreg -l | awk -F'"' '/IOPlatformSerialNumber/{print $4}')
    echo "$output" | grep "Recovery key" | sed "s/Recovery key = '\(.*\)'/\1/" > "${SCRIPT_DIR}/${serial_num}_$(date +"%Y-%m-%d_%H:%M_%p")"
  else
    abort "There was a problem enabling FileVault."
  fi
}

generate_new_filevault_recovery_key () {
  local output
  local password
  local serial_num

  quote_string_for_use_within_expect_tcl_script_double_quotes "$2" password

  output=$(execute_sudo "expect" << EOF
    #since we use expect inside a bash-script, we have to escape tcl-$.
    set timeout 180
    spawn fdesetup changerecovery --user $1 -personal
    expect {
      -re "Enter the password for (the )?user '$1':" {
        send "$password\r"
      }
      default {
        exit 2
      }
    }
    expect {
      "Error: User authentication failed." {
        exit 1
      }
      "Please reboot to complete the process." {
        exit 0
      }
    }
    exit 0
EOF
  )

  if [[ $? -eq 0 ]]; then
    # retrieve and store recovery key
    serial_num=$(ioreg -l | awk -F'"' '/IOPlatformSerialNumber/{print $4}')
    echo "$output" | grep "New personal recovery key" | sed "s/New personal recovery key = '\(.*\)'/\1/" > "${SCRIPT_DIR}/${serial_num}_$(date +"%Y-%m-%d_%H:%M_%p")"
  else  
    abort "There was a problem generating a new FileVault personal recovery key."
  fi  
}

get_account_with_filevault_permissions () {
  local _filevault_user=$1
  local _filevault_password=$2

  local account_list
  local current_user_realname
  local filevault_user_realname
  local realname
  local new_adminpass
  local confirm_adminpass
  declare -a account_display_list

  # get realname of current user
  get_account_realname "$(logname)" current_user_realname

  # retrieve list of accounts (by username) with permissions to unlock FileVault
  account_list=$(execute_sudo "fdesetup" "list" | grep -v '^preboot,' | awk -F ',' '{ print $1 }')

  # generate selection menu using account realnames
  # (f) below splits the result of the variable expansion at newlines
  for username in ${(f)account_list}; do
    get_account_realname "$username" realname
    account_display_list+=("$realname")
  done

  # display list of accounts with FileVault unlock permissions with current
  # user marked as the default and prompt user to make selection.
  printf "\n"
  printf "%s\n" "Accounts with permissions to unlock FileVault"
  PS3="Select account for unlocking FileVault: "
  select_with_default account_display_list "$current_user_realname" filevault_user_realname

  # get username of selected account
  get_account_username "$filevault_user_realname" $_filevault_user

  # prompt for password of selected account
  printf "\n"
  printf "%s\n" "Please provide password for ${(P)_filevault_user} ($filevault_user_realname)."
  get_account_password "admin" "${(P)_filevault_user}" $_filevault_password "verify"
  if [[ ${(P)_filevault_password} =~ '^[[:space:]]+|[[:space:]]+$' ]]; then
    display_error 'The password for `'${(P)_filevault_user}'` begins or ends with whitespace.  It will need to be changed.'
    get_password_and_confirm "admin" "${(P)_filevault_user}" new_adminpass

    printf "\n"
    ohai 'Changing `'${(P)_filevault_user}'` account password.'
    change_user_password "${(P)_filevault_user}" "${(P)_filevault_password}" "$new_adminpass"
    : ${(P)_filevault_password::=$new_adminpass}
  fi
}

grant_account_filevault_access () {
  local admin_password
  local preboot_password

  quote_string_for_use_within_expect_tcl_script_double_quotes "$2" preboot_password
  quote_string_for_use_within_expect_tcl_script_double_quotes "$4" admin_password
  
  execute_sudo "expect" >/dev/null << EOF
    #since we use expect inside a bash-script, we have to escape tcl-$.
    spawn fdesetup add -usertoadd $1 -user $3
    expect {
      -re "Enter the password for user '$3':" {
        send "$admin_password\r"
      }
    }
    expect {
      "Enter the password for the added user '$1':" {
        send "$preboot_password\r"
      }
    }
    expect eof
EOF

  FILEVAULT_ENABLED_ACCOUNTS+=("$1")
}

remove_filevault_unlock_for_other_users () {
  local list_of_fv_users
  local user

  enable_account "preboot"

  list_of_fv_users=$(execute_sudo "fdesetup" "list" | grep -v "^preboot," | awk -F "," '{print $1}')

  # remove any user that isn't preboot
  for user in ${(f)list_of_fv_users}; do
    if [ "$user" != "(null)" ]; then
      execute_sudo "fdesetup" "remove" "-user" "$user"
    fi
  done

  disable_account "preboot"
}

