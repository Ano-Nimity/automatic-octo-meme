#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

info() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

confirm() {
 local prompt="${1:-Continue?}"
 local reply

 printf '%s [y/N] ' "$prompt" >/dev/tty
 IFS= read -r reply </dev/tty

 case "$reply" in
  [yY]|[yY][eE][sS]) return 0 ;;
  *) return 1 ;;
 esac
}

pause() {
  local prompt="${1:-Press Return to continue.}"

  printf '%s' "$prompt" >/dev/tty
  IFS= read -r _ </dev/tty
}

console_user() {
  /usr/bin/stat -f '%Su' /dev/console
}

home_for_user() {
  /usr/bin/dscl . -read "/Users/$1" NFSHomeDirectory |
    /usr/bin/awk '{$1=""; sub(/^ /, ""); print}'
}

user_exists() {
  /usr/bin/id "$1" &>/dev/null
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] ||
    die "This project only supports macOS."

  [[ "$(uname -m)" == "arm64" ]] ||
    die "This configuration requires Apple silicon."
}

require_admin_user() {
  local user="${1:-$(console_user)}"

  /usr/sbin/dseditgroup -o checkmember -m "$user" admin |
    /usr/bin/grep -q "yes" ||
    die "Run this while logged in as a macOS administrator."
}

brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif command -v brew &>/dev/null; then
    eval "$(brew shellenv)"
  else
    return 1
  fi
}

upsert_managed_block() {
  local file="$1"
  local marker="$2"
  local content="$3"
  local begin="# >>> ${marker} >>>"
  local end="# <<< ${marker} <<<"
  local original temporary

  original="$(mktemp)"
  temporary="$(mktemp)"

  if [[ -f "$file" ]]; then
    if [[ -r "$file" ]]; then
      /bin/cat "$file" >"$original"
    else
      sudo /bin/cat "$file" | /bin/cat >"$original"
    fi

    /usr/bin/awk -v begin="$begin" -v end="$end" '
      $0 == begin { skipping=1; next }
      $0 == end { skipping=0; next }
      !skipping { print }
    ' "$original" >"$temporary"
  fi

  {
    /bin/cat "$temporary"
    printf '\n%s\n%s\n%s\n' "$begin" "$content" "$end"
  } >"${temporary}.new"

  if [[ -w "$file" ]] ||
     [[ ! -e "$file" && -w "$(dirname "$file")" ]]; then
    /bin/cp "${temporary}.new" "$file"
  else
    sudo /bin/cp "${temporary}.new" "$file"
  fi

  /bin/rm -f "$original" "$temporary" "${temporary}.new"
}
