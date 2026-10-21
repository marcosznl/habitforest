import AppIntents

/// Which macOS Focus a habit belongs to. Used by the Focus Filter to decide what is visible.
enum HabitContext: String, CaseIterable, Codable, Identifiable, AppEnum {
    case any, work, personal

    var id: String { rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Contexto"

    static var caseDisplayRepresentations: [HabitContext: DisplayRepresentation] = [
        .any: DisplayRepresentation(title: "Todos", image: .init(systemName: "circle.grid.2x2")),
        .work: DisplayRepresentation(title: "Trabalho", image: .init(systemName: "briefcase.fill")),
        .personal: DisplayRepresentation(title: "Pessoal", image: .init(systemName: "person.fill")),
    ]

    var title: String {
        switch self {
        case .any: "Todos"
        case .work: "Trabalho"
        case .personal: "Pessoal"
        }
    }

    var symbolName: String {
        switch self {
        case .any: "circle.grid.2x2"
        case .work: "briefcase.fill"
        case .personal: "person.fill"
        }
    }
}
