import SwiftUI

/// A habit with its living tree and the continuous 30-day matrix.
struct EverydayHabitRow: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    var index: Int
    var onEdit: () -> Void

    static let dayCount = 30

    @State private var notePopoverDay: Date? = nil
    @State private var noteDraft = ""

    var body: some View {
        let calculator = habit.calculator()
        let days = calculator.window(days: Self.dayCount)
        let summary = calculator.summary()

        HStack(spacing: 16) {
            header(summary: summary)
                .frame(width: 230, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.date) { day in
                        TreeCellView(day: day, species: habit.species, tint: habit.themeColor,
                                     note: habit.log(on: day.date)?.dailyNote)
                            .onTapGesture { tap(day) }
                            .popover(isPresented: notePopoverBinding(for: day.date), arrowEdge: .bottom) {
                                NoteEntryView(habitName: habit.name, text: $noteDraft) {
                                    store.setNote(noteDraft, for: habit, on: day.date)
                                    notePopoverDay = nil
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .defaultScrollAnchor(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(habit.isPausedInGreenhouse ? 0.7 : 1)
        .contextMenu { contextMenu }
    }

    private func header(summary: StreakCalculator.Summary) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TreeView(species: habit.species, stage: summary.stage, health: summary.health,
                         tint: habit.themeColor, animated: true)
                    .frame(width: 52, height: 52)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .padding(3)
                        .background(.regularMaterial, in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(habit.name).font(.headline).lineLimit(1)
                    if habit.isPausedInGreenhouse {
                        Image(systemName: "snowflake").foregroundStyle(.cyan).help("Na Estufa")
                    }
                }
                Text("\(summary.currentStreak) dias · \(summary.stage.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    HealthBadge(health: summary.health)
                    if habit.targetMinutes > 0 {
                        Text("\(habit.focusMinutesToday)/\(habit.targetMinutes) min")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Regar hoje", systemImage: "drop.fill") { store.toggle(habit) }
        Button("Nota de hoje…", systemImage: "square.and.pencil") { openNote(for: DayMath.today()) }
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
        // Tapping a day before the habit existed back-fills it and moves the planting date.
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

/// One-line journal entry shown after watering.
struct NoteEntryView: View {
    let habitName: String
    @Binding var text: String
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diário · \(habitName)", systemImage: "book.closed.fill")
                .font(.subheadline.weight(.semibold))
            TextField("Como foi hoje? (opcional)", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("Salvar", action: onSave).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}
