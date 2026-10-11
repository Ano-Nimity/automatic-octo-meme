#!/usr/bin/env bash
# System settings and per-user preferences. Safe to run repeatedly.

set -euo pipefail
IFS=$'\n\t'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common.sh
source "${script_dir}/scripts/common.sh"

require_macos

admin_user="${1:-$(console_user)}"
standard_user="${2:-player_one}"
vm_user="${3:-player_two}"

require_admin_user "$admin_user"

user_exists "$standard_user" ||
  die "The ${standard_user} account does not exist."

user_exists "$vm_user" ||
  die "The ${vm_user} account does not exist."

sudo -v

info "Setting the computer name to 0xC0RE"

sudo /usr/sbin/scutil --set ComputerName "0xC0RE"
sudo /usr/sbin/scutil --set LocalHostName "0xC0RE"
sudo /usr/sbin/scutil --set HostName "0xC0RE"

info "Ensuring FileVault and automatic login are off"

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.loginwindow \
  autoLoginUser -string ""

filevault_status="$(sudo /usr/bin/fdesetup status || true)"

if [[ "$filevault_status" == *"FileVault is On"* ]]; then
  warn "FileVault is currently enabled."

  if confirm "Disable FileVault now? Decryption can take a while."; then
    sudo /usr/bin/fdesetup disable
  else
    warn "FileVault remains enabled."
  fi
fi

info "Configuring power and restart behavior"

sudo /usr/bin/pmset -a sleep 0
sudo /usr/bin/pmset -a displaysleep 15
sudo /usr/bin/pmset -a disksleep 0
sudo /usr/bin/pmset -a womp 1
sudo /usr/bin/pmset -a autorestart 1

sudo /usr/sbin/systemsetup -setrestartpowerfailure on >/dev/null
sudo /usr/sbin/systemsetup -setwakeonnetworkaccess on >/dev/null

info "Enabling automatic security and macOS updates"

sudo /usr/sbin/softwareupdate --schedule on

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticCheckEnabled -bool true

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticDownload -bool true

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SoftwareUpdate \
  CriticalUpdateInstall -bool true

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SoftwareUpdate \
  ConfigDataInstall -bool true

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticallyInstallMacOSUpdates -bool true

info "Enabling the macOS firewall"

firewall="/usr/libexec/ApplicationFirewall/socketfilterfw"

sudo "$firewall" --setglobalstate on
sudo "$firewall" --setstealthmode on
sudo "$firewall" --setallowsigned on
sudo "$firewall" --setallowsignedapp on

ensure_access_group() {
  local group="$1"
  shift

  if ! /usr/bin/dscl . -read "/Groups/${group}" &>/dev/null; then
    sudo /usr/sbin/dseditgroup -o create "$group"
  fi

  local user

  for user in "$@"; do
    if ! /usr/sbin/dseditgroup -o checkmember -m "$user" "$group" |
      /usr/bin/grep -q "yes"; then
      sudo /usr/sbin/dseditgroup \
        -o edit \
        -a "$user" \
        -t user \
        "$group"
    fi
  done
}

info "Enabling SSH for all three local accounts"

ensure_access_group \
  com.apple.access_ssh \
  "$admin_user" \
  "$standard_user" \
  "$vm_user"

if ! sudo /usr/sbin/systemsetup -setremotelogin on; then
  warn "Remote Login needs Full Disk Access. Enable it manually in System Settings."
fi

info "Starting Screen Sharing"

ensure_access_group \
  com.apple.access_screensharing \
  "$admin_user" \
  "$standard_user" \
  "$vm_user"

sudo /bin/launchctl enable system/com.apple.screensharing

if ! sudo /bin/launchctl print \
    system/com.apple.screensharing &>/dev/null; then
  sudo /bin/launchctl bootstrap system \
    /System/Library/LaunchDaemons/com.apple.screensharing.plist ||
    true
fi

warn "Toggle Screen Sharing off and on once in System Settings to grant Screen Recording."

info "Creating the dedicated SharedFiles SMB share"

share_group="mac-file-share"
share_path="/Users/Shared/Files"

ensure_access_group \
  "$share_group" \
  "$admin_user" \
  "$standard_user" \
  "$vm_user"

sudo /bin/mkdir -p "$share_path"
sudo /usr/sbin/chown root:"$share_group" "$share_path"
sudo /bin/chmod 2770 "$share_path"

if ! /bin/ls -lde "$share_path" |
    /usr/bin/grep -Fq "group:${share_group} allow"; then
  sudo /bin/chmod +a \
    "group:${share_group} allow read,write,execute,delete,append,file_inherit,directory_inherit" \
    "$share_path"
fi

sudo /usr/sbin/sharing -r SharedFiles 2>/dev/null || true

sudo /usr/sbin/sharing \
  -a "$share_path" \
  -n SharedFiles \
  -S SharedFiles \
  -s 001 \
  -g 000

