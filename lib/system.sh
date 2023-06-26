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

  log_message 'Checking provided login account passwords for problems.'

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
      enable_account "$username" 
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
  DISABLED_ACCOUNTS+=("$1")
  force_failed_login "$1"
}

disable_accounts_without_provided_password () {
  typeset username

  ohai "Disabling accounts for which passwords were not provided."
  for username in "${ACCOUNTS_TO_DISABLE[@]}"; do
    log_message "Disabling $username"
    disable_account "$username"
  done
}

enable_account () {
  execute_sudo "pwpolicy" "-u" "$1" "-enableuser" >/dev/null 2>&1
  DISABLED_ACCOUNTS=("${(@)DISABLED_ACCOUNTS:#${1}}")
}

enable_secure_token_for_account () {
  add_user_to_admin_group "$3"
  execute_sudo "sysadminctl" "-secureTokenOn" "$1" "-password" "$2" "-adminUser" "$3" "-adminPassword" "$4" 2>/dev/null
  (($ADMINS[(Ie)$3])) || remove_user_from_admin_group "$3"
}

enable_secure_token_for_all_accounts () {
  typeset username

  log_message 'Ensuring all login accounts have a secure token.'
  log_message 'DISABLED_ACCOUNTS: '${DISABLED_ACCOUNTS[@]}
  log_message 'ACCOUNTS_TO_DISABLE: '${ACCOUNTS_TO_DISABLE[@]}

  for username in "${LOGIN_ACCOUNTS[@]}"; do
    (($DISABLED_ACCOUNTS[(Ie)$username])) && [[ $username != "preboot" ]] && continue
    (($ACCOUNTS_TO_DISABLE[(Ie)$username])) && continue
    (($SECURE_TOKEN_HOLDERS[(Ie)$username])) && continue
    [[ "$1" == "preboot" ]] || [[ "$username" == "preboot" ]] && enable_account "preboot"
    enable_secure_token_for_account "$username" "${PASSWORDS[$username]}" "$1" "${PASSWORDS[$1]}"
    [[ "$1" == "preboot" ]] || [[ "$username" == "preboot" ]] && disable_account "preboot"
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

find_account_with_filevault_access_and_known_good_password () {
  # search for an account with FileVaule access for which the provided
  # password has no problems.
  #
  # sets the passed referenced variables as follows:
  #   $1 - account username, if matching requirements
  #   $2 - array of other choices with no password provided

  log_message "Starting find_account_with_filevault_access_and_known_good_password()"

  typeset -a _other_choices_without_password
  typeset username

  for username in "${FILEVAULT_ENABLED_ACCOUNTS[@]}"; do
    log_message "  Checking $username"

    # skip account if it has problem password
    (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])) && continue

    log_message "    Password for $username is good"

    # skip account if password has not be provided
    if [[ -z "${PASSWORDS[$username]}" ]]; then
      log_message '    No password was provided for '$username
      _other_choices_without_password+=("$username")
      continue
    fi

    log_message "    $username has FileVault access"
    : ${(P)1::=$username}
    break
  done

  set -A $2 ${(kv)_other_choices_without_password}

  log_message "Ending find_account_with_filevault_access_and_known_good_password()"
}

find_account_with_full_privileges_and_known_good_password () {
  # search for an account with a Secure Token and FileVault access for which
  # the provided password has no problems.
  # 
  # sets the passed referenced variables as follows:
  #   $1 - account username, if matching requirements
  #   $2 - array of other choices with problem passwords
  #   $3 - array of other choices with no password provided

  typeset -a _other_choices_with_password=()
  typeset -a _other_choices_without_password=()
  typeset username

  log_message "Starting find_account_with_full_privileges_and_known_good_password()"

  for username in "${FILEVAULT_ENABLED_ACCOUNTS[@]}"; do
    log_message "  Checking $username"

    # skip account without a Secure Token
    (($SECURE_TOKEN_HOLDERS[(Ie)$username])) || continue

    log_message "    $username has Secure Token"

    # skip account if it has problem password
    if (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])); then
      log_message "    $username has problem password"
      _other_choices_with_password+=("$username")
      continue
    fi

    # skip account if password has not be provided
    if [[ -z "${PASSWORDS[$username]}" ]]; then
      log_message '    No password was provided for '$username
      _other_choices_without_password+=("$username")
      continue
    fi

    log_message "    $username has Secure Token and FileVault access and a known, good password"
    : ${(P)1::=$username}
    break
  done

  set -A $2 ${(kv)_other_choices_with_password}
  set -A $3 ${(kv)_other_choices_without_password}

  log_message "Ending find_account_with_full_privileges_and_known_good_password()"
}

