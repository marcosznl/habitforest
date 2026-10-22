// Gera o ícone do app (AppIcon.appiconset) a partir do mesmo desenho das árvores do app.
//
// Uso, a partir da raiz do projeto:
//   swiftc -parse-as-library -o /tmp/gerar-icone Tools/GerarIcone/main.swift Shared/Core/*.swift Shared/Rendering/*.swift
//   /tmp/gerar-icone App/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import SwiftUI

/// Arte do ícone em 1024×1024: quadrado arredondado verde-limão, tigela de terra e um pinheiro.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.56), Color(red: 0.70, green: 0.87, blue: 0.29)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    Canvas { ctx, size in
                        let rimY = size.height * 0.66
                        var soil = Path()
                        soil.addRect(CGRect(x: 0, y: rimY, width: size.width, height: size.height - rimY))
                        ctx.fill(soil, with: .color(Color(red: 0.49, green: 0.29, blue: 0.10)))
                        ctx.fill(Path(CGRect(x: size.width / 2, y: rimY, width: size.width / 2, height: size.height - rimY)),
                                 with: .color(Color(red: 0.42, green: 0.24, blue: 0.08)))
                        var rim = Path()
                        rim.move(to: CGPoint(x: 0, y: rimY))
                        rim.addQuadCurve(to: CGPoint(x: size.width, y: rimY), control: CGPoint(x: size.width / 2, y: rimY - size.height * 0.07))
                        rim.addLine(to: CGPoint(x: size.width, y: rimY + size.height * 0.03))
                        rim.addQuadCurve(to: CGPoint(x: 0, y: rimY + size.height * 0.03), control: CGPoint(x: size.width / 2, y: rimY - size.height * 0.04))
                        rim.closeSubpath()
                        ctx.fill(rim, with: .color(Color(red: 0.62, green: 0.39, blue: 0.16)))
                    }
                }
                .overlay {
                    TreeView(species: .pine, stage: .mature, showsGround: false)
                        .frame(width: 600, height: 600)
                        .offset(y: 824 * 0.66 - 600 * 0.9 - 824 / 2 + 300 - 824 * 0.025)
                }
                .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct GerarIcone {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let image = renderer.cgImage else { fatalError("falha ao renderizar o ícone") }

        let sizes = [16, 32, 128, 256, 512]
        var entries: [String] = []
        for size in sizes {
            for scale in [1, 2] {
                let pixels = size * scale
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try resized(image, to: pixels).write(to: output.appending(path: name))
                entries.append("""
                    { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(size)x\(size)" }
                """)
            }
        }
        let contents = """
        {
          "images" : [
        \(entries.joined(separator: ",\n"))
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }

        """
        try contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
        print("Ícone gerado em \(output.path)")
    }

    static func resized(_ image: CGImage, to pixels: Int) throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        NSImage(cgImage: image, size: NSSize(width: 1024, height: 1024))
            .draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
