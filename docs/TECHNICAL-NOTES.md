# Technical notes

## File map (`Rise/Sources/`)
| File | What's in it |
|---|---|
| `Rise/RiseApp.swift` | App entry, AppDelegate (notifications), **model** (`Alarm`, `Mission`, `MissionKind`, `Ringing`, `WakeCheck`), **AlarmEngine** (scheduling, ringing, snooze, wake-up check, extras timers, notifications, lock-screen card updates), `Provision` (installed profile expiry), `AlarmActivity` (Live Activity start/update) |
| `Rise/Audio.swift` | `AlarmAudio` (silent keep-alive loop, ringing, ramp, backup siren, speech, ducking, mic mode, volume lock, preview), `SystemVolume` (MPVolumeView trick), `AlarmSound` (generated sounds), `SoundFiles` (WAV writer) |
| `Rise/Views.swift` | Alarm list, editor (missions, sound, snooze, extras, test buttons), Settings, WakeCheckView, RingingView |
| `Rise/Missions.swift` | MissionRunner (+ Emergency button), EmergencyEscape, MathFallback, per-mission settings rows, Math, Shake, Scan (+ camera scanner) |
| `Rise/MoreMissions.swift` | Memory, Typing, Tap, Photo match (+ PhotoStore, CameraPicker), Say the word (+ SpeechListener), `normalizedWords` |
| `Rise/Weather.swift` | Open-Meteo forecast + air quality + geocoding, LocationFetcher, header, detail page, place picker |
| `Rise/CustomSounds.swift` | SoundLibrary (import, CAF notification copy, delete), `Alarm.soundURL` / `notificationSoundName` |
| `Rise/Stats.swift` | WakeRecord, WakeStats (streaks), StreakCard, StatsView (Swift Charts) |
| `RiseShared/AlarmActivityAttributes.swift` | Live Activity data shared by app and widget |
| `RiseWidget/RiseWidget.swift` | Lock-screen card + Dynamic Island layouts |

Saved data (UserDefaults): `alarms`, `weatherPlace`, `customSounds`, `wakeRecords`, `emergencyEscape`, `escapeCount`. Files: Library/Sounds (generated WAVs, custom CAF copies), Application Support (custom sound originals, reference photos).

## How ringing works (iOS 17 has no alarm API for apps)
- **AlarmKit** (a real system alarm UI, full-screen lock-screen alarms) is **iOS 26+ only**. Before that, alarm apps keep themselves running with silent background audio, and that's what Rise does.
- While any alarm, snooze or wake-up check is pending, Rise plays a **silent loop** with background audio, so iOS keeps it running. A 1-second timer checks what's due.
- At alarm time: audio session switches to non-mixable `.playback` (plays on silent), the sound loops, the phone volume is set via a hidden `MPVolumeView` slider, and KVO on `outputVolume` pushes it back up if lowered (volume lock).
- **Backup:** each upcoming alarm also has 10 scheduled notifications (30 s apart) with its sound (a ≤ 30 s WAV/CAF in Library/Sounds), in case iOS killed the app. They're removed when the app rings itself. Tapping one opens Rise and rings properly (mission included).
- Limit: Rise must be running. Open it once after a phone restart; don't swipe it away; Low Power Mode may interfere.
- iOS allows at most 64 pending notifications: 6 alarms × 10 + the wake-up check.

## Lock-screen card (Live Activity): hard-won rules
1. An app can only **start** a Live Activity while it's open on screen, and iOS ends it after **8 hours**.
2. iOS **refuses updates from an app that's only alive because of background audio**. The phone log said: `Process is only playing background media so is forbidden to update activity`. So the app can't flip the card to "ringing" at alarm time.
3. Workaround: when the card is updated (in the foreground), its **stale date = alarm time**. iOS re-renders it as `isStale` at that time, and the widget draws "Wake up!" for stale cards.
4. iOS only marks it stale if the last update was **at least about 2 minutes** earlier. That's why the 15 s test never shows it and the 3-minute test does.
5. The app must treat `.stale` as a current activity. 0.4.3 ended it by mistake.
6. Buttons on the card are `rise://snooze` / `rise://open` **links** (they open the app). Interactive no-unlock buttons need App Intents metadata, which xtool doesn't generate.

## xtool quirks
- **Extensions ship empty:** xtool links each extension from an empty `stub.c` with `-e _NSExtensionMain`, so the widget target's code was never linked. That caused (a) no card and (b) zsign failing with *"Can't find free space of LoadCommands for CodeSignature"* (zsign measures from `__text`, which didn't exist). Fix in `Package.swift`: `linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]` on RiseWidget. After changes, check the appex contains `AlarmLiveActivity`.
- Extension `CFBundleShortVersionString` must match the app's.
- `iconPath` sets `CFBundleIconFile`; `CFBundleIcons/CFBundlePrimaryIcon/CFBundleIconFiles = [Icon]` was added in Info.plist as well.
- No App Intents metadata step, so no interactive widget buttons and no Siri/Shortcuts actions.

## Other gotchas
- **JSON:** `.convertFromSnakeCase` turns `temperature_2m` into `temperature2M` (capital M), so decoding silently failed ("Weather unavailable"). Use explicit `CodingKeys`.
- **Removed enum cases** would break decoding of every saved alarm. `MissionKind.init(from:)` maps unknown kinds (steps, squats) to `.math`, and the engine caps converted counts at 10.
- `Text(timerInterval: Date()...end)` crashes if redrawn after `end`; use a fixed start date.
- Apple WeatherKit needs a paid account, so the app uses **Open-Meteo** (free, no key; attribution shown).
- Photo match uses Vision feature prints (revision 1). Thresholds 18/15/12 are guesses; the failure message shows the score so they can be tuned.
- Say the word switches the audio session to `.playAndRecord` with `.defaultToSpeaker` and mutes the alarm while listening.
- Notification sounds must be ≤ 30 s Linear PCM (WAV/CAF/AIFF); imported MP3s get a 29 s CAF copy made on import.

## Device facts
- Requires iOS 17.
- Installed only through AltStore (free Apple ID, 7-day signing that AltStore refreshes). The IPA is built unsigned. The in-app "Signing" date comes from the profile Rise was installed with, so after an AltStore refresh it's only a minimum.

## Saved data and restarts (0.7.4)
After a restart iOS can launch Rise in the background before the first unlock (prewarming, background audio). Saved data (UserDefaults) is locked until then and reads as empty, and saving that empty state wiped the alarms and weather place. `whenDataReadable` (RiseApp.swift) delays loading until `isProtectedDataAvailable`, and each store (`AlarmEngine`, `WakeStats`, `SoundLibrary`) refuses to save or reschedule until it has loaded. Anything new that reads UserDefaults at launch must go through it too.
