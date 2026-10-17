import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UserNotifications

struct AlarmListView: View {
    @EnvironmentObject private var engine: AlarmEngine
    @StateObject private var weather = WeatherModel()
    @State private var editing: Alarm?
    @State private var showWeather = false
    @State private var pickingPlace = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeatherHeader(weather: weather, openDetail: { showWeather = true }, pickPlace: { pickingPlace = true })
                }
                Section { StreakCard() }
                Section {
                    if let next = engine.nextRing {
                        Text("Rings in \(next, style: .relative)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach($engine.alarms) { $alarm in
                        AlarmRow(alarm: $alarm)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = alarm }
                    }
                    .onDelete { engine.alarms.remove(atOffsets: $0) }
                }
            }
            .refreshable { await weather.refresh() }
            .task { await weather.refresh() }
            .navigationDestination(isPresented: $showWeather) { WeatherDetailView(weather: weather) }
            .sheet(isPresented: $pickingPlace) { PlacePicker(weather: weather) }
            .overlay {
                if engine.alarms.isEmpty {
                    ContentUnavailableView("No alarms", systemImage: "alarm", description: Text("Tap + to add one."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Solid black bar: iOS's default frosted bar turns grey once the list scrolls under it.
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Alarm() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { alarm in
                AlarmEditor(alarm: alarm, isNew: engine.alarm(alarm.id) == nil) { engine.upsert($0) }
            }
            .onChange(of: engine.ringing) { _, ring in
                if ring != nil { editing = nil }   // get the editor out of the way of the ringing screen
            }
        }
    }

}

struct AlarmRow: View {
    @Binding var alarm: Alarm

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString(alarm.hour, alarm.minute))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                HStack(spacing: 6) {
                    Text(daysSummary(alarm.days))
                    if !alarm.label.isEmpty { Text("· \(alarm.label)") }
                    ForEach(alarm.missions) { Image(systemName: $0.kind.icon) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $alarm.enabled).labelsHidden()
        }
        .opacity(alarm.enabled ? 1 : 0.5)
    }
}

/// Calendar weekdays (1 = Sunday) starting from the user's first day of the week.
let weekdayOrder: [Int] = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }

func timeString(_ hour: Int, _ minute: Int) -> String {
    let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
}

func daysSummary(_ days: Set<Int>) -> String {
    switch days {
    case []: return "Once"
    case Set(1...7): return "Every day"
    case [2, 3, 4, 5, 6]: return "Weekdays"
    case [1, 7]: return "Weekends"
    default:
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdayOrder.filter(days.contains).map { symbols[$0 - 1] }.joined(separator: " ")
    }
}

