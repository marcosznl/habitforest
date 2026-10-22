import SwiftUI

/// Um dia na matriz de hábitos: a árvore como estava no fim daquele dia.
struct TreeCellView: View {
    let day: DaySnapshot
    let species: TreeSpecies
    let tint: Color
    var note: String?
    var size: CGFloat = 26

    @State private var isHovering = false

    private var isToday: Bool { day.date == DayMath.today() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(background)
            content
                .padding(size * 0.06)
            if note != nil {
                Circle()
                    .fill(tint)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: size * 0.32, y: -size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: day.state == .pending ? [3, 2] : []))
            }
        }
        .scaleEffect(isHovering ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    @ViewBuilder
    private var content: some View {
        switch day.state {
        case .completed:
            TreeView(species: species, stage: day.stage, health: day.health, tint: tint, showsGround: false)
        case .missed:
            StumpView().opacity(day.health == .withered ? 0.9 : 0.6)
        case .frozen:
            Image(systemName: "snowflake")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.cyan)
        case .pending:
            Image(systemName: "drop")
                .font(.system(size: size * 0.4))
                .foregroundStyle(tint.opacity(0.8))
        case .beforeStart:
            Circle().fill(.secondary.opacity(0.25)).frame(width: size * 0.12)
        }
    }

    private var background: Color {
        switch day.state {
        case .completed: tint.opacity(0.10 + 0.06 * Double(day.stage.rawValue))
        case .missed: Color.brown.opacity(0.12)
        case .frozen: Color.cyan.opacity(0.12)
        case .pending: tint.opacity(0.06)
        case .beforeStart: Color.primary.opacity(0.03)
        }
    }

    private var tooltip: String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let state: String = switch day.state {
        case .completed: "Regada · \(day.stage.title) (\(day.streak) dias)"
        case .missed: day.health == .withered ? "Não regada · árvore seca" : "Não regada · perdendo folhas"
        case .frozen: "Na Estufa"
        case .pending: "Pendente — clique para regar"
        case .beforeStart: "Antes do plantio"
        }
        return [date, state, note.map { "“\($0)”" }].compactMap { $0 }.joined(separator: "\n")
    }
}
