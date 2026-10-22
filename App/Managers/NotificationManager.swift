import Foundation
import UserNotifications

/// Lembretes diários com botões de ação ("Regar Árvore", "Adiar 15 min") direto no banner.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    enum Identifier {
        static let reminderCategory = "HABIT_REMINDER"
        static let focusCategory = "FOCUS_COMPLETE"
        static let waterAction = "WATER_TREE"
        static let snoozeAction = "SNOOZE_15"
        static let habitIDKey = "habitID"
        static let reminderPrefix = "habit-"
    }

    private let center = UNUserNotificationCenter.current()
    private(set) var isAuthorized = false

    func configure() {
        center.delegate = self
        let water = UNNotificationAction(identifier: Identifier.waterAction, title: "Regar Árvore",
                                         options: [], icon: UNNotificationActionIcon(systemImageName: "drop.fill"))
        let snooze = UNNotificationAction(identifier: Identifier.snoozeAction, title: "Adiar 15 min",
                                          options: [], icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        let reminder = UNNotificationCategory(identifier: Identifier.reminderCategory, actions: [water, snooze],
                                              intentIdentifiers: [], options: [])
        let focus = UNNotificationCategory(identifier: Identifier.focusCategory, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([reminder, focus])
        Task { await refreshAuthorization() }
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    private func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: - Agendamento

    /// Agenda lembretes avulsos para os próximos dias, pulando os dias já concluídos.
    /// Pedidos avulsos (em vez de um gatilho repetido) deixam um hábito concluído em silêncio hoje.
    func reschedule(for habits: [Habit]) {
        guard !DemoMode.isActive else { return }
        let plans: [(id: String, content: UNMutableNotificationContent, date: DateComponents)] = habits
            .filter { $0.reminderEnabled && !$0.isPausedInGreenhouse }
            .flatMap { habit -> [(id: String, content: UNMutableNotificationContent, date: DateComponents)] in
                let daysAhead = max(1, 60 / max(1, habits.count))
                return (0..<min(7, daysAhead)).compactMap { offset in
                    let day = DayMath.add(offset, to: .now)
                    guard !habit.isCompleted(on: day) else { return nil }
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
                    components.hour = habit.reminderHour
                    components.minute = habit.reminderMinute
                    guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return nil }
                    return ("\(Identifier.reminderPrefix)\(habit.id.uuidString)-\(DayMath.key(day))",
                            reminderContent(for: habit), components)
                }
            }

        Task {
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Identifier.reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for plan in plans {
                let trigger = UNCalendarNotificationTrigger(dateMatching: plan.date, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: plan.id, content: plan.content, trigger: trigger))
            }
        }
    }

    private func reminderContent(for habit: Habit) -> UNMutableNotificationContent {
        let summary = habit.summary
        let content = UNMutableNotificationContent()
        content.title = "Hora de regar: \(habit.name)"
        content.body = switch summary.health {
        case .healthy: summary.currentStreak > 0
            ? "Sua árvore está há \(summary.currentStreak.diasTexto) crescendo. Não pare agora!"
            : "Plante hoje a primeira semente."
        case .struggling: "As folhas estão caindo… regue hoje para salvar a sequência."
        case .withered: "Sua árvore secou. Que tal plantar de novo hoje?"
        }
        content.categoryIdentifier = Identifier.reminderCategory
        content.userInfo = [Identifier.habitIDKey: habit.id.uuidString]
        content.threadIdentifier = habit.id.uuidString
        applyFocusPolicy(to: content)
        return content
    }

    private func applyFocusPolicy(to content: UNMutableNotificationContent) {
        if FocusFilterState.current.muteReminders {
            content.interruptionLevel = .passive
            content.sound = nil
        } else {
            content.interruptionLevel = .active
            content.sound = .default
        }
    }

    private func snooze(habitID: String, original: UNNotificationContent) async {
        guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
        content.title = "Lembrete adiado: " + original.title.replacingOccurrences(of: "Hora de regar: ", with: "")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "snooze-\(habitID)-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    func notifyFocusFinished(habitName: String?, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Sessão de foco concluída 🌲"
        content.body = habitName.map { "\(minutes) min dedicados a \($0). Sua floresta agradece." }
            ?? "\(minutes) minutos de foco. Respire e descanse."
        content.categoryIdentifier = Identifier.focusCategory
        applyFocusPolicy(to: content)
        center.add(UNNotificationRequest(identifier: "focus-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let muted = await MainActor.run { FocusFilterState.current.muteReminders }
        return muted ? [.list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let habitID = content.userInfo[Identifier.habitIDKey] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Identifier.waterAction:
                if let habitID, let uuid = UUID(uuidString: habitID), let habit = HabitStore.shared.habit(id: uuid) {
                    HabitStore.shared.setCompleted(habit, completed: true)
                }
            case Identifier.snoozeAction:
                if let habitID { Task { await self.snooze(habitID: habitID, original: content) } }
            case UNNotificationDefaultActionIdentifier:
                MainWindowController.shared.show()
            default:
                break
            }
        }
    }
}
