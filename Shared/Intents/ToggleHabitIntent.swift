import AppIntents
import Foundation

/// Um hábito como Atalhos, Siri e os botões do widget o veem. Vem do snapshot do widget, então
/// é resolvido do mesmo jeito no app e na extensão do widget em sandbox.
struct HabitEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Hábito"
    static var defaultQuery = HabitEntityQuery()

    var id: UUID
    var name: String
    var speciesTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(speciesTitle)")
    }

    init(id: UUID, name: String, speciesTitle: String) {
        self.id = id
        self.name = name
        self.speciesTitle = speciesTitle
    }

    init(_ habit: WidgetHabit) {
        self.init(id: habit.id, name: habit.name, speciesTitle: habit.species.title)
    }
}

struct HabitEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        SnapshotStore.load().habits.filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        SnapshotStore.load().habits.filter { !$0.isPaused }.map(HabitEntity.init)
    }
}

/// "Regar Árvore": alterna a conclusão de hoje. Usado pelo widget interativo e por Atalhos.
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Regar Árvore"
    static var description = IntentDescription("Marca ou desmarca o hábito de hoje na sua floresta.")

    @Parameter(title: "Hábito")
    var habit: HabitEntity

    init() {}

    init(habit: HabitEntity) {
        self.habit = habit
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let completed = HabitActionRelay.toggleToday(habitID: habit.id)
        let message = completed ? "\(habit.name) foi regada 🌳" : "\(habit.name) foi desmarcada"
        return .result(dialog: "\(message)")
    }
}
