import Foundation
import WidgetKit

/// Cópia leve da floresta que o app publica para o widget e os App Intents.
/// O widget roda em sandbox e não consegue abrir o banco no iCloud Drive, então lê esta cópia.
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

    /// Últimos `count` dias em relação a *agora*, preenchendo os dias que o snapshot não conhece.
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

    /// Atualização otimista usada quando o widget marca um hábito com o app fechado.
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
