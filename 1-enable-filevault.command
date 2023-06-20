#!/usr/bin/env zsh
#
# This script performs the following tasks:
#  * Ensure all *enabled* login accounts have passwords that meet the
#    complexity requirements for HIGH or EXTREME locations.
#  * Ensure all login accounts have a SECURE TOKEN.
#  * Ensure all login accounts for HIGH locations have access to
#    unlock FileVault.
#  * Ensure a preboot account exists and is configured as the only account that
#    can unlock FileVault for EXTREME locations
#  * Ensure a preboot account is configured to only unlock FileVault for
#    EXTREME locations and is not used as a regular user account.
#  * Provide a smooth transition between HIGH and EXTREME configurations
#
# Copyright (c) 2023 Doug Campbell. All rights reserved.

SCRIPT_DIR=$( cd -- "$( dirname -- "${(%):-%x}" )" &> /dev/null && pwd )

. "${SCRIPT_DIR}/lib/config.sh"
. "${SCRIPT_DIR}/lib/display.sh"
. "${SCRIPT_DIR}/lib/filevault.sh"
. "${SCRIPT_DIR}/lib/globals.sh"
. "${SCRIPT_DIR}/lib/input.sh"
. "${SCRIPT_DIR}/lib/preboot.sh"
. "${SCRIPT_DIR}/lib/quoting.sh"
. "${SCRIPT_DIR}/lib/system.sh"
. "${SCRIPT_DIR}/lib/util.sh"

SCRIPT_USER=$(logname)

# set DEBUG to 0 to enable debugging messages
DEBUG=1

