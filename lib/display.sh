#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

display_error () {
  local i

  text=("${(@f)$(printf "%s" "${1}" | fold -sw 70)}")
  printf "${tty_red}ERROR: ${text[1]}${tty_reset}\n"

  text=("${text[@]:1}")
  for i in "${text[@]}"
  do
    printf "${tty_red}       ${i}${tty_reset}\n"
  done
}

display_message () {
  local i

  text=("${(@f)$(printf "%s" "${1}" | fold -sw 70)}")
  for i in "${text[@]}"
  do
    printf "${tty_cyan}${i}${tty_reset}\n"
  done
}

display_prompt () {
  printf "${tty_grey}${1} ${tty_reset}"
}

display_variable_state () {
  ohai_debug 'Variable State'
  ohai_debug '  LOGIN_ACCOUNTS: '${LOGIN_ACCOUNTS[@]}
  ohai_debug '  FILEVAULT_ENABLED_ACCOUNTS: '${FILEVAULT_ENABLED_ACCOUNTS[@]}
  ohai_debug '  Usernames of PASSWORDS provided: '${(k)PASSWORDS[@]}
  ohai_debug '  ADMINS: '${ADMINS[@]}
  ohai_debug '  DISABLED_ACCOUNTS: '${DISABLED_ACCOUNTS[@]}
  ohai_debug '  SECURE_TOKEN_HOLDERS: '${SECURE_TOKEN_HOLDERS[@]}
  ohai_debug '  ACCOUNTS_TO_DISABLE: '${ACCOUNTS_TO_DISABLE[@]}
  ohai_debug '  ACCOUNTS_WITH_PROBLEM_PASSWORDS: '${ACCOUNTS_WITH_PROBLEM_PASSWORDS[@]}
  ohai_debug '  main_username: '$1
  ohai_debug '  fv_username: '$2
  ohai_debug '  secure_token_user_username: '$3
}

display_warning () {
  local i

  text=("${(@f)$(printf "%s" "${1}" | fold -sw 70)}")
  printf "${tty_yellow}WARNING: ${text[1]}${tty_reset}\n"

  text=("${text[@]:1}")
  for i in "${text[@]}"
  do
    printf "${tty_yellow}         ${i}${tty_reset}\n"
  done
}

ohai () {
  local i

  text=("${(@f)$(printf "%s" "$(shell_join "$@")" | fold -sw 70)}")
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "${text[1]}"

  text=("${text[@]:1}")
  for i in "${text[@]}"
  do
    printf "  ${tty_bold}  %s${tty_reset}\n" "${i}"
  done
}

ohai_debug () {
  typeset line

  text=("${(@f)$(printf "%s" "$(shell_join "$@")" | fold -sw 70)}")
  printf "${tty_purple}DEBUG: ${tty_bold}%s${tty_reset}\n" "${text[1]}"

  text=("${text[@]:1}")
  for line in "${text[@]}"
  do
    printf "       ${tty_bold}%s${tty_reset}\n" "$line"
  done
}

prepare_display_environment () {
  # change Terminal.app theme to "Homebrew" and set window size to 1024 x 768
  osascript -e '
  tell application "Terminal"
    set current settings of window 1 to settings set "Homebrew"
    set bounds of front window to {0, 23, 1024, 791}
  end tell
  '
  clear
  
  # configure string formatters
  # from bash(1) man page
  #   -t fd  True if file descriptor fd is open and refers to a terminal.
  if [[ -t 1 ]]
  then
    tty_escape () { printf "\033[%sm" "$1"; }
  else
    tty_escape () { :; }
  fi
  tty_mkbold () { tty_escape "1;$1"; }
  tty_underline="$(tty_escape "4;39")"
  tty_blue="$(tty_mkbold 34)"
  tty_purple="$(tty_mkbold 35)"
  tty_cyan="$(tty_mkbold 36)"
  tty_red="$(tty_mkbold 31)"
  tty_yellow="$(tty_mkbold 33)"
  tty_green="$(tty_mkbold 32)"
  tty_grey="$(tty_mkbold 90)"
  tty_bold="$(tty_mkbold 39)"
  tty_reset="$(tty_escape 0)"
}

