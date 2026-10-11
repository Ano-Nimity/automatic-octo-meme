# automatic-octo-meme
mac reimaging

Upload and run

## Repository structure

.
├── Brewfile
├── README.md
├── bootstrap.sh
├── configure.sh
└── scripts/
    └── common.sh

Complete Setup Assistant, skip Apple ID, create the administrator account, connect Ethernet, then run:


/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ano-Nimity/automatic-octo-meme/main/bootstrap.sh)"
The script prompts separately for passwords for player_one and player_two.

Required post-install steps
Log into both player accounts once.
Open System Settings → General → Sharing.
Verify Remote Login permits all three accounts.
Toggle Screen Sharing off and back on once, then permit all three accounts.
Verify File Sharing exposes only:

/Users/Shared/Files
as:

SharedFiles
Test before GUI login:

ssh player_one@0xC0RE.local
ssh player_two@0xC0RE.local

### Verify SMB access
Open **System Settings → General → Sharing → File Sharing**.
1. Confirm `SharedFiles` points to `/Users/Shared/Files`.
2. Disable guest access.
3. Remove any automatically added Public folders you do not want exposed.
4. Open **Options** or **Windows File Sharing**.
5. Enable the administrator, `player_one`, and `player_two` if macOS lists them.
6. Enter each account’s password when macOS requests it.
7. Optionally enable **Only allow SMB encrypted connections**.
8. 
From another computer, authenticate as `player_one` and then `player_two`:

smb://0xC0RE.local/SharedFiles


From another Mac, connect to:

smb://0xC0RE.local/SharedFiles
Configure Little Snitch and Proton VPN to allow LAN access on 10.1.10.0/24.
Confirm FileVault is off and reboot recovery works.
Install VMware Fusion under player_two
Log into player_two.
Visit Broadcom Support.
Sign in or create a Broadcom account.
Open My Downloads → Free Software Downloads.
Download VMware Fusion Pro 26H1u1 or a newer security-fixed universal DMG.
Open the DMG and launch its installer.
When prompted, authenticate using the administrator account.
Finish Fusion’s first launch while logged into player_two.
Log out and back into player_two; Fusion will then be added to that user’s Dock.

## If setup stops
A Homebrew cask failure stops the bootstrap before later configuration steps.
Fix the reported application problem and rerun the same command. Existing
standard accounts and completed configuration are detected and reused.
