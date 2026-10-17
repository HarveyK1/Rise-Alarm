import ActivityKit
import RiseShared
import SwiftUI
import UIKit
import UserNotifications

@main
struct RiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = AlarmEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // An overlay rather than fullScreenCover: a cover can't appear while the editor sheet is up.
            ZStack {
                AlarmListView()
                if let check = engine.wakeCheck {
                    WakeCheckView(check: check)
                        .transition(.opacity)
                        .zIndex(1)
                }
                if let ring = engine.ringing {
                    RingingView(ring: ring)
                        .id(ring.id)
                        .transition(.move(edge: .bottom))
                        .zIndex(2)
                }
            }
            .animation(.easeInOut, value: engine.ringing)
            .animation(.easeInOut, value: engine.wakeCheck)
            .environmentObject(engine)
            .tint(.orange)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                // Links from the lock-screen card. "rise://open" needs nothing: the ringing screen is already up.
                if url.host == "snooze" { engine.snooze() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.appBecameActive() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AlarmEngine.shared.start()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // Tapping an alarm notification starts that alarm's mission, even if iOS killed the app overnight.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let note = response.notification
        guard let raw = note.request.content.userInfo["alarmID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { AlarmEngine.shared.openedFromNotification(id, firedAt: note.date) }
    }
}

// MARK: - Model

enum MissionKind: String, Codable, CaseIterable, Identifiable {
    case math, shake, scan, memory, typing, tap, photo, speak

    var id: String { rawValue }

    /// Kinds that no longer exist (steps, squats) load as maths instead of breaking every saved alarm.
    init(from decoder: Decoder) throws {
        self = MissionKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .math
    }

    var title: String {
        switch self {
        case .math: "Math"
        case .shake: "Shake"
        case .scan: "Scan a code"
        case .memory: "Memory tiles"
        case .typing: "Typing"
        case .tap: "Tap challenge"
        case .photo: "Photo match"
        case .speak: "Say the word"
        }
    }

    var icon: String {
        switch self {
        case .math: "function"
        case .shake: "iphone.radiowaves.left.and.right"
        case .scan: "qrcode.viewfinder"
        case .memory: "square.grid.3x3.fill"
        case .typing: "keyboard"
        case .tap: "hand.tap.fill"
        case .photo: "camera.viewfinder"
        case .speak: "waveform"
        }
    }

    /// Needs something registered in the editor first (a code or a reference photo), stored in `Mission.code`.
    var needsSetup: Bool { self == .scan || self == .photo }
}

struct Mission: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: MissionKind
    var count: Int
    var difficulty = 1
    var codeName = ""   // scan/photo: what the user calls the spot
    var code = ""       // scan: the code's contents; photo: changes on each new reference photo

    init(kind: MissionKind) {
        self.kind = kind
        count = switch kind {
        case .math, .memory, .typing: 3
        case .shake: 20
        case .scan, .photo: 1
        case .tap: 40
        case .speak: 5
        }
    }
}

struct Alarm: Codable, Identifiable, Equatable {
    var id = UUID()
    var hour = 7
    var minute = 0
    var days: Set<Int> = []         // Calendar weekdays, 1 = Sunday. Empty = rings once.
    var label = ""
    var enabled = true
    var missions: [Mission] = []
    var sound: AlarmSound = .beeps
    var volume = 1.0                // phone volume the alarm forces, 0...1
    var snoozeMinutes = 5           // 0 = no snooze
    var maxSnoozes = 3              // 0 = unlimited
    // Round 3 extras. Stored already so saved alarms keep decoding when their settings land.
    var gentleRamp = false
    var backupSound = false
    var wakeUpCheckMinutes = 0      // 0 = off
    var speakTime = false
    var speakLabel = false
    var customSound: UUID?          // an imported sound; overrides `sound` while it exists
}

/// "Are you up?" shown a few minutes after dismissing; ignore it for 100 s and the alarm rings again.
struct WakeCheck: Identifiable, Equatable {
    let id = UUID()
    let alarmID: UUID
    let started: Date
    var deadline: Date { started.addingTimeInterval(100) }
}

struct Ringing: Identifiable, Equatable {
    let id = UUID()
    let started = Date()
    let alarmID: UUID
    let snoozes: Int
}

enum Provision {
    /// Expiry of the profile Rise was installed with (AltStore can renew signing without changing it); nil if unreadable.
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()
}

// MARK: - Engine

@MainActor
final class AlarmEngine: ObservableObject {
    static let shared = AlarmEngine()

    @Published var alarms: [Alarm] = [] { didSet { save(); reschedule() } }
    @Published private(set) var ringing: Ringing?
    @Published private(set) var nextRing: Date?
    @Published private(set) var wakeCheck: WakeCheck?

