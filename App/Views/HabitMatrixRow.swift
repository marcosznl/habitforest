import SwiftUI

/// Medidas compartilhadas entre o cabeçalho de dias e as linhas, para as colunas ficarem alinhadas.
struct HabitMatrixLayout {
    static let dayCount = 14
    static let nameWidth: CGFloat = 250
    static let actionWidth: CGFloat = 64
    static let spacing: CGFloat = 6
    static let rowPadding: CGFloat = 12
    static let columnGap: CGFloat = 14

    let cell: CGFloat

    /// Ajusta o tamanho das células para as duas semanas ocuparem a largura disponível.
    init(width: CGFloat) {
        let fixed = Self.nameWidth + Self.actionWidth + Self.rowPadding * 2 + Self.columnGap * 2
        let available = width - fixed - Self.spacing * CGFloat(Self.dayCount - 1)
        cell = min(46, max(18, (available / CGFloat(Self.dayCount)).rounded(.down)))
    }
}

/// Um hábito: sua árvore viva, as últimas duas semanas e o botão de regar hoje.
struct HabitMatrixRow: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    var layout: HabitMatrixLayout
    var onEdit: () -> Void

    @State private var notePopoverDay: Date? = nil
    @State private var noteDraft = ""
    @State private var choosingSpecies = false

    var body: some View {
        let calculator = habit.calculator()
        let days = calculator.window(days: HabitMatrixLayout.dayCount)
        let summary = calculator.summary()

        HStack(spacing: HabitMatrixLayout.columnGap) {
            header(summary: summary)
                .frame(width: HabitMatrixLayout.nameWidth, alignment: .leading)

            HStack(spacing: HabitMatrixLayout.spacing) {
                ForEach(days, id: \.date) { day in
                    TreeCellView(day: day, species: habit.species, tint: habit.themeColor,
                                 note: habit.log(on: day.date)?.dailyNote, size: layout.cell)
                        .onTapGesture { tap(day) }
                        .popover(isPresented: notePopoverBinding(for: day.date), arrowEdge: .bottom) {
                            NoteEntryView(habitName: habit.name, date: day.date, text: $noteDraft) {
                                store.setNote(noteDraft, for: habit, on: day.date)
                                notePopoverDay = nil
                            }
                        }
                }
            }

            waterButton(done: summary.completedToday)
                .frame(width: HabitMatrixLayout.actionWidth)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, HabitMatrixLayout.rowPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(habit.isPausedInGreenhouse ? 0.7 : 1)
        .contextMenu { contextMenu }
    }

    private func header(summary: StreakCalculator.Summary) -> some View {
        HStack(spacing: 10) {
            Button { choosingSpecies = true } label: {
                TreeEmblemView(species: habit.species, stage: summary.stage, health: summary.health,
                               tint: habit.themeColor, animated: true)
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .help("\(habit.species.title) — clique para trocar a árvore")
            .popover(isPresented: $choosingSpecies, arrowEdge: .trailing) {
                SpeciesPicker(selection: Binding(
                    get: { habit.species },
                    set: { species in
                        habit.species = species
                        habit.themeColorHex = species.defaultHex
                        store.habitDidChange()
                        Haptics.perform(.alignment)
                    }
                ), stage: max(summary.stage, .young))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(habit.name).font(.rubik(.headline, weight: .semibold)).lineLimit(1)
                    if habit.isPausedInGreenhouse {
                        Image(systemName: "snowflake").foregroundStyle(.cyan).help("Na Estufa")
                    }
                }
                Text(streakText(summary))
                    .font(.inter(.caption))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    HealthBadge(health: summary.health)
                    if habit.targetMinutes > 0 {
                        Text("\(habit.focusMinutesToday)/\(habit.targetMinutes) min hoje")
                            .font(.inter(.caption2).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// "3 dias seguidos · falta 1 para Árvore Jovem"
    private func streakText(_ summary: StreakCalculator.Summary) -> String {
        let streak = summary.currentStreak == 1 ? "1 dia seguido" : "\(summary.currentStreak) dias seguidos"
        let next: (Int, GrowthStage)? = switch summary.stage {
        case .seed: (1, .sprout)
        case .sprout: (4, .young)
        case .young: (15, .mature)
        case .mature: (31, .ancient)
        case .ancient: nil
        }
        guard let (goal, stage) = next else { return "\(streak) · \(summary.stage.title)" }
        let missing = goal - summary.currentStreak
        return "\(streak) · \(missing == 1 ? "falta 1" : "faltam \(missing)") para \(stage.title)"
    }

    private func waterButton(done: Bool) -> some View {
        Button {
            let completed = store.toggle(habit)
            if completed { openNote(for: DayMath.today()) }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: done ? "drop.fill" : "drop")
                    .font(.system(size: 20, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(done ? "Regada" : "Regar")
                    .font(.inter(.caption2, weight: .semibold))
            }
            .foregroundStyle(done ? habit.themeColor : .primary)
            .frame(width: 58, height: 50)
            .background(done ? habit.themeColor.opacity(0.22) : Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(habit.isPausedInGreenhouse)
        .help(habit.isPausedInGreenhouse ? "Hábito na Estufa" : (done ? "Desfazer a rega de hoje" : "Regar a árvore hoje"))
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Regar hoje", systemImage: "drop.fill") { store.toggle(habit) }
        Button("Nota de hoje…", systemImage: "square.and.pencil") { openNote(for: DayMath.today()) }
        Menu("Trocar árvore") {
            ForEach(TreeSpecies.allCases) { species in
                Button(species.title) {
                    habit.species = species
                    habit.themeColorHex = species.defaultHex
                    store.habitDidChange()
                }
            }
        }
        Divider()
        Button(habit.isPausedInGreenhouse ? "Sair da Estufa" : "Levar para a Estufa",
               systemImage: habit.isPausedInGreenhouse ? "sun.max" : "snowflake") {
            store.setGreenhouse(habit, paused: !habit.isPausedInGreenhouse)
        }
        Button("Editar…", systemImage: "pencil", action: onEdit)
        Divider()
        Button("Excluir", systemImage: "trash", role: .destructive) { store.delete(habit) }
    }

    private func tap(_ day: DaySnapshot) {
        // Um dia anterior ao plantio pode ser marcado, mas não muda a data de plantio.
        let completed = store.toggle(habit, on: day.date)
        if completed && day.date == DayMath.today() {
            openNote(for: day.date)
        }
    }

    private func openNote(for day: Date) {
        noteDraft = habit.log(on: day)?.dailyNote ?? ""
        notePopoverDay = DayMath.start(of: day)
    }

    private func notePopoverBinding(for day: Date) -> Binding<Bool> {
        Binding(
            get: { notePopoverDay == day },
            set: { if !$0 { notePopoverDay = nil } }
        )
    }
}

/// Cabeçalho da matriz: dia da semana e dia do mês de cada coluna, com "Hoje" em destaque.
struct HabitMatrixHeader: View {
    var layout: HabitMatrixLayout

    var body: some View {
        HStack(spacing: HabitMatrixLayout.columnGap) {
            Text("Hábito")
                .font(.inter(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: HabitMatrixLayout.nameWidth, alignment: .leading)
            HStack(spacing: HabitMatrixLayout.spacing) {
                ForEach(DayMath.days(count: HabitMatrixLayout.dayCount), id: \.self) { day in
                    let isToday = day == DayMath.today()
                    VStack(spacing: 0) {
                        Text(isToday ? "Hoje" : day.formatted(.dateTime.weekday(layout.cell >= 34 ? .abbreviated : .narrow)))
                            .font(.inter(.caption2, weight: isToday ? .bold : .regular))
                            .fixedSize()
                        Text(day.formatted(.dateTime.day()))
                            .font(.inter(.caption2, weight: isToday ? .bold : .regular).monospacedDigit())
                    }
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    .frame(width: layout.cell)
                }
            }
            Text("Hoje")
                .font(.inter(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: HabitMatrixLayout.actionWidth)
        }
        .padding(.horizontal, HabitMatrixLayout.rowPadding)
    }
}

/// Grade com as espécies para escolher a árvore de um hábito.
struct SpeciesPicker: View {
    @Binding var selection: TreeSpecies
    var stage: GrowthStage = .mature

    private let columns = Array(repeating: GridItem(.fixed(84)), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Escolha a árvore").font(.rubik(.headline, weight: .semibold))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(TreeSpecies.allCases) { species in
                    Button { selection = species } label: {
                        VStack(spacing: 2) {
                            TreeView(species: species, stage: stage, animated: species == selection)
                                .frame(width: 60, height: 60)
                            Text(species.title).font(.inter(.caption))
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(species == selection ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(species == selection ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }
}

/// Anotação de uma linha mostrada depois de regar.
struct NoteEntryView: View {
    let habitName: String
    var date: Date = .now
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diário · \(habitName)", systemImage: "book.closed.fill")
                .font(.inter(.subheadline, weight: .semibold))
            Text(DayMath.start(of: date) == DayMath.today() ? "Árvore regada! Quer anotar algo sobre hoje?"
                 : date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.inter(.caption))
                .foregroundStyle(.secondary)
            TextField("Uma linha sobre o dia (opcional)", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("Salvar", action: onSave).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}
