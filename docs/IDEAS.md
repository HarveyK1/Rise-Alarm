# Ideas, backlog and limitations

## To check next
- Test the **round 3 extras** on the phone: gentle wake-up, backup loud sound, wake-up check (try "1 min after"), talking alarm, emergency escape.
- Test **custom sound import** and the **stats/streak** card (0.7.0).
- Photo match: if matching feels too strict or loose, note the scores shown and tune the 18/15/12 thresholds.

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
