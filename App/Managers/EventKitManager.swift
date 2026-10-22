import AppKit
import EventKit
import Observation

/// Blocos de tempo no Calendário para sessões de foco e sincronização dos hábitos com o Lembretes nos dois sentidos.
@MainActor
@Observable
final class EventKitManager {
    static let shared = EventKitManager()

    static let calendarTitle = "Hábitos"
    /// Nome usado antes da troca do nome do app; a lista/calendário antigo é renomeado.
    private static let legacyCalendarTitle = "HabitForest"
    private static let urlScheme = "habitforest"

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
    /// pede uma vez e já sincroniza (criando a lista HabitForest).
    func prepareRemindersSync(_ habitStore: HabitStore) async {
        guard AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) else { return }
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

    /// Calendário ou lista do app; se ainda estiver com o nome antigo, renomeia para "Hábitos".
    private func existingCalendar(for type: EKEntityType) -> EKCalendar? {
        let calendars = store.calendars(for: type)
        if let current = calendars.first(where: { $0.title == Self.calendarTitle }) {
            return current
        }
        guard let legacy = calendars.first(where: { $0.title == Self.legacyCalendarTitle }) else { return nil }
        legacy.title = Self.calendarTitle
        try? store.saveCalendar(legacy, commit: true)
        return legacy
    }

    // MARK: - Sincronização com o Lembretes
    //
    // Cada hábito ganha um lembrete por dia na lista "Hábitos", só com o nome do hábito e a
    // data. O app guarda um índice (identificador do lembrete → hábito e dia); se o índice não
    // conhecer um lembrete, ele é reconhecido pelo nome do hábito e pela data. A sincronização é
    // nos dois sentidos e guarda o último estado combinado de cada lembrete: assim dá para saber
    // quem mudou desde a última vez, o app ou o Lembretes, e quem mudou vence. Ela roda ao abrir o
    // app, na virada do dia e sempre que o Lembretes muda (inclusive marcações feitas no iPhone que
    // chegam pelo iCloud) enquanto o app está aberto, mesmo só na barra de menus. Com o app fechado,
    // o que mudou é conciliado na próxima abertura, olhando os últimos 14 dias.

    private static let catchUpDays = 14
    private static let syncStateKey = "remindersSyncState"
    private static let indexKey = "remindersIndex"

