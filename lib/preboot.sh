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
  local password

  ohai 'Configuring Pre-Boot Authentication account.'            

  # check if preboot account exists
  if [[ -n "${PASSWORDS[preboot]}" ]]; then
    # check if preboot account has a Secure Token
    if ! (($SECURE_TOKEN_HOLDERS[(Ie)preboot])); then
      enable_account "preboot"
      enable_secure_token_for_account "preboot" "${PASSWORDS[preboot]}" "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}"
      disable_account "preboot"
    fi
  else
    ohai 'A `preboot` account is required to configure whole disc encryption with preboot authentication.'
    printf '\n'
    ohai 'Please provide a password for the `preboot` account.'
    get_password_and_confirm "preboot" password
    printf "\n"
    ohai 'Creating preboot account.'
    create_preboot_account "$password" "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}"
    PASSWORDS[preboot]=$password
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

