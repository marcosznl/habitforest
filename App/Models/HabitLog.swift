import Foundation
import SwiftData

@Model
final class HabitLog {
    var id: UUID = UUID()
    /// Always the start of the local day.
    var date: Date = Date.now
    var isCompleted: Bool = false
    var minutesFocused: Int = 0
    /// Optional one-line journal entry written when the habit is completed.
    var dailyNote: String?
    /// Day covered by Greenhouse mode after the pause ended.
    var isFrozen: Bool = false
    var habit: Habit?

    init(date: Date, isCompleted: Bool = false, minutesFocused: Int = 0, dailyNote: String? = nil, isFrozen: Bool = false) {
        self.id = UUID()
        self.date = DayMath.start(of: date)
        self.isCompleted = isCompleted
        self.minutesFocused = minutesFocused
        self.dailyNote = dailyNote
        self.isFrozen = isFrozen
    }
}
