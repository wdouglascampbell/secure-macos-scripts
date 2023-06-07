#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

configure_filevault () {
  local filevault_user
  local filevault_password
  local filevault_state

  get_filevault_state filevault_state

  case "$filevault_state" in

  "off")
    ohai "FileVaule is off. Proceeding with encryption..."
    ohai "Click 'OK' button in response to the dialog that appears stating that"
    ohai "'fdesetup would like to enable FileVault.'"
    enable_filevault "$1"
    ;;

  "decrypting")
    ohai 'FileVault is currently decrypting the drive. Re-run this script once the drive has been fully decrypted in order to re-enable encryption.'
    ;;

  "on")
    ohai 'FileVault is on.' 

    # ensure preboot account can unlock FileVault
    if [[ $(execute_sudo "fdesetup" "list" | grep -c '^preboot,') -eq 0 ]]; then
      ohai '`preboot` account does not have permissions to unlock FileVault.'
      get_account_with_filevault_permissions filevault_user filevault_password

      enable_account "preboot"
      grant_account_filevault_access "preboot" "$1" "$filevault_user" "$filevault_password"
      disable_account "preboot"
    fi

    hide_account "preboot"
    remove_filevault_unlock_for_other_users
    ;;

  esac
}

get_filevault_state () {
  local _state=$1

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
  enable_account "preboot"

  # fdesetup complains when a non-admin account is used to enable FileVault
  # even though it will still enable FileVault so temporarily add preboot
  # to admin group.
  add_user_to_admin_group "preboot"

  encrypt_using_fdesetup_with_expect "preboot" "$1"

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

