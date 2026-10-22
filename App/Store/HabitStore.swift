import Foundation
import Observation
import SwiftData
import SwiftUI

/// Fonte única de verdade dos hábitos. Toda alteração passa por aqui para que o retorno (som,
/// tátil), as notificações, o Lembretes e o snapshot do widget fiquem consistentes.
@MainActor
@Observable
final class HabitStore {
    static let shared = HabitStore(context: PersistenceController.shared.container.mainContext)

    let context: ModelContext
    private(set) var habits: [Habit] = []
    /// Incrementado a cada alteração; views com cálculos pesados podem se basear nele.
    private(set) var revision = 0
    /// Definido pelo Filtro de Foco; `nil` mostra tudo.
    private(set) var focusContext: HabitContext?
    private(set) var focusMutesReminders = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(context: ModelContext) {
        self.context = context
        reload()
        applyFocusFilterFromDefaults()

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: HabitActionRelay.pendingActionsNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.drainPendingActions() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: FocusFilterState.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFocusFilterFromDefaults() }
        })
    }

    // MARK: - Consultas

    func reload() {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        habits = (try? context.fetch(descriptor)) ?? []
        revision += 1
    }

    /// Hábitos visíveis no Foco atual do macOS.
    var visibleHabits: [Habit] {
        guard let focusContext, focusContext != .any else { return habits }
        return habits.filter { $0.context == focusContext || $0.context == .any }
    }

    var activeHabits: [Habit] { visibleHabits.filter { !$0.isPausedInGreenhouse } }

    var greenhouseHabits: [Habit] { habits.filter(\.isPausedInGreenhouse) }

    func habit(id: UUID) -> Habit? { habits.first { $0.id == id } }

    var completedTodayCount: Int { activeHabits.filter { $0.isCompleted(on: .now) }.count }

    // MARK: - Criar, editar e excluir

    @discardableResult
    func addHabit(name: String, species: TreeSpecies, colorHex: String, targetMinutes: Int, context habitContext: HabitContext) -> Habit {
        let habit = Habit(name: name, species: species, themeColorHex: colorHex, targetMinutes: targetMinutes,
                          context: habitContext, sortOrder: (habits.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(habit)
        commit()
        Haptics.perform(.levelChange)
        AudioManager.shared.play(.leafRustle)
        return habit
    }

    func delete(_ habit: Habit) {
        context.delete(habit)
        commit()
        Haptics.perform(.generic)
    }

    func move(from source: IndexSet, to destination: Int) {
        var ordered = habits
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in ordered.enumerated() { habit.sortOrder = index }
        commit()
        Haptics.perform(.alignment)
    }

    /// Salva edições feitas direto nas propriedades do hábito (folha de edição).
    func habitDidChange() {
        commit()
    }

    // MARK: - Registro diário

    /// Alterna o dia informado. Devolve o novo estado de conclusão.
    @discardableResult
    func toggle(_ habit: Habit, on day: Date = .now) -> Bool {
        let newValue = !habit.isCompleted(on: day)
        setCompleted(habit, on: day, completed: newValue)
        return newValue
    }

    func setCompleted(_ habit: Habit, on day: Date = .now, completed: Bool, feedback: Bool = true) {
        let day = DayMath.start(of: day)
        guard day <= DayMath.today() else { return }
        let log = logForEditing(habit, on: day)
        guard log.isCompleted != completed else { return }
        log.isCompleted = completed
        log.isFrozen = false
        commit()

        if feedback {
            if completed {
                AudioManager.shared.play(.waterDrop)
                Haptics.perform(.levelChange)
            } else {
                Haptics.perform(.generic)
            }
        }
        Task { await EventKitManager.shared.reflectCompletion(of: habit, on: day, completed: completed) }
    }

    func setNote(_ note: String, for habit: Habit, on day: Date = .now) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = logForEditing(habit, on: day)
        log.dailyNote = trimmed.isEmpty ? nil : String(trimmed.prefix(140))
        commit()
    }

    /// Soma minutos de foco de uma sessão Pomodoro; atingir a meta conclui o hábito.
    func addFocusMinutes(_ minutes: Int, to habit: Habit, on day: Date = .now) {
        guard minutes > 0 else { return }
        let log = logForEditing(habit, on: day)
        log.minutesFocused += minutes
        commit()
        if !log.isCompleted, habit.targetMinutes == 0 || log.minutesFocused >= habit.targetMinutes {
            setCompleted(habit, on: day, completed: true)
        }
    }

    // MARK: - Estufa

    func setGreenhouse(_ habit: Habit, paused: Bool) {
        guard habit.isPausedInGreenhouse != paused else { return }
        if paused {
            habit.greenhouseSince = DayMath.today()
        } else if let since = habit.greenhouseSince {
            // Grava os dias pausados para a sequência continuar ignorando-os depois de sair da estufa.
            var day = DayMath.start(of: since)
            let today = DayMath.today()
            while day < today {
                let log = logForEditing(habit, on: day)
                if !log.isCompleted { log.isFrozen = true }
                day = DayMath.add(1, to: day)
            }
            habit.greenhouseSince = nil
        }
        habit.isPausedInGreenhouse = paused
        commit()
        Haptics.perform(.alignment)
        AudioManager.shared.play(.leafRustle)
    }

    // MARK: - Ações externas (widget, Atalhos, notificações)

    func drainPendingActions() {
        let actions = PendingActionQueue.drain()
        guard !actions.isEmpty else { return }
        for action in actions {
            guard let habit = habit(id: action.habitID) else { continue }
            setCompleted(habit, on: action.day, completed: action.completed, feedback: false)
        }
        publishSnapshot()
    }

    // MARK: - Filtro de Foco

    func applyFocusFilterFromDefaults() {
        let state = FocusFilterState.current
        focusContext = state.context == .any ? nil : state.context
        focusMutesReminders = state.muteReminders
    }

    // MARK: - Interno

    private func logForEditing(_ habit: Habit, on day: Date) -> HabitLog {
        if let existing = habit.log(on: day) { return existing }
        let log = HabitLog(date: day)
        context.insert(log)
        log.habit = habit
        habit.logs.append(log)
        return log
    }

    private func commit() {
        try? context.save()
        reload()
        publishSnapshot()
        NotificationManager.shared.reschedule(for: habits)
    }

    /// Grava a cópia leve que o widget e os App Intents leem.
    func publishSnapshot() {
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            habits: habits.map { habit in
                let calculator = habit.calculator()
                let summary = calculator.summary()
                return WidgetHabit(
                    id: habit.id,
                    name: habit.name,
                    species: habit.species,
                    colorHex: habit.themeColorHex,
                    streak: summary.currentStreak,
                    health: summary.health,
                    isPaused: habit.isPausedInGreenhouse,
                    days: calculator.window(days: 30)
                )
            }
        )
        SnapshotStore.save(snapshot)
    }
}

extension HabitStore {
    /// Planta uma pequena floresta na primeira abertura para o painel nunca começar vazio.
    func seedIfNeeded() {
        guard habits.isEmpty, !UserDefaults.standard.bool(forKey: "didSeed") else { return }
        UserDefaults.standard.set(true, forKey: "didSeed")
        addHabit(name: "Ler 20 páginas", species: .oak, colorHex: TreeSpecies.oak.defaultHex, targetMinutes: 0, context: .personal)
        addHabit(name: "Programar", species: .pine, colorHex: TreeSpecies.pine.defaultHex, targetMinutes: 50, context: .work)
        addHabit(name: "Meditar", species: .cherry, colorHex: TreeSpecies.cherry.defaultHex, targetMinutes: 10, context: .personal)
    }
}