sudo /bin/launchctl enable system/com.apple.smbd

if ! sudo /bin/launchctl print system/com.apple.smbd &>/dev/null; then
  sudo /bin/launchctl bootstrap system \
    /System/Library/LaunchDaemons/com.apple.smbd.plist ||
    true
fi

info "Reducing optional diagnostic submission"

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.SubmitDiagInfo \
  SubmitDiagInfo -bool false

sudo /usr/bin/defaults write \
  /Library/Preferences/com.apple.applicationaccess \
  allowDiagnosticSubmission -bool false

apply_user_preferences() {
  local user="$1"
  local home

  home="$(home_for_user "$user")"

  info "Applying preferences for ${user}"

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain KeyRepeat -int 2

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain InitialKeyRepeat -int 15

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain ApplePressAndHoldEnabled -bool false

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain AppleShowAllExtensions -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    NSGlobalDomain com.apple.mouse.scaling -float -1

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder ShowPathbar -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder FXEnableExtensionChangeWarning -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder FXPreferredViewStyle -string "Nlsv"

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder AppleShowAllFiles -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder FXDefaultSearchScope -string "SCcf"

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder _FXSortFoldersFirst -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.finder ShowMountedServersOnDesktop -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.desktopservices DSDontWriteNetworkStores -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.desktopservices DSDontWriteUSBStores -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.dock autohide -bool true

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.dock autohide-delay -float 0

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.dock autohide-time-modifier -float 0.3

  sudo -u "$user" /bin/mkdir -p \
    "${home}/Pictures/Screenshots"

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.screencapture \
    location -string "${home}/Pictures/Screenshots"

  sudo -u "$user" HOME="$home" /usr/bin/defaults write \
    com.apple.screencapture disable-shadow -bool true

  local profile_content shell_content

  # shellcheck disable=SC2016
  profile_content='if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi'

  # shellcheck disable=SC2016
  shell_content='export HOMEBREW_NO_ANALYTICS=1
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
alias update-mac="brew update && brew upgrade && brew cleanup"'

  sudo -u "$user" /usr/bin/touch \
    "${home}/.zprofile" \
    "${home}/.zshrc"

  upsert_managed_block \
    "${home}/.zprofile" \
    "0xC0RE Homebrew" \
    "$profile_content"

  upsert_managed_block \
    "${home}/.zshrc" \
    "0xC0RE shell" \
    "$shell_content"

  sudo /usr/sbin/chown \
    "$user":staff \
    "${home}/.zprofile" \
    "${home}/.zshrc"

  if command -v dockutil &>/dev/null; then
    local support dock_script dock_agent

    support="${home}/Library/Application Support/0xC0RE"
    dock_script="${support}/configure-dock.sh"
    dock_agent="${home}/Library/LaunchAgents/local.0xcore.configure-dock.plist"

    sudo -u "$user" /bin/mkdir -p \
      "$support" \
      "$(dirname "$dock_agent")"

    sudo /usr/bin/tee "$dock_script" >/dev/null <<'DOCK_SCRIPT'
#!/usr/bin/env bash

set -euo pipefail

/bin/sleep 10

items=(
  "/Applications/iTerm.app"
  "/Applications/LibreWolf.app"
  "/Applications/Bitwarden.app"
  "/Applications/Signal.app"
  "/Applications/Draw Things.app"
  "/System/Applications/System Settings.app"
)

if [[ "$(/usr/bin/id -un)" == "player_two" ]]; then
  items+=("/Applications/VMware Fusion.app")
fi

for item in "${items[@]}"; do
  [[ -e "$item" ]] || continue

  name="$(/usr/bin/basename "$item" .app)"

  /opt/homebrew/bin/dockutil \
    --find "$name" \
    --homedir "$HOME" \
    >/dev/null 2>&1 ||
    /opt/homebrew/bin/dockutil \
      --add "$item" \
      --no-restart \
      --homedir "$HOME"
done

/usr/bin/killall Dock 2>/dev/null || true
DOCK_SCRIPT

    sudo /bin/chmod 700 "$dock_script"
    sudo /usr/sbin/chown "$user":staff "$dock_script"

    sudo /usr/bin/tee "$dock_agent" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.0xcore.configure-dock</string>
  <key>ProgramArguments</key>
  <array>
    <string>${dock_script}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

    sudo /bin/chmod 600 "$dock_agent"
    sudo /usr/sbin/chown "$user":staff "$dock_agent"

    if [[ "$(console_user)" == "$user" ]]; then
      sudo -u "$user" HOME="$home" "$dock_script"
    fi
  fi
}

brew_env || true

apply_user_preferences "$admin_user"
apply_user_preferences "$standard_user"
apply_user_preferences "$vm_user"

if [[ "$(console_user)" == "$admin_user" ]]; then
  /usr/bin/killall Finder Dock SystemUIServer \
    2>/dev/null || true
fi

info "System configuration complete"
