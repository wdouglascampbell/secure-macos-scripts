#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

add_user_to_admin_group () {
  execute_sudo "dseditgroup" "-o" "edit" "-a" "$1" "-t" "user" "admin"
}

change_user_password () { 
  execute_sudo "dscl" "." "-passwd" "/Users/$1" "$2" "$3" 
  if [[ -f "/Users/$1/Library/Keychains/login.keychain-db" ]]; then 
    execute_sudo "security" "set-keychain-password" "-o" "$2" -p "$3" \
                            "/Users/$1/Library/Keychains/login.keychain" >/dev/null 2>&1 
  fi 
} 

check_all_login_accounts_for_problem_passwords () {
  local username
  local password

  ohai 'Checking provided login account passwords for problems.'

  for username password in "${(kv)PASSWORDS[@]}"; do
    # check account password for leading or trailing spaces
    [[ $password =~ '^[[:space:]]+' ]] || [[ $password =~ '[[:space:]]+$' ]] && ACCOUNTS_WITH_PROBLEM_PASSWORDS+=("$username")
  done
}

confirm_all_login_account_passwords_meet_requirements () {
  local check_password_func
  local username
  local password
  local new_password

  ohai 'Confirming passwords provided for login accounts meet requirements.'

  for username password in "${(kv)PASSWORDS[@]}"; do
    if [[ $username == "preboot" ]]; then
      check_password_func="check_preboot_password_complexity"
    else
      check_password_func="check_password_complexity"
      [[ $is_account_enabled -ne 0 ]] && enable_account "$username" 
    fi

    if ! "$check_password_func" "$password"; then
      display_error 'The password for account `'$username'` is correct but it does not meet our requirements. It will need to be changed. Please enter a new password.'
      if [[ $username == "preboot" ]]; then
        get_password_and_confirm "preboot" new_password
      else
        get_password_and_confirm "admin" "$username" new_password
      fi

      printf "\n"
      ohai 'Changing `'$username'` account password.'
      [[ "$username" == "preboot" ]] && enable_account "preboot"
      change_user_password "$username" "$password" "$new_password"
      [[ "$username" == "preboot" ]] && disable_account "preboot"
      PASSWORDS[$username]=$new_password
    fi
  done
}

disable_account () {
  execute_sudo "pwpolicy" "-u" "$1" "-disableuser" >/dev/null 2>&1
}

enable_account () {
  execute_sudo "pwpolicy" "-u" "$1" "-enableuser" >/dev/null 2>&1
}

enable_secure_token_for_account () {
  add_user_to_admin_group "$3"
  execute_sudo "sysadminctl" "-secureTokenOn" "$1" "-password" "$2" "-adminUser" "$3" "-adminPassword" "$4" 2>/dev/null
  (($ADMINS[(Ie)$3])) || remove_user_from_admin_group "$3"
}

enable_secure_token_for_all_accounts () {
  typeset username

  ohai 'Ensuring all login accounts have a secure token.'

  for username in "${LOGIN_ACCOUNTS[@]}"; do
    (($SECURE_TOKEN_HOLDERS[(Ie)$username])) && continue
    [[ "$1" == "preboot" ]] && enable_account "preboot"
    enable_secure_token_for_account "$username" "${PASSWORDS[$username]}" "$1" "${PASSWORDS[$1]}"
    [[ "$1" == "preboot" ]] && disable_account "preboot"
    SECURE_TOKEN_HOLDERS+=("$username")
  done
}

