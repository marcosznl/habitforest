import Foundation

/// Calendar helpers. Every log and snapshot day is normalized to the start of the local day.
enum DayMath {
    static var calendar: Calendar { Calendar.current }

    static func start(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func today(_ now: Date = .now) -> Date {
        start(of: now)
    }

    static func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start(of: date)) ?? date
    }

    /// `count` days ending at `end` (inclusive), oldest first.
    static func days(endingAt end: Date = .now, count: Int) -> [Date] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { add(-$0, to: end) }
    }

    static func distance(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: start(of: a), to: start(of: b)).day ?? 0
    }

    static func nextMidnight(after date: Date = .now) -> Date {
        add(1, to: date)
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String {
        keyFormatter.string(from: date)
    }

    static func date(fromKey key: String) -> Date? {
        keyFormatter.date(from: key).map(start(of:))
    }

    static func shortLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
