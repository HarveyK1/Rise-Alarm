# Rise: notes for Claude

Personal iPhone alarm app with wake-up missions. Swift/SwiftUI, built on Windows with **WSL Ubuntu + xtool** (compiler only), installed through **AltStore** from this repo's source onto the user's iPhone (iOS 17). App ID `app.risealarm.Rise`. Full background: `docs/HISTORY.md`, `docs/FEATURES.md`, `docs/TECHNICAL-NOTES.md`, `docs/SETUP.md`, `docs/IDEAS.md`. Licence: GPL-3.0.

## Rules
- **The phone gets Rise only through AltStore** (from the source below), as the user chose on 17 Oct 2026. Never install with xtool, Sideloadly or any other tool on the user's Apple ID. A new signing certificate revokes AltStore's and breaks AltStore and every app it installed. Ship updates by publishing a release (see Publishing). xtool only **builds** an unsigned IPA and isn't signed in to any Apple ID.
- Rise is original work: don't copy code, sounds, images or text from other apps, and don't help bypass any app's paywall, IAP or ads.
- Never type the user's passwords (Apple ID, GitHub). Sign-ins are done by the user.
- The user isn't a developer: explain steps plainly, give exact commands, and ask for screenshots when testing.

## Build (run from PowerShell)
- From the repo folder: `wsl -d Ubuntu -u root --cd "$PWD" -- bash -c "tr -d '\r' < Rise/build.sh > /root/build.sh && bash /root/build.sh"` (build.sh uses the working directory, no hardcoded paths).
- Bump `CFBundleShortVersionString` and `CFBundleVersion` (set to the same value) in **both** `Rise/Info.plist` and `Rise/RiseWidget-Info.plist` (they must match).
- After building, check the IPA: both versions match, and `Payload/Rise.app/PlugIns/RiseWidget.appex/RiseWidget` contains `AlarmLiveActivity` (xtool's empty-extension quirk; see TECHNICAL-NOTES).
- PowerShell mangles `$`, `${...}` and nested quotes in `bash -c "..."`; put multi-line or quoted logic in a script file and run that.
- Test pure logic with Swift scripts in WSL: `. /root/.local/share/swiftly/env.sh; swift file.swift`.
- Device logs (debugging only): `idevicesyslog` with `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015` (see SETUP.md).

## Publishing (after every build, the user's standing request)
Public repo **github.com/HarveyK1/Rise-Alarm** (gh account `HarveyK1`; check `gh api user --jq .login` first, since another account is also logged in). Commits use the repo-local noreply email, never a real address.
1. Commit the code + docs (not the source yet) and `git push`, so the release tag points at the new code.
2. Put the release notes in a file (PowerShell breaks quoted multi-line args), then `gh release create v<version> Rise.ipa --title "Rise <version>" --notes-file <file>`.
3. Only then `python update_source.py "what changed"` (reads Rise.ipa and adds the version to `altstore-source.json`; AltStore rejects mismatched versions/permissions, so never edit those by hand), commit it and push. This order means AltStore never sees a version whose IPA isn't uploaded.
4. Verify: the source URL loads, and the downloadURL size matches.
`*.xip`, `*.zip` and `*.ipa` are never committed (.gitignore). **Never publish personal details:** no Apple ID, team ID, emails, device model or IDs, location, Windows username or local folder paths. Commits must use the noreply email (the user's GitHub web edits once leaked their real email). Before pushing, scan for these.

## Code conventions
- Swift 5 language mode, iOS 17 minimum, SwiftUI. Keep changes small and match the surrounding style (short doc comments explaining *why*).
- Saved data must keep decoding across versions: add new properties as optionals or with defaults; unknown `MissionKind` values decode as `.math`.
- Anything that can block an alarm from being dismissed must have a fallback (`MathFallback`).
- iOS limits that shape the design (Live Activity stale-date trick, background-audio keep-alive, no AlarmKit before iOS 26) are in `docs/TECHNICAL-NOTES.md`; read it before touching ringing or the lock-screen card.

## Status
v0.7.3 published (About section; first AltStore update on the new app ID). Round 3 extras, custom sounds and stats are not yet confirmed on device. Backlog in `docs/IDEAS.md`. When versions change, update `docs/HISTORY.md` and `docs/FEATURES.md`.
