import SwiftUI

/// As nove espécies botânicas em que um hábito pode crescer.
enum TreeSpecies: String, CaseIterable, Codable, Identifiable, Sendable {
    case oak, pine, bonsai, cherry, willow, cactus, sequoia, bamboo, birch, ipe, palm, baobab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oak: "Carvalho"
        case .pine: "Pinheiro"
        case .bonsai: "Bonsai"
        case .cherry: "Cerejeira"
        case .willow: "Salgueiro"
        case .cactus: "Cacto"
        case .sequoia: "Sequoia"
        case .bamboo: "Bambu"
        case .birch: "Bétula"
        case .ipe: "Ipê-Amarelo"
        case .palm: "Palmeira"
        case .baobab: "Baobá"
        }
    }

    var symbolName: String {
        switch self {
        case .oak, .birch, .willow: "tree.fill"
        case .pine, .sequoia: "tree"
        case .bonsai: "leaf.fill"
        case .cherry: "camera.macro"
        case .cactus: "sun.max.fill"
        case .bamboo: "line.3.horizontal"
        case .ipe: "sun.haze.fill"
        case .palm: "beach.umbrella.fill"
        case .baobab: "tree.fill"
        }
    }

    /// Cor de tema sugerida ao escolher a espécie.
    var defaultHex: String {
        switch self {
        case .oak: "#3E8E41"
        case .pine: "#1F6F50"
        case .bonsai: "#5B8C2A"
        case .cherry: "#E58FB0"
        case .willow: "#7FB069"
        case .cactus: "#4F9D69"
        case .sequoia: "#2E5E3E"
        case .bamboo: "#79B33C"
        case .birch: "#B5C94C"
        case .ipe: "#F2C318"
        case .palm: "#3F9A4A"
        case .baobab: "#6E9A3A"
        }
    }

    var leafColor: Color {
        switch self {
        case .oak: Color(red: 0.24, green: 0.56, blue: 0.25)
        case .pine: Color(red: 0.12, green: 0.42, blue: 0.30)
        case .bonsai: Color(red: 0.36, green: 0.55, blue: 0.17)
        case .cherry: Color(red: 0.96, green: 0.62, blue: 0.75)
        case .willow: Color(red: 0.50, green: 0.70, blue: 0.40)
        case .cactus: Color(red: 0.31, green: 0.62, blue: 0.41)
        case .sequoia: Color(red: 0.18, green: 0.37, blue: 0.24)
        case .bamboo: Color(red: 0.47, green: 0.70, blue: 0.24)
        case .birch: Color(red: 0.71, green: 0.79, blue: 0.30)
        case .ipe: Color(red: 0.97, green: 0.78, blue: 0.14)
        case .palm: Color(red: 0.28, green: 0.62, blue: 0.30)
        case .baobab: Color(red: 0.43, green: 0.60, blue: 0.24)
        }
    }

    var trunkColor: Color {
        switch self {
        case .birch: Color(red: 0.95, green: 0.94, blue: 0.90)
        case .sequoia: Color(red: 0.55, green: 0.27, blue: 0.18)
        case .cherry: Color(red: 0.36, green: 0.22, blue: 0.20)
        case .bamboo: Color(red: 0.55, green: 0.70, blue: 0.30)
        case .cactus: Color(red: 0.25, green: 0.50, blue: 0.33)
        case .palm: Color(red: 0.62, green: 0.47, blue: 0.30)
        case .baobab: Color(red: 0.62, green: 0.52, blue: 0.44)
        default: Color(red: 0.42, green: 0.29, blue: 0.19)
        }
    }

    /// Espécies que mudam de cor no outono e ficam claras no inverno.
    var isDeciduous: Bool {
        switch self {
        case .oak, .cherry, .willow, .birch: true
        default: false
        }
    }

    /// Espécies menores continuam baixas mesmo quando ancestrais.
    var heightFactor: CGFloat {
        switch self {
        case .bonsai: 0.72
        case .cactus: 0.85
        case .sequoia: 1.08
        case .palm: 1.05
        default: 1
        }
    }
}
