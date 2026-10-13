#!/usr/bin/env bash
# Fresh-Mac entry point. Safe to rerun after a partial or complete run.

set -euo pipefail
IFS=$'\n\t'

readonly REPOSITORY="Ano-Nimity/automatic-octo-meme"
readonly SOURCE_REF="${MAC_SETUP_REF:-main}"
readonly INSTALL_ROOT="/Users/Shared/automatic-octo-meme"

script_path="${BASH_SOURCE[0]:-}"

if [[ -n "$script_path" && -f "$script_path" ]] &&
   script_dir="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)"; then
  :
else
  script_dir=""
fi

install_repository_copy() {
  local temporary archive source staging backup

  temporary="$(mktemp -d)"
  archive="${temporary}/source.tar.gz"
  source="${temporary}/source"
  staging="${INSTALL_ROOT}.new"
  backup="${INSTALL_ROOT}.old"

  printf 'Downloading %s (%s)...\n' "$REPOSITORY" "$SOURCE_REF"

  /usr/bin/curl --fail --silent --show-error --location \
    "https://github.com/${REPOSITORY}/archive/${SOURCE_REF}.tar.gz" \
    --output "$archive"

  /bin/mkdir -p "$source"
  /usr/bin/tar -xzf "$archive" -C "$source" --strip-components=1

  [[ -f "${source}/Brewfile" ]] || {
    printf 'Downloaded repository is missing Brewfile.\n' >&2
    exit 1
  }

  /usr/bin/sudo /bin/rm -rf "$staging" "$backup"
  /usr/bin/sudo /usr/bin/ditto "$source" "$staging"

  if [[ -e "$INSTALL_ROOT" ]]; then
    /usr/bin/sudo /bin/mv "$INSTALL_ROOT" "$backup"
  fi

  /usr/bin/sudo /bin/mv "$staging" "$INSTALL_ROOT"
  /usr/bin/sudo /bin/rm -rf "$backup"
  /usr/bin/sudo /usr/sbin/chown -R "$(id -un):staff" "$INSTALL_ROOT"

  /usr/bin/sudo /bin/chmod +x \
    "${INSTALL_ROOT}/bootstrap.sh" \
    "${INSTALL_ROOT}/configure.sh"

  /bin/rm -rf "$temporary"
}

if [[ -z "$script_dir" ||
      ! -f "${script_dir}/scripts/common.sh" ||
      ! -f "${script_dir}/Brewfile" ]]; then
  install_repository_copy
  exec /usr/bin/env bash "${INSTALL_ROOT}/bootstrap.sh" "$@"
fi

# shellcheck source=scripts/common.sh
source "${script_dir}/scripts/common.sh"

require_macos

admin_user="$(console_user)"

[[ "$admin_user" != "root" && "$admin_user" != "loginwindow" ]] ||
  die "Log into the administrator desktop before running setup."

require_admin_user "$admin_user"

cat <<EOF

0xC0RE fresh-Mac setup

Administrator detected: ${admin_user}
Standard accounts:      player_one, player_two
Repository copy:        ${INSTALL_ROOT}

This installs third-party software, creates both standard accounts, disables
FileVault, enables SSH/SMB/Screen Sharing, and changes system/user preferences.

macOS will still require several visible approvals after the script finishes.
EOF

confirm "Review the repository files before continuing. Start setup?" ||
  die "Setup cancelled."

info "Refreshing administrator credentials"

sudo -v

while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

sudo_keepalive_pid=$!
trap 'kill "$sudo_keepalive_pid" 2>/dev/null || true' EXIT

info "Installing Xcode Command Line Tools"

if ! /usr/bin/xcode-select -p &>/dev/null; then
  /usr/bin/xcode-select --install 2>/dev/null || true
  pause "Complete the Apple Command Line Tools window, then press Return."

  /usr/bin/xcode-select -p &>/dev/null ||
    die "Command Line Tools were not detected."
else
  info "Command Line Tools are already installed"
fi

