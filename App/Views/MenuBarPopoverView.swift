import SwiftUI

/// Menu bar popover (⌘⇧H from anywhere). ⌘1…⌘9 water the matching habit.
struct MenuBarPopoverView: View {
    @Environment(HabitStore.self) private var store
    @Environment(FocusSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.activeHabits.isEmpty {
                ContentUnavailableView("Floresta vazia", systemImage: "leaf", description: Text("Plante um hábito no painel."))
                    .frame(height: 160)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(store.activeHabits.prefix(12).enumerated()), id: \.element.id) { index, habit in
                            PopoverHabitRow(habit: habit, number: index < 9 ? index + 1 : nil)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .background(numberShortcuts)
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            SceneBackgroundView(showsHills: true)
                .frame(height: 74)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hoje").font(.title2.weight(.bold))
                    Text("\(store.completedTodayCount) de \(store.activeHabits.count) árvores regadas")
                        .font(.caption)
                }
                Spacer()
                ProgressView(value: Double(store.completedTodayCount), total: Double(max(1, store.activeHabits.count)))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            .foregroundStyle(.white)
            .shadow(radius: 3)
            .padding(12)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            FocusMiniStatus()
            HStack {
                Button {
                    StatusItemController.shared.closePopover()
                    MainWindowController.shared.show()
                } label: {
                    Label("Abrir Floresta", systemImage: "macwindow")
                }
                .keyboardShortcut("o", modifiers: .command)
                Spacer()
                if !session.isActive {
                    Button {
                        session.start(minutes: 25)
                    } label: {
                        Label("Foco 25 min", systemImage: "timer")
                    }
                }
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Sair do HabitForest")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
    }

    /// Invisible buttons that own the ⌘1…⌘9 shortcuts while the popover is key.
    private var numberShortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("") { water(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func water(_ number: Int) {
        let habits = store.activeHabits
        guard number - 1 < habits.count else { return }
        store.toggle(habits[number - 1])
    }
}

private struct PopoverHabitRow: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    let number: Int?

    @State private var hovering = false

    var body: some View {
        let summary = habit.summary
        Button {
            store.toggle(habit)
        } label: {
            HStack(spacing: 10) {
                TreeView(species: habit.species, stage: summary.stage, health: summary.health, tint: habit.themeColor)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name).lineLimit(1)
                    Text("\(summary.currentStreak) dias · \(summary.stage.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let number {
                    Text("⌘\(number)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                Image(systemName: summary.completedToday ? "drop.fill" : "drop")
                    .font(.title3)
                    .foregroundStyle(summary.completedToday ? habit.themeColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
