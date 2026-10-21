import SwiftUI

/// The whole forest on the living landscape. Click a tree to water it.
struct ForestGridView: View {
    @Environment(HabitStore.self) private var store
    @State private var anchor: NSView? = nil
    @State private var exportError: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardHeader(title: "Floresta", subtitle: forestSubtitle) {
                ShareLink(item: ForestPortrait(habitIDs: store.visibleHabits.map(\.id)),
                          preview: SharePreview("Retrato da Floresta", image: Image(systemName: "tree.fill"))) {
                    Label("Retrato", systemImage: "photo")
                }
                Menu {
                    Button("Compartilhar Retrato (PNG)…", systemImage: "photo") { sharePortrait() }
                    Button("Compartilhar dados (JSON)…", systemImage: "curlybraces") { shareJSON() }
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                .fixedSize()
                .background(ViewAnchor { anchor = $0 })
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(store.visibleHabits) { habit in
                        ForestTile(habit: habit)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(24)
        .alert("Não foi possível exportar", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var forestSubtitle: String {
        let ancient = store.habits.filter { $0.summary.stage == .ancient }.count
        return "\(store.habits.count) árvores · \(ancient) ancestrais"
    }

    private func sharePortrait() {
        do {
            let url = try ExportService.writePortrait(for: store.visibleHabits)
            ExportService.share([url], from: anchor)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func shareJSON() {
        do {
            let url = try ExportService.writeJSON(for: store.habits)
            ExportService.share([url], from: anchor)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ForestTile: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    @State private var bounce = false

    var body: some View {
        let summary = habit.summary
        VStack(spacing: 6) {
            TreeView(species: habit.species, stage: summary.stage, health: summary.health,
                     tint: habit.themeColor, animated: true)
                .frame(height: 150)
                .scaleEffect(bounce ? 1.06 : 1, anchor: .bottom)
            Text(habit.name).font(.headline).lineLimit(1)
            Text("\(habit.species.title) · \(summary.stage.title)")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label("\(summary.currentStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Image(systemName: summary.completedToday ? "drop.fill" : "drop")
                    .foregroundStyle(summary.completedToday ? .blue : .secondary)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            store.toggle(habit)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { bounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring) { bounce = false }
            }
        }
        .help(summary.completedToday ? "Regada hoje — clique para desfazer" : "Clique para regar")
    }
}

/// Static panorama rendered to PNG for sharing.
struct ForestPortraitView: View {
    let habits: [Habit]

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneLayers(scenery: Scenery(), animated: false, showsHills: true)

            HStack(alignment: .bottom, spacing: -12) {
                ForEach(habits) { habit in
                    let summary = habit.summary
                    VStack(spacing: 4) {
                        TreeView(species: habit.species, stage: summary.stage, health: summary.health, tint: habit.themeColor)
                            .frame(width: 180, height: 220)
                        Text(habit.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                        Text("\(summary.currentStreak) dias")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Retrato da Floresta")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(Date.now.formatted(date: .long, time: .omitted))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(radius: 6)
            .padding(36)
        }
        .environment(\.colorScheme, .light)
    }
}
