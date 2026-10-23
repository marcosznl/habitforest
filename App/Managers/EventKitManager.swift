import AppKit
import EventKit
import Observation

/// Blocos de tempo no Calendário para sessões de foco e sincronização dos hábitos com o Lembretes nos dois sentidos.
@MainActor
@Observable
final class EventKitManager {
    static let shared = EventKitManager()

    static let calendarTitle = "Hábitos"
    private static let urlScheme = "habitos"

    @ObservationIgnored private let store = EKEventStore()
    private(set) var calendarAuthorized = false
    private(set) var remindersAuthorized = false
    private(set) var remindersDenied = false
    private(set) var todaysEvents: [EKEvent] = []
    var lastError: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let status = EKEventStore.authorizationStatus(for: .reminder)
        remindersAuthorized = status == .fullAccess
        remindersDenied = status == .denied || status == .restricted || status == .writeOnly
    }

    /// Na abertura: se a sincronização está ligada e o acesso ao Lembretes ainda não foi pedido,
    /// pede uma vez e já sincroniza (criando a lista Hábitos).
    func prepareRemindersSync(_ habitStore: HabitStore) async {
        guard !DemoMode.isActive, AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) else { return }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            await requestRemindersAccess()
        }
        refreshStatus()
        await syncReminders(store: habitStore)
    }

    /// Abre Ajustes do Sistema › Privacidade e Segurança › Lembretes.
    func openRemindersPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestCalendarAccess() async {
        do {
            calendarAuthorized = try await store.requestFullAccessToEvents()
            if calendarAuthorized { loadTodaysEvents() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestRemindersAccess() async {
        do {
            remindersAuthorized = try await store.requestFullAccessToReminders()
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Calendário

    func loadTodaysEvents() {
        guard calendarAuthorized else { todaysEvents = []; return }
        let start = DayMath.today()
        let predicate = store.predicateForEvents(withStart: start, end: DayMath.add(1, to: start), calendars: nil)
        todaysEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Grava uma sessão de foco concluída (ou planejada) como bloco de tempo no calendário Hábitos.
    @discardableResult
    func addFocusBlock(title: String, start: Date, minutes: Int, notes: String? = nil) -> Bool {
        guard calendarAuthorized, let calendar = habitCalendar() else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.notes = notes
        event.url = URL(string: "\(Self.urlScheme)://focus")
        do {
            try store.save(event, span: .thisEvent)
            loadTodaysEvents()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func habitCalendar() -> EKCalendar? {
        if let existing = existingCalendar(for: .event) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.color = NSColor(red: 0.24, green: 0.56, blue: 0.25, alpha: 1)
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            lastError = error.localizedDescription
            return store.defaultCalendarForNewEvents
        }
    }

    /// Calendário ou lista do app.
    private func existingCalendar(for type: EKEntityType) -> EKCalendar? {
        store.calendars(for: type).first { $0.title == Self.calendarTitle }
    }

    // MARK: - Sincronização com o Lembretes
    //
    // Cada hábito tem um único lembrete recorrente (todo dia) na lista "Hábitos", só com o nome do
    // hábito. Quem cria o lembrete de cada dia é o próprio Lembretes, no Mac ou no iPhone, mesmo com o
    // app desligado: ao marcar o lembrete recorrente, o Lembretes guarda uma cópia concluída e passa
    // o recorrente para o dia seguinte. O app lê essas cópias (o histórico) para regar os dias certos.
    //
    // A sincronização é nos dois sentidos e guarda o último estado combinado de cada hábito e dia:
    // assim dá para saber quem mudou desde a última vez, o app ou o Lembretes, e quem mudou vence.
    // Ela roda ao abrir o app, na virada do dia e sempre que o Lembretes muda enquanto o app está
    // aberto (mesmo só na barra de menus); com o app fechado, os últimos 14 dias são conciliados na
    // próxima abertura.

    private static let catchUpDays = 14
    private static let syncStateKey = "remindersSyncState"
    private static let mastersKey = "remindersMasters"
    private static let aliasesKey = "remindersAliases"

    private var syncEnabled: Bool { !DemoMode.isActive && AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) && remindersAuthorized }
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    private(set) var lastReminderSync: Date?

    /// Último estado (regado ou não) combinado entre app e Lembretes, por hábito e dia.
    private var syncState: [String: Bool] {
        get { AppGroup.defaults.dictionary(forKey: Self.syncStateKey) as? [String: Bool] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.syncStateKey) }
    }

    /// Hábito → identificador do lembrete recorrente dele.
    private var masterIndex: [String: String] {
        get { AppGroup.defaults.dictionary(forKey: Self.mastersKey) as? [String: String] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.mastersKey) }
    }

    /// Hábito → nomes que ele já teve, para reconhecer cópias antigas depois de uma renomeação.
    private var aliases: [String: [String]] {
        get { AppGroup.defaults.dictionary(forKey: Self.aliasesKey) as? [String: [String]] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.aliasesKey) }
    }

    /// Passa a sincronizar sempre que o banco do Lembretes/Calendário mudar.
    func startObserving(_ habitStore: HabitStore) {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadTodaysEvents()
                self?.scheduleSync(habitStore)
            }
        }
    }

    /// Agrupa rajadas de mudanças numa única sincronização.
    func scheduleSync(_ habitStore: HabitStore) {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.syncReminders(store: habitStore)
        }
    }

    private func remindersList() -> EKCalendar? {
        if let existing = existingCalendar(for: .reminder) {
            return existing
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = Self.calendarTitle
        list.color = NSColor(red: 0.24, green: 0.56, blue: 0.25, alpha: 1)
        list.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first
        do {
            try store.saveCalendar(list, commit: true)
            return list
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func reminders(in list: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [list])) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func stateKey(_ habitID: UUID, _ day: Date) -> String {
        "\(habitID.uuidString)|\(DayMath.key(day))"
    }

    private static func normalizedTitle(_ reminder: EKReminder) -> String {
        (reminder.title ?? "").replacingOccurrences(of: "🌳", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func dueDay(_ reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map(DayMath.start(of:))
    }

    /// Dia que uma cópia concluída rega: o dia em que foi marcada (ou o vencimento, se faltar a data).
    private static func creditedDay(_ reminder: EKReminder) -> Date? {
        reminder.completionDate.map(DayMath.start(of:)) ?? dueDay(reminder)
    }

    /// Concilia os últimos 14 dias nos dois sentidos e mantém um lembrete recorrente por hábito,
    /// sempre apontando para o próximo dia ainda não regado.
    func syncReminders(store habitStore: HabitStore) async {
        guard syncEnabled, !isSyncing, let list = remindersList() else { return }
        isSyncing = true
        defer { isSyncing = false }

        let today = DayMath.today()
        let oldest = DayMath.add(-(Self.catchUpDays - 1), to: today)
        var state = syncState
        var masters = masterIndex
        var names = aliases
        let all = await reminders(in: list)
        var claimed = Set<String>()

        // Lembretes avulsos pendentes são sobras do modelo antigo (um por dia) ou cópias desmarcadas:
        // eles não contam como rega e saem da lista no fim.
        let strays = all.filter { !$0.hasRecurrenceRules && !$0.isCompleted }

        for habit in habitStore.habits {
            let id = habit.id.uuidString
            var known = names[id] ?? []
            if !known.contains(habit.name) { known.append(habit.name) }
            names[id] = known

            // Lembrete recorrente do hábito: pelo índice ou pelo nome. Duplicados são removidos.
            let recurring = all.filter { $0.hasRecurrenceRules && !claimed.contains($0.calendarItemIdentifier) }
            var master = recurring.first { $0.calendarItemIdentifier == masters[id] }
                ?? recurring.first { known.contains(Self.normalizedTitle($0)) }
            for duplicate in recurring where duplicate !== master && known.contains(Self.normalizedTitle(duplicate)) {
                try? store.remove(duplicate, commit: false)
            }

            // Histórico: cópias concluídas deste hábito dentro da janela.
            var copies = all.filter {
                !$0.hasRecurrenceRules && $0.isCompleted && known.contains(Self.normalizedTitle($0))
                    && (Self.creditedDay($0) ?? .distantPast) >= oldest
            }
            var doneInReminders: Set<Date> { Set(copies.compactMap(Self.creditedDay)) }

            // Concilia cada dia da janela.
            var day = oldest
            while day <= today {
                let key = stateKey(habit.id, day)
                let inApp = habit.isCompleted(on: day)
                let inReminders = doneInReminders.contains(day)
                if inApp != inReminders {
                    let remindersChanged = state[key].map { $0 != inReminders } ?? inReminders
                    if remindersChanged {
                        habitStore.setCompleted(habit, on: day, completed: inReminders, feedback: false)
                    } else if inApp {
                        if day == today, let current = master, Self.dueDay(current) == today {
                            // Marcar o recorrente faz o Lembretes guardar a cópia e avançar para amanhã.
                            current.isCompleted = true
                            try? store.save(current, commit: false)
                        } else {
                            copies.append(createCompletedCopy(title: habit.name, on: day, in: list))
                        }
                    } else {
                        for copy in copies where Self.creditedDay(copy) == day {
                            try? store.remove(copy, commit: false)
                        }
                        copies.removeAll { Self.creditedDay($0) == day }
                    }
                }
                state[key] = habit.isCompleted(on: day)
                day = DayMath.add(1, to: day)
            }

            // Estufa: sem lembrete recorrente enquanto o hábito está pausado.
            if habit.isPausedInGreenhouse {
                if let current = master { try? store.remove(current, commit: false) }
                masters[id] = nil
                continue
            }

            // O recorrente aponta para hoje, ou para amanhã se hoje já foi regado.
            let next = habit.isCompleted(on: today) ? DayMath.add(1, to: today) : today
            if master == nil {
                master = createRecurring(for: habit, startingOn: next, in: list)
            } else if let current = master {
                var changed = false
                if current.title != habit.name { current.title = habit.name; changed = true }
                if current.isCompleted { current.isCompleted = false; changed = true }
                if Self.dueDay(current) != next {
                    current.dueDateComponents = dueComponents(for: habit, on: next)
                    changed = true
                }
                if changed { try? store.save(current, commit: false) }
            }
            if let current = master {
                masters[id] = current.calendarItemIdentifier
                claimed.insert(current.calendarItemIdentifier)
            }
        }

        // Recorrentes de hábitos que não existem mais.
        let habitIDs = Set(habitStore.habits.map(\.id.uuidString))
        for (habitID, reminderID) in masters where !habitIDs.contains(habitID) {
            if let orphan = all.first(where: { $0.calendarItemIdentifier == reminderID }) {
                try? store.remove(orphan, commit: false)
            }
            masters[habitID] = nil
        }
        for stray in strays { try? store.remove(stray, commit: false) }

        state = state.filter { key, _ in
            let parts = key.split(separator: "|")
            guard parts.count == 2, let day = DayMath.date(fromKey: String(parts[1])) else { return false }
            return day >= oldest
        }
        syncState = state
        masterIndex = masters
        aliases = names.filter { habitIDs.contains($0.key) }
        AppGroup.defaults.removeObject(forKey: "remindersIndex")
        try? store.commit()
        lastReminderSync = .now
    }

    private func dueComponents(for habit: Habit, on day: Date) -> DateComponents {
        var due = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if habit.reminderEnabled {
            due.hour = habit.reminderHour
            due.minute = habit.reminderMinute
        }
        return due
    }

    private func createRecurring(for habit: Habit, startingOn day: Date, in list: EKCalendar) -> EKReminder? {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = habit.name
        reminder.dueDateComponents = dueComponents(for: habit, on: day)
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        do {
            try store.save(reminder, commit: false)
            return reminder
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Cópia concluída para um dia regado no app que o Lembretes ainda não conhece.
    private func createCompletedCopy(title: String, on day: Date, in list: EKCalendar) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
        reminder.isCompleted = true
        reminder.completionDate = Calendar.current.date(byAdding: .hour, value: 12, to: day)
        try? store.save(reminder, commit: false)
        return reminder
    }

    /// Uma marcação feita no app: a próxima sincronização percebe que foi o app que mudou.
    func reflectCompletion(of habit: Habit, on day: Date, completed: Bool) async {
        guard syncEnabled else { return }
        scheduleSync(HabitStore.shared)
    }

    /// Remove o lembrete recorrente de um hábito que foi excluído (o histórico fica).
    func removeReminders(forHabit habitID: UUID) async {
        guard syncEnabled, let list = remindersList() else { return }
        var masters = masterIndex
        if let reminderID = masters[habitID.uuidString],
           let master = await reminders(in: list).first(where: { $0.calendarItemIdentifier == reminderID }) {
            try? store.remove(master, commit: true)
        }
        masters[habitID.uuidString] = nil
        masterIndex = masters
    }
}
