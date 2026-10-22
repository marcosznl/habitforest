import SwiftUI

/// Popover da barra de menus (⌘⇧H de qualquer lugar). Clique num hábito para regá-lo.
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
                        ForEach(store.activeHabits.prefix(12)) { habit in
                            PopoverHabitRow(habit: habit)
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
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            SceneBackgroundView(showsHills: true)
                .frame(height: 74)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hoje").font(.rubik(.title2))
                    Text("\(store.completedTodayCount) de \(store.activeHabits.count) árvores regadas")
                        .font(.inter(.caption))
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
                .help("Sair do Hábitos")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
    }

}

private struct PopoverHabitRow: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit

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
                    Text("\(summary.currentStreak.diasTexto) · \(summary.stage.title)")
                        .font(.inter(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: summary.completedToday ? "drop.fill" : "drop")
                    .font(.rubik(.title3))
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