main () {
  typeset filevault_state
  typeset fv_username
  typeset main_username
  typeset username password new_password
  typeset secure_token_user_username
  typeset -a other_choices_with_password
  typeset -a other_choices_without_password

  get_login_account_list
  get_info_all_login_accounts
  get_filevault_account_list
  get_passwords_for_remaining_login_accounts
  get_filevault_state filevault_state
  check_all_login_accounts_for_problem_passwords
  [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"

  if [[ "$filevault_state" == "on" ]]; then
    if [[ $DEBUG -eq 0 ]]; then
      ohai_debug 'FileVault is Enabled.'
      ohai_debug 'Checkpoint 1'
      ohai_debug 'Searching for account with a Secure Token and FileVault access.'
      ohai_debug 'Searching accounts with FileVault access for ones that also have a Secure Token and a known, good password.'
    fi

    other_choices_with_password=()
    other_choices_without_password=()
    unset username
    for username in "${FILEVAULT_ENABLED_ACCOUNTS[@]}"; do
      [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
      # if account does not have secure token, skip it
      (($SECURE_TOKEN_HOLDERS[(Ie)$username])) || continue
      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 1a - '$username' has Secure Token'

      # if account has a problem password, skip it
      if (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])); then
        [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 1b - '$username' has problem password'
        other_choices_with_password+=("$username")
        continue
      fi

      # if account password has not been provided, skip it
      if [[ -z "${PASSWORDS[$username]}" ]]; then
        [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 1c - '$username' has no provided password'
        other_choices_without_password+=("$username") 
        continue
      fi

      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 1d - '$username' has Secure Token and FileVault access and a known, good password.'
      main_username=$username
      break
    done
    [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
    [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 2'
    if [[ -z "$main_username" ]]; then
      if [[ $DEBUG -eq 0 ]]; then
        ohai_debug 'Checkpoint 3'
        ohai_debug 'Search did not find an account matching search criteria.'
        ohai_debug 'Searching accounts with FileVault access that have a known but problematic password for ones that also have a Secure Token.'
        ohai_debug 'other_choices_with_password: '${other_choices_with_password[@]}
      fi

      unset username
      for username in "${other_choices_with_password[@]}"; do
        [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
        printf '\n'
        printf "%s\n" 'The password provided for `'$username'` is correct but it contains leading or trailing'
        printf "%s\n" 'spaces. It needs to be changed or some operations will be unsuccesful. In order for it'
        printf "%s\n" 'to be used. Please provide a new password.'

        if [[ $username == "preboot" ]]; then
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 3a - preboot account'
          get_password_and_confirm "preboot" new_password
        else
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 3b - non-preboot account'
          get_password_and_confirm "admin" "$username" new_password
        fi

        printf "\n"
        ohai 'Changing `'$username'` account password.'
        (($DISABLED_ACCOUNTS[(Ie)$username])) && enable_account "$username"
        change_user_password "$username" "${PASSWORDS[$username]}" "$new_password"
        [[ "$username" == "preboot" ]] && disable_account "preboot"
        PASSWORDS[$username]=$new_password

        # remove account from ACCOUNTS_WITH_PROBLEM_PASSWORDS
        ACCOUNTS_WITH_PROBLEM_PASSWORDS=("${(@)ACCOUNTS_WITH_PROBLEM_PASSWORDS:#${username}}")

        main_username=$username
        break
      done
      [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 4'
      if [[ -z "$main_username" ]]; then
        if [[ $DEBUG -eq 0 ]]; then
          ohai_debug 'Checkpoint 5'
          ohai_debug 'Search did not find an account matching search criteria.'
          ohai_debug 'Searching accounts with FileVault access where password is unknown for ones that also have a Secure Token.'
          ohai_debug 'other_choices_without_password: '${other_choices_without_password[@]}
        fi

        if [[ ${#other_choices_without_password} -gt 0 ]]; then
          if [[ ${#other_choices_without_password} -eq 1 ]]; then
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5a'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'There is one account that has FileVault access and a Secure Token but with no known password.'
            printf "\n"
            printf "%s\n" "The password for the following account is needed so that some of the operations can"
            printf "%s\n" "complete successfully."
          else
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5b'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'There are multiple accounts that have FileVault access and a Secure Token but with no known password.'
            printf "\n"
            printf "%s\n" "The password for one of the following accounts is needed so that some of the operations"
            printf "%s\n" "can complete successfully."
          fi
          
          while true; do
            if [[ ${#other_choices_without_password} -eq 1 ]]; then
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5c'
              username=${other_choices_without_password[1]}
            else
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5d'
              PS3="Select account: "
              select_with_default other_choices_without_password "" username
            fi
          
            printf "\n"
            printf "%s\n" 'Please provide password for `'$username'`.'
            if [[ $username == "preboot" ]]; then
              get_account_password "preboot" password "verify"
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5e - preboot account'
            else
              get_account_password "admin" "$username" password "verify" 
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5f - non-preboot account'
            fi
    
            has_no_leading_trailing_whitespace "$password" && printf '\n' && break

            printf '\n'
            printf "%s\n" 'The password provided for `'$username'` is correct but it contains leading or trailing'
            printf "%s\n" 'spaces. It needs to be changed in order to proceed. Please provide a new password.'

            if [[ $username == "preboot" ]]; then
              get_password_and_confirm "preboot" new_password
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5g - preboot account'
            else
              get_password_and_confirm "admin" "$username" new_password
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5h - non-preboot account'
            fi

            printf "\n"
            ohai 'Changing `'$username'` account password.'
            (($DISABLED_ACCOUNTS[(Ie)$username])) && enable_account "$username"
            change_user_password "$username" "$password" "$new_password"
            [[ "$username" == "preboot" ]] && disable_account "preboot"
            password=$new_password
            break
          done

          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 5i'
          PASSWORDS[$username]=$password

          # account no longer requires disabling since we have a password for it
          ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")

          main_username=$username
        fi
        [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
        [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 6'
        if [[ -z "$main_username" ]]; then
          if [[ $DEBUG -eq 0 ]]; then
            ohai_debug 'Checkpoint 7'
            ohai_debug 'Search did not find an account matching search criteria.'
            ohai_debug 'Searching accounts with FileVault access for ones with a known, goood password.'
          fi    

          other_choices_without_password=()
          unset username
          for username in "${FILEVAULT_ENABLED_ACCOUNTS[@]}"; do
            [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
            (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])) && continue
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 7a - password does not have problems'
            if [[ -z "${PASSWORDS[$username]}" ]]; then
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 7b - actually, there is no password provided for this username'
              other_choices_without_password+=("$username")
              continue
            fi

            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 7c - account has FileVault access and a known, good password'
            fv_username=$username
            break
          done

          [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 8'
          if [[ -z "$fv_username" ]]; then
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Search did not find an account matching search criteria.'
            if [[ ${#other_choices_without_password} -gt 0 ]]; then
              if [[ ${#other_choices_without_password} -eq 1 ]]; then
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9a'
                [[ $DEBUG -eq 0 ]] && ohai_debug 'There is one account that has FileVault access but with no known password.'
                printf "\n"
                printf "%s\n" "The password for the following account is needed so that some of the operations can"
                printf "%s\n" "complete successfully."
              else
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9b'
                [[ $DEBUG -eq 0 ]] && ohai_debug 'There are multiple accounts that have FileVault access but with no known password.'
                printf "\n"
                printf "%s\n" "The password for one of the following accounts is needed so that some of the operations"
                printf "%s\n" "can complete successfully."
              fi

              while true; do
                if [[ ${#other_choices_without_password} -eq 1 ]]; then
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9c'
                  username=${other_choices_without_password[1]}
                else
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9d'
                  PS3="Select account: "
                  select_with_default other_choices_without_password "" username
                fi

                printf "\n"
                printf "%s\n" 'Please provide password for `'$username'`.'
                if [[ $username == "preboot" ]]; then
                  get_account_password "preboot" password "verify"
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9e'
                else
                  get_account_password "admin" "$username" password "verify" 
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9f'
                fi
                PASSWORDS[$username]=$password
    
                # account no longer requires disabling since we have a password for it
                ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")

                has_no_leading_trailing_whitespace "$password" && printf '\n' &&  break
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9g'
                display_error 'Unfortunately this password while correct contains leading or trailing spaces.  Please select a different account to try.'
                ACCOUNTS_WITH_PROBLEM_PASSWORDS+=("$username")
                other_choices_without_password=("${(@)other_choices_without_password:#${username}}")
                if [[ ${#other_choices_without_password} -eq 0 ]]; then
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9h'
                  display_error 'All of the accounts with FileVault access have a password with leading or trailing spaces but do not have a Secure Token so there is no way to change the password.'
                  abort 'Oops. Unfortunately there is no way to resolve this issue in a non-destructive way.'
                fi
              done

              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9i'
              fv_username=$username
            else
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 9j'
              abort 'Oops! No accounts have FileVault access. This should never happen.'
            fi
          fi

          if [[ $DEBUG -eq 0 ]]; then
            display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
            ohai_debug 'Checkpoint 10'
            ohai_debug '`'$fv_username'` account has FileVault access and has been selected to administrate FileVault access.'
            ohai_debug 'Searching accounts with a Secure Token for ones with a known, goood password.'
          fi

          other_choices_without_password=()
          unset username
          for username in "${SECURE_TOKEN_HOLDERS[@]}"; do
            [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
            (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])) && continue
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 10a - account does not have problem password'
            if [[ -z "${PASSWORDS[$username]}" ]]; then
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 10b - actually, account does not have a password'
              other_choices_without_password+=("$username")
              continue
            fi

            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 10c - account has Secure Token'
            secure_token_user_username=$username
            break
          done
          [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 11'
          if [[ -z "$secure_token_user_username" ]]; then
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Search did not find an account matching search criteria.'
            if [[ ${#other_choices_without_password} -gt 0 ]]; then
              if [[ ${#other_choices_without_password} -eq 1 ]]; then
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12a'
                [[ $DEBUG -eq 0 ]] && ohai_debug 'There is one account that has a Secure Token but with no known password.'
                printf "\n"
                printf "%s\n" "The password for the following account is needed so that some of the operations can"
                printf "%s\n" "complete successfully."
              else
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12b'
                [[ $DEBUG -eq 0 ]] && ohai_debug 'There are multiple accounts that have a Secure Token but with no known password.'
                printf "\n"
                printf "%s\n" "The password for one of the following accounts is needed so that some of the operations"
                printf "%s\n" "can complete successfully."
              fi

              while true; do
                if [[ ${#other_choices_without_password} -eq 1 ]]; then
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12c'
                  username=${other_choices_without_password[1]}
                else
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12d'
                  PS3="Select account: "
                  select_with_default other_choices_without_password "" username
                fi

                printf "\n"
                printf "%s\n" 'Please provide password for `'$username'`.'
                if [[ $username == "preboot" ]]; then
                  get_account_password "preboot" password "verify"
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12e - preboot account'
                else
                  get_account_password "admin" "$username" password "verify" 
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12f - non-preboot account'
                fi
                PASSWORDS[$username]=$password

                # account no longer requires disabling since we have a password for it
                ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#${username}}")
                
                has_no_leading_trailing_whitespace "$password" && printf '\n' && break
                [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12g'
                display_error 'Unfortunately this password while correct contains leading or trailing spaces.  Please select a different account to try.'
                ACCOUNTS_WITH_PROBLEM_PASSWORDS+=("$username")
                other_choices_without_password=("${(@)other_choices_without_password:#${username}}")
                if [[ ${#other_choices_without_password} -eq 0 ]]; then
                  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12h'
                  display_error 'All of the accounts with a Secure Token have a password with leading or trailing spaces but do not have FileVault access so there is no way to change the password.'
                  abort 'Oops. Unfortunately there is no way to resolve this issue in a non-destructive way.'
                fi
              done

              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12i'
              secure_token_user_username=$username
            else
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 12j'
              abort 'Oops! No accounts have a Secure Token.  This can happen in rare circumstances but unfortunately there is no way to resolve this issue in a non-destructive way.'
            fi
          fi

          if [[ $DEBUG -eq 0 ]]; then
            display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
            ohai_debug 'Checkpoint 13'
            ohai_debug 'Adding FileVault access to account with only Secure Token access.'
            ohai_debug 'secure_token_user_username password: '${PASSWORDS[$secure_token_user_username]}
            ohai_debug 'fv_username password: '${PASSWORDS[$fv_username]}
          fi
          [[ $fv_username == "preboot" || $secure_token_user_username == "preboot" ]] && enable_account "preboot"
          grant_account_filevault_access "$secure_token_user_username" "${PASSWORDS[$secure_token_user_username]}" "$fv_username" "${PASSWORDS[$fv_username]}"
          [[ $fv_username == "preboot" || $secure_token_user_username == "preboot" ]] && disable_account "preboot"
          
          main_username=$secure_token_user_username
        fi
      fi
    fi
  else
    if [[ $DEBUG -eq 0 ]]; then
      ohai_debug 'Checkpoint 14'
      ohai_debug 'FileVault is Disabled.'
      ohai_debug 'Searching for account with a Secure Token and FileVault access.'
      ohai_debug 'Searching accounts with a Secure Token and FileVault access for ones with a known, good password.'
    fi
    
    other_choices_with_password=()
    other_choices_without_password=()
    unset username
    for username in "${FILEVAULT_ENABLED_ACCOUNTS[@]}"; do
      [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
      # if account does not have secure token, skip it
      (($SECURE_TOKEN_HOLDERS[(Ie)$username])) || continue
      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 14a - account has secure token'

      # if account has a problem password, skip it
      if (($ACCOUNTS_WITH_PROBLEM_PASSWORDS[(Ie)$username])); then
        [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 14b - account has problem password'
        other_choices_with_password+=("$username")
        continue
      fi

      # if account password has not been provided, skip it
      if [[ -z "${PASSWORDS[$username]}" ]]; then
        [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 14c - actually, account does not have a provided password'
        other_choices_without_password+=("$username") 
        continue
      fi

      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 14d - account has Secure Token and FileVault access and a known, good password'
      main_username=$username
      break
    done
    [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
    [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 15'
    if [[ -z "$main_username" ]]; then
      if [[ $DEBUG -eq 0 ]]; then
        ohai_debug 'Checkpoint 16'
        ohai_debug 'Search did not find an account matching search criteria.'
        ohai_debug 'Checking if any accounts with a Secure Token and FileVault access have a problematic password to prompt user to change it.'
        ohai_debug 'other_choices_with_password: '${other_choices_with_password[@]}
      fi

      unset username
      for username in "${other_choices_with_password[@]}"; do
        [[ $DEBUG -eq 0 ]] && ohai_debug 'username: '$username
        printf '\n'
        printf "%s\n" 'The password provided for `'$username'` is correct but it contains leading or trailing'
        printf "%s\n" 'spaces. It needs to be changed or some operations will be unsuccesful. In order for it'
        printf "%s\n" 'to be used. Please provide a new password.'

        if [[ $username == "preboot" ]]; then
          get_password_and_confirm "preboot" new_password
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 16a - preboot account'
        else
          get_password_and_confirm "admin" "$username" new_password
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 16b - non-preboot account'
        fi

        printf "\n"
        ohai 'Changing `'$username'` account password.'
        (($DISABLED_ACCOUNTS[(Ie)$username])) && enable_account "$username"
        change_user_password "$username" "${PASSWORDS[$username]}" "$new_password"
        [[ "$username" == "preboot" ]] && disable_account "preboot"
        PASSWORDS[$username]=$new_password

        # remove account from ACCOUNTS_WITH_PROBLEM_PASSWORDS
        ACCOUNTS_WITH_PROBLEM_PASSWORDS=("${(@)ACCOUNTS_WITH_PROBLEM_PASSWORDS:#${username}}")

        main_username=$username
        break
      done

      [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
      [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 17'
      if [[ -z "$main_username" ]]; then
        if [[ $DEBUG -eq 0 ]]; then
          ohai_debug 'Checkpoint 18'
          ohai_debug 'No accounts with a Secure Token and FileVault access and a known, problematic password where found.'
          ohai_debug 'other_choices_without_password: '${other_choices_without_password[@]}
        fi

        if [[ ${#other_choices_without_password} -gt 0 ]]; then
          if [[ ${#other_choices_without_password} -eq 1 ]]; then
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18a'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'There is one account that has a Secure Token but with no known password.'
            printf "\n"
            printf "%s\n" "The password for the following account is needed so that some of the operations can"
            printf "%s\n" "complete successfully."
          else
            [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18b'
            [[ $DEBUG -eq 0 ]] && ohai_debug 'There are multiple accounts that have a Secure Token but with no known password.'
            printf "\n"
            printf "%s\n" "The password for one of the following accounts is needed so that some of the operations"
            printf "%s\n" "can complete successfully."
          fi

          while true; do
            if [[ ${#other_choices_without_password} -eq 1 ]]; then
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18c'
              username=${other_choices_without_password[1]}
            else
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18d'
              PS3="Select account: "
              select_with_default other_choices_without_password "" username
            fi

            printf "\n"
            printf "%s\n" 'Please provide password for `'$username'`.'
            if [[ $username == "preboot" ]]; then
              get_account_password "preboot" password "verify"
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18e'
            else
              get_account_password "admin" "$username" password "verify"
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18f'
            fi
            PASSWORDS[$username]=$password

            has_no_leading_trailing_whitespace "$password" && printf '\n' && break

            printf '\n'
            printf "%s\n" 'The password provided for `'$username'` is correct but it contains leading or trailing'
            printf "%s\n" 'spaces. It needs to be changed or some operations will be unsuccesful. In order for it'
            printf "%s\n" 'to be used. Please provide a new password.'

            if [[ $username == "preboot" ]]; then
              get_password_and_confirm "preboot" new_password
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18g - preboot account'
            else
              get_password_and_confirm "admin" "$username" new_password
              [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18h - non-preboot account'
            fi

            printf "\n"
            ohai 'Changing `'$username'` account password.'
            (($DISABLED_ACCOUNTS[(Ie)$username])) && enable_account "$username"
            change_user_password "$username" "${PASSWORDS[$username]}" "$new_password"
            [[ "$username" == "preboot" ]] && disable_account "preboot"
            PASSWORDS[$username]=$new_password
            break
          done

          main_username=$username
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18i'
        else
          [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 18j'
          abort 'Oops! No accounts have a Secure Token.  This can happen in rare circumstances but unfortunately there is no way to resolve this issue in a non-destructive way.'
        fi
      fi
    fi
  fi

  if [[ $DEBUG -eq 0 ]]; then
    ohai_debug 'Checkpoint 19'
    display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
    ohai_debug 'preboot password: '${PASSWORDS[preboot]}
  fi
  update_secure_token_holder_list
  enable_secure_token_for_all_accounts $main_username
  confirm_all_login_account_passwords_meet_requirements
  update_secure_token_holder_list
  enable_secure_token_for_all_accounts $main_username

  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 26'
  [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  if [[ $EXTREME -eq 0 ]]; then
    [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 27'
    configure_preboot_account
    configure_filevault_extreme $main_username
  else
    [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 28'
    [[ "$filevault_state" == "off" ]] && enable_filevault $main_username
    [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 29'
    enable_filevault_access_for_all_accounts $main_username
    is_account_exist "preboot" && remove_account "preboot" && ACCOUNTS_TO_DISABLE=("${(@)ACCOUNTS_TO_DISABLE:#preboot}")
    show_others_option_from_login_screen
  fi

  [[ $DEBUG -eq 0 ]] && ohai_debug 'Checkpoint 30'
  [[ $DEBUG -eq 0 ]] && display_variable_state "$main_username" "$fv_username" "$secure_token_user_username"
  # disable accounts that passwords were not provided for
  [[ $DEBUG -eq 0 ]] && ohai_debug "Disabling accounts that passwords weren't provided for."
  unset username
  for username in "${ACCOUNTS_TO_DISABLE[@]}"; do
    disable_account "$username"
  done
}

typeset choice
typeset -a security_levels=("EXTREME" "HIGH")

prepare_display_environment
check_run_command_as_root
check_run_command_as_admin

printf "%s\n" "A security level choice must be made."
PS3="Select security level: "
select_with_default security_levels "EXTREME" choice
[[ $choice == "EXTREME" ]] && EXTREME=0 || EXTREME=1

[[ $EXTREME -eq 0 ]] && ohai 'Current Security Level: EXTREME' || ohai 'Current Security Level: HIGH'

# get script user password
# note: we get this separately because we need to have sudo prior to attempting to verify
#       the remaining accounts just in case they are currently disabled.
ohai 'Getting password for account currently running this script.'
get_account_password_aux $SCRIPT_USER
printf '\n'

# Invalidate sudo timestamp before exiting (if it wasn't active before).
if [[ -x /usr/bin/sudo ]] && ! /usr/bin/sudo -n -v 2>/dev/null
then
  trap '/usr/bin/sudo -k' EXIT
fi

get_sudo "${PASSWORDS[$SCRIPT_USER]}"

check_for_security_level_downgrade_attempt

main "$@"

printf '\n'
display_message "The script has completed running."
printf '\n'

if [[ $EXTREME -eq 0 ]]; then
  display_message 'It is strongly recommended that you reboot the computer and practice unlocking the disk encryption by using the new "Pre-Boot Authentication" account to authenticate'
else
  display_message 'It is strongly recommended that you reboot the computer and practice unlocking the disk encryption.'
fi
printf "\n"

ask_yes_no "Reboot now? (y/n)"
if [[ $? -eq 0 ]]; then
  clear
  printf '\n'
  display_message "Restarting computer in 5 seconds..."
  printf '\n'
  display_message "If a dialog appears stating '"'"Terminal" wants access to control "System Events". Allowing control will provide access to documents and data in "System Events", and to perform actions within that app.'"' Please click 'OK'."
  printf '\n'
  display_message "If a dialog appears stating '"'"System Events" would like to access files in your Desktop folder.'"' Please click 'OK'."
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
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"'${SCRIPT_DIR}'/close-terminal.command", hidden:false}' >/dev/null 2>&1
  execute_sudo "reboot"
fi

kill `ps -A | grep -w Terminal.app | grep -v grep | awk '{print $1}'`

exit 0
