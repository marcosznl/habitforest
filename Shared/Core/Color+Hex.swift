import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        if value.count == 8 {
            self.init(.sRGB,
                      red: Double((rgb >> 24) & 0xFF) / 255,
                      green: Double((rgb >> 16) & 0xFF) / 255,
                      blue: Double((rgb >> 8) & 0xFF) / 255,
                      opacity: Double(rgb & 0xFF) / 255)
        } else {
            self.init(.sRGB,
                      red: Double((rgb >> 16) & 0xFF) / 255,
                      green: Double((rgb >> 8) & 0xFF) / 255,
                      blue: Double(rgb & 0xFF) / 255,
                      opacity: 1)
        }
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#3E8E41" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Mistura linear com outra cor (0 = esta, 1 = a outra).
    func mixed(with other: Color, amount: Double) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let t = max(0, min(1, amount))
        return Color(.sRGB,
                     red: a.redComponent + (b.redComponent - a.redComponent) * t,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                     opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }
}
