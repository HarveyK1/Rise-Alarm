# History: how Rise came to be

A written record of how Rise was built (16–17 Oct 2026), so nothing is lost if the original chat is.

---

## Part 1: building an iPhone app on Windows with no Mac

Rise started as a personal alarm app: an alarm you have to get up to turn off, with wake-up missions, written from scratch.

- **Why xtool:** it builds iOS apps on Linux/WSL from a SwiftPM project with no Mac, and `xtool dev build --ipa` makes an unsigned IPA.
- **Xcode:** a free Apple developer account was used to download `Xcode_27.1.xip`. xtool only takes Apple's iOS SDK from it.
- **Toolchain:** Swift 6.4.1 through swiftly (it needed extra apt packages, starting with libncurses), xtool 1.22.2 extracted to `/opt/xtool`, and the iOS 27.1 SDK built from the xip.
- **App name:** "Rise". Bundle id `app.risealarm.Rise` (since 0.7.2).

## Part 2: versions

| Version | What changed | Notes |
|---|---|---|
| 0.1.0 | Round 1: alarms, repeat days, labels, 5 generated sounds, snooze + max snoozes, volume, Math/Shake/Scan missions, ringing screen, signing timer, "test in 10 s" | Compiled first try and confirmed ringing on device; Math worked |
| 0.2.0 | Lock-screen **Live Activity** (widget extension); per-alarm "Save & ring in 5 / 15 seconds" test buttons | The card didn't appear (see the fix below) |
| 0.3.0 | Solid black ringing screen; **Shake fills the screen** as you shake; duplicate lock-screen notification removed; **weather** header (Open-Meteo); card status/error in Settings | Shake and the test buttons confirmed |
| 0.3.1 | Weather fix (`temperature_2m` decoding bug); title removed | |
| (fix) | Signing failed with "Can't find free space of LoadCommands" | Cause: **the widget extension was being shipped empty** (xtool stub + `_NSExtensionMain`). Fixed with a linker flag, which also fixed the missing card |
| 0.4.0 | Weather redesign: place ›, big temperature, high/low, 12-hour row; detail page (feels like, air quality gauge, wind, humidity, hourly rain %); "Use my current location" or search | |
| 0.4.1 | Weather in its own card | |
| 0.4.2 | **Volume lock**: the volume buttons can't turn a ringing alarm down | Confirmed working with the phone locked too |
| 0.4.3 | Card should switch to "Wake up!" using a **stale date** | Phone logs showed iOS forbids Live Activity updates from background-audio apps |
| 0.4.4 | Bug: the app ended the card when it went stale | **Confirmed:** card switches to "Wake up! / Snooze / Stop" |
| 0.4.5 | No extra "Tap to turn it off" notification when the card is showing | |
| 0.5.0 | Round 2: Memory tiles, Typing, Tap challenge, Steps, Squats, Photo match, Say the word; "Save & ring in 3 minutes" test (needed to see the card switch) | Memory, Typing, Tap, Photo and Speech confirmed |
| 0.5.1 | Typing phrases never repeat (15+ per length); **app icon** (sunrise) | Icon confirmed |
| 0.5.2 | Preview plays at the alarm's volume (sets the phone volume, then restores it) | Confirmed |
| 0.6.0 | Round 3: gentle wake-up, backup loud sound, wake-up check, talking alarm, emergency escape | Not yet confirmed on device |
| 0.6.1 | **Steps and Squats removed** (didn't work, not wanted); the whole "Add mission" row is tappable | Old saved ones load as maths |
| 0.6.2 | Solid black top bar (no grey frosted bar when scrolling) | Confirmed |
| 0.7.0 | **Custom sounds** (import from Files) + **wake-up stats & streak** | Not yet confirmed |
| 0.7.1 | AltStore-only: the Settings "Signing" section ("at least X days left", then "Refreshed by AltStore ✓"); false re-sign reminders removed | First update delivered through the AltStore source |
| 0.7.2 | New neutral app ID `app.risealarm.Rise` (no personal details anywhere in the project) | A new app to AltStore: install it from the source, delete the old one, set alarms up again |

## Part 3: how it gets to the phone

- Early builds were sideloaded directly, then installed straight over USB with xtool.
- On a free Apple ID only one sideloading tool can sign at a time (each new certificate revokes the previous one), so on 17 Oct 2026 everything moved to **AltStore + this repo's AltStore source**: auto-refresh every 7 days, and new versions appear as updates. **Confirmed working.**
- xtool is now only the build tool, signed out of any Apple ID, with its saved login data deleted.
- **Published 17 Oct 2026:** public repo [HarveyK1/Rise-Alarm](https://github.com/HarveyK1/Rise-Alarm) with a release per version and `altstore-source.json` (generated from each IPA by `update_source.py`). Licensed under **GPL-3.0**.

## Decisions worth remembering

- Rise is original work: no code, sounds or art from other apps, and no help bypassing any app's paywall.
- **AltStore is the only install method**; no direct installs with other tools.
- Steps and Squats were removed because they didn't work and weren't wanted.
- The extra notification under the lock-screen card was removed (the card is enough).
