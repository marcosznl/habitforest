import SwiftUI

/// A floresta inteira: uma ilha isométrica com uma árvore para cada dia regado e, abaixo,
/// a árvore atual de cada hábito. Clique num cartão para regar.
struct ForestGridView: View {
    @Environment(HabitStore.self) private var store
    @State private var anchor: NSView? = nil
    @State private var exportError: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        let season = Scenery().season
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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

                ForestIslandView(trees: Self.islandTrees(for: store.visibleHabits), season: season, animated: true)
                    .frame(height: 600)
                    .frame(maxWidth: .infinity)

                Text("Suas árvores").font(.rubik(.title2))
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.visibleHabits) { habit in
                        ForestTile(habit: habit, season: season)
                    }
                }
            }
            .padding(24)
        }
        .alert("Não foi possível exportar", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Uma árvore por dia regado nos últimos 60 dias, no estágio daquele dia: os primeiros dias de
    /// uma sequência aparecem como brotos e os seguintes cada vez maiores, até a ancestral.
    /// A ilha começa vazia e só cresce: dias não regados não deixam árvores secas.
    static func islandTrees(for habits: [Habit]) -> [IslandTree] {
        let entries = habits.flatMap { habit in
            habit.calculator().window(days: 60).compactMap { day -> (Date, IslandTree)? in
                guard day.state == .completed else { return nil }
                return (day.date, IslandTree(species: habit.species, stage: day.stage, health: .healthy, tint: habit.themeColor))
            }
        }
        return entries.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private var forestSubtitle: String {
        let planted = Self.islandTrees(for: store.habits).count
        let ancient = store.habits.filter { $0.summary.stage == .ancient }.count
        let trees = planted == 1 ? "1 árvore plantada" : "\(planted) árvores plantadas"
        guard planted > 0 else { return "Regue um hábito para plantar a primeira árvore da ilha." }
        return "\(trees) nos últimos 60 dias · \(ancient) \(ancient == 1 ? "ancestral" : "ancestrais")"
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
    let season: Season
    @State private var bounce = false

    var body: some View {
        let summary = habit.summary
        VStack(spacing: 8) {
            TreeEmblemView(species: habit.species, stage: summary.stage, health: summary.health,
                           tint: habit.themeColor, season: season, animated: true)
                .frame(width: 120, height: 120)
                .scaleEffect(bounce ? 1.06 : 1)
            Text(habit.name).font(.rubik(.headline, weight: .semibold)).lineLimit(1)
            Text("\(habit.species.title) · \(summary.stage.title)")
                .font(.inter(.caption)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label("\(summary.currentStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Image(systemName: summary.completedToday ? "drop.fill" : "drop")
                    .foregroundStyle(summary.completedToday ? .blue : .secondary)
            }
            .font(.inter(.caption, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

/// Panorama estático renderizado em PNG para compartilhar.
struct ForestPortraitView: View {
    let habits: [Habit]

    var body: some View {
        let scenery = Scenery()
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.42, blue: 0.32), Color(red: 0.03, green: 0.18, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)

            ForestIslandView(trees: ForestGridView.islandTrees(for: habits), season: scenery.season)
                .padding(.top, 120)
                .padding(.horizontal, 160)
                .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 6) {
                Text("Retrato da Floresta")
                    .font(.rubik(size: 44, weight: .bold))
                Text("\(Date.now.formatted(date: .long, time: .omitted)) · \(scenery.season.title)")
                    .font(.rubik(size: 18, weight: .medium))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
    }
}
