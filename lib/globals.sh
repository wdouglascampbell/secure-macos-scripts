#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

typeset -a ACCOUNTS_TO_DISABLE
typeset -a ACCOUNTS_WITH_PROBLEM_PASSWORDS
typeset -a ADMINS
typeset -a DISABLED_ACCOUNTS
typeset -a FILEVAULT_ENABLED_ACCOUNTS
typeset -a LOGIN_ACCOUNTS
typeset -a PASSWORD_CHANGE_REQUIRED_ACCOUNTS
typeset -A PASSWORDS
typeset -a SECURE_TOKEN_HOLDERS

typeset -i RESET_PREBOOT_PASSWORD=1  # default: 1 (false)

typeset SCRIPT_USER

