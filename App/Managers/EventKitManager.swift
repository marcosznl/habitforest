import AppKit
import EventKit
import Observation

/// Blocos de tempo no Calendário para sessões de foco e sincronização dos hábitos com o Lembretes nos dois sentidos.
@MainActor
@Observable
final class EventKitManager {
    static let shared = EventKitManager()

    static let calendarTitle = "HabitForest"
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

    /// Grava uma sessão de foco concluída (ou planejada) como bloco de tempo no calendário HabitForest.
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
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) {
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

    // MARK: - Sincronização com o Lembretes
    //
    // Cada hábito ganha um lembrete por dia na lista "HabitForest", identificado por um marcador
    // `habitforest://habit/<id>?day=<aaaa-mm-dd>` (na URL e nas notas, porque o Lembretes nem sempre
    // preserva a URL). A sincronização é nos dois sentidos e guarda o último estado combinado de cada
    // lembrete: assim dá para saber quem mudou desde a última vez, o app ou o Lembretes, e quem
    // mudou vence. Ela roda ao abrir o app, na virada do dia e sempre que o Lembretes muda
    // (inclusive marcações feitas no iPhone que chegam pelo iCloud) enquanto o app está aberto,
    // mesmo só na barra de menus. Com o app fechado, o que mudou é conciliado na próxima abertura,
    // olhando os últimos 14 dias.

    private static let catchUpDays = 14
    private static let syncStateKey = "remindersSyncState"

    private var syncEnabled: Bool { AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) && remindersAuthorized }
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    private(set) var lastReminderSync: Date?

    /// Último estado (regado ou não) combinado entre app e Lembretes, por marcador.
    private var syncState: [String: Bool] {
        get { AppGroup.defaults.dictionary(forKey: Self.syncStateKey) as? [String: Bool] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: Self.syncStateKey) }
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
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == Self.calendarTitle }) {
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

    private func marker(habitID: UUID, day: Date) -> String {
        "\(Self.urlScheme)://habit/\(habitID.uuidString)?day=\(DayMath.key(day))"
    }

    private static let markerPattern = /habitforest:\/\/habit\/([0-9A-Fa-f-]{36})\?day=(\d{4}-\d{2}-\d{2})/

    /// Lê o marcador do lembrete (URL ou notas) e devolve o hábito e o dia a que ele pertence.
    private func parseMarker(_ reminder: EKReminder) -> (habitID: UUID, day: Date, key: String)? {
        for text in [reminder.url?.absoluteString, reminder.notes].compactMap({ $0 }) {
            guard let match = text.firstMatch(of: Self.markerPattern),
                  let id = UUID(uuidString: String(match.1)),
                  let day = DayMath.date(fromKey: String(match.2)) else { continue }
            return (id, day, marker(habitID: id, day: day))
        }
        return nil
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
        var covered = Set<String>()

        for reminder in await reminders(in: list) {
            guard let (habitID, day, key) = parseMarker(reminder), day >= oldest else { continue }
            covered.insert(key)

            guard let habit = habitStore.habit(id: habitID) else {
                // Hábito excluído: tira os lembretes pendentes dele.
                if !reminder.isCompleted { try? store.remove(reminder, commit: false) }
                state[key] = nil
                continue
            }
            if habit.isPausedInGreenhouse && !reminder.isCompleted && day >= today {
                try? store.remove(reminder, commit: false)
                state[key] = nil
                continue
            }

            let inApp = habit.isCompleted(on: day)
            let inReminders = reminder.isCompleted
            if inApp != inReminders {
                let remindersChanged = state[key].map { $0 != inReminders } ?? inReminders
                if remindersChanged {
                    habitStore.setCompleted(habit, on: day, completed: inReminders, feedback: false)
                } else {
                    reminder.isCompleted = inApp
                    try? store.save(reminder, commit: false)
                }
            }

            let final = habit.isCompleted(on: day)
            if day < today && !final {
                try? store.remove(reminder, commit: false)
                state[key] = nil
            } else {
                state[key] = final
            }
        }

        for habit in habitStore.habits where !habit.isPausedInGreenhouse {
            for day in [today, DayMath.add(1, to: today)] {
                let key = marker(habitID: habit.id, day: day)
                guard !covered.contains(key) else { continue }
                let done = habit.isCompleted(on: day)
                createReminder(for: habit, on: day, marker: key, completed: done, in: list)
                state[key] = done
            }
        }

        // Esquece estados de dias que saíram da janela.
        state = state.filter { key, _ in
            guard let dayKey = key.split(separator: "=").last, let day = DayMath.date(fromKey: String(dayKey)) else { return false }
            return day >= oldest
        }
        syncState = state
        try? store.commit()
        lastReminderSync = .now
    }

    private func createReminder(for habit: Habit, on day: Date, marker key: String, completed: Bool, in list: EKCalendar) {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = "🌳 \(habit.name)"
        reminder.url = URL(string: key)
        reminder.notes = "Marque para regar sua árvore no HabitForest.\n\(key)"
        var due = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if habit.reminderEnabled {
            due.hour = habit.reminderHour
            due.minute = habit.reminderMinute
        }
        reminder.dueDateComponents = due
        reminder.isCompleted = completed
        try? store.save(reminder, commit: false)
    }

    /// Espelha no lembrete uma marcação feita no app, se a sincronização estiver ligada.
    func reflectCompletion(of habit: Habit, on day: Date, completed: Bool) async {
        guard syncEnabled, !isSyncing, let list = remindersList() else { return }
        let key = marker(habitID: habit.id, day: day)
        guard let reminder = await reminders(in: list).first(where: { parseMarker($0)?.key == key }) else { return }
        if reminder.isCompleted != completed {
            reminder.isCompleted = completed
            try? store.save(reminder, commit: true)
        }
        var state = syncState
        state[key] = completed
        syncState = state
    }

    /// Remove os lembretes pendentes de um hábito que foi excluído.
    func removeReminders(forHabit habitID: UUID) async {
        guard syncEnabled, let list = remindersList() else { return }
        for reminder in await reminders(in: list) where !reminder.isCompleted && parseMarker(reminder)?.habitID == habitID {
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()
    }
}