    let audio = AlarmAudio()
    private var nextFire: [UUID: Date] = [:]
    private var snoozed: [UUID: (date: Date, count: Int)] = [:]
    private var pendingCheck: (alarmID: UUID, at: Date)?
    private var firstRang: [UUID: Date] = [:]   // when each alarm first rang this morning (before any snoozes)
    private var testAlarm: Alarm?
    private var tick: Timer?
    private var backupTimer: Timer?
    private var talkTimer: Timer?
    private let center = UNUserNotificationCenter.current()

    private init() {
        guard let data = UserDefaults.standard.data(forKey: "alarms") else { return }
        if var saved = try? JSONDecoder().decode([Alarm].self, from: data) {
            // A removed mission (e.g. 30 steps) loads as maths; keep it within maths' normal 1...10.
            for a in saved.indices {
                for m in saved[a].missions.indices where saved[a].missions[m].kind == .math {
                    saved[a].missions[m].count = min(saved[a].missions[m].count, 10)
                }
            }
            alarms = saved
        } else {
            // Keep unreadable data instead of overwriting it on the next save.
            UserDefaults.standard.set(data, forKey: "alarms.unreadable")
        }
    }

    func start() {
        SoundFiles.generate()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
        reschedule()
    }

    func retryLockScreen() {
        AlarmActivity.forget()
        reschedule()
    }

    func appBecameActive() {
        checkDue()
        reschedule()
        audio.restartIfNeeded()
    }

    func openedFromNotification(_ id: UUID, firedAt: Date) {
        // Only rings if the app missed this alarm (e.g. iOS killed it overnight) and it's recent.
        guard ringing == nil, Date().timeIntervalSince(firedAt) < 30 * 60, alarm(id) != nil else { return }
        fire(id, snoozes: 0)
    }

    func alarm(_ id: UUID) -> Alarm? {
        alarms.first { $0.id == id } ?? (testAlarm?.id == id ? testAlarm : nil)
    }

    var canSnooze: Bool {
        guard let r = ringing, let a = alarm(r.alarmID), a.snoozeMinutes > 0 else { return false }
        return a.maxSnoozes == 0 || r.snoozes < a.maxSnoozes
    }

    func upsert(_ alarm: Alarm) {
        var list = alarms
        if let i = list.firstIndex(where: { $0.id == alarm.id }) { list[i] = alarm } else { list.append(alarm) }
        list.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        alarms = list
    }

    func snooze() {
        guard canSnooze, let r = ringing, let a = alarm(r.alarmID) else { return }
        snoozed[r.alarmID] = (Date().addingTimeInterval(Double(a.snoozeMinutes) * 60), r.snoozes + 1)
        stop()
    }

    func dismiss(escaped: Bool = false) {
        guard let r = ringing else { return }
        snoozed[r.alarmID] = nil
        if r.alarmID != testAlarm?.id {   // test alarms don't count towards stats
            WakeStats.shared.add(rang: firstRang[r.alarmID] ?? r.started, snoozes: r.snoozes, escaped: escaped)
        }
        firstRang[r.alarmID] = nil
        let checkMinutes = alarm(r.alarmID)?.wakeUpCheckMinutes ?? 0
        if checkMinutes > 0 {
            pendingCheck = (r.alarmID, Date().addingTimeInterval(Double(checkMinutes) * 60))
        } else if r.alarmID == testAlarm?.id {
            testAlarm = nil   // kept until its wake-up check is done otherwise
        }
        stop()
    }

    /// The mission has started: no backup siren or talking while it's being done.
    func startMission() {
        stopExtras()
        audio.duck(true)
    }

    /// "Yes, I'm up!" on the wake-up check.
    func confirmAwake() {
        guard let check = wakeCheck else { return }
        wakeCheck = nil
        if check.alarmID == testAlarm?.id { testAlarm = nil }
        center.removeAllDeliveredNotifications()
        reschedule()
    }

    /// Rings a copy of `alarm` (sound, missions, snooze and all) after `seconds`, without touching the real one.
    func testRing(_ alarm: Alarm = Alarm(snoozeMinutes: 0), in seconds: Double) {
        var test = alarm
        test.id = UUID()
        test.label = alarm.label.isEmpty ? "Test alarm" : "Test: \(alarm.label)"
        testAlarm = test
        snoozed[test.id] = (Date().addingTimeInterval(seconds), 0)
        reschedule()
    }

    private func stop() {
        stopExtras()
        audio.stopRinging()
        ringing = nil
        center.removeAllDeliveredNotifications()
        reschedule()
    }

