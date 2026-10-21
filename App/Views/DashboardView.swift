import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case everyday, forest, focus, stats, greenhouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: "Everyday"
        case .forest: "Floresta"
        case .focus: "Foco"
        case .stats: "Estatísticas"
        case .greenhouse: "Estufa"
        }
    }

    var symbolName: String {
        switch self {
        case .everyday: "calendar"
        case .forest: "tree.fill"
        case .focus: "timer"
        case .stats: "chart.bar.xaxis"
        case .greenhouse: "snowflake"
        }
    }
}

/// Navigation state shared with AppKit (menu bar, notifications, intents).
@MainActor
@Observable
final class DashboardNavigation {
    static let shared = DashboardNavigation()
    var section: DashboardSection = .everyday
    var isAddingHabit = false
}

/// Identifies the habit being edited without holding the model object in view state.
private struct EditingHabit: Identifiable {
    let id: UUID
}

struct DashboardView: View {
    @Environment(HabitStore.self) private var store
    @Environment(DashboardNavigation.self) private var navigation

    @State private var editing: EditingHabit? = nil

    var body: some View {
        @Bindable var navigation = navigation
        HStack(spacing: 0) {
            SidebarView(selection: $navigation.section)
                .frame(width: 200)
            Divider()
            ZStack {
                SceneBackgroundView()
                    .opacity(navigation.section == .forest ? 1 : 0.55)
                    .ignoresSafeArea()
                detail
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .sheet(isPresented: $navigation.isAddingHabit) {
            HabitEditorView(habit: nil)
        }
        .sheet(item: $editing) { item in
            if let habit = store.habit(id: item.id) {
                HabitEditorView(habit: habit)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .everyday: everyday
        case .forest: ForestGridView()
        case .focus: FocusTimerView()
        case .stats: HeatmapView()
        case .greenhouse: GreenhouseView()
        }
    }

    private var everyday: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardHeader(title: "Everyday", subtitle: subtitle) {
                Button { navigation.isAddingHabit = true } label: {
                    Label("Plantar hábito", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            }

            if let focus = store.focusContext {
                Label("Modo Foco ativo: mostrando hábitos de \(focus.title)", systemImage: "moon.circle.fill")
                    .font(.callout)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
            }

            if store.visibleHabits.isEmpty {
                ContentUnavailableView("Nenhuma árvore plantada", systemImage: "leaf",
                                       description: Text("Plante seu primeiro hábito com ⌘N."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(store.visibleHabits.enumerated()), id: \.element.id) { index, habit in
                        EverydayHabitRow(habit: habit, index: index) { editing = EditingHabit(id: habit.id) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var subtitle: String {
        let done = store.completedTodayCount
        let total = store.activeHabits.count
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(date.capitalized) · \(done) de \(total) árvores regadas hoje"
    }
}

struct DashboardHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.weight(.bold))
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            Spacer()
            SceneryBadge()
            actions
        }
    }
}

struct SceneryBadge: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let scenery = Scenery(date: context.date)
            HStack(spacing: 8) {
                Label(scenery.time.title, systemImage: scenery.time.symbolName)
                Label(scenery.season.title, systemImage: scenery.season.symbolName)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .help("Clima de hoje: \(scenery.weather.title)")
        }
    }
}

private struct SidebarView: View {
    @Environment(HabitStore.self) private var store
    @Binding var selection: DashboardSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TreeView(species: .oak, stage: .mature, showsGround: false).frame(width: 26, height: 26)
                Text("HabitForest").font(.title3.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            ForEach(DashboardSection.allCases) { section in
                Button {
                    selection = section
                    Haptics.perform(.alignment)
                } label: {
                    HStack {
                        Label(section.title, systemImage: section.symbolName)
                        Spacer()
                        if section == .greenhouse, !store.greenhouseHabits.isEmpty {
                            Text("\(store.greenhouseHabits.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background(selection == section ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            FocusMiniStatus()
                .padding(.horizontal, 6)

            SettingsLink {
                Label("Ajustes", systemImage: "gearshape")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 44)
        .padding(.bottom, 14)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView(material: .sidebar).ignoresSafeArea())
    }
}

/// Compact timer state shown in the sidebar and the menu bar popover.
struct FocusMiniStatus: View {
    @Environment(FocusSession.self) private var session

    var body: some View {
        if session.isActive {
            HStack {
                Image(systemName: "timer")
                Text(session.remainingLabel).monospacedDigit()
                Spacer()
                Button {
                    session.phase == .running ? session.pause() : session.start()
                } label: {
                    Image(systemName: session.phase == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Greenhouse: habits paused for vacations without breaking their streak.
struct GreenhouseView: View {
    @Environment(HabitStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardHeader(title: "Estufa", subtitle: "Hábitos protegidos durante férias: a sequência fica congelada.") {}
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.habits) { habit in
                        GlassCard {
                            HStack(spacing: 14) {
                                let summary = habit.summary
                                ZStack {
                                    TreeView(species: habit.species, stage: summary.stage, health: summary.health,
                                             tint: habit.themeColor, animated: !habit.isPausedInGreenhouse)
                                    if habit.isPausedInGreenhouse {
                                        RoundedRectangle(cornerRadius: 22)
                                            .fill(.cyan.opacity(0.12))
                                            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.cyan.opacity(0.5)))
                                    }
                                }
                                .frame(width: 64, height: 64)
                                VStack(alignment: .leading) {
                                    Text(habit.name).font(.headline)
                                    if let since = habit.greenhouseSince, habit.isPausedInGreenhouse {
                                        Text("Na estufa desde \(since.formatted(date: .abbreviated, time: .omitted)) · sequência de \(summary.currentStreak) dias preservada")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("\(summary.currentStreak) dias · \(summary.stage.title)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Toggle("Estufa", isOn: Binding(
                                    get: { habit.isPausedInGreenhouse },
                                    set: { store.setGreenhouse(habit, paused: $0) }
                                ))
                                .toggleStyle(.switch)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
