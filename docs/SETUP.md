# Setup: rebuild everything from scratch

The current machine already has all of this. Use this guide on a new PC or if something breaks.

## 1. WSL + Ubuntu (Windows)
1. Admin PowerShell: `winget install --id Microsoft.WSL -e --source winget`
2. Restart Windows if asked (the Virtual Machine Platform feature).
3. Normal PowerShell (puts Ubuntu on F: because C: was short on space):
   `wsl --install -d Ubuntu --no-launch` (add `--location <folder>` to put it on a drive with more space)
4. Run everything as root so no Linux password is needed: `wsl -d Ubuntu -u root -- <command>`
5. Remove Ubuntu completely with `wsl --unregister Ubuntu` if ever needed.

## 2. Swift + xtool (inside Ubuntu, as root)
```bash
apt-get update && apt-get install -y curl ca-certificates gnupg rsync unzip zip libimobiledevice-utils
cd /root && curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
tar zxf "swiftly-$(uname -m).tar.gz" && ./swiftly init --quiet-shell-followup --assume-yes
# swiftly prints a list of system packages; at the time it was:
apt-get -y install binutils-gold gnupg2 libc6-dev libcurl4-openssl-dev libgcc-15-dev libpython3-dev \
  libstdc++-15-dev libxml2-dev libncurses-dev libz3-dev pkg-config zlib1g-dev
. /root/.local/share/swiftly/env.sh && swift --version   # 6.4.1
mkdir -p /opt/xtool && cd /opt/xtool
curl -fsSL -o xtool.AppImage "https://github.com/xtool-org/xtool/releases/download/1.22.2/xtool-$(uname -m).AppImage"
chmod +x xtool.AppImage && ./xtool.AppImage --appimage-extract >/dev/null
ln -sf /opt/xtool/squashfs-root/AppRun /usr/local/bin/xtool
```

## 3. iOS SDK from Xcode
1. Download Xcode (27.1 was used) from developer.apple.com/download/all with a **free** Apple developer account. Don't pay for the Developer Program.
2. Copy the xip into Ubuntu and install the SDK (takes 10–20 min):
```bash
mkdir -p /root/xcode && cp "/mnt/c/path/to/Xcode_27.1.xip" /root/xcode/
xtool sdk install /root/xcode/Xcode_27.1.xip
xtool sdk status
```

## 4. Build and publish
- Build with the command in README.md. It makes an **unsigned** `Rise.ipa` and needs **no Apple ID** (xtool is only used as the compiler).
- Publishing needs the GitHub CLI signed in as **HarveyK1** (`gh auth status`; switch with `gh auth switch`). The steps are in README.md "Making a new version".

## 5. Installing on the phone: AltStore only
- AltServer on the PC installs AltStore on the phone (with the Apple ID; you type it into AltServer).
- In AltStore: Sources → + → the source URL from README.md → install Rise. Updates appear in My Apps.
- Auto-refresh needs AltServer running, the phone on the same Wi-Fi, Wi-Fi sync on for the phone in iTunes, and Background App Refresh on for AltStore.
- **Don't use any other sideloading tool with the same Apple ID** (xtool install, Sideloadly, AltServer's "Sideload .ipa"). A free Apple ID effectively has one sideloading certificate at a time, so a new one revokes AltStore's and every app it installed stops opening.

## 6. Optional: reading the phone's logs (debugging)
Useful for iOS-level problems. It's how the lock-screen card issues were found. No Apple ID involved.
- Windows needs iTunes / Apple Mobile Device Service (comes with AltServer/iTunes). It listens on `127.0.0.1:27015`.
- `%USERPROFILE%\.wslconfig` contains `[wsl2]` / `networkingMode=mirrored` (then `wsl --shutdown`), so Ubuntu can reach it.
- With the phone plugged in and unlocked:
  `wsl -d Ubuntu -u root -- bash -c 'export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015; idevicesyslog --no-colors -K -q > /root/phone.log'`
  then grep it for `Rise`, `liveactivitiesd`, `chronod`.

## Troubleshooting
- **PowerShell mangles `$` or nested quotes** inside `wsl ... bash -c "..."`. Put the commands in a `.sh` file and run that, or use single quotes. For gh release notes, use `--notes-file`.
- **`$'\r': command not found`**: the script has Windows line endings. The `tr -d '\r'` in the README command handles it.
- **AltStore says the app's permissions or version don't match the source**: regenerate the entry with `update_source.py` from the exact IPA that was uploaded.
- **Swift test scripts** run with `. /root/.local/share/swiftly/env.sh; swift file.swift`. Used to check JSON decoding and streak logic.
