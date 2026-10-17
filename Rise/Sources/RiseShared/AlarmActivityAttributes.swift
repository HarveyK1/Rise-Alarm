import ActivityKit
import Foundation

/// The lock-screen Live Activity's data. The app starts and updates it; the widget extension draws it.
public struct AlarmActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var alarmTime: Date
        public var label: String
        public var ringing: Bool        // also treat the card as ringing once it goes stale at alarmTime
        public var snoozeMinutes: Int   // snooze offered when it rings; 0 = none

        public init(alarmTime: Date, label: String, ringing: Bool, snoozeMinutes: Int) {
            self.alarmTime = alarmTime
            self.label = label
            self.ringing = ringing
            self.snoozeMinutes = snoozeMinutes
        }
    }

    public init() {}
}
