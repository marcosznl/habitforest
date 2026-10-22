import SwiftUI

enum Hemisphere: String, CaseIterable, Identifiable {
    case automatic, north, south

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automático (região)"
        case .north: "Hemisfério Norte"
        case .south: "Hemisfério Sul"
        }
    }

    private static let southernRegions: Set<String> = [
        "BR", "AR", "CL", "UY", "PY", "BO", "PE", "AU", "NZ", "ZA", "NA", "BW", "MZ", "MG", "AO", "ZW", "ZM", "LS", "SZ",
    ]

    var isSouthern: Bool {
        switch self {
        case .north: false
        case .south: true
        case .automatic: Self.southernRegions.contains(Locale.current.region?.identifier ?? "")
        }
    }

    static var current: Hemisphere {
        Hemisphere(rawValue: AppGroup.defaults.string(forKey: SettingsKey.hemisphere) ?? "") ?? .automatic
    }
}

enum TimeOfDay: String, CaseIterable {
    case morning, afternoon, sunset, night

    init(date: Date) {
        let hour = Double(Calendar.current.component(.hour, from: date))
            + Double(Calendar.current.component(.minute, from: date)) / 60
        switch hour {
        case 5..<11: self = .morning
        case 11..<17: self = .afternoon
        case 17..<19.5: self = .sunset
        default: self = .night
        }
    }

    var title: String {
        switch self {
        case .morning: "Manhã"
        case .afternoon: "Tarde"
        case .sunset: "Pôr do Sol"
        case .night: "Noite"
        }
    }

    var symbolName: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var skyColors: [Color] {
        switch self {
        case .morning: [Color(red: 0.55, green: 0.78, blue: 0.96), Color(red: 0.98, green: 0.86, blue: 0.70)]
        case .afternoon: [Color(red: 0.30, green: 0.60, blue: 0.95), Color(red: 0.70, green: 0.87, blue: 0.98)]
        case .sunset: [Color(red: 0.36, green: 0.27, blue: 0.55), Color(red: 0.98, green: 0.55, blue: 0.35)]
        case .night: [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.13, green: 0.17, blue: 0.33)]
        }
    }

    /// Multiplicador aplicado à paisagem para escurecer as cenas noturnas.
    var landscapeDimming: Double {
        switch self {
        case .morning: 0.05
        case .afternoon: 0
        case .sunset: 0.25
        case .night: 0.6
        }
    }
}

enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    init(date: Date, hemisphere: Hemisphere = .current) {
        let month = Calendar.current.component(.month, from: date)
        let shifted = hemisphere.isSouthern ? ((month + 5) % 12) + 1 : month
        switch shifted {
        case 3...5: self = .spring
        case 6...8: self = .summer
        case 9...11: self = .autumn
        default: self = .winter
        }
    }

    var title: String {
        switch self {
        case .spring: "Primavera"
        case .summer: "Verão"
        case .autumn: "Outono"
        case .winter: "Inverno"
        }
    }

    var symbolName: String {
        switch self {
        case .spring: "camera.macro"
        case .summer: "sun.max"
        case .autumn: "leaf"
        case .winter: "snowflake"
        }
    }

    var groundColors: (back: Color, front: Color) {
        switch self {
        case .spring: (Color(red: 0.45, green: 0.72, blue: 0.40), Color(red: 0.33, green: 0.60, blue: 0.30))
        case .summer: (Color(red: 0.38, green: 0.66, blue: 0.27), Color(red: 0.27, green: 0.53, blue: 0.20))
        case .autumn: (Color(red: 0.76, green: 0.55, blue: 0.27), Color(red: 0.60, green: 0.42, blue: 0.20))
        case .winter: (Color(red: 0.86, green: 0.90, blue: 0.95), Color(red: 0.76, green: 0.82, blue: 0.90))
        }
    }
}

enum Weather: String {
    case clear, rain, snow, fallingLeaves, petals, fireflies

    var title: String {
        switch self {
        case .clear: "Céu limpo"
        case .rain: "Chuva"
        case .snow: "Neve"
        case .fallingLeaves: "Folhas ao vento"
        case .petals: "Pétalas"
        case .fireflies: "Vaga-lumes"
        }
    }

    /// Determinístico por dia, para todas as views mostrarem o mesmo clima.
    static func forDay(_ date: Date, season: Season, time: TimeOfDay) -> Weather {
        let seed = abs(DayMath.key(date).hashValueStable) % 100
        switch season {
        case .winter: return seed < 60 ? .snow : .clear
        case .autumn: return seed < 25 ? .rain : .fallingLeaves
        case .spring: return seed < 30 ? .rain : .petals
        case .summer:
            if seed < 20 { return .rain }
            return time == .night || time == .sunset ? .fireflies : .clear
        }
    }
}

struct Scenery {
    let time: TimeOfDay
    let season: Season
    let weather: Weather

    init(date: Date = .now, hemisphere: Hemisphere = .current) {
        time = TimeOfDay(date: date)
        season = Season(date: date, hemisphere: hemisphere)
        weather = Weather.forDay(date, season: season, time: time)
    }

    var skyGradient: LinearGradient {
        var colors = time.skyColors
        if weather == .rain { colors = colors.map { $0.mixed(with: .gray, amount: 0.45) } }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var hills: (back: Color, front: Color) {
        let base = season.groundColors
        let dim = time.landscapeDimming
        return (base.back.mixed(with: .black, amount: dim), base.front.mixed(with: .black, amount: dim))
    }
}

private extension String {
    /// FNV-1a; o `hashValue` muda a cada execução, este não.
    var hashValueStable: Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(truncatingIfNeeded: hash)
    }
}
