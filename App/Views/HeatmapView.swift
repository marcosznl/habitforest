import Charts
import SwiftUI

/// Swift Charts statistics: GitHub-style 365-day heatmap, completion by weekday and focus time.
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
                        Text("Mapa de calor").font(.headline)
                        heatmap(cells)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Conclusão por dia da semana").font(.headline)
                            weekdayChart(weekdayRates(from: cells))
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Minutos de foco (30 dias)").font(.headline)
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

    // MARK: - Data

    private func heatCells(for habits: [Habit]) -> [HeatCell] {
        let days = DayMath.days(count: 365)
        guard let first = days.first else { return [] }
        let calendar = Calendar.current
        let calculators = habits.map { $0.calculator() }
        // Align columns to the start of the week so rows are weekdays.
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

    // MARK: - Charts

    private func heatmap(_ cells: [HeatCell]) -> some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday
        return Chart(cells) { cell in
            RectangleMark(
                x: .value("Semana", cell.week),
                y: .value("Dia", cell.weekday),
                width: .ratio(0.85),
                height: .ratio(0.85)
            )
            .foregroundStyle(by: .value("Conclusão", cell.ratio))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(range: Gradient(colors: [
            Color.primary.opacity(0.06), Color(red: 0.6, green: 0.85, blue: 0.5), Color(red: 0.13, green: 0.5, blue: 0.2),
        ]))
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .chartYAxis {
            AxisMarks(values: [0, 2, 4, 6]) { value in
                AxisValueLabel {
                    if let row = value.as(Int.self) { Text(symbols[(row + firstWeekday - 1) % 7]) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 4.33)) { value in
                AxisValueLabel {
                    if let week = value.as(Double.self), let cell = cells.first(where: { $0.week == Int(week) }) {
                        Text(cell.date.formatted(.dateTime.month(.abbreviated)))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 150)
    }

    private func weekdayChart(_ rates: [WeekdayRate]) -> some View {
        Chart(rates) { item in
            BarMark(x: .value("Dia", item.label), y: .value("Taxa", item.rate))
                .foregroundStyle(Color.green.gradient)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(item.rate.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2).foregroundStyle(.secondary)
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

    // MARK: - Tiles

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
                Text(value).font(.title.weight(.bold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
