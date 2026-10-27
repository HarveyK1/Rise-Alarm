# Ideas, backlog and limitations

## To check next
- Test the **round 3 extras** on the phone: gentle wake-up, backup loud sound, wake-up check (try "1 min after"), talking alarm, emergency escape.
- Test **custom sound import** and the **stats/streak** card (0.7.0).
- Photo match: if matching feels too strict or loose, note the scores shown and tune the 18/15/12 thresholds.
- **AltStore app IDs and HTTP 503 (researched 17 Oct 2026):**
  - **Limit:** a free Apple ID can register 10 app IDs per 7 days. Each ID expires 7 days after it's made and stops counting. AltStore → My Apps → View App IDs shows each one and its expiry date. Hitting the limit gives its own error ("cannot register more than 10 App IDs within a 7 day period", AltStore error 1009), not a 503.
  - **Rise uses 2 IDs:** the app plus the lock-screen card extension.
  - **Updates don't make new IDs:** AltStore reuses the existing ID for an app it already has (its `FetchProvisioningProfilesOperation`). The IDs used up on 16–17 Oct came from one-offs: direct installs, the old app ID, and the new `app.risealarm.Rise` in 0.7.2. Don't change the app ID again.
  - **Can't remove or reset them:** they live on Apple's servers. SideStore has a Delete button, but warns that on a free account deleting doesn't free a slot.
  - **SideStore** (AltStore fork, AGPL-3.0) has two things AltStore doesn't. A custom app ID box on install lets you reuse an unexpired ID you already have (Sideloadly also lets you set a custom ID). Its "Use Main Profile" option signs extensions with the main app's ID, so Rise would need 1 ID; untested whether the lock-screen card still works that way. It also refreshes on the phone with no PC (LocalDevVPN; one-time PC setup with iTunes and iloader). Switching means moving over fully, because two tools on one Apple ID revoke each other.
  - **HTTP 503 cause:** in Sept 2026 Apple started rejecting sign-ins from tools that identify as Xcode, which broke AltStore, SideStore and iLoader. AltServer for Mac 1.7.6 fixed it. No confirmed fix found for AltServer on Windows (check for updates in its tray menu). SideStore's fix is only in 0.7.0-alpha; 0.6.4 and older can't sign in. Avoid unofficial "patched AltServer" builds, since they handle the Apple ID password.
  - **Decision:** stay on AltStore. Look at SideStore again once a non-alpha version with the sign-in fix is out.

## Suggested, not picked yet
1. **Bedtime reminder ("arm for tonight")**: a nightly notification; opening Rise restarts the 8-hour lock-screen card and re-arms after a phone restart. *(Small; most useful for reliability.)*
2. **"Ready for tonight?" check** on the home screen: warns if notifications are off, Low Power Mode is on, or the card isn't showing. *(Small.)*
3. **Good-morning screen** after the mission: weather, rain chance, calendar events, streak. *(Medium.)*
4. ~~Wake-up stats & streak~~: **done in 0.7.0**.
5. ~~Custom sounds~~: **done in 0.7.0** (import from Files). You can also hand over audio files to be built into the app.
6. **Skip next / quick nap**: "skip tomorrow only" for repeating alarms; "ring in 20 minutes". *(Small.)*
7. **Home-screen widget**: next alarm + weather (the widget extension already exists). *(Small–medium.)*

## Rejected / not possible
- **Steps and Squats missions**: built in 0.5.0, removed in 0.6.1 (didn't work, not wanted).
- **Siri / Shortcuts / interactive lock-screen buttons**: need App Intents metadata that xtool can't generate.
- **Prevent uninstall / prevent power-off**: need Apple-granted Screen Time permissions.
- **Full-screen lock-screen alarm**: AlarmKit is iOS 26+ only.
- **Sleep tracking through the mic**: heavy on battery, low accuracy.
- **Using iOS's own ringtones**: Apple doesn't let other apps use them; Rise generates its own and imports yours.

## Known limitations
- Rise must be running to ring properly: open it after a restart, don't swipe it away, avoid Low Power Mode. Backup notifications cover the worst case, but they're short.
- The lock-screen card needs Rise opened within 8 hours of the alarm, and switches to "Wake up!" only if the alarm was set more than about 2 minutes before ringing.
- Card buttons open the app (unlock needed); they can't act from the lock screen.
- Free Apple ID signing lasts 7 days. AltStore refreshes it automatically only while AltServer is running on the PC on the same Wi-Fi; if it lapses, refresh in AltStore.
