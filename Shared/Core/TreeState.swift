import Foundation

/// O que aconteceu com um hábito num dia do calendário.
enum DayState: String, Codable, Sendable {
    case completed
    case missed
    /// Coberto pela Estufa: não conta nem quebra a sequência.
    case frozen
    /// Hoje, ainda não feito.
    case pending
    /// Antes de o hábito existir.
    case beforeStart
}

/// Estágio de crescimento definido pela sequência atual.
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
    /// Viva e verde.
    case healthy
    /// Folhas caindo: um dia falhado, sequência ainda salvável.
    case struggling
    /// Seca: dois ou mais dias falhados seguidos, sequência quebrada.
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
