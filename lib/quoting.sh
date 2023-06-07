#!/usr/bin/env zsh
# shebang for syntax detection, not a command
# do *not* set executable!

#######################################
# Description:
#   Quote a given string to be used in PHP code and enclosed
#   inside single quotes.
#   1. Search string and replace all instances of \ with \\
#   2. Search string and replace all instances of ' with \'
#   Note: When using BASH variable expansion and substring replacment
#         it is necessary to escape ' and \ with a backslash.
#   Reference: https://www.php.net/manual/en/language.types.string.php#language.types.string.syntax.single
# Arguments:
#   String to be quoted
#   Name of string to be derefenced for storing quoted string 
#######################################
quote_string_for_use_in_php_single_quotes () {
  local PHP_STRING=$1
  local _string_quoted_for_php_single_quotes=$2

  PHP_STRING=${PHP_STRING//\\/\\\\}
  PHP_STRING=${PHP_STRING//\'/\\\'}

  : ${(P)_string_quoted_for_php_single_quotes::=$PHP_STRING}
}

#######################################
# Description:
#   Quote a given string to be used in sed replacment which
#   uses single quotes.  The form of the sed command will be
#   something like the following:
#   sed -E 's/PATTERN/'"${QUOTED_STRING}"'/' file
#   1. Search string and replace all instances of \ with \\
#   2. Search string and replace all instances of & with \&
#   3. Search string and replace all instances of / (the delmited we are using
#      with sed) with \/
#   4. Search string and insert a backslash character before all instances of
#      the linefeed character
#   Note: When using BASH variable expansion and substring replacment
#         it is necessary to escape \ with a backslash and since /
#         is the delimiter in the variable expansion and substring replacment
#         it must also be escaped with a backslash.
#   Note: ! history expansion and ` command expansion do not seem to occur after
#         variable expansion has occured on the command line so they do not need
#         to be escaped.
#   Note: A backslash must proceed a linefeed in order for the command to be
#         continued on the next line.
# Arguments:
#   String to be quoted
#   Name of string to be derefenced for storing quoted string 
#######################################
quote_string_for_use_in_sed_single_quotes () {
  local SED_STRING=$1
  local _string_quoted_for_sed_single_quotes=$2

  SED_STRING=${SED_STRING//\\/\\\\}
  SED_STRING=${SED_STRING//&/\\&}
  SED_STRING=${SED_STRING//\//\\\/}
  # Note: Hex x0A is a linefeed character and x5C is \
  SED_STRING=${SED_STRING//$'\x0A'/$'\x5C\x0A'}

  : ${(P)_string_quoted_for_sed_single_quotes::=$SED_STRING}
}

#######################################
# Description:
#   Quote a given string to be used during cyrus imap login
#   as a double quote enclosed password.
#   . LOGIN "[USERNAME]" "[PASSWORD]"
#   1. Search string and replace all instances of \ with \\
#   2. Search string and replace all instances of " with \"
#   Note: When using BASH variable expansion and substring replacment
#         it is necessary to escape " and \ with a backslash
# Arguments:
#   String to be quoted
#   Name of string to be derefenced for storing quoted string
#######################################
quote_string_for_use_with_cyrus_imap_login_password () {
  local PW_STRING=$1
  local _string_quoted_for_cyrus_imap_login=$2

  PW_STRING=${PW_STRING//\\/\\\\}
  PW_STRING=${PW_STRING//\"/\\\"}

  : ${(P)_string_quoted_for_cyrus_imap_login::=$PW_STRING}
}

#######################################
# Description:
#   Quote a given string to be used within the double quotes
#   of an expect tcl script.
#   1. Search string and replace all instances of \ with \\
#   2. Search string and replace all instances of { with \{
#   3. Search string and replace all instances of [ with \[
#   4. Search string and replace all instances of } with \}
#   5. Search string and replace all instances of ] with \]
#   6. Search string and replace all instances of " with \"
# Arguments:
#   String to be quoted
#   Name of string to be derefenced for storing quoted string
#######################################
quote_string_for_use_within_expect_tcl_script_double_quotes () {
  local string=$1
  local _string_quoted_for_expect=$2

  # ensure tcl/expect special characters { [ } ] are quoted
  # and " / should be quoted as well since they will be placed
  # within double quotes.

  string=${string//\\/\\\\}
  string=${string//\{/\\\{}
  string=${string//\[/\\\[}
  string=${string//\}/\\\}}
  string=${string//\]/\\\]}
  string=${string//\"/\\\"}

  : ${(P)_string_quoted_for_expect::=$string}
}

