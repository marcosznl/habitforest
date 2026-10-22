import Charts
import SwiftUI

/// Estatísticas com Swift Charts: mapa de calor de 365 dias estilo GitHub, conclusão por dia da semana e tempo de foco.
struct HeatmapView: View {
    @Environment(HabitStore.self) private var store
    @State private var selectedHabitID: UUID? = nil

    struct HeatCell: Identifiable {
        var id: Date { date }
        let date: Date
        let week: Int
        let weekday: Int
        let ratio: Double
    }

    struct WeekdayRate: Identifiable {
        var id: Int { weekday }
        let weekday: Int
        let label: String
        let rate: Double
    }

    struct FocusDay: Identifiable {
        var id: Date { date }
        let date: Date
        let minutes: Int
    }

    var body: some View {
        let habits = selectedHabits
        let cells = heatCells(for: habits)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashboardHeader(title: "Estatísticas", subtitle: "Últimos 365 dias") {
                    Picker("Hábito", selection: $selectedHabitID) {
                        Text("Floresta inteira").tag(UUID?.none)
                        ForEach(store.habits) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .frame(width: 220)
                }

                tiles(habits: habits, cells: cells)

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mapa de calor").font(.rubik(.headline, weight: .semibold))
                        heatmap(cells)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Conclusão por dia da semana").font(.rubik(.headline, weight: .semibold))
                            weekdayChart(weekdayRates(from: cells))
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Minutos de foco (30 dias)").font(.rubik(.headline, weight: .semibold))
                            focusChart(focusDays(for: habits))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var selectedHabits: [Habit] {
        if let selectedHabitID, let habit = store.habit(id: selectedHabitID) { return [habit] }
        return store.habits
    }

    // MARK: - Dados

    private func heatCells(for habits: [Habit]) -> [HeatCell] {
        let days = DayMath.days(count: 365)
        guard let first = days.first else { return [] }
        let calendar = Calendar.current
        let calculators = habits.map { $0.calculator() }
        // Alinha as colunas ao início da semana para que as linhas sejam os dias da semana.
        let firstWeekdayOffset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7

        return days.enumerated().map { index, day in
            let states = calculators.map { $0.state(on: day) }
            let relevant = states.filter { $0 == .completed || $0 == .missed || $0 == .pending }
            let done = states.filter { $0 == .completed }.count
            let ratio = relevant.isEmpty ? 0 : Double(done) / Double(relevant.count)
            let position = index + firstWeekdayOffset
            return HeatCell(date: day, week: position / 7, weekday: position % 7, ratio: ratio)
        }
    }

    private func weekdayRates(from cells: [HeatCell]) -> [WeekdayRate] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday
        return (0..<7).map { row in
            let values = cells.filter { $0.weekday == row }.map(\.ratio)
            let rate = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return WeekdayRate(weekday: row, label: symbols[(row + firstWeekday - 1) % 7], rate: rate)
        }
    }

    private func focusDays(for habits: [Habit]) -> [FocusDay] {
        DayMath.days(count: 30).map { day in
            FocusDay(date: day, minutes: habits.reduce(0) { $0 + ($1.log(on: day)?.minutesFocused ?? 0) })
        }
    }

    // MARK: - Gráficos

    private func heatmap(_ cells: [HeatCell]) -> some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday
        let weeks = (cells.map(\.week).max() ?? 52) + 1
        // Cada dia ocupa um quadrado [semana, semana+1] × [dia, dia+1], com uma pequena folga.
        return Chart(cells) { cell in
            RectangleMark(
                xStart: .value("Semana", Double(cell.week) + 0.1),
                xEnd: .value("Semana", Double(cell.week) + 0.9),
                yStart: .value("Dia", Double(cell.weekday) + 0.1),
                yEnd: .value("Dia", Double(cell.weekday) + 0.9)
            )
            .foregroundStyle(Self.heatColor(cell.ratio))
            .cornerRadius(2)
        }
        .chartXScale(domain: 0...Double(weeks))
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartYAxis {
            AxisMarks(values: [0.5, 2.5, 4.5, 6.5]) { value in
                AxisValueLabel {
                    if let row = value.as(Double.self) { Text(symbols[(Int(row) + firstWeekday - 1) % 7]) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 4.35)) { value in
                AxisValueLabel {
                    if let week = value.as(Double.self), let cell = cells.first(where: { $0.week == Int(week) }) {
                        Text(cell.date.formatted(.dateTime.month(.abbreviated)))
                    }
                }
            }
        }
        .frame(height: 150)
    }

    /// Verde mais forte conforme mais hábitos foram regados no dia.
    private static func heatColor(_ ratio: Double) -> Color {
        guard ratio > 0 else { return Color.primary.opacity(0.07) }
        return Color(red: 0.62, green: 0.86, blue: 0.45).mixed(with: Color(red: 0.10, green: 0.45, blue: 0.18), amount: ratio)
    }

    private func weekdayChart(_ rates: [WeekdayRate]) -> some View {
        Chart(rates) { item in
            BarMark(x: .value("Dia", item.label), y: .value("Taxa", item.rate))
                .foregroundStyle(Color.green.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(item.rate.formatted(.percent.precision(.fractionLength(0))))
                        .font(.inter(.caption2)).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(rate, format: .percent.precision(.fractionLength(0)))
                    }
                }
            }
        }
        .frame(height: 200)
    }

    private func focusChart(_ days: [FocusDay]) -> some View {
        Chart(days) { day in
            BarMark(x: .value("Dia", day.date, unit: .day), y: .value("Minutos", day.minutes))
                .foregroundStyle(Color.teal.gradient)
                .cornerRadius(3)
        }
        .frame(height: 200)
    }

    // MARK: - Cartões

    private func tiles(habits: [Habit], cells: [HeatCell]) -> some View {
        let summaries = habits.map(\.summary)
        let last30 = cells.suffix(30).map(\.ratio)
        let rate30 = last30.isEmpty ? 0 : last30.reduce(0, +) / Double(last30.count)
        let completions = habits.reduce(0) { $0 + $1.logs.filter(\.isCompleted).count }
        return HStack(spacing: 12) {
            StatTile(title: "Sequência atual", value: "\(summaries.map(\.currentStreak).max() ?? 0)", symbol: "flame.fill", color: .orange)
            StatTile(title: "Melhor sequência", value: "\(summaries.map(\.bestStreak).max() ?? 0)", symbol: "trophy.fill", color: .yellow)
            StatTile(title: "Taxa 30 dias", value: rate30.formatted(.percent.precision(.fractionLength(0))), symbol: "chart.line.uptrend.xyaxis", color: .green)
            StatTile(title: "Regas totais", value: "\(completions)", symbol: "drop.fill", color: .blue)
            StatTile(title: "Horas de foco", value: String(format: "%.1f", Double(habits.reduce(0) { $0 + $1.totalFocusMinutes }) / 60), symbol: "timer", color: .teal)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(value).font(.rubik(.title)).monospacedDigit()
                Text(title).font(.inter(.caption)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