    private func stopExtras() {
        backupTimer?.invalidate()
        backupTimer = nil
        talkTimer?.invalidate()
        talkTimer = nil
    }

    private func checkDue() {
        guard ringing == nil else { return }
        let now = Date()
        if let check = wakeCheck, now >= check.deadline {
            wakeCheck = nil
            if check.alarmID != testAlarm?.id { WakeStats.shared.markLastCheckFailed() }
            fire(check.alarmID, snoozes: 0)   // missed the wake-up check: ring again, mission and all
            return
        }
        if wakeCheck == nil, let pending = pendingCheck, pending.at <= now {
            pendingCheck = nil
            wakeCheck = WakeCheck(alarmID: pending.alarmID, started: now)
            reschedule()
            return
        }
        if let due = snoozed.first(where: { $0.value.date <= now }) {
            fire(due.key, snoozes: due.value.count)
        } else if let id = nextFire.first(where: { $0.value <= now })?.key {
            fire(id, snoozes: 0)
        }
    }

    private func fire(_ id: UUID, snoozes: Int) {
        nextFire[id] = nil
        snoozed[id] = nil
        ring(id, snoozes: snoozes)
        if snoozes == 0, let i = alarms.firstIndex(where: { $0.id == id }), alarms[i].days.isEmpty, alarms[i].enabled {
            alarms[i].enabled = false   // one-time alarm; didSet reschedules
        } else {
            reschedule()
        }
    }

    private func ring(_ id: UUID, snoozes: Int) {
        guard let a = alarm(id) else { return }
        ringing = Ringing(alarmID: id, snoozes: snoozes)
        if snoozes == 0 { firstRang[id] = Date() }
        audio.startRinging(a.soundURL, volume: a.volume, ramp: a.gentleRamp)
        startExtras(for: a)
        // The app is ringing it now: drop the backup burst, including one that may have just landed.
        let burst = (0..<10).map { "\(id)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: burst)
        center.removeDeliveredNotifications(withIdentifiers: burst)
        // The lock-screen card already says "Wake up!" with Snooze/Stop; only notify when it isn't there
        // (iOS ended it after 8 hours, or Live Activities are off).
        guard UIApplication.shared.applicationState != .active, !AlarmActivity.isShowing else { return }
        let content = UNMutableNotificationContent()
        content.title = a.label.isEmpty ? "Alarm" : a.label
        content.body = "Tap to turn it off"
        content.userInfo = ["alarmID": id.uuidString]
        center.add(UNNotificationRequest(identifier: "ringing", content: content, trigger: nil))
    }

    /// Backup loud sound after 40 s of no response, and the talking alarm every minute.
    private func startExtras(for a: Alarm) {
        stopExtras()
        if a.backupSound {
            backupTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.audio.escalate() }
            }
        }
        guard a.speakTime || (a.speakLabel && !a.label.isEmpty) else { return }
        let label = a.speakLabel && !a.label.isEmpty ? [a.label] : []
        let say: @MainActor () -> Void = { [weak self] in
            let time = a.speakTime ? ["It's \(Date().formatted(date: .omitted, time: .shortened))"] : []
            self?.audio.speak((label + time).joined(separator: ". "))
        }
        talkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in MainActor.assumeIsolated { say() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.talkTimer != nil { say() }   // first time shortly after it starts ringing
        }
    }

    private func reschedule() {
        let now = Date()
        var fresh: [UUID: Date] = [:]
        for a in alarms where a.enabled {
            if let old = nextFire[a.id], old <= now {
                fresh[a.id] = old   // due, waiting behind an alarm that's still ringing
            } else if let next = nextDate(for: a, after: now) {
                fresh[a.id] = next
            }
        }
        nextFire = fresh
        let upcoming = (nextFire.map { ($0.key, $0.value) } + snoozed.map { ($0.key, $0.value.date) })
            .sorted { $0.1 < $1.1 }
        nextRing = upcoming.first?.1
        audio.setKeepAlive(!upcoming.isEmpty || ringing != nil || pendingCheck != nil || wakeCheck != nil)
        scheduleNotifications(upcoming)
        updateLockScreen(next: upcoming.first)
    }

    /// Lock-screen card: the ringing alarm if there is one, else the next alarm, else nothing.
    private func updateLockScreen(next: (UUID, Date)?) {
        if let r = ringing, let a = alarm(r.alarmID) {
            AlarmActivity.show(.init(alarmTime: r.started, label: a.label, ringing: true,
                                     snoozeMinutes: canSnooze ? a.snoozeMinutes : 0))
        } else if let next, let a = alarm(next.0) {
            // Worked out now: iOS won't let the app update the card once it's ringing in the background.
            let used = snoozed[next.0]?.count ?? 0
            let canSnoozeThen = a.snoozeMinutes > 0 && (a.maxSnoozes == 0 || used < a.maxSnoozes)
            AlarmActivity.show(.init(alarmTime: next.1, label: a.label, ringing: false,
                                     snoozeMinutes: canSnoozeThen ? a.snoozeMinutes : 0))
        } else {
            AlarmActivity.show(nil)
        }
    }

    private func nextDate(for a: Alarm, after now: Date) -> Date? {
        let cal = Calendar.current
        let base = DateComponents(hour: a.hour, minute: a.minute, second: 0)
        if a.days.isEmpty { return cal.nextDate(after: now, matching: base, matchingPolicy: .nextTime) }
        return a.days.compactMap { day -> Date? in
            var c = base
            c.weekday = day
            return cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
        }.min()
    }

    /// Backup in case iOS kills the app overnight: a burst of 10 notifications, 30 s apart, per alarm.
    private func scheduleNotifications(_ upcoming: [(UUID, Date)]) {
        center.removeAllPendingNotificationRequests()
        // iOS keeps at most 64 pending: 6 alarms x 10, plus the wake-up check.
        for (id, date) in upcoming.prefix(6) {
            guard let a = alarm(id) else { continue }
            for i in 0..<10 {
                let at = date.addingTimeInterval(Double(i) * 30)
                guard at > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = a.label.isEmpty ? "Alarm" : a.label
                content.body = "Open Rise to turn off your alarm"
                content.sound = UNNotificationSound(named: UNNotificationSoundName(a.notificationSoundName))
                content.userInfo = ["alarmID": id.uuidString]
                center.add(UNNotificationRequest(identifier: "\(id)-\(i)", content: content, trigger: trigger(at)))
            }
        }
        if let check = pendingCheck, check.at > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Wake-up check"
            content.body = "Still up? Open Rise and tap \"Yes, I'm up!\" within 100 seconds, or the alarm rings again."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "wakecheck", content: content, trigger: trigger(check.at)))
        }
        // No re-sign reminders: AltStore refreshes Rise itself, and the installed profile date can't see that.
    }

    private func trigger(_ date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: "alarms")
        }
    }
}