struct AlarmEditor: View {
    @State var alarm: Alarm
    let isNew: Bool
    let onSave: (Alarm) -> Void
    @EnvironmentObject private var engine: AlarmEngine
    @Environment(\.dismiss) private var dismiss
    @State private var registering: Mission?
    @ObservedObject private var library = SoundLibrary.shared
    @State private var importing = false
    @State private var importFailed = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Section("Repeat") { DayPicker(days: $alarm.days) }
                Section { TextField("Label", text: $alarm.label) }
                Section {
                    ForEach($alarm.missions) { $mission in
                        MissionSettings(mission: $mission) { registering = mission }
                    }
                    .onDelete { alarm.missions.remove(atOffsets: $0) }
                    Menu {
                        ForEach(MissionKind.allCases) { kind in
                            Button(kind.title, systemImage: kind.icon) { alarm.missions.append(Mission(kind: kind)) }
                        }
                    } label: {
                        Label("Add mission", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)   // whole row is the button
                            .contentShape(Rectangle())
                    }
                } header: {
                    Text("Wake-up missions")
                } footer: {
                    Text("Missions run in order and must all be done to turn the alarm off. No missions = one tap.")
                }
                Section {
                    Picker("Sound", selection: soundChoice) {
                        ForEach(AlarmSound.allCases) { Text($0.title).tag("builtin:\($0.rawValue)") }
                        ForEach(library.sounds) { Text($0.name).tag("custom:\($0.id.uuidString)") }
                    }
                    .onChange(of: alarm.soundURL) { _, url in engine.audio.preview(url, volume: alarm.volume) }
                    LabeledContent("Volume") {
                        Slider(value: $alarm.volume, in: 0.3...1) { editing in
                            if !editing { engine.audio.preview(alarm.soundURL, volume: alarm.volume) }   // hear it on release
                        }
                    }
                    Button("Preview", systemImage: "play.circle") { engine.audio.preview(alarm.soundURL, volume: alarm.volume) }
                    Button("Import sound from Files…", systemImage: "square.and.arrow.down") { importing = true }
                } header: {
                    Text("Sound")
                } footer: {
                    if importFailed { Text("That file couldn't be used as a sound. Try an MP3, M4A or WAV.").foregroundStyle(.red) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                    guard case .success(let url) = result else { return }
                    if let sound = library.importSound(from: url) {
                        alarm.customSound = sound.id
                        importFailed = false
                    } else {
                        importFailed = true
                    }
                }
                Section("Snooze") {
                    Picker("Snooze", selection: $alarm.snoozeMinutes) {
                        Text("Off").tag(0)
                        ForEach([1, 3, 5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    if alarm.snoozeMinutes > 0 {
                        Picker("Max snoozes", selection: $alarm.maxSnoozes) {
                            ForEach([1, 2, 3, 5, 10], id: \.self) { Text("\($0)").tag($0) }
                            Text("Unlimited").tag(0)
                        }
                    }
                }
                Section {
                    Toggle("Gentle wake-up", isOn: $alarm.gentleRamp)
                    Toggle("Backup loud sound", isOn: $alarm.backupSound)
                    Picker("Wake-up check", selection: $alarm.wakeUpCheckMinutes) {
                        Text("Off").tag(0)
                        ForEach([1, 3, 5, 10, 15], id: \.self) { Text("\($0) min after").tag($0) }
                    }
                    Toggle("Read the time out loud", isOn: $alarm.speakTime)
                    Toggle("Read the label out loud", isOn: $alarm.speakLabel)
                        .disabled(alarm.label.isEmpty)
                } header: {
                    Text("Extras")
                } footer: {
                    Text("Gentle wake-up: volume rises over 30 seconds. Backup loud sound: a full-volume siren if you don't respond within 40 seconds. Wake-up check: asks if you're up after turning it off and rings again if you don't answer within 100 seconds. Reading out loud happens every minute until you start the mission.")
                }
                Section {
                    Button("Save & ring in 5 seconds", systemImage: "bolt.fill") { save(testIn: 5) }
                    Button("Save & ring in 15 seconds (lock your phone)", systemImage: "lock.fill") { save(testIn: 15) }
                    Button("Save & ring in 3 minutes (tests the lock-screen card)", systemImage: "rectangle.on.rectangle") {
                        save(testIn: 180)
                    }
                } header: {
                    Text("Test")
                } footer: {
                    Text("Rings a copy of this alarm with these exact settings: sound, missions and snooze. The real alarm isn't affected. iOS only switches the lock-screen card to \"Wake up!\" if it was last updated over about 2 minutes before ringing, so use the 3-minute test to check the card.")
                }
                .disabled(missingCode)
            }
            .navigationTitle(isNew ? "New alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(missingCode)
                }
            }
            .sheet(item: $registering) { mission in
                if mission.kind == .photo {
                    CameraPicker { photo in
                        PhotoStore.save(photo, for: mission.id)
                        setCode(UUID().uuidString, for: mission)   // marks it registered and refreshes the thumbnail
                    }
                    .ignoresSafeArea()
                } else {
                    RegisterCodeView { code in
                        setCode(code, for: mission)
                        registering = nil
                    }
                }
            }
        }
    }

    /// One picker over built-in ("builtin:beeps") and imported ("custom:<id>") sounds.
    private var soundChoice: Binding<String> {
        Binding {
            alarm.customSound.flatMap(library.sound).map { "custom:\($0.id.uuidString)" }
                ?? "builtin:\(alarm.sound.rawValue)"
        } set: { choice in
            if choice.hasPrefix("custom:") {
                alarm.customSound = UUID(uuidString: String(choice.dropFirst("custom:".count)))
            } else {
                alarm.customSound = nil
                alarm.sound = AlarmSound(rawValue: String(choice.dropFirst("builtin:".count))) ?? .beeps
            }
        }
    }

    /// A scan or photo mission that hasn't had its code / reference photo set up yet.
    private var missingCode: Bool {
        alarm.missions.contains { $0.kind.needsSetup && $0.code.isEmpty }
    }

    private func setCode(_ code: String, for mission: Mission) {
        if let i = alarm.missions.firstIndex(where: { $0.id == mission.id }) { alarm.missions[i].code = code }
    }

    private func save(testIn seconds: Double? = nil) {
        alarm.enabled = true
        onSave(alarm)
        if let seconds { engine.testRing(alarm, in: seconds) }
        dismiss()
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        } set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            alarm.hour = parts.hour ?? 7
            alarm.minute = parts.minute ?? 0
        }
    }
}

struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack {
            ForEach(weekdayOrder, id: \.self) { day in
                let on = days.contains(day)
                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                    .font(.subheadline.bold())
                    .frame(width: 36, height: 36)
                    .background(on ? Color.orange : Color.white.opacity(0.1), in: Circle())
                    .foregroundStyle(on ? Color.black : Color.primary)
                    .onTapGesture { if on { days.remove(day) } else { days.insert(day) } }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var engine: AlarmEngine
    @State private var notificationsOn = true
    @State private var volume = AVAudioSession.sharedInstance().outputVolume
    @State private var cardRefresh = 0
    @AppStorage("emergencyEscape") private var escapeAllowed = true
    @AppStorage("escapeCount") private var escapeUses = 0

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if let icon = UIImage(named: "Icon") {
                        Image(uiImage: icon).resizable().frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rise").font(.title2.bold())
                        Text("Version \(Self.info("CFBundleShortVersionString"))").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Build", value: Self.info("CFBundleVersion"))
                LabeledContent("App ID", value: Bundle.main.bundleIdentifier ?? "?")
                LabeledContent("Made by", value: "HarveyK1")
                LabeledContent("Licence", value: "GPL-3.0")
                Link("What's new", destination: URL(string: "https://github.com/HarveyK1/Rise-Alarm/releases")!)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/HarveyK1/Rise-Alarm")!)
                Button("Copy AltStore source link") {
                    UIPasteboard.general.string = "https://raw.githubusercontent.com/HarveyK1/Rise-Alarm/main/altstore-source.json"
                }
            } header: {
                Text("About")
            } footer: {
                Text("Updates come through AltStore → My Apps. Weather data by Open-Meteo.")
            }

            Section {
                // The date comes from the profile Rise was installed with. An AltStore refresh can renew the
                // signing without changing that copy, so it's a minimum, and once passed, AltStore has refreshed it.
                if let expiry = Provision.expiry {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let left = expiry.timeIntervalSince(context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(left > 0 ? "At least \(remaining(left))" : "Refreshed by AltStore ✓")
                                .font(.title2.bold())
                            if left > 0 {
                                ProgressView(value: max(0, min(left / (7 * 86_400), 1)))
                            }
                        }
                    }
                } else {
                    Text("Can't read the signing date.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Signing")
            } footer: {
                Text("AltStore refreshes Rise automatically while AltServer is running on your PC on the same Wi-Fi. AltStore → My Apps shows exactly how many days are left. If it ever runs out, Rise won't open and alarms won't ring, so refresh it in AltStore.")
            }

            CustomSoundsSection()

            Section {
                Toggle("Emergency escape", isOn: $escapeAllowed)
                if escapeUses > 0 {
                    LabeledContent("Used", value: "\(escapeUses) time\(escapeUses == 1 ? "" : "s")")
                    Button("Reset pledge length") { escapeUses = 0 }
                }
            } header: {
                Text("Missions")
            } footer: {
                Text("Adds an Emergency button to missions: type a pledge to turn the alarm off without the mission. The pledge gets longer each time you use it.")
            }

            Section {
                let _ = cardRefresh   // re-read the status after the retry button
                LabeledContent("Status", value: AlarmActivity.isShowing ? "Showing" : "Not showing")
                if let error = AlarmActivity.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
                Button("Try starting the card now") {
                    engine.retryLockScreen()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { cardRefresh += 1 }
                }
            } header: {
                Text("Lock-screen card")
            } footer: {
                Text("Shows your next alarm on the lock screen and lights up when it rings. Needs an alarm turned on. If it says Not showing, screenshot this and send it over.")
            }

            Section {
                LabeledContent("Notifications", value: notificationsOn ? "On" : "Off: turn on in iPhone Settings")
                LabeledContent("Phone volume", value: "\(Int(volume * 100))%")
                Button("Ring a test alarm in 10 seconds") { engine.testRing(in: 10) }
            } header: {
                Text("Make sure it rings")
            } footer: {
                Text("Rise can only ring while it's running. Leave it open in the background at night (don't swipe it away), keep Low Power Mode off, and open Rise once after restarting your phone. The lock-screen card only starts while Rise is open and iOS ends it after 8 hours, so open Rise before bed. To test: tap the button, lock your phone, wait.")
            }
        }
        .navigationTitle("Settings")
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsOn = settings.authorizationStatus == .authorized
        }
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }

    private func remaining(_ seconds: TimeInterval) -> String {
        let s = Int(seconds), days = s / 86_400, hours = s % 86_400 / 3600
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s") \(hours) h left" }
        return "\(hours) h \(s % 3600 / 60) min left"
    }
}

struct WakeCheckView: View {
    let check: WakeCheck
    @EnvironmentObject private var engine: AlarmEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                Text("Are you up?").font(.largeTitle.bold())
                Text("Tap the button before the timer runs out, or the alarm rings again.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(timerInterval: check.started...check.deadline, countsDown: true)
                    .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                Spacer()
                Button {
                    engine.confirmAwake()
                } label: {
                    Text("Yes, I'm up!").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
    }
}

struct RingingView: View {
    let ring: Ringing
    @EnvironmentObject private var engine: AlarmEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var inMission = false

    var body: some View {
        let alarm = engine.alarm(ring.alarmID)
        let missions = alarm?.missions ?? []
        ZStack {
            Color.black.ignoresSafeArea()
            if inMission {
                MissionRunner(missions: missions, finished: { engine.dismiss() }, escaped: { engine.dismiss(escaped: true) })
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 80, weight: .thin, design: .rounded))
                    }
                    if let label = alarm?.label, !label.isEmpty {
                        Text(label).font(.title2)
                    }
                    Spacer()
                    if engine.canSnooze, let alarm {
                        Button("Snooze \(alarm.snoozeMinutes) min") { engine.snooze() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    Button {
                        if missions.isEmpty {
                            engine.dismiss()
                        } else {
                            inMission = true
                            engine.startMission()
                        }
                    } label: {
                        Text(missions.isEmpty ? "Turn off" : "Start mission").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(32)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if inMission { engine.audio.duck(phase == .active) }
        }
    }
}
