import ActivityKit
import RiseShared
import SwiftUI
import WidgetKit

@main
struct RiseWidgets: WidgetBundle {
    var body: some Widget {
        AlarmLiveActivity()
    }
}

/// Lock-screen card + Dynamic Island: "Next alarm 7:00", then "Wake up!" with Snooze / Stop when it rings.
/// Snooze and Stop are links into the app (unlock, then Rise handles them).
///
/// iOS forbids Live Activity updates from an app that's only alive for background audio (which is how Rise
/// rings), so the app can't flip the card to "ringing". Instead the card's stale date is the alarm time:
/// iOS re-renders it with `isStale` when that passes, and the card shows the ringing look by itself.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmActivityAttributes.self) { context in
            LockScreenCard(state: context.state, ringing: context.state.ringing || context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.orange)
                .widgetURL(URL(string: "rise://open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").font(.title2).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.alarmTime, style: .time).font(.title2.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.ringing || context.isStale {
                        ActionButtons(state: context.state)
                    } else {
                        Text(context.state.label.isEmpty ? "Next alarm" : context.state.label)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.alarmTime, style: .time).font(.caption2)
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "rise://open"))
        }
    }
}

struct LockScreenCard: View {
    let state: AlarmActivityAttributes.ContentState
    let ringing: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ringing ? "Wake up!" : "Next alarm").font(.headline)
                    if !state.label.isEmpty {
                        Text(state.label).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(state.alarmTime, style: .time)
                    .font(.system(size: 40, weight: .light, design: .rounded))
            }
            if ringing { ActionButtons(state: state) }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

struct ActionButtons: View {
    let state: AlarmActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            if state.snoozeMinutes > 0, let url = URL(string: "rise://snooze") {
                Link(destination: url) { pill("Snooze \(state.snoozeMinutes) min", Color.white.opacity(0.15)) }
            }
            if let url = URL(string: "rise://open") {
                Link(destination: url) { pill("Stop", Color.orange) }
            }
        }
    }

    private func pill(_ title: String, _ background: Color) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: Capsule())
    }
}
