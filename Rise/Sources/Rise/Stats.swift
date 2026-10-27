import Charts
import SwiftUI

/// One morning: from the first ring to turning it off.
struct WakeRecord: Codable, Identifiable {
    var id = UUID()
    let rang: Date
    let up: Date
    let snoozes: Int
    let escaped: Bool
    var checkFailed: Bool?   // optional so records saved before it existed still load

    var minutes: Double { up.timeIntervalSince(rang) / 60 }
    /// Counts towards the streak: no snooze, no emergency escape, no missed wake-up check.
    var clean: Bool { snoozes == 0 && !escaped && checkFailed != true }
}

final class WakeStats: ObservableObject {
    static let shared = WakeStats()
    @Published private(set) var records: [WakeRecord] = []
    private var loaded = false   // see whenDataReadable

    private init() {}

    func load() {
        loaded = true
        if let data = UserDefaults.standard.data(forKey: "wakeRecords"),
           let saved = try? JSONDecoder().decode([WakeRecord].self, from: data) {
            records = saved
        }
    }

    func add(rang: Date, snoozes: Int, escaped: Bool) {
        records.append(WakeRecord(rang: rang, up: Date(), snoozes: snoozes, escaped: escaped))
        records = Array(records.suffix(400))   // about a year of mornings
        save()
    }

    /// The wake-up check after the last alarm was missed (they went back to sleep).
    func markLastCheckFailed() {
        guard !records.isEmpty else { return }
        records[records.count - 1].checkFailed = true
        save()
    }

    func reset() {
        records = []
        save()
    }

    /// Alarm days in a row (newest first) where every wake-up was clean. Days with no alarm don't break it.
    var streak: Int {
        var count = 0
        for day in cleanByDay.reversed() {
            guard day else { break }
            count += 1
        }
        return count
    }

    var bestStreak: Int {
        var best = 0, run = 0
        for day in cleanByDay {
            run = day ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// Oldest first: was every wake-up that day clean?
    private var cleanByDay: [Bool] {
        let days = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.up) }
        return days.keys.sorted().map { day in days[day]!.allSatisfy(\.clean) }
    }

    var recent: [WakeRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        return records.filter { $0.up >= cutoff }
    }

    private func save() {
        guard loaded else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: "wakeRecords")
    }
}

func durationText(_ minutes: Double) -> String {
    let seconds = Int(minutes * 60)
    return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
}

/// Home-screen card; only shows once there's something to show.
struct StreakCard: View {
    @ObservedObject private var stats = WakeStats.shared

    var body: some View {
        if !stats.records.isEmpty {
            NavigationLink { StatsView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(stats.streak > 0 ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stats.streak)-day streak").font(.headline)
                        if let average = average {
                            Text("Up in \(durationText(average)) on average lately")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var average: Double? {
        let recent = stats.recent
        return recent.isEmpty ? nil : recent.map(\.minutes).reduce(0, +) / Double(recent.count)
    }
}

struct StatsView: View {
    @ObservedObject private var stats = WakeStats.shared
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "flame.fill").font(.system(size: 48)).foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text("\(stats.streak)-day streak").font(.title.bold())
                        Text("Best: \(stats.bestStreak) day\(stats.bestStreak == 1 ? "" : "s")").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("A morning counts when you got up with no snooze, no emergency escape and no missed wake-up check. Test alarms don't count.")
            }

            let recent = stats.recent
            if !recent.isEmpty {
                Section("Time to get up, last 14 days") {
                    Chart(recent) { record in
                        BarMark(x: .value("Day", record.up, unit: .day), y: .value("Minutes", record.minutes))
                            .foregroundStyle(record.clean ? Color.orange : Color.gray)
                    }
                    .chartYAxisLabel("minutes")
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }

                Section("Last 14 days") {
                    LabeledContent("Average time to get up",
                                   value: durationText(recent.map(\.minutes).reduce(0, +) / Double(recent.count)))
                    LabeledContent("Snoozes", value: "\(recent.map(\.snoozes).reduce(0, +))")
                    LabeledContent("Emergency escapes", value: "\(recent.filter(\.escaped).count)")
                    LabeledContent("Missed wake-up checks", value: "\(recent.filter { $0.checkFailed == true }.count)")
                }
            }

            Section("Recent mornings") {
                ForEach(stats.records.suffix(10).reversed()) { record in
                    HStack {
                        Image(systemName: record.clean ? "checkmark.circle.fill" : "moon.zzz.fill")
                            .foregroundStyle(record.clean ? Color.green : Color.secondary)
                        VStack(alignment: .leading) {
                            Text(record.up.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                            Text(details(record)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Reset stats", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Wake-up stats")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all wake-up stats?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset stats", role: .destructive) { stats.reset() }
        }
    }

    private func details(_ record: WakeRecord) -> String {
        var parts = ["Up in \(durationText(record.minutes))"]
        if record.snoozes > 0 { parts.append("\(record.snoozes) snooze\(record.snoozes == 1 ? "" : "s")") }
        if record.escaped { parts.append("emergency escape") }
        if record.checkFailed == true { parts.append("missed wake-up check") }
        return parts.joined(separator: " · ")
    }
}