info "Installing Rosetta 2"

if [[ "$(uname -m)" == "arm64" ]] &&
   ! /usr/bin/pgrep oahd >/dev/null 2>&1 &&
   [[ ! -e /Library/Apple/usr/libexec/oah ]]; then
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license
else
  info "Rosetta 2 is already available"
fi

info "Installing Homebrew"

if ! command -v brew &>/dev/null &&
   [[ ! -x /opt/homebrew/bin/brew ]]; then
  NONINTERACTIVE=1 /bin/bash -c \
    "$(/usr/bin/curl -fsSL \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew_env || die "Homebrew installation failed."
brew analytics off

ensure_standard_user() {
  local username="$1"
  local full_name="$2"
  local expected_home="/Users/${username}"
  local actual_home actual_shell

  if user_exists "$username"; then
    actual_home="$(home_for_user "$username")"
    actual_shell="$(
      /usr/bin/dscl . -read "/Users/${username}" UserShell |
        /usr/bin/awk '{print $2}'
    )"

    if /usr/sbin/dseditgroup -o checkmember -m "$username" admin |
        /usr/bin/grep -q "yes"; then
      die "Existing ${username} is an administrator; refusing to adopt it."
    fi

    [[ "$actual_home" == "$expected_home" ]] ||
      die "Existing ${username} has unexpected home directory: ${actual_home}"

    [[ "$actual_shell" == "/bin/zsh" ]] ||
      die "Existing ${username} has unexpected shell: ${actual_shell}"
if [[ ! -d "$expected_home" ]]; then
 sudo /usr/sbin/createhomedir -c -u "$username"
fi

[[ -d "$expected_home" ]] ||
 die "Home directory was not created for ${username}."

    info "Existing standard ${username} account passed validation"
    return
  fi

  cat <<EOF
sysadminctl will now request a password for ${username}.
The password is entered directly into Apple's account tool and is not saved.
EOF

  sudo /usr/sbin/sysadminctl \
    -addUser "$username" \
    -fullName "$full_name" \
    -home "$expected_home" \
    -shell /bin/zsh \
    -password -

  user_exists "$username" || die "${username} was not created."
  if [[ ! -d "$expected_home" ]]; then
 sudo /usr/sbin/createhomedir -c -u "$username"
fi

[[ -d "$expected_home" ]] ||
 die "Home directory was not created for ${username}."
}

info "Creating the standard user accounts"

ensure_standard_user player_one "Player One"
ensure_standard_user player_two "Player Two"

info "Installing requested applications"

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_ENV_HINTS=1

brew bundle --file="${script_dir}/Brewfile"

info "Applying system and account configuration"

/usr/bin/env bash \
  "${script_dir}/configure.sh" \
  "$admin_user" \
  player_one \
  player_two

info "Finalizing the installed setup files"

if [[ "$(cd "$script_dir" && pwd -P)" != "$INSTALL_ROOT" ]]; then
  staging="${INSTALL_ROOT}.new"
  backup="${INSTALL_ROOT}.old"

  sudo /bin/rm -rf "$staging" "$backup"
  sudo /usr/bin/ditto "$script_dir" "$staging"

  if [[ -e "$INSTALL_ROOT" ]]; then
    sudo /bin/mv "$INSTALL_ROOT" "$backup"
  fi

  sudo /bin/mv "$staging" "$INSTALL_ROOT"
  sudo /bin/rm -rf "$backup"
fi

sudo /usr/sbin/chown -R "${admin_user}:staff" "$INSTALL_ROOT"
sudo /bin/chmod -R a+rX "$INSTALL_ROOT"

sudo /bin/chmod +x \
  "${INSTALL_ROOT}/bootstrap.sh" \
  "${INSTALL_ROOT}/configure.sh"

cat <<EOF

Setup completed.

Next:
  1. Complete the manual approvals in the setup tutorial.
  2. Log into player_one and player_two once.
  3. Reboot after completing the manual approvals.
EOF