ensure_script_user_has_secure_token_enable () {
  local username
  typeset -a secure_token_holders_missing_password

  if ! (($SECURE_TOKEN_HOLDERS[(Ie)$SCRIPT_USER)); then
    for username in "${SECURE_TOKEN_HOLDERS[@]}"
    do
      ! (($PASSWORDS[(Ie)$username])) && secure_token_holders_missing_password+=("$username") && continue

   # check whether password begins or ends in spaces or it won't work for us!
   # or actually the way we enable the secure token won't work with such passwords I think
   # maybe I should change how I enable it to use expect?

      [[ $username == "preboot" ]] && enable_account "preboot"
      add_user_to_admin_group "$username"
      enable_secure_token_for_account "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}" "$username" "${PASSWORDS[$username]}"
      SECURE_TOKEN_HOLDERS+=("$SCRIPT_USER")
      ! (($ADMINS[(Ie)$username])) && remove_user_from_admin_group "$username"
      [[ $username == "preboot" ]] && disable_account "preboot"
      break
    done
    if ! (($SECURE_TOKEN_HOLDERS[(Ie)$SCRIPT_USER])); then
      printf "\n"
      ohai 'The current account, `'$SCRIPT_USER'`, does not have a secure token.'
      ohai "An account with a secure token is required."
      printf "\n"
      printf "%s\n" "Accounts with a secure token"
      PS3="Select account: "
      select_with_default secure_token_holders_missing_password "" username
      enable_account "$SCRIPT_USER"
      printf "\n"
      printf "%s\n" 'Please provide password for `'$username'`.'
      if [[ $username == "preboot" ]]; then
        get_password_and_confirm "preboot" password
      else
        get_password_and_confirm "admin" "$username" password
      fi
      PASSWORDS[$username]=$password

      # account no longer requires disabling since we have a password for it
      ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")

      add_user_to_admin_group "$username"
      enable_secure_token_for_account "$SCRIPT_USER" "${PASSWORDS[$SCRIPT_USER]}" "$username" "${PASSWORDS[$username]}"
      SECURE_TOKEN_HOLDERS+=("$SCRIPT_USER")
      ! (($ADMINS[(Ie)$username])) && remove_user_from_admin_group "$username"
      [[ $username == "preboot" ]] && disable_account "preboot"
    fi
  fi
}

get_account_realname () {
  local _realname=$2

  : ${(P)_realname::=$(
    execute_sudo "dscl" "." "-read" "/Users/$1" "RealName" | \
    tr '\n' ' ' | \
    awk '{print substr($0, index($0,$2))}' | \
    sed -e's/[[:space:]]*$//'
  )}
}

get_account_username () {
  local _username=$2

  : ${(P)_username::=$(
    execute_sudo "dscl" "." "-list" "/Users" "RealName" | \
    grep -E '[[:space:]]'"$1" | \
    awk '{print $1}'
  )}
}

get_account_password_aux () {
  local username=$1
  local is_account_enabled
  local password
  local new_password

  is_account_enabled=$(pwpolicy -u $username authentication-allowed | grep -c "is disabled")
  # note: although the preboot account should always be disabled, we don't need
  # to confuse the user with this information.
  [[ $username == "preboot" || $is_account_enabled -eq 0 ]] && disabled="" || disabled=" (disabled)"

  printf '\n'
  printf "%s\n" 'Please provide password for `'$username'`'$disabled'.'
  trap "return" INT
  while true; do
    if [[ $username == "preboot" ]]; then
      get_account_password "preboot" password "verify"
    else
      [[ $is_account_enabled -ne 0 ]] && enable_account "$username"
      get_account_password "admin" "$username" password "verify"
    fi

    if [[ $? -eq 0 ]]; then
      PASSWORDS[$username]=$password
      trap - INT
      break
    else
      [[ $username != "preboot" && $is_account_enabled -ne 0 ]] && disable_account "$username"
    fi

    case "$username" in
      "$SCRIPT_USER")
        printf '\n'
        display_error 'This is the currently logged in account. You must enter a password for this account.'
        ;;
      "preboot")
        printf '\n'
        if [[ $EXTREME -eq 0 ]]; then
          display_error 'Access to the `preboot` account is required for the EXTREME security level.'
          ask_yes_no 'Would you like to reset the `preboot` password? (y/n)'
          if [[ $? -eq 0 ]]; then
            trap - INT
            printf '\n\n'
            printf "%s\n" 'Please enter a new password for `preboot`.'
            get_password_and_confirm "preboot" password
            PASSWORDS[$username]=$password
            RESET_PREBOOT_PASSWORD=0
            break
          else
            printf '\n\n'
            printf "%s\n" 'Please provide password for `preboot`.'
          fi
        else
          trap - INT
          break
        fi
        ;;
      *)
        printf '\n'
        printf '\n'
        ohai '`'$username'` will be disabled.'
        ACCOUNTS_TO_DISABLE+=("$username")
        trap - INT
        break
    esac
  done
}

