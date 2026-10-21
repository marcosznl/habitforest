import Foundation
import WidgetKit

/// Lightweight copy of the forest that the app publishes for the widget and App Intents.
/// The widget is sandboxed and cannot open the SwiftData store in iCloud Drive, so it reads this.
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var habits: [WidgetHabit]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, habits: [])
}

struct WidgetHabit: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var species: TreeSpecies
    var colorHex: String
    var streak: Int
    var health: TreeHealth
    var isPaused: Bool
    var days: [DaySnapshot]

    var stage: GrowthStage { GrowthStage(streak: streak) }

    var completedToday: Bool {
        days.first { $0.date == DayMath.today() }?.state == .completed
    }

    /// Last `count` days relative to *now*, filling days the snapshot does not know about.
    func window(days count: Int, today: Date = DayMath.today()) -> [DaySnapshot] {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let lastKnown = days.last
        return DayMath.days(endingAt: today, count: count).map { day in
            if let known = byDate[day] { return known }
            if let first = days.first, day < first.date {
                return DaySnapshot(date: day, state: .beforeStart, streak: 0, health: .healthy)
            }
            let state: DayState = isPaused ? .frozen : (day == today ? .pending : .missed)
            return DaySnapshot(date: day, state: state, streak: lastKnown?.streak ?? 0, health: lastKnown?.health ?? .healthy)
        }
    }

    /// Optimistic update used when the widget toggles a habit while the app is not running.
    mutating func applyToday(completed: Bool, today: Date = DayMath.today()) {
        let previous = days.last { $0.date < today }
        let baseStreak = previous?.streak ?? 0
        let newStreak = completed ? baseStreak + 1 : baseStreak
        let snapshot = DaySnapshot(
            date: today,
            state: completed ? .completed : .pending,
            streak: newStreak,
            health: completed ? .healthy : (previous?.health ?? .healthy)
        )
        if let index = days.firstIndex(where: { $0.date == today }) {
            days[index] = snapshot
        } else {
            days.append(snapshot)
        }
        streak = newStreak
        health = snapshot.health
    }
}

enum SnapshotStore {
    static var url: URL { AppGroup.containerURL.appending(path: "widget-snapshot.json") }

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    static func save(_ snapshot: WidgetSnapshot, reloadWidgets: Bool = true) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }
}
