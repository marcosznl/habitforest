import Foundation

/// A day with the tree state as it was at the end of that day.
struct DaySnapshot: Hashable, Codable, Sendable {
    var date: Date
    var state: DayState
    var streak: Int
    var health: TreeHealth

    var stage: GrowthStage { GrowthStage(streak: streak) }
}

/// Pure streak/health engine shared by the app and the widget.
///
/// Rules:
/// - Completed days grow the streak.
/// - Greenhouse (frozen) days are neutral: they never count and never break.
/// - A single missed day is a grace day: the tree turns `.struggling` but the streak survives
///   if the next day is completed.
/// - Two consecutive missed days wither the tree and reset the streak to zero.
/// - Today is `pending` until done and never counts as a miss.
struct StreakCalculator: Sendable {
    let start: Date
    let completed: Set<Date>
    let frozen: Set<Date>
    let today: Date

    init(start: Date, completed: Set<Date>, frozen: Set<Date>, today: Date = DayMath.today()) {
        let normalizedCompleted = Set(completed.map(DayMath.start(of:)))
        let earliestLog = normalizedCompleted.min() ?? DayMath.start(of: start)
        self.start = min(DayMath.start(of: start), earliestLog)
        self.completed = normalizedCompleted
        self.frozen = Set(frozen.map(DayMath.start(of:)))
        self.today = DayMath.start(of: today)
    }

    func state(on day: Date) -> DayState {
        let day = DayMath.start(of: day)
        if day < start { return .beforeStart }
        if completed.contains(day) { return .completed }
        if frozen.contains(day) { return .frozen }
        if day >= today { return .pending }
        return .missed
    }

    /// Every day from the habit start through `end`, oldest first.
    func timeline(through end: Date? = nil) -> [DaySnapshot] {
        let end = DayMath.start(of: end ?? today)
        guard end >= start else { return [] }

        var result: [DaySnapshot] = []
        result.reserveCapacity(DayMath.distance(from: start, to: end) + 1)
        var streak = 0
        var consecutiveMisses = 0
        var day = start

        while day <= end {
            let state = state(on: day)
            switch state {
            case .completed:
                streak += 1
                consecutiveMisses = 0
            case .missed:
                consecutiveMisses += 1
                if consecutiveMisses >= 2 { streak = 0 }
            case .frozen, .pending, .beforeStart:
                break
            }
            let health: TreeHealth = switch consecutiveMisses {
            case 0: .healthy
            case 1: .struggling
            default: .withered
            }
            result.append(DaySnapshot(date: day, state: state, streak: streak, health: health))
            day = DayMath.add(1, to: day)
        }
        return result
    }

    /// Last `count` days ending today, padding days before the habit started.
    func window(days count: Int) -> [DaySnapshot] {
        let full = timeline()
        let byDate = Dictionary(full.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        return DayMath.days(endingAt: today, count: count).map { day in
            byDate[day] ?? DaySnapshot(date: day, state: .beforeStart, streak: 0, health: .healthy)
        }
    }

    struct Summary: Sendable {
        var currentStreak: Int
        var bestStreak: Int
        var health: TreeHealth
        var completedToday: Bool
        var stage: GrowthStage { GrowthStage(streak: currentStreak) }
    }

    func summary() -> Summary {
        let full = timeline()
        let last = full.last
        return Summary(
            currentStreak: last?.streak ?? 0,
            bestStreak: full.map(\.streak).max() ?? 0,
            health: last?.health ?? .healthy,
            completedToday: completed.contains(today)
        )
    }
}
