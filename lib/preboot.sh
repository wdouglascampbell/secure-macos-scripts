#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

change_preboot_password () {
  enable_account "preboot"
  change_user_password "preboot" "$1" "$2"
  disable_account "preboot"
}

check_preboot_password_complexity () {
  if [[ $1 =~ '^[[:space:]]+|[[:space:]]+$' ]]; then
    display_error "Password must not begin or end with whitespace."
    return 1
  fi

  [[ ${#1} -ge $PREBOOT_PASS_MIN_LENGTH ]] && return 0

  display_error "Password must be $PREBOOT_PASS_MIN_LENGTH characters in length."
  return 1
}

configure_preboot_account () {
  local _preboot_password=$1
  local adminuser
  local adminpass
  local new_adminpass
  local confirm_adminpass
  local preboot_confirm
  local new_preboot_password

  # check if preboot account exists
  is_account_exist "preboot"
  if [[ $? -eq 0 ]]; then
    ohai '`preboot` account exists. Please verify password.'
    get_account_password "preboot" $_preboot_password "verify"

    check_preboot_password_complexity "${(P)_preboot_password}"
    if [[ $? -ne 0 ]]; then
      display_error 'The current `preboot` account password does not meet our requirements. It will need to be changed. Please enter a new password.'
      get_password_and_confirm "preboot" new_preboot_password

      printf "\n"
      ohai "Changing preboot account password."
      change_preboot_password "${(P)_preboot_password}" "$new_preboot_password"
      : ${(P)_preboot_password::=$new_preboot_password}
    fi

    # check if preboot account has a Secure Token
    if [[ $(sysadminctl -secureTokenStatus preboot 2>&1 | grep "DISABLED" | wc -l) -eq 1 ]]; then
      adminuser=$(logname)
      printf "\n"
      ohai 'Administrator credentials are required to give preboot account permissions to unlock disc encryption.'
      ohai 'Please provide a password for the `'$adminuser'` account.'

      get_account_password "admin" "$adminuser" adminpass "verify"
      if [[ $adminpass =~ '^[[:space:]]+|[[:space:]]+$' ]]; then
        display_error 'The password for `'$adminuser'` begins or ends with whitespace. It will need to be changed. Please enter a new password.'
        get_password_and_confirm "admin" "$adminuser" new_adminpass

        printf "\n"
        ohai 'Changing `'$adminuser'` account password.'
        change_user_password "$adminuser" "$adminpass" "$new_adminpass"
        adminpass=$new_adminpass
      fi

      enable_account "preboot"
      enable_secure_token_for_account "preboot" "${(P)_preboot_password}" "$adminuser" "$adminpass"
      disable_account "preboot"
    fi
  else
    ohai 'A `preboot` account is required to configure whole disc encryption with preboot'
    ohai 'authentication.'
    ohai 'Please provide a password for the `preboot` account.'
    get_password_and_confirm "preboot" $_preboot_password
  
    adminuser=$(logname)
    printf "\n"
    ohai 'Administrator credentials are required to give preboot account permissions to unlock disc encryption.'
    ohai 'Please provide a password for the `'$adminuser'` account.'
    get_account_password "admin" "$adminuser" adminpass "verify"
    if [[ $adminpass =~ '^[[:space:]]+|[[:space:]]+$' ]]; then
      display_error 'The password for `'$adminuser'` begins or ends with whitespace. It will need to be changed. Please enter a new password.'
      get_password_and_confirm "admin" "$adminuser" new_adminpass

      printf "\n"
      ohai 'Changing `'$adminuser'` account password.'
      change_user_password "$adminuser" "$adminpass" "$new_adminpass"
      adminpass=$new_adminpass
    fi

    printf "\n"
    ohai 'Creating preboot account.'
    create_preboot_account "${(P)_preboot_password}" "$adminuser" "$adminpass"
  fi
}

create_preboot_account () {
  local maxid
  local userid

  # Find out the next available user ID
  maxid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
  userid=$((maxid+1))
  
  # Create the user account
  execute_sudo "dscl" "." "-create" "/Users/preboot"
  execute_sudo "dscl" "." "-create" "/Users/preboot" "UserShell" "/bin/zsh"
  execute_sudo "dscl" "." "-create" "/Users/preboot" "RealName" "Pre-Boot Authentication"
  execute_sudo "dscl" "." "-create" "/Users/preboot" "UniqueID" "$userid"
  execute_sudo "dscl" "." "-create" "/Users/preboot" "PrimaryGroupID" "20"
  execute_sudo "dscl" "." "-create" "/Users/preboot" "NFSHomeDirectory" "/Users/preboot"
  execute_sudo "dscl" "." "-passwd" "/Users/preboot" "$1"
  
  hide_account "preboot"
  
  enable_secure_token_for_account "preboot" "$1" "$2" "$3"
  
  # Create the home directory
  pushd -q /Users
  execute_sudo "createhomedir" "-c" "-upreboot" >/dev/null 2>&1
  popd -q
}

verify_preboot_password () {
  enable_account "preboot"

  is_user_password_valid "preboot" "$1"
  result=$?

  disable_account "preboot"

  return $result
}