    private var syncEnabled: Bool { AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) && remindersAuthorized }
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    private(set) var lastReminderSync: Date?

    /// Último estado (regado ou não) combinado entre app e Lembretes, por hábito e dia.
    private var syncState: [String: Bool] {
        get { AppGroup.defaults.dictionary(forKey: Self.syncStateKey) as? [String: Bool] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.syncStateKey) }
    }

    /// Identificador de cada lembrete criado → chave do hábito e dia que ele representa.
    private var reminderIndex: [String: String] {
        get { AppGroup.defaults.dictionary(forKey: Self.indexKey) as? [String: String] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.indexKey) }
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

    private typealias ReminderTarget = (habitID: UUID, day: Date, key: String)

    private func key(habitID: UUID, day: Date) -> String {
        "\(habitID.uuidString)|\(DayMath.key(day))"
    }

    private func parseKey(_ key: String) -> ReminderTarget? {
        let parts = key.split(separator: "|")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let day = DayMath.date(fromKey: String(parts[1])) else { return nil }
        return (id, day, key)
    }

    /// Marcador usado pelas versões anteriores (na URL e nas notas), para migrar os lembretes antigos.
    private static let legacyMarker = /habitforest:\/\/habit\/([0-9A-Fa-f-]{36})\?day=(\d{4}-\d{2}-\d{2})/

    /// Descobre a que hábito e dia o lembrete pertence: pelo índice, pelo marcador antigo ou,
    /// por último, pelo nome do hábito e pela data.
    private func identify(_ reminder: EKReminder, habits: [Habit], index: [String: String]) -> ReminderTarget? {
        if let stored = index[reminder.calendarItemIdentifier], let target = parseKey(stored) {
            return target
        }
        for text in [reminder.url?.absoluteString, reminder.notes].compactMap({ $0 }) {
            if let match = text.firstMatch(of: Self.legacyMarker),
               let id = UUID(uuidString: String(match.1)),
               let day = DayMath.date(fromKey: String(match.2)) {
                return (id, day, key(habitID: id, day: day))
            }
        }
        let title = (reminder.title ?? "").replacingOccurrences(of: "🌳", with: "").trimmingCharacters(in: .whitespaces)
        guard let habit = habits.first(where: { $0.name == title }),
              let components = reminder.dueDateComponents,
              let due = Calendar.current.date(from: components) else { return nil }
        let day = DayMath.start(of: due)
        return (habit.id, day, key(habitID: habit.id, day: day))
    }

    /// Deixa o lembrete só com o nome do hábito: tira emoji, texto e link de versões anteriores.
    private func clean(_ reminder: EKReminder, for habit: Habit) -> Bool {
        var changed = false
        if reminder.title != habit.name {
            reminder.title = habit.name
            changed = true
        }
        if reminder.url?.scheme == Self.urlScheme {
            reminder.url = nil
            changed = true
        }
        if let notes = reminder.notes, notes.contains("\(Self.urlScheme)://") {
            reminder.notes = nil
            changed = true
        }
        return changed
    }

    private func reminders(in list: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [list])) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Concilia os últimos 14 dias nos dois sentidos, cria os lembretes de hoje e de amanhã e
    /// remove lembretes de dias que já passaram sem rega (para a lista não acumular atrasados).
    func syncReminders(store habitStore: HabitStore) async {
        guard syncEnabled, !isSyncing, let list = remindersList() else { return }
        isSyncing = true
        defer { isSyncing = false }

        let today = DayMath.today()
        let oldest = DayMath.add(-(Self.catchUpDays - 1), to: today)
        var state = syncState
        var index = reminderIndex
        var covered = Set<String>()

        for reminder in await reminders(in: list) {
            let id = reminder.calendarItemIdentifier
            guard let (habitID, day, key) = identify(reminder, habits: habitStore.habits, index: index), day >= oldest else { continue }
            guard !covered.contains(key) else { continue }
            covered.insert(key)

            guard let habit = habitStore.habit(id: habitID) else {
                // Hábito excluído: tira os lembretes pendentes dele.
                if !reminder.isCompleted { try? store.remove(reminder, commit: false) }
                state[key] = nil
                index[id] = nil
                continue
            }
            if habit.isPausedInGreenhouse && !reminder.isCompleted && day >= today {
                try? store.remove(reminder, commit: false)
                state[key] = nil
                index[id] = nil
                continue
            }

            var needsSave = clean(reminder, for: habit)
            let inApp = habit.isCompleted(on: day)
            let inReminders = reminder.isCompleted
            if inApp != inReminders {
                let remindersChanged = state[key].map { $0 != inReminders } ?? inReminders
                if remindersChanged {
                    habitStore.setCompleted(habit, on: day, completed: inReminders, feedback: false)
                } else {
                    reminder.isCompleted = inApp
                    needsSave = true
                }
            }

            let final = habit.isCompleted(on: day)
            if day < today && !final {
                try? store.remove(reminder, commit: false)
                state[key] = nil
                index[id] = nil
            } else {
                if needsSave { try? store.save(reminder, commit: false) }
                state[key] = final
                index[id] = key
            }
        }

        for habit in habitStore.habits where !habit.isPausedInGreenhouse {
            for day in [today, DayMath.add(1, to: today)] {
                let key = key(habitID: habit.id, day: day)
                guard !covered.contains(key) else { continue }
                let done = habit.isCompleted(on: day)
                if let id = createReminder(for: habit, on: day, completed: done, in: list) {
                    index[id] = key
                    state[key] = done
                }
            }
        }

        // Esquece o que saiu da janela de 14 dias.
        state = state.filter { key, _ in (parseKey(key)?.day ?? .distantPast) >= oldest }
        index = index.filter { _, key in (parseKey(key)?.day ?? .distantPast) >= oldest }
        syncState = state
        reminderIndex = index
        try? store.commit()
        lastReminderSync = .now
    }

    /// Cria o lembrete do dia (só com o nome do hábito e a data) e devolve o identificador dele.
    private func createReminder(for habit: Habit, on day: Date, completed: Bool, in list: EKCalendar) -> String? {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = habit.name
        var due = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if habit.reminderEnabled {
            due.hour = habit.reminderHour
            due.minute = habit.reminderMinute
        }
        reminder.dueDateComponents = due
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: false)
            return reminder.calendarItemIdentifier
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Espelha no lembrete uma marcação feita no app, se a sincronização estiver ligada.
    func reflectCompletion(of habit: Habit, on day: Date, completed: Bool) async {
        guard syncEnabled, !isSyncing, let list = remindersList() else { return }
        let target = key(habitID: habit.id, day: day)
        let index = reminderIndex
        guard let reminder = await reminders(in: list).first(where: { identify($0, habits: [habit], index: index)?.key == target }) else { return }
        if reminder.isCompleted != completed {
            reminder.isCompleted = completed
            try? store.save(reminder, commit: true)
        }
        var state = syncState
        state[target] = completed
        syncState = state
    }

    /// Remove os lembretes pendentes de um hábito que foi excluído.
    func removeReminders(forHabit habitID: UUID) async {
        guard syncEnabled, let list = remindersList() else { return }
        let habits = HabitStore.shared.habits
        let index = reminderIndex
        for reminder in await reminders(in: list)
        where !reminder.isCompleted && identify(reminder, habits: habits, index: index)?.habitID == habitID {
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()
    }
}
