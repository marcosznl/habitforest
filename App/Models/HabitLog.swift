import Foundation
import SwiftData

@Model
final class HabitLog {
    var id: UUID = UUID()
    /// Sempre o início do dia local.
    var date: Date = Date.now
    var isCompleted: Bool = false
    var minutesFocused: Int = 0
    /// Anotação opcional de uma linha escrita ao concluir o hábito.
    var dailyNote: String?
    /// Dia coberto pela Estufa depois que a pausa terminou.
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
