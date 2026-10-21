import Foundation
import SwiftData
import SwiftUI

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var treeType: String = TreeSpecies.oak.rawValue
    var themeColorHex: String = TreeSpecies.oak.defaultHex
    var createdAt: Date = Date.now
    /// Daily focus goal in minutes (0 = simple check-off habit).
    var targetMinutes: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog] = []
    /// Greenhouse mode: paused for vacations without breaking the streak.
    var isPausedInGreenhouse: Bool = false
    var greenhouseSince: Date?
    var sortOrder: Int = 0
    /// Which Focus Filter context shows this habit (`HabitContext`).
    var contextRaw: String = HabitContext.any.rawValue
    var reminderEnabled: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0

    init(name: String,
         species: TreeSpecies = .oak,
         themeColorHex: String? = nil,
         targetMinutes: Int = 0,
         context: HabitContext = .any,
         sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.treeType = species.rawValue
        self.themeColorHex = themeColorHex ?? species.defaultHex
        self.createdAt = DayMath.today()
        self.targetMinutes = targetMinutes
        self.contextRaw = context.rawValue
        self.sortOrder = sortOrder
    }
}

extension Habit {
    var species: TreeSpecies {
        get { TreeSpecies(rawValue: treeType) ?? .oak }
        set { treeType = newValue.rawValue }
    }

    var context: HabitContext {
        get { HabitContext(rawValue: contextRaw) ?? .any }
        set { contextRaw = newValue.rawValue }
    }

    var themeColor: Color { Color(hex: themeColorHex) }

    func log(on day: Date) -> HabitLog? {
        let day = DayMath.start(of: day)
        return logs.first { $0.date == day }
    }

    func isCompleted(on day: Date) -> Bool {
        log(on: day)?.isCompleted ?? false
    }

    /// Days covered by Greenhouse mode: past frozen logs plus the ongoing pause.
    var frozenDays: Set<Date> {
        var days = Set(logs.filter { $0.isFrozen && !$0.isCompleted }.map(\.date))
        if isPausedInGreenhouse, let since = greenhouseSince {
            var day = DayMath.start(of: since)
            let today = DayMath.today()
            while day <= today {
                days.insert(day)
                day = DayMath.add(1, to: day)
            }
        }
        return days
    }

    func calculator(today: Date = DayMath.today()) -> StreakCalculator {
        StreakCalculator(
            start: createdAt,
            completed: Set(logs.filter(\.isCompleted).map(\.date)),
            frozen: frozenDays,
            today: today
        )
    }

    var summary: StreakCalculator.Summary { calculator().summary() }

    var focusMinutesToday: Int { log(on: .now)?.minutesFocused ?? 0 }

    var totalFocusMinutes: Int { logs.reduce(0) { $0 + $1.minutesFocused } }
}
