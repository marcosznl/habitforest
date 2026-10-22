import AppIntents
import SwiftUI
import WidgetKit

@main
struct HabitForestWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitWidget()
    }
}

/// Widget interativo de mesa: a matriz de hábitos fixada no papel de parede, com um
/// botão "Regar Árvore" por hábito.
struct HabitWidget: Widget {
    let kind = "HabitForestMatrix"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitTimelineProvider()) { entry in
            HabitWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    SceneLayers(scenery: Scenery(date: entry.date), animated: false, showsHills: true)
                        .overlay(Color.black.opacity(0.15))
                }
                .widgetURL(URL(string: "habitforest://habitos"))
        }
        .configurationDisplayName("Floresta de Hábitos")
        .description("Sua matriz de hábitos com árvores que crescem a cada dia.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]
}

struct HabitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: .now, habits: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        let habits = SnapshotStore.load().habits
        completion(HabitEntry(date: .now, habits: habits.isEmpty && context.isPreview ? Self.sample : habits))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let habits = SnapshotStore.load().habits
        // Atualiza à meia-noite (nova coluna) e de hora em hora para o fundo acompanhar o horário.
        let now = Date.now
        let entries = (0..<6).map { offset in
            HabitEntry(date: Calendar.current.date(byAdding: .hour, value: offset, to: now) ?? now, habits: habits)
        }
        completion(Timeline(entries: entries, policy: .after(min(DayMath.nextMidnight(), entries.last!.date.addingTimeInterval(3600)))))
    }

    static let sample: [WidgetHabit] = [
        ("Ler", TreeSpecies.oak, 18), ("Programar", .pine, 33), ("Meditar", .cherry, 6), ("Correr", .birch, 2),
    ].map { name, species, streak in
        let days = DayMath.days(count: 30).enumerated().map { index, day in
            DaySnapshot(date: day, state: index % 9 == 4 ? .missed : .completed, streak: max(0, streak - (29 - index)), health: .healthy)
        }
        return WidgetHabit(id: UUID(), name: name, species: species, colorHex: species.defaultHex,
                           streak: streak, health: .healthy, isPaused: false, days: days)
    }
}

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitEntry

    init(entry: HabitEntry) {
        Typography.register()
        self.entry = entry
    }

    var body: some View {
        if entry.habits.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.rubik(.title))
                Text("Abra o HabitForest para plantar seu primeiro hábito.")
                    .font(.inter(.caption)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
        } else {
            switch family {
            case .systemSmall: SmallForest(habits: Array(entry.habits.prefix(4)))
            case .systemMedium: MatrixWidget(habits: Array(entry.habits.prefix(4)), days: 14, nameWidth: 92)
            case .systemLarge: MatrixWidget(habits: Array(entry.habits.prefix(8)), days: 21, nameWidth: 92)
            default: MatrixWidget(habits: Array(entry.habits.prefix(8)), days: 30, nameWidth: 130)
            }
        }
    }
}

/// Árvores em 2×2, cada uma um botão que rega o hábito.
private struct SmallForest: View {
    let habits: [WidgetHabit]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                ForEach(habits.prefix(2)) { tile($0) }
            }
            if habits.count > 2 {
                GridRow {
                    ForEach(habits.dropFirst(2).prefix(2)) { tile($0) }
                }
            }
        }
    }

    private func tile(_ habit: WidgetHabit) -> some View {
        Button(intent: ToggleHabitIntent(habit: HabitEntity(habit))) {
            VStack(spacing: 0) {
                TreeView(species: habit.species, stage: habit.stage, health: habit.health, tint: Color(hex: habit.colorHex))
                Text("\(habit.streak)d")
                    .font(.inter(.caption2, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(4)
            .background(.white.opacity(habit.completedToday ? 0.25 : 0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct MatrixWidget: View {
    let habits: [WidgetHabit]
    let days: Int
    let nameWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hábitos").font(.rubik(.headline, weight: .semibold))
                Spacer()
                let done = habits.filter(\.completedToday).count
                Text("\(done)/\(habits.count) hoje").font(.inter(.caption).monospacedDigit())
            }
            .foregroundStyle(.white)

            ForEach(habits) { habit in
                HStack(spacing: 6) {
                    Button(intent: ToggleHabitIntent(habit: HabitEntity(habit))) {
                        ZStack {
                            Circle().fill(.white.opacity(habit.completedToday ? 0.3 : 0.1))
                            TreeView(species: habit.species, stage: habit.stage, health: habit.health,
                                     tint: Color(hex: habit.colorHex), showsGround: false)
                                .padding(2)
                        }
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)

                    Text(habit.name)
                        .font(.inter(.caption, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: nameWidth - 32, alignment: .leading)

                    GeometryReader { proxy in
                        let spacing: CGFloat = 2
                        let side = min(14, (proxy.size.width - spacing * CGFloat(days - 1)) / CGFloat(days))
                        HStack(spacing: spacing) {
                            ForEach(habit.window(days: days), id: \.date) { day in
                                WidgetCell(day: day, tint: Color(hex: habit.colorHex))
                                    .frame(width: side, height: side)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: 26)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetCell: View {
    let day: DaySnapshot
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay {
                if day.state == .pending {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 1]))
                }
            }
            .widgetAccentable(day.state == .completed)
    }

    private var fill: Color {
        switch day.state {
        case .completed:
            let base = day.health == .healthy ? tint : tint.mixed(with: .orange, amount: 0.5)
            return base.opacity(0.45 + 0.13 * Double(day.stage.rawValue))
        case .missed: return Color.brown.opacity(day.health == .withered ? 0.55 : 0.35)
        case .frozen: return Color.cyan.opacity(0.45)
        case .pending: return .white.opacity(0.08)
        case .beforeStart: return .white.opacity(0.05)
        }
    }
}