get_info_all_login_accounts () {
  typeset username

  ohai 'Retrieving information on all system login accounts.'

  unset username
  for username in "${LOGIN_ACCOUNTS[@]}"
  do
    if is_account_admin "$username"; then
      ADMINS+=("$username")
    fi
    if is_account_secure_token_enabled "$username"; then
      SECURE_TOKEN_HOLDERS+=("$username")
    fi
    if ! is_account_enabled "$username"; then
      DISABLED_ACCOUNTS+=("$username")
    fi
  done
}

get_passwords_for_remaining_login_accounts () {
  typeset username

  if [[ ${#LOGIN_ACCOUNTS} -gt 1 ]]; then
    ohai 'Getting passwords for remaining login accounts.'

    printf '\n'
    ohai 'You will be prompted for a password for each account. You may press Ctrl+C to skip an account. Skipped accounts will be disabled. Under certain circumstances you may be required later to provide a password for a skipped account because it has access permissions not provided by other accounts.'

    for username in "${LOGIN_ACCOUNTS[@]}"
    do 
      [[ $username == $SCRIPT_USER ]] && continue
      get_account_password_aux $username
    done
  fi
}

get_login_account_list () {
  ohai 'Getting list of system login accounts.'

  LOGIN_ACCOUNTS=$(
    dscl . list /Users UniqueID | \
    awk '$2 > 500 && $2 < 1000 { printf "%s ", $1 }'
  )
  LOGIN_ACCOUNTS=(${(@s: :)LOGIN_ACCOUNTS})
}

get_sudo () {
  printf "%s" "$1" | sudo -S -l mkdir >/dev/null 2>&1 
}

hide_account () {
  execute_sudo "dscl" "." "-create" "/Users/$1" "IsHidden" "1"
}

hide_others_option_from_login_screen () {
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.loginwindow" "SHOWOTHERUSERS_MANAGED" "-bool" "FALSE"
}

is_account_admin () {
  dsmemberutil checkmembership -U "$1" -G "admin" | grep "is a member" >/dev/null
}

is_account_enabled () {
  pwpolicy -u $username authentication-allowed | grep "is disabled" > /dev/null
}

is_account_secure_token_enabled () {
  sysadminctl -secureTokenStatus $1 2>&1 | grep "ENABLED" >/dev/null
}

is_account_exist () {
  [[ $(dscl . -list /Users UniqueID | grep "$1" | wc -l) -eq 1 ]]
  return
}

is_user_password_valid () {
  dscl /Local/Default -authonly "$1" "$2" 2>/dev/null 1>&2 && return 0

  display_error "Password Invalid!"
  return 1
}

remove_account () {
  enable_account "$1"
  execute_sudo "dscl" "." "-delete" "/Users/$1"
  execute_sudo "rm" "-rf" "/Users/$1"
}

remove_user_from_admin_group () {
  execute_sudo "dseditgroup" "-o" "edit" "-d" "$1" "-t" "user" "admin"
}

update_secure_token_holder_list () {
  typeset username

  ohai 'Updating Secure Token Holders list.'

  unset SECURE_TOKEN_HOLDERS

  for username in "${LOGIN_ACCOUNTS[@]}"
  do
    if is_account_secure_token_enabled "$username"; then
      SECURE_TOKEN_HOLDERS+=("$username")
    fi
  done
}

