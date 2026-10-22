import Foundation
import SwiftData

/// Modo demonstração (`--demo`): banco só em memória com uma floresta de exemplo, usado para
/// capturas de tela. Não grava no banco real nem mexe no Lembretes, nas notificações ou no widget.
enum DemoMode {
    static let isActive = ProcessInfo.processInfo.arguments.contains("--demo")

    private struct Spec {
        var name: String
        var species: TreeSpecies
        var context: HabitContext
        var targetMinutes = 0
        var createdDaysAgo: Int
        var streakDays: Int
        var doneToday: Bool
        var earlierRate: Double
        var pausedDaysAgo: Int? = nil
        var notes: [Int: String] = [:]
    }

    private static let specs: [Spec] = [
        Spec(name: "Ler 20 páginas", species: .oak, context: .personal, createdDaysAgo: 300, streakDays: 44, doneToday: true,
             earlierRate: 0.8, notes: [0: "Terminei o capítulo 12", 3: "Li no parque"]),
        Spec(name: "Programar", species: .pine, context: .work, targetMinutes: 50, createdDaysAgo: 220, streakDays: 21,
             doneToday: true, earlierRate: 0.75),
        Spec(name: "Meditar", species: .cherry, context: .personal, targetMinutes: 10, createdDaysAgo: 120, streakDays: 9,
             doneToday: false, earlierRate: 0.7),
        Spec(name: "Beber 2 L de água", species: .palm, context: .any, createdDaysAgo: 70, streakDays: 16, doneToday: true,
             earlierRate: 0.65),
        Spec(name: "Inglês", species: .ipe, context: .personal, createdDaysAgo: 50, streakDays: 5, doneToday: true,
             earlierRate: 0.6, notes: [0: "Assisti a um episódio sem legenda"]),
        Spec(name: "Correr 5 km", species: .birch, context: .personal, createdDaysAgo: 90, streakDays: 0, doneToday: false,
             earlierRate: 0.55),
        Spec(name: "Alongar", species: .cactus, context: .any, createdDaysAgo: 3, streakDays: 2, doneToday: false, earlierRate: 0),
        Spec(name: "Violão", species: .bamboo, context: .personal, createdDaysAgo: 80, streakDays: 12, doneToday: false,
             earlierRate: 0.7, pausedDaysAgo: 4),
    ]

    @MainActor
    static func seed(into context: ModelContext) {
        let today = DayMath.today()
        var random = SeededRandom(seed: 42)

        for (order, spec) in specs.enumerated() {
            let habit = Habit(name: spec.name, species: spec.species, targetMinutes: spec.targetMinutes,
                              context: spec.context, sortOrder: order)
            habit.createdAt = DayMath.add(-spec.createdDaysAgo, to: today)
            context.insert(habit)

            // A sequência atual termina hoje, ontem ou na véspera da pausa na Estufa; o dia antes dela
            // fica sem rega para a sequência ter exatamente `streakDays` dias.
            let lastDone = spec.pausedDaysAgo.map { $0 + 1 } ?? (spec.doneToday ? 0 : 1)
            let firstDone = lastDone + spec.streakDays - 1

            for daysAgo in stride(from: spec.createdDaysAgo, through: 0, by: -1) {
                let done: Bool
                if spec.streakDays == 0 {
                    // Sequência quebrada: dois dias seguidos sem rega antes de hoje.
                    done = daysAgo > 2 && random.next() < spec.earlierRate
                } else if daysAgo < lastDone || daysAgo == firstDone + 1 {
                    done = false
                } else if daysAgo <= firstDone {
                    done = true
                } else {
                    done = random.next() < spec.earlierRate
                }
                guard done else { continue }

                let log = HabitLog(date: DayMath.add(-daysAgo, to: today), isCompleted: true,
                                   minutesFocused: spec.targetMinutes > 0 ? spec.targetMinutes + Int(random.next() * 25) : 0,
                                   dailyNote: spec.notes[daysAgo])
                context.insert(log)
                log.habit = habit
                habit.logs.append(log)
            }

            if let paused = spec.pausedDaysAgo {
                habit.isPausedInGreenhouse = true
                habit.greenhouseSince = DayMath.add(-paused, to: today)
            }
        }
        try? context.save()
    }

    /// Gerador simples e determinístico, para a demonstração sair igual toda vez.
    private struct SeededRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
    }
}