/// The lock-screen Live Activity. iOS only lets Rise start or update it while Rise is open on screen
/// ("Process is only playing background media so is forbidden to update activity"), and ends it after
/// 8 hours. So everything the card needs for ringing is sent ahead of time; see the widget's isStale.
@MainActor
enum AlarmActivity {
    private static var shown: AlarmActivityAttributes.ContentState?
    /// Why the card couldn't start last time (shown in Settings); nil when it's fine.
    private(set) static var lastError: String?

    static var isShowing: Bool {
        Activity<AlarmActivityAttributes>.activities.contains(where: isCurrent)
    }

    /// Stale counts as current: that's the card showing "Wake up!" after its stale date (the alarm time).
    private static func isCurrent(_ activity: Activity<AlarmActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    /// Forget what's on screen so the next show() re-sends it (Settings' retry button).
    static func forget() { shown = nil }

    static func show(_ state: AlarmActivityAttributes.ContentState?) {
        let all = Activity<AlarmActivityAttributes>.activities
        let live = all.first(where: isCurrent)
        for old in all where old.id != live?.id {   // ended by iOS or swiped away
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        guard let state else {
            shown = nil
            if let live { Task { await live.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        // Stale at the alarm time, so iOS redraws the card as ringing by itself (the widget checks isStale).
        let content = ActivityContent(state: state, staleDate: state.ringing ? nil : state.alarmTime)
        if let live {
            guard state != shown else { return }
            // Light the screen up only when it starts ringing, not on every update.
            let alert: AlertConfiguration? = state.ringing && shown?.ringing != true
                ? AlertConfiguration(title: "Wake up!",
                                     body: "\(state.label.isEmpty ? "Your alarm is ringing" : state.label)",
                                     sound: .default)
                : nil
            shown = state
            Task { await live.update(content, alertConfiguration: alert) }
        } else if !ActivityAuthorizationInfo().areActivitiesEnabled {
            lastError = "Live Activities are off for Rise: iPhone Settings → Rise → Live Activities."
        } else if UIApplication.shared.applicationState == .active {
            do {
                _ = try Activity.request(attributes: AlarmActivityAttributes(), content: content)
                shown = state
                lastError = nil
            } catch {
                lastError = "\(error)"
            }
        } else {
            lastError = "Not started yet: iOS only allows it while Rise is open on screen."
        }
    }
}