find_account_with_secure_token_and_known_good_password () {
  # search for an account with a Secure Token for which the provided
  # password has no problems.
  #
  # sets the passed referenced variables as follows:
  #   $1 - account username, if matching requirements
  #   $2 - array of other choices with no password provided

  log_message "Starting find_account_with_secure_token_and_known_good_password()"

  typeset -a _other_choices_without_password
  typeset username

  for username in "${SECURE_TOKEN_HOLDERS[@]}"; do
    log_message "  Checking $username"

    # skip account if it has problem password
    (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])) && continue

    log_message "    Password for $username is good"

    # skip account if password has not be provided
    if [[ -z "${PASSWORDS[$username]}" ]]; then
      log_message '    No password was provided for '$username
      _other_choices_without_password+=("$username")
      continue
    fi

    log_message "    $username has Secure Token"
    : ${(P)1::=$username}
    break
  done

  set -A $2 ${(kv)_other_choices_without_password}

  log_message "Ending find_account_with_secure_token_and_known_good_password()"
}

force_failed_login () {
  # Make a failed login attempt.

  # This is only necessary because Apple does not honor the disabling of an
  # account on the first reboot. If, however, a login attempt, even one using a
  # wrong password, is attempted, prior to rebooting, the disabling of the
  # account is properly honored at the macOS account login screen.

  execute "expect" >/dev/null << EOF
    spawn su $1
    expect {
      "Password:" {
        send "notapassword\r"
      }
    }
    expect {
      "su: Sorry" {
        exit 0
      }
    }
    exit 0
EOF
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
        else
          ACCOUNTS_TO_DISABLE+=("$username")
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

get_password_for_account_in_list () {
  typeset _other_choices_without_password=$1
  typeset _username=$2
  typeset _password=$3

  if [[ ${#${(P)1}} -eq 1 ]]; then
    : ${(P)_username::=${${(P)_other_choices_without_password}[1]}}
  else
    PS3="Select account: "
    select_with_default "$_other_choices_without_password" "" "$_username"
  fi

  printf '\n'
  display_message 'Please provide password for `'${(P)_username}'`.'

  log_message "Getting password for ${(P)_username}"
  if [[ "${(P)_username}" == "preboot" ]]; then
    get_account_password "preboot" "$_password" "verify"
  else
    get_account_password "admin" "${(P)_username}" "$_password" "verify"
  fi

  PASSWORDS[${(P)_username}]=${(P)_password}
}

get_privileged_accounts () {
  typeset filevault_state=$1
  typeset _full_priv_account=$2
  typeset _fv_priv_account=$3
  typeset _secure_token_priv_account=$4

  typeset -a other_choices_with_password
  typeset -a other_choices_without_password
  typeset username password

  if [[ "$filevault_state" == "on" ]]; then
    log_message 'Checkpoint 1 - FileVault is Enabled.'
    log_message 'Searching for account with a Secure Token and FileVault access.'
    log_message 'Searching accounts with FileVault access for ones that also have a Secure Token and a known, good password.'

    find_account_with_full_privileges_and_known_good_password "$_full_priv_account" other_choices_with_password other_choices_without_password

    log_message 'Checkpoint 2'
    log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
    if [[ -z "${(P)_full_priv_account}" ]]; then
      log_message 'Checkpoint 3'
      log_message 'Search did not find an account matching search criteria.'
      log_message 'Searching accounts with FileVault access that have a known but problematic password for ones that also have a Secure Token.'
      log_message 'other_choices_with_password: '${other_choices_with_password[@]}

      if [[ ${#other_choices_with_password} -gt 0 ]]; then
        replace_problem_password_on_account "${other_choices_with_password[1]}"
        : ${(P)_full_priv_account::=${other_choices_with_password[1]}}
      fi

      log_message 'Checkpoint 4'
      log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
      if [[ -z "${(P)_full_priv_account}" ]]; then
        log_message 'Checkpoint 5'
        log_message 'Search did not find an account matching search criteria.'
        log_message 'Searching accounts with FileVault access where password is unknown for ones that also have a Secure Token.'
        log_message 'other_choices_without_password: '${other_choices_without_password[@]}

        if [[ ${#other_choices_without_password} -gt 0 ]]; then
          if [[ ${#other_choices_without_password} -eq 1 ]]; then
            log_message 'Checkpoint 5a - There is one account that has FileVault access and a Secure Token but with no known password.'
            printf "\n"
            display_message "The password for the following account is needed so that some of the operations can complete successfully."
          else
            log_message 'Checkpoint 5b - There are multiple accounts that have FileVault access and a Secure Token but with no known password.'
            printf "\n"
            display_message "The password for one of the following accounts is needed so that some of the operations can complete successfully."
          fi
          
          get_password_for_account_in_list other_choices_without_password username password
          if has_no_leading_trailing_whitespace "$password"; then
            printf '\n'
          else
            replace_problem_password_on_account "$username"
          fi

          log_message "Checkpoint 5c - have good password for $username"

          # account no longer requires disabling since we have a password for it
          ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")

          : ${(P)_full_priv_account::=$username}
        fi

        log_message 'Checkpoint 6'
        log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
        if [[ -z "${(P)_full_priv_account}" ]]; then
          log_message 'Checkpoint 7'
          log_message 'Search did not find an account matching search criteria.'
          log_message 'Searching accounts with FileVault access for ones with a known, goood password.'

          find_account_with_filevault_access_and_known_good_password "$_fv_priv_account" other_choices_without_password

          log_message 'Checkpoint 8'
          log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
          if [[ -z "${(P)_fv_priv_account}" ]]; then
            log_message 'Checkpoint 9 - Search did not find an account matching search criteria.'
            if [[ ${#other_choices_without_password} -gt 0 ]]; then
              if [[ ${#other_choices_without_password} -eq 1 ]]; then
                log_message 'Checkpoint 9a - There is one account that has FileVault access but with no known password.'
                printf "\n"
                display_message "The password for the following account is needed so that some of the operations can complete successfully."
              else
                log_message 'Checkpoint 9b - There are multiple accounts that have FileVault access but with no known password.'
                printf "\n"
                display_message "The password for one of the following accounts is needed so that some of the operations can complete successfully."
              fi

              get_password_for_account_in_list other_choices_without_password username password
    
              # account no longer requires disabling since we have a password for it
              ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")

              if has_no_leading_trailing_whitespace "$password"; then
                printf '\n'
              else
                log_message "Checkpoint 9c - $username has a problem password - a different account must be selected"
                display_error 'Unfortunately this password while correct contains leading or trailing spaces.  Please select a different account to try.'
                ACCOUNTS_WITH_PROBLEM_PASSWORDS+=("$username")
                other_choices_without_password=("${(@)other_choices_without_password:#${username}}")
                if [[ ${#other_choices_without_password} -eq 0 ]]; then
                  log_message 'Checkpoint 9d - no accounts with FileVault access and without a Secure Token have a good password'
                  display_error 'All of the accounts with FileVault access have a password with leading or trailing spaces but do not have a Secure Token so there is no way to change the password.'
                  abort 'Oops. Unfortunately there is no way to resolve this issue in a non-destructive way.'
                fi
              fi

              log_message "Checkpoint 9e - good password found for $username"
              : ${(P)_fv_priv_account::=$username}
            else
              log_message 'Checkpoint 9f - no accounts with FileVault access'
              abort 'Oops! No accounts have FileVault access. This should never happen.'
            fi
          fi

          log_message 'Checkpoint 10'
          log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
          log_message '`'$fv_username'` account has FileVault access and has been selected to administrate FileVault access.'
          log_message 'Searching accounts with a Secure Token for ones with a known, goood password.'

          find_account_with_secure_token_and_known_good_password "$_secure_token_priv_account" other_choices_without_password

          log_message 'Checkpoint 11'
          log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
          if [[ -z "${(P)_secure_token_priv_account}" ]]; then
            log_message 'Checkpoint 12 - Search did not find an account matching search criteria.'
            log_message 'other_choices_without_password: '${other_choices_without_password[@]}
            if [[ ${#other_choices_without_password} -gt 0 ]]; then
              if [[ ${#other_choices_without_password} -eq 1 ]]; then
                log_message 'Checkpoint 12a - There is one account that has a Secure Token but with no known password.'
                printf "\n"
                display_message "The password for the following account is needed so that some of the operations can complete successfully."
              else
                log_message 'Checkpoint 12b - There are multiple accounts that have a Secure Token but with no known password.'
                printf "\n"
                display_message "The password for one of the following accounts is needed so that some of the operations can complete successfully."
              fi

              get_password_for_account_in_list other_choices_without_password username password

              # account no longer requires disabling since we have a password for it
              ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")
                
              if has_no_leading_trailing_whitespace "$password"; then
                printf '\n'
              else
                log_message "Checkpoint 12c - $username has a problem password - a different account must be selected"
                display_error 'Unfortunately this password while correct contains leading or trailing spaces.  Please select a different account to try.'
                ACCOUNTS_WITH_PROBLEM_PASSWORDS+=("$username")
                other_choices_without_password=("${(@)other_choices_without_password:#${username}}")
                if [[ ${#other_choices_without_password} -eq 0 ]]; then
                  log_message 'Checkpoint 12d - all accounts with a Secure Token but without FileVault access have a good password'
                  display_error 'All of the accounts with a Secure Token have a password with leading or trailing spaces but do not have FileVault access so there is no way to change the password.'
                  abort 'Oops. Unfortunately there is no way to resolve this issue in a non-destructive way.'
                fi
              fi

              log_message "Checkpoint 12e - good password found for $username"
              : ${(P)_secure_token_priv_account::=$username}
            else
              log_message 'Checkpoint 12f - no accounts with a Secure Token'
              abort 'Oops! No accounts have a Secure Token.  This can happen in rare circumstances but unfortunately there is no way to resolve this issue in a non-destructive way.'
            fi
          fi

          log_message 'Checkpoint 13'
          log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
          log_message 'Adding FileVault access to account with only Secure Token access.'
          [[ $LOG_SECRETS -eq 0 ]] && log_message 'Secure Token Account ('${(P)_secure_token_priv_account}') password: '${PASSWORDS[${(P)_secure_token_priv_account}]}
          [[ $LOG_SECRETS -eq 0 ]] && log_message 'FileVault Account ('${(P)_fv_priv_account}') password: '${PASSWORDS[${(P)_fv_priv_account}]}
          [[ "${(P)_fv_priv_account}" == "preboot" || "${(P)_secure_token_priv_account}" == "preboot" ]] && enable_account "preboot"
          grant_account_filevault_access "${(P)_secure_token_priv_account}" "${PASSWORDS[${(P)_secure_token_priv_account}]}" "${(P)_fv_priv_account}" "${PASSWORDS[${(P)_fv_priv_account}]}"
          [[ "${(P)_fv_priv_account}" == "preboot" || "${(P)_secure_token_priv_account}" == "preboot" ]] && disable_account "preboot"
          
          : ${(P)_full_priv_account::=${(P)_secure_token_priv_account}}
        fi
      fi
    fi
  else
    log_message 'Checkpoint 14 - FileVault is Disabled.'
    log_message 'Searching for account with a Secure Token and FileVault access.'
    log_message 'Searching accounts with a Secure Token and FileVault access for ones with a known, good password.'
    
    find_account_with_full_privileges_and_known_good_password "$_full_priv_account" other_choices_with_password other_choices_without_password

    log_message 'Checkpoint 15'
    log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
    if [[ -z "${(P)_full_priv_account}" ]]; then
      log_message 'Checkpoint 16'
      log_message 'Search did not find an account matching search criteria.'
      log_message 'Checking if any accounts with a Secure Token and FileVault access have a problematic password to prompt user to change it.'
      log_message 'other_choices_with_password: '${other_choices_with_password[@]}

      if [[ ${#other_choices_with_password} -gt 0 ]]; then
        replace_problem_password_on_account "${other_choices_with_password[1]}"
        : ${(P)_full_priv_account::=${other_choices_with_password[1]}}
      fi

      log_message 'Checkpoint 17'
      log_variable_state "${(P)_full_priv_account}" "${(P)_fv_priv_account}" "${(P)_secure_token_priv_account}"
      if [[ -z "${(P)_full_priv_account}" ]]; then
        log_message 'Checkpoint 18'
        log_message 'No accounts with a Secure Token and FileVault access and a known, problematic password where found.'
        log_message 'other_choices_without_password: '${other_choices_without_password[@]}

        if [[ ${#other_choices_without_password} -gt 0 ]]; then
          if [[ ${#other_choices_without_password} -eq 1 ]]; then
            log_message 'Checkpoint 18a - There is one account that has a Secure Token but with no known password.'
            printf "\n"
            display_message "The password for the following account is needed so that some of the operations can complete successfully."
          else
            log_message 'Checkpoint 18b - There are multiple accounts that have a Secure Token but with no known password.'
            printf "\n"
            display_message "The password for one of the following accounts is needed so that some of the operations can complete successfully."
          fi

          get_password_for_account_in_list other_choices_without_password username password

          if has_no_leading_trailing_whitespace "$password"; then
            printf '\n'
          else
            replace_problem_password_on_account "$username"
          fi

          log_message "Checkpoint 18c - good password found for $username"
          : ${(P)_full_priv_account::=$username}
        else
          log_message 'Checkpoint 18d - no accounts with a Secure Token'
          abort 'Oops! No accounts have a Secure Token.  This can happen in rare circumstances but unfortunately there is no way to resolve this issue in a non-destructive way.'
        fi
      fi
    fi
  fi
}

get_info_all_login_accounts () {
  typeset username

  log_message 'Retrieving information on all system login accounts.'

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
    display_message 'You will be prompted for a password for each account. You may press Ctrl+C to skip an account. Skipped accounts will be disabled. Under certain circumstances you may be required later to provide a password for a skipped account because it has access permissions not provided by other accounts.'

    log_message '*old* DISABLED_ACCOUNTS: '${DISABLED_ACCOUNTS[@]}
    for username in "${LOGIN_ACCOUNTS[@]}"
    do 
      [[ $username == $SCRIPT_USER ]] && continue
      get_account_password_aux $username
    done
    printf '\n'
    log_message '*new* DISABLED_ACCOUNTS: '${DISABLED_ACCOUNTS[@]}
  fi
}

get_login_account_list () {
  log_message 'Getting list of system login accounts.'

  LOGIN_ACCOUNTS=$(
    dscl . list /Users UniqueID | \
    awk '$2 > 500 && $2 < 1000 { printf "%s ", $1 }'
  )
  LOGIN_ACCOUNTS=(${(@s: :)LOGIN_ACCOUNTS})
}

get_sudo () {
  # Invalidate sudo timestamp before exiting (if it wasn't active before).
  [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
  SUDO_INVALIDATE_ON_EXIT=$?

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
  pwpolicy -u $username authentication-allowed | grep "allows user" > /dev/null
}

is_account_secure_token_enabled () {
  sysadminctl -secureTokenStatus $1 2>&1 | grep "ENABLED" >/dev/null
}

is_account_exist () {
  [[ $(dscl . -list /Users UniqueID | grep "$1" | wc -l) -eq 1 ]]
  return
}

is_user_password_valid () {
  local is_account_enabled

  is_account_enabled=$(pwpolicy -u $1 authentication-allowed | grep -c "is disabled")
  [[ $is_account_enabled -ne 0 ]] && enable_account "$1"
  dscl /Local/Default -authonly "$1" "$2" 2>/dev/null 1>&2
  result=$?
  [[ $is_account_enabled -ne 0 ]] && disable_account "$1"
  [[ $result -eq 0 ]] && return 0

  display_error "Password Invalid!"
  return 1
}

remove_account () {
  pushd -q /Users
  enable_account "$1"
  execute_sudo "dscl" "." "-delete" "/Users/$1"
  execute_sudo "zsh" "-c" "tccutil reset SystemPolicyAllFiles com.apple.Terminal >/dev/null"
  log_message "Attempting to remove /Users/$1"
  while ! sudo rm -rf /Users/$1 >/dev/null 2>&1; do
    log_message "Attempt failed. Waiting 1 second"
    sleep 1
  done
  popd -q
}

remove_user_from_admin_group () {
  execute_sudo "dseditgroup" "-o" "edit" "-d" "$1" "-t" "user" "admin"
}

replace_problem_password_on_account () {
  typeset username=$1
  typeset new_password

  log_message "Replacing problem password for $username"

  printf '\n'
  display_message 'The password provided for `'$username'` is correct but it contains leading or trailing spaces. It needs to be changed or some operations will be unsuccessful. In order for it to be used. Please provide a new password.'

  if [[ "$username" == "preboot" ]]; then
    get_password_and_confirm "preboot" new_password
  else
    get_password_and_confirm "admin" "$username" new_password
  fi

  printf '\n'
  ohai '  Changing `'$username'` account password.'
  (($DISABLED_ACCOUNTS[(Ie)$username])) && enable_account "$username"
  change_user_password "$username" "${PASSWORDS[$username]}" "$new_password"
  [[ "$username" == "preboot" ]] && disable_account "preboot"
  PASSWORDS[$username]=$new_password

  # remove account from ACCOUNTS_WITH_PROBLEM_PASSWORDS
  ACCOUNTS_WITH_PROBLEM_PASSWORDS=("${(@)ACCOUNTS_WITH_PROBLEM_PASSWORDS:#${username}}")
}

reset_tcc_configuration () {
  execute_sudo "tccutil" "reset" "SystemPolicyDesktopFolder" "com.apple.Terminal"
  execute_sudo "tccutil" "reset" "SystemPolicyDownloadsFolder" "com.apple.Terminal"
  execute_sudo "tccutil" "reset" "SystemPolicyDocumentsFolder" "com.apple.Terminal"
  execute_sudo "tccutil" "reset" "SystemPolicyAllFiles" "com.apple.Terminal"
  execute_sudo "tccutil" "reset" "SystemPolicyDesktopFolder" "com.apple.SystemEvents"
}

show_others_option_from_login_screen () {
  execute_sudo "defaults" "write" "/Library/Preferences/com.apple.loginwindow" "SHOWOTHERUSERS_MANAGED" "-bool" "TRUE"
}

update_secure_token_holder_list () {
  typeset username

  log_message 'Updating Secure Token Holders list.'
  log_message '*old* SECURE_TOKEN_HOLDERS = '${SECURE_TOKEN_HOLDERS[@]}

  SECURE_TOKEN_HOLDERS=()

  for username in "${LOGIN_ACCOUNTS[@]}"
  do
    if is_account_secure_token_enabled "$username"; then
      SECURE_TOKEN_HOLDERS+=("$username")
    fi
  done
  log_message '*new* SECURE_TOKEN_HOLDERS = '${SECURE_TOKEN_HOLDERS[@]}
}

