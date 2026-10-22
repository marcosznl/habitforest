import Foundation

/// Um dia com o estado da árvore como estava no fim dele.
struct DaySnapshot: Hashable, Codable, Sendable {
    var date: Date
    var state: DayState
    var streak: Int
    var health: TreeHealth

    var stage: GrowthStage { GrowthStage(streak: streak) }
}

/// Motor puro de sequência e saúde, compartilhado pelo app e pelo widget.
///
/// Regras:
/// - Dias concluídos aumentam a sequência.
/// - Dias na Estufa (congelados) são neutros: não contam nem quebram.
/// - Um único dia falhado é de tolerância: a árvore fica `.struggling`, mas a sequência sobrevive
///   se o dia seguinte for concluído.
/// - Dois dias falhados seguidos secam a árvore e zeram a sequência.
/// - Hoje fica `pending` até ser feito e nunca conta como falha.
/// - Dias anteriores ao plantio são neutros; um dia antigo marcado depois conta só como ele mesmo.
struct StreakCalculator: Sendable {
    /// Dia do plantio do hábito.
    let start: Date
    /// Primeiro dia da linha do tempo: o plantio ou um dia antigo marcado depois, o que vier antes.
    let firstDay: Date
    let completed: Set<Date>
    let frozen: Set<Date>
    let today: Date

    init(start: Date, completed: Set<Date>, frozen: Set<Date>, today: Date = DayMath.today()) {
        let normalizedCompleted = Set(completed.map(DayMath.start(of:)))
        self.start = DayMath.start(of: start)
        self.firstDay = min(self.start, normalizedCompleted.min() ?? self.start)
        self.completed = normalizedCompleted
        self.frozen = Set(frozen.map(DayMath.start(of:)))
        self.today = DayMath.start(of: today)
    }

    func state(on day: Date) -> DayState {
        let day = DayMath.start(of: day)
        if completed.contains(day) { return .completed }
        if day < start { return .beforeStart }
        if frozen.contains(day) { return .frozen }
        if day >= today { return .pending }
        return .missed
    }

    /// Todos os dias do início do hábito até `end`, do mais antigo ao mais novo.
    func timeline(through end: Date? = nil) -> [DaySnapshot] {
        let end = DayMath.start(of: end ?? today)
        guard end >= firstDay else { return [] }

        var result: [DaySnapshot] = []
        result.reserveCapacity(DayMath.distance(from: firstDay, to: end) + 1)
        var streak = 0
        var consecutiveMisses = 0
        var day = firstDay

        while day <= end {
            let state = state(on: day)
            switch state {
            case .completed:
                streak += 1
                consecutiveMisses = 0
            case .missed:
                consecutiveMisses += 1
                if consecutiveMisses >= 2 { streak = 0 }
            case .beforeStart:
                streak = 0
                consecutiveMisses = 0
            case .frozen, .pending:
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

    /// Últimos `count` dias até hoje, completando os dias anteriores ao plantio.
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
