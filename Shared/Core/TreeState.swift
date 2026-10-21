import Foundation

/// What happened on a single calendar day for a habit.
enum DayState: String, Codable, Sendable {
    case completed
    case missed
    /// Covered by Greenhouse mode: neither counts nor breaks the streak.
    case frozen
    /// Today, not done yet.
    case pending
    /// Before the habit existed.
    case beforeStart
}

/// Growth stage driven by the current streak.
enum GrowthStage: Int, Codable, CaseIterable, Comparable, Sendable {
    case seed, sprout, young, mature, ancient

    init(streak: Int) {
        switch streak {
        case ...0: self = .seed
        case 1...3: self = .sprout
        case 4...14: self = .young
        case 15...30: self = .mature
        default: self = .ancient
        }
    }

    static func < (lhs: GrowthStage, rhs: GrowthStage) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .seed: "Semente"
        case .sprout: "Broto"
        case .young: "Árvore Jovem"
        case .mature: "Adulta"
        case .ancient: "Ancestral"
        }
    }

    var rangeDescription: String {
        switch self {
        case .seed: "dia 0"
        case .sprout: "dias 1–3"
        case .young: "dias 4–14"
        case .mature: "dias 15–30"
        case .ancient: "30+ dias"
        }
    }
}

enum TreeHealth: String, Codable, CaseIterable, Sendable {
    /// Alive and green.
    case healthy
    /// Leaves falling: one day missed, streak still rescuable.
    case struggling
    /// Dry: two or more consecutive days missed, streak broken.
    case withered

    var title: String {
        switch self {
        case .healthy: "Saudável"
        case .struggling: "Perdendo folhas"
        case .withered: "Seca"
        }
    }

    var symbolName: String {
        switch self {
        case .healthy: "leaf.fill"
        case .struggling: "wind"
        case .withered: "flame"
        }
    }
}
