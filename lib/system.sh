#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

add_user_to_admin_group () {
  execute_sudo "dseditgroup" "-o" "edit" "-a" "$1" "-t" "user" "admin"
}

change_user_password () { 
  execute_sudo "dscl" "." "-passwd" "/Users/$1" "$2" "$3" 
  if [[ -f "/Users/$1/Library/Keychains/login.keychain" ]]; then 
    execute_sudo "security" "set-keychain-password" "-o" "$2" -p "$3" \ 
                            "/Users/$1/Library/Keychains/login.keychain" >/dev/null 2>&1 
  fi 
} 

disable_account () {
  execute_sudo "pwpolicy" "-u" "$1" "-disableuser" >/dev/null 2>&1
}

enable_account () {
  execute_sudo "pwpolicy" "-u" "$1" "-enableuser" >/dev/null 2>&1
}

enable_secure_token_for_account () {
  execute_sudo "sysadminctl" "-secureTokenOn" "$1" "-password" "$2" "-adminUser" "$3" "-adminPassword" "$4" 2>/dev/null
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

get_local_account_list () {
  local _local_account_list=$1
  local tmp

  tmp=$(
    dscl . list /Users UniqueID | \
    awk '$2 > 500 && $2 < 1000 { printf "%s ", $1 }'
  )
  tmp=(${(@s: :)tmp})

  set -A $_local_account_list ${(kv)tmp}
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
}

remove_user_from_admin_group () {
  execute_sudo "dseditgroup" "-o" "edit" "-d" "$1" "-t" "user" "admin"
}

