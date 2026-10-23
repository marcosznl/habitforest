import Foundation
import WidgetKit

/// Uma marcação feita fora do processo do app (botão do widget, Atalhos) esperando para ser aplicada
/// ao banco SwiftData pelo app.
struct PendingAction: Codable, Hashable, Sendable {
    var id = UUID()
    var habitID: UUID
    var day: Date
    var completed: Bool
}

enum PendingActionQueue {
    static var url: URL { AppGroup.containerURL.appending(path: "pending-actions.json") }

    static func enqueue(_ action: PendingAction) {
        var actions = load()
        actions.removeAll { $0.habitID == action.habitID && $0.day == action.day }
        actions.append(action)
        write(actions)
    }

    /// Devolve todas as ações na fila e a esvazia.
    static func drain() -> [PendingAction] {
        let actions = load()
        if !actions.isEmpty { write([]) }
        return actions
    }

    private static func load() -> [PendingAction] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingAction].self, from: data)) ?? []
    }

    private static func write(_ actions: [PendingAction]) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Ponto de entrada para marcações que podem rodar dentro da extensão do widget.
enum HabitActionRelay {
    static let pendingActionsNotification = Notification.Name("com.marcosznl.habitos.pendingActions")

    /// Inverte o estado de hoje do hábito no snapshot, enfileira para o app e acorda o app.
    @discardableResult
    static func toggleToday(habitID: UUID) -> Bool {
        var snapshot = SnapshotStore.load()
        var newValue = true
        if let index = snapshot.habits.firstIndex(where: { $0.id == habitID }) {
            newValue = !snapshot.habits[index].completedToday
            snapshot.habits[index].applyToday(completed: newValue)
            SnapshotStore.save(snapshot, reloadWidgets: false)
        }
        PendingActionQueue.enqueue(PendingAction(habitID: habitID, day: DayMath.today(), completed: newValue))
        DistributedNotificationCenter.default().postNotificationName(
            pendingActionsNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        WidgetCenter.shared.reloadAllTimelines()
        return newValue
    }
}
