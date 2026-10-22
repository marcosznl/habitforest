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
    private(set) var todaysEvents: [EKEvent] = []
    var lastError: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
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

    private var syncEnabled: Bool { AppGroup.defaults.bool(forKey: SettingsKey.remindersSync) && remindersAuthorized }

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

    private func marker(for habit: Habit, on day: Date) -> URL? {
        URL(string: "\(Self.urlScheme)://habit/\(habit.id.uuidString)?day=\(DayMath.key(day))")
    }

    private func reminders(in list: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [list])) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// Garante o lembrete de hoje para cada hábito ativo e concilia a conclusão nos dois sentidos:
    /// marcar o lembrete no Lembretes rega a árvore, e regar a árvore aqui marca o lembrete.
    func syncReminders(store habitStore: HabitStore) async {
        guard syncEnabled, let list = remindersList() else { return }
        let today = DayMath.today()
        let existing = await reminders(in: list)

        for habit in habitStore.habits where !habit.isPausedInGreenhouse {
            guard let url = marker(for: habit, on: today) else { continue }
            let doneHere = habit.isCompleted(on: today)
            if let reminder = existing.first(where: { $0.url == url }) {
                if reminder.isCompleted && !doneHere {
                    habitStore.setCompleted(habit, on: today, completed: true, feedback: false)
                } else if doneHere && !reminder.isCompleted {
                    reminder.isCompleted = true
                    try? store.save(reminder, commit: false)
                }
            } else {
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = list
                reminder.title = "🌳 \(habit.name)"
                reminder.url = url
                reminder.notes = "Criado pelo HabitForest — marque aqui para regar sua árvore."
                var due = Calendar.current.dateComponents([.year, .month, .day], from: today)
                if habit.reminderEnabled {
                    due.hour = habit.reminderHour
                    due.minute = habit.reminderMinute
                }
                reminder.dueDateComponents = due
                reminder.isCompleted = doneHere
                try? store.save(reminder, commit: false)
            }
        }
        try? store.commit()
    }

    /// Espelha no lembrete uma marcação feita no app, se a sincronização estiver ligada.
    func reflectCompletion(of habit: Habit, on day: Date, completed: Bool) async {
        guard syncEnabled, let list = remindersList(), let url = marker(for: habit, on: day) else { return }
        guard let reminder = await reminders(in: list).first(where: { $0.url == url }),
              reminder.isCompleted != completed else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
    }
}
