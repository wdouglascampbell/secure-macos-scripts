#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

ask_yes_no () {
  local result

  while true; do
    display_prompt "$1"; read -k1 yn
    case $yn in
      [Yy] )
        result=0
        break
        ;;
      [Nn] )
        result=1
        break
        ;;
      * )
        printf '\n'
        display_error "Invalid response. Please try again."
        ;;
    esac
  done

  return $result
}

check_password_complexity () {
  local character_type_count=0
  local min_length

  if [[ $1 =~ '^[[:space:]]+|[[:space:]]+$' ]]; then
    display_error "Password must not begin or end with whitespace."
    return 1
  fi

  [[ $EXTREME -eq 0 ]] && min_length=8 || min_length=16
  if [[ ${#1} -lt $min_length ]]; then
    display_error "Password must be $min_length characters in length."
    return 1
  fi

  [[ $EXTREME -eq 0 ]] && return 0

  [[ $1 =~ '[[:upper:]]' ]] && (( character_type_count++ ))
  [[ $1 =~ '[[:lower:]]' ]] && (( character_type_count++ ))
  [[ $1 =~ '[[:digit:]]' ]] && (( character_type_count++ ))
  [[ $1 =~ '[^[:upper:][:lower:][:digit:]]' ]] && (( character_type_count++ ))
  [[ $character_type_count -ge 3 ]] && return 0
  
  display_error "Password does not meet complexity requirements."
  printf "\n"
  printf "%7s${tty_red}%s${tty_reset}\n" "" "It must contain characters from 3 of the following 4 categoies:"
  printf "%7s${tty_red}%s${tty_reset}\n" "" " + Uppercase letters"
  printf "%7s${tty_red}%s${tty_reset}\n" "" " + Lowercase letters"
  printf "%7s${tty_red}%s${tty_reset}\n" "" " + Numbers"
  printf "%7s${tty_red}%s${tty_reset}\n" "" " + Special characters like ~\`\!@#\$ etc"

  return 1
}

get_input_from_user () {
  local PROMPT=$1
  local RESPONSE=$2
  local SECRET=${3:-0}
  local REGEX=${4:""}
  local VER_FUNC=${5:""}
  local VER_FUNC_NUM_ARGS=$((${#}-5))
  local VER_FUNC_ARGS=()
  local ERROR_MSG
  local input

  if [[ $VER_FUNC_NUM_ARGS -ge 1 ]]; then
    shift 5
    for ((i=1; i<=$VER_FUNC_NUM_ARGS; i++)); do
      VER_FUNC_ARGS+=("$1")
      shift
    done
  fi

  while true; do
    ERROR_MSG=""
    if [[ $SECRET -eq 0 ]]; then
      display_prompt "${PROMPT}"
      read -r input
    else
      unset input
      display_prompt "${PROMPT}"
      char_prompt=""
      while IFS= read -r -s -k 1 "?$char_prompt" char
      do
        [[ $char == $'\x0A' ]] && break
        if [[ $char == $'\x7F' ]]; then
          [[ ${#input} -eq 0 ]] && char_prompt="" && continue
          char_prompt=$(printf "\b \b")
          input=${input::-1}
        else
          char_prompt='*'
          input+="$char"
        fi
      done
    fi
    [[ $SECRET -eq 1 ]] && printf "\n"
    if [[ -n $input ]]; then
      if [[ -n $REGEX ]]; then
        printf "%s" "${input}" | perl -ne 'exit 1 if ! /'$REGEX'/'
        [[ $? -ne 0 ]] && ERROR_MSG="Invalid input!"
      fi
      if [[ -z $ERROR_MSG ]]; then
        [[ -z $VER_FUNC ]] && break
        $VER_FUNC "${VER_FUNC_ARGS[@]}" "$input" 1
        [[ $? -eq 0 ]] && break || continue
      fi
    else
      ERROR_MSG="You must provide a response!"
    fi
    display_error "${ERROR_MSG}"
  done

  # dereference 2nd pass parameter ${(P)2} and use substituion to
  # always set to input from the user.
  : ${(P)RESPONSE::=$input}
}

get_account_password () {
  local account_type=$1
  local user
  local _password
  local prompt_type
  local prompt='Password:'
  local check_pw_func
  declare -a check_pw_func_args=()

  if [[ $account_type == "preboot" ]]; then
    _password=$2
    prompt_type=$3
  else
    user=$2
    _password=$3
    prompt_type=$4
  fi

  case "$prompt_type" in
    "confirm")
      prompt='Confirm :'
      check_pw_func=''
      ;;
    "verify")
      case "$account_type" in
        "admin" | "user")
          check_pw_func='is_user_password_valid'
          check_pw_func_args=("$user")
          ;;
        "preboot")
          check_pw_func='verify_preboot_password'
          ;;
      esac
      ;;
    *)
      case "$account_type" in
        "admin" | "user")
          check_pw_func='check_password_complexity'
          ;;
        "preboot")
          check_pw_func='check_preboot_password_complexity'
          ;;
      esac
      ;;
    esac

  get_input_from_user "$prompt" $_password 1 "" "$check_pw_func" "${check_pw_func_args[@]}"
}

get_password_and_confirm () {
  local account_type=$1
  local user
  local _password
  local confirm_password
  declare -a base_func_call

  base_func_call=("get_account_password" "$account_type")
  if [[ $account_type == "preboot" ]]; then
    _password=$2
  else
    user=$2
    base_func_call+=("$user")
    _password=$3
  fi

  while true; do
    "${base_func_call[@]}" "$_password"
    "${base_func_call[@]}" confirm_password "confirm"
    [[ ${(P)_password} == $confirm_password ]] && break
    display_error "Passwords do not match! Please try again."
  done
}

has_no_leading_trailing_whitespace () {
  [[ $1 =~ '^[^[:space:]]+' ]] && [[ $1 =~ '[^[:space:]]+$' ]] && return 0

  display_error "Password must not begin or end with whitespace."
  return 1
}

select_with_default () {
  local _itemlist=$1
  local defaultitem=$2
  local _selection=$3

  local i
  local item

  # Print numbered menu items, based on the arguments passed.
  i=0
  for item in ${(P)_itemlist}; do
    if [[ "$item" == "$defaultitem" ]]; then
      printf '%s\n' "$((++i))) $item (*)"
    else
      printf '%s\n' "$((++i))) $item"
    fi
  done >&2 # Print to stderr, as `select` does.

  # Prompt the user for the index of the desired item.
  while :; do
    printf %s "${PS3-#? }" >&2 # Print the prompt string to stderr, as `select` does.
    read -r index
    # Make sure that the input is either empty or that a valid index was entered.
    [[ -n $defaultitem ]] && [[ -z $index ]] && : ${(P)_selection::=$defaultitem} && break
    (( index >= 1 && index <= ${#${(P)_itemlist}} )) 2>/dev/null || { echo "Invalid selection. Please try again." >&2; continue; }
    : ${(P)_selection::="${(P)_itemlist: $(( index - 1 )):1}"}
    break
  done
}

