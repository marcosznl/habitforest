import CoreText
import SwiftUI

/// Tipografia do app: Rubik nos títulos e números, Inter no texto corrido (as mesmas do site do Forest).
/// As duas são fontes variáveis com licença OFL, empacotadas em `Shared/Fonts`.
enum Typography {
    private static let registration: Void = {
        for name in ["Rubik", "Inter"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registra as fontes no processo; pode ser chamado várias vezes.
    static func register() {
        _ = registration
    }

    /// Tamanhos dos estilos de texto do macOS.
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}

extension Font {
    /// Rubik (títulos, números de destaque).
    static func rubik(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .custom("Rubik", size: Typography.size(for: style), relativeTo: style).weight(weight)
    }

    static func rubik(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Rubik", size: size).weight(weight)
    }

    /// Inter (texto corrido, legendas).
    static func inter(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: Typography.size(for: style), relativeTo: style).weight(weight)
    }
}
