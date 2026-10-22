import SwiftUI

/// Árvore desenhada proceduralmente no estilo "chapado em duas tonalidades" (luz vindo da esquerda):
/// espécie × estágio × saúde, com variação opcional por estação e animação (balanço, folhas caindo).
struct TreeView: View {
    var species: TreeSpecies
    var stage: GrowthStage
    var health: TreeHealth = .healthy
    var tint: Color? = nil
    var season: Season? = nil
    var animated = false
    var showsGround = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: 0)
        }
    }

    private func canvas(time: Double) -> some View {
        Canvas { ctx, size in
            TreePainter(species: species, stage: stage, health: health, tint: tint, season: season,
                        time: time, animated: animated, showsGround: showsGround)
                .draw(in: &ctx, size: size)
        }
        .accessibilityLabel("\(species.title), \(stage.title), \(health.title)")
    }
}

/// Toco seco desenhado nos dias não regados da matriz de hábitos.
struct StumpView: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2, ground = size.height * 0.82
            ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.28, y: ground - s * 0.04, width: s * 0.56, height: s * 0.1)),
                     with: .color(.black.opacity(0.15)))
            let stump = CGRect(x: cx - s * 0.13, y: ground - s * 0.24, width: s * 0.26, height: s * 0.24)
            ctx.fill(Path(stump), with: .color(Color(red: 0.42, green: 0.30, blue: 0.18)))
            ctx.fill(Path(CGRect(x: cx, y: stump.minY, width: stump.width / 2, height: stump.height)),
                     with: .color(Color(red: 0.33, green: 0.23, blue: 0.14)))
            ctx.fill(Path(ellipseIn: CGRect(x: stump.minX, y: stump.minY - s * 0.045, width: stump.width, height: s * 0.09)),
                     with: .color(Color(red: 0.80, green: 0.64, blue: 0.40)))
        }
    }
}

/// Emblema circular com tigela de terra, como os passos do app Forest.
struct TreeEmblemView: View {
    var species: TreeSpecies
    var stage: GrowthStage
    var health: TreeHealth = .healthy
    var tint: Color? = nil
    var season: Season? = nil
    var animated = false

    static let background = Color(red: 0.92, green: 0.90, blue: 0.64)
    static let soil = Color(red: 0.49, green: 0.29, blue: 0.10)
    static let soilRim = Color(red: 0.60, green: 0.37, blue: 0.15)

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Self.background)
                Canvas { ctx, size in
                    let rimY = size.height * 0.64
                    var bowl = Path()
                    bowl.addArc(center: CGPoint(x: size.width / 2, y: rimY), radius: size.width * 0.42,
                                startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                    bowl.closeSubpath()
                    ctx.fill(bowl, with: .color(Self.soil))
                    ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.08, y: rimY - size.height * 0.045,
                                                    width: size.width * 0.84, height: size.height * 0.09)),
                             with: .color(Self.soilRim))
                }
                // O chão da árvore (90% da altura dela) fica alinhado à borda da tigela (64% do círculo).
                let treeHeight = d * 0.8
                TreeView(species: species, stage: stage, health: health, tint: tint, season: season,
                         animated: animated, showsGround: false)
                    .frame(width: treeHeight, height: treeHeight)
                    .offset(y: d * 0.64 - treeHeight * 0.4 - d / 2)
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct TreePainter {
    let species: TreeSpecies
    let stage: GrowthStage
    let health: TreeHealth
    let tint: Color?
    var season: Season? = nil
    let time: Double
    let animated: Bool
    let showsGround: Bool

    // MARK: - Paleta

    private var baseLeaf: Color {
        var color = tint.map { species.leafColor.mixed(with: $0, amount: 0.3) } ?? species.leafColor
        if let season, species.isDeciduous {
            switch season {
            case .autumn: color = color.mixed(with: Color(red: 0.92, green: 0.42, blue: 0.13), amount: 0.7)
            case .winter: color = color.mixed(with: Color(red: 0.74, green: 0.86, blue: 0.96), amount: 0.65)
            default: break
            }
        }
        switch health {
        case .healthy: return color
        case .struggling: return color.mixed(with: Color(red: 0.86, green: 0.74, blue: 0.26), amount: 0.55)
        case .withered: return Color(red: 0.56, green: 0.48, blue: 0.22)
        }
    }

    private var leafLight: Color { baseLeaf.mixed(with: Color(red: 1, green: 1, blue: 0.85), amount: 0.2) }
    private var leafDark: Color { baseLeaf.mixed(with: .black, amount: 0.2) }

    private var trunkBase: Color {
        health == .withered ? Color(red: 0.50, green: 0.42, blue: 0.16) : species.trunkColor
    }
    private var trunkLight: Color { trunkBase }
    private var trunkDark: Color { trunkBase.mixed(with: .black, amount: 0.25) }

    private var stageHeight: CGFloat {
        switch stage {
        case .seed: 0.14
        case .sprout: 0.32
        case .young: 0.55
        case .mature: 0.75
        case .ancient: 0.9
        }
    }

    private struct Geo {
        let s: CGFloat, cx: CGFloat, ground: CGFloat, h: CGFloat
        var top: CGFloat { ground - h }
    }

    // MARK: - Desenho

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let cx = size.width / 2
        let ground = size.height * 0.9
        let g = Geo(s: s, cx: cx, ground: ground, h: s * stageHeight * species.heightFactor)

        if showsGround {
            let width = s * (0.3 + CGFloat(stage.rawValue) * 0.07)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - width / 2, y: ground - s * 0.03, width: width, height: s * 0.07)),
                     with: .color(.black.opacity(0.18)))
        }

        var tree = ctx
        if animated && health != .withered {
            let sway = sin(time * 1.3 + Double(species.rawValue.count)) * (health == .struggling ? 0.04 : 0.02)
            tree.translateBy(x: cx, y: ground)
            tree.rotate(by: .radians(sway))
            tree.translateBy(x: -cx, y: -ground)
        }

        switch stage {
        case .seed: drawSeed(&tree, g)
        case .sprout: drawSprout(&tree, g)
        default:
            if health == .withered && ![.cactus, .bamboo, .bonsai].contains(species) {
                drawDead(&tree, g)
            } else {
                switch species {
                case .oak: drawRound(&tree, g, flatten: 1)
                case .cherry: drawRound(&tree, g, flatten: 0.85, blossoms: .white)
                case .ipe: drawRound(&tree, g, flatten: 0.8, blossoms: Color(red: 1, green: 0.95, blue: 0.62))
                case .palm: drawPalm(&tree, g)
                case .baobab: drawBaobab(&tree, g)
                case .pine: drawConifer(&tree, g, widthFactor: 0.66, trunkShare: 0.14)
                case .sequoia: drawConifer(&tree, g, widthFactor: 0.42, trunkShare: 0.3)
                case .bonsai: drawBonsai(&tree, g)
                case .willow: drawWillow(&tree, g)
                case .cactus: drawCactus(&tree, g)
                case .bamboo: drawBamboo(&tree, g)
                case .birch: drawBirch(&tree, g)
                }
            }
        }

        if stage == .ancient && health == .healthy && showsGround { drawFlowers(&ctx, g) }
        if health == .struggling && stage != .seed { drawFallingLeaves(&ctx, g) }
    }

    // MARK: - Utilitários

    /// Preenche o caminho com a tonalidade escura e repinta a metade à esquerda de `axis` com a clara.
    private func twoTone(_ ctx: inout GraphicsContext, _ path: Path, axis: CGFloat, light: Color, dark: Color) {
        ctx.fill(path, with: .color(dark))
        let bounds = path.boundingRect
        guard axis > bounds.minX else { return }
        var left = ctx
        left.clip(to: Path(CGRect(x: bounds.minX - 1, y: bounds.minY - 1, width: axis - bounds.minX + 1, height: bounds.height + 2)))
        left.fill(path, with: .color(light))
    }

    private func ellipse(_ center: CGPoint, _ w: CGFloat, _ h: CGFloat, angle: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    private func circle(_ center: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private func drawTrunk(_ ctx: inout GraphicsContext, _ g: Geo, width: CGFloat, topY: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: g.cx - width / 2, y: g.ground))
        p.addLine(to: CGPoint(x: g.cx - width * 0.32, y: topY))
        p.addLine(to: CGPoint(x: g.cx + width * 0.32, y: topY))
        p.addLine(to: CGPoint(x: g.cx + width / 2, y: g.ground))
        p.closeSubpath()
        twoTone(&ctx, p, axis: g.cx, light: trunkLight, dark: trunkDark)
    }

    /// Copa em forma de nuvem: uma elipse central com calombos na borda, achatados embaixo.
    private func cloudCanopy(center: CGPoint, rx: CGFloat, ry: CGFloat, bumps: Int) -> Path {
        var path = Path(ellipseIn: CGRect(x: center.x - rx * 0.86, y: center.y - ry * 0.86, width: rx * 1.72, height: ry * 1.72))
        let bump = min(rx, ry) * 0.44
        for i in 0..<bumps {
            let a = -Double.pi / 2 + Double(i) / Double(bumps) * 2 * .pi
            let wobble = 1 + 0.1 * CGFloat(sin(Double(i) * 2.7 + Double(species.rawValue.count)))
            let r = bump * wobble * (sin(a) > 0.55 ? 0.8 : 1)
            let x = center.x + CGFloat(cos(a)) * (rx - bump * 0.72)
            let y = center.y + CGFloat(sin(a)) * (ry - bump * 0.72)
            path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        return path
    }

    /// Duas tonalidades, brilho no alto à esquerda e sombra embaixo, para dar volume à copa.
    private func shadeCanopy(_ ctx: inout GraphicsContext, _ canopy: Path, center: CGPoint, rx: CGFloat, ry: CGFloat) {
        twoTone(&ctx, canopy, axis: center.x + rx * 0.06, light: leafLight, dark: leafDark)
        var inside = ctx
        inside.clip(to: canopy)
        inside.fill(Path(ellipseIn: CGRect(x: center.x - rx * 1.4, y: center.y + ry * 0.42, width: rx * 2.8, height: ry * 1.4)),
                    with: .color(.black.opacity(0.12)))
        guard health != .withered else { return }
        let highlight = leafLight.mixed(with: .white, amount: 0.28)
        inside.fill(Path(ellipseIn: CGRect(x: center.x - rx * 0.78, y: center.y - ry * 0.98, width: rx * 0.72, height: ry * 0.62)),
                    with: .color(highlight.opacity(0.65)))
    }

    /// Pequenas marcas de folhagem: escuras no lado claro e claras no lado escuro.
    private func leafTicks(_ ctx: inout GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat) {
        guard health != .withered else { return }
        for (dx, dy) in [(-0.5, -0.05), (-0.25, 0.35), (0.35, -0.3), (0.55, 0.2), (0.1, 0.05)] {
            let p = CGPoint(x: center.x + rx * dx, y: center.y + ry * dy)
            var tick = Path()
            tick.move(to: CGPoint(x: p.x - rx * 0.09, y: p.y - ry * 0.05))
            tick.addQuadCurve(to: CGPoint(x: p.x + rx * 0.09, y: p.y - ry * 0.05), control: CGPoint(x: p.x, y: p.y + ry * 0.08))
            let color = dx < 0.06 ? leafDark.opacity(0.45) : leafLight.opacity(0.45)
            ctx.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: max(0.8, rx * 0.04), lineCap: .round))
        }
    }

    // MARK: - Primeiros estágios

    private func drawSeed(_ ctx: inout GraphicsContext, _ g: Geo) {
        let mound = CGRect(x: g.cx - g.s * 0.15, y: g.ground - g.s * 0.07, width: g.s * 0.3, height: g.s * 0.11)
        twoTone(&ctx, Path(ellipseIn: mound), axis: g.cx,
                light: Color(red: 0.55, green: 0.35, blue: 0.16), dark: Color(red: 0.45, green: 0.28, blue: 0.12))
        ctx.fill(ellipse(CGPoint(x: g.cx, y: g.ground - g.s * 0.07), g.s * 0.09, g.s * 0.06, angle: -0.4),
                 with: .color(Color(red: 0.86, green: 0.70, blue: 0.42)))
        guard health != .withered else { return }
        ctx.fill(ellipse(CGPoint(x: g.cx + g.s * 0.025, y: g.ground - g.s * 0.13), g.s * 0.07, g.s * 0.035, angle: -0.6),
                 with: .color(leafLight))
    }

    private func drawSprout(_ ctx: inout GraphicsContext, _ g: Geo) {
        switch species {
        case .cactus:
            let body = Path(roundedRect: CGRect(x: g.cx - g.s * 0.08, y: g.ground - g.h * 0.7, width: g.s * 0.16, height: g.h * 0.7),
                            cornerRadius: g.s * 0.08)
            twoTone(&ctx, body, axis: g.cx, light: leafLight, dark: leafDark)
        case .bamboo:
            let shoot = Path(roundedRect: CGRect(x: g.cx - g.s * 0.025, y: g.top, width: g.s * 0.05, height: g.h), cornerRadius: g.s * 0.02)
            twoTone(&ctx, shoot, axis: g.cx, light: leafLight, dark: leafDark)
            ctx.fill(ellipse(CGPoint(x: g.cx + g.s * 0.07, y: g.top + g.h * 0.2), g.s * 0.14, g.s * 0.05, angle: -0.5), with: .color(leafDark))
        case .pine, .sequoia:
            // Pinheirinho: caule curto e dois andares pequenos.
            let stemTop = g.ground - g.h * 0.3
            drawTrunk(&ctx, g, width: g.s * 0.035, topY: stemTop)
            for (i, scale) in [1.0, 0.7].enumerated() {
                let base = stemTop - CGFloat(i) * g.h * 0.28
                let half = g.s * (species == .sequoia ? 0.08 : 0.11) * CGFloat(scale)
                var tier = Path()
                tier.move(to: CGPoint(x: g.cx, y: base - g.h * 0.45 * CGFloat(scale)))
                tier.addLine(to: CGPoint(x: g.cx + half, y: base))
                tier.addLine(to: CGPoint(x: g.cx - half, y: base))
                tier.closeSubpath()
                twoTone(&ctx, tier, axis: g.cx, light: leafLight, dark: leafDark)
            }
        case .palm:
            // Brotinho de palmeira: três folhas compridas saindo do chão.
            let base = CGPoint(x: g.cx, y: g.ground - g.h * 0.12)
            ctx.fill(ellipse(base, g.s * 0.07, g.h * 0.24), with: .color(trunkBase))
            for angle in [Double.pi + 0.6, -Double.pi / 2 - 0.15, -0.6] {
                let length = g.h * 0.75
                let center = CGPoint(x: base.x + cos(angle) * length / 2, y: base.y + sin(angle) * length / 2)
                ctx.fill(ellipse(center, length, g.s * 0.07, angle: angle), with: .color(cos(angle) < 0 ? leafLight : leafDark))
            }
        case .baobab:
            // Mini baobá: tronquinho bojudo com um tufo.
            var trunk = Path()
            trunk.move(to: CGPoint(x: g.cx - g.s * 0.06, y: g.ground))
            trunk.addQuadCurve(to: CGPoint(x: g.cx - g.s * 0.025, y: g.ground - g.h * 0.6), control: CGPoint(x: g.cx - g.s * 0.1, y: g.ground - g.h * 0.3))
            trunk.addLine(to: CGPoint(x: g.cx + g.s * 0.025, y: g.ground - g.h * 0.6))
            trunk.addQuadCurve(to: CGPoint(x: g.cx + g.s * 0.06, y: g.ground), control: CGPoint(x: g.cx + g.s * 0.1, y: g.ground - g.h * 0.3))
            trunk.closeSubpath()
            twoTone(&ctx, trunk, axis: g.cx, light: trunkLight, dark: trunkDark)
            twoTone(&ctx, ellipse(CGPoint(x: g.cx, y: g.ground - g.h * 0.72), g.s * 0.2, g.s * 0.08), axis: g.cx, light: leafLight, dark: leafDark)
        case .willow:
            // Salgueirinho: caule com folhas finas caindo.
            let tip = CGPoint(x: g.cx, y: g.top)
            var stem = Path()
            stem.move(to: CGPoint(x: g.cx, y: g.ground))
            stem.addLine(to: tip)
            ctx.stroke(stem, with: .color(trunkBase), style: StrokeStyle(lineWidth: max(1, g.s * 0.03), lineCap: .round))
            for dx in [-0.09, -0.03, 0.03, 0.09] {
                var strand = Path()
                strand.move(to: tip)
                strand.addQuadCurve(to: CGPoint(x: tip.x + g.s * dx * 1.4, y: tip.y + g.h * 0.55),
                                    control: CGPoint(x: tip.x + g.s * dx * 1.6, y: tip.y))
                ctx.stroke(strand, with: .color(dx < 0 ? leafLight : leafDark), style: StrokeStyle(lineWidth: max(1, g.s * 0.03), lineCap: .round))
            }
        case .bonsai:
            // Muda de bonsai já no vasinho.
            let potTop = g.ground - g.s * 0.08
            var pot = Path()
            pot.move(to: CGPoint(x: g.cx - g.s * 0.14, y: potTop))
            pot.addLine(to: CGPoint(x: g.cx + g.s * 0.14, y: potTop))
            pot.addLine(to: CGPoint(x: g.cx + g.s * 0.1, y: g.ground))
            pot.addLine(to: CGPoint(x: g.cx - g.s * 0.1, y: g.ground))
            pot.closeSubpath()
            twoTone(&ctx, pot, axis: g.cx, light: Color(red: 0.70, green: 0.38, blue: 0.25), dark: Color(red: 0.55, green: 0.28, blue: 0.18))
            drawSeedling(&ctx, g, from: potTop, stem: trunkBase, bud: nil)
        default:
            // Carvalho, cerejeira, ipê e bétula: caule com duas folhas e um detalhe da espécie.
            let bud: Color? = switch species {
            case .cherry: .white
            case .ipe: Color(red: 0.98, green: 0.80, blue: 0.15)
            case .oak: Color(red: 0.62, green: 0.42, blue: 0.20)
            default: nil
            }
            let stem = species == .birch ? Color(red: 0.92, green: 0.91, blue: 0.86) : leafDark
            drawSeedling(&ctx, g, from: g.ground, stem: stem, bud: bud)
        }
    }

    /// Caule com duas folhas arredondadas (clara à esquerda, escura à direita) e nervura central.
    private func drawSeedling(_ ctx: inout GraphicsContext, _ g: Geo, from base: CGFloat, stem stemColor: Color, bud: Color?) {
        let wilt = health == .withered
        let tip = CGPoint(x: g.cx + (wilt ? g.s * 0.06 : 0), y: g.top + (wilt ? g.h * 0.25 : 0))
        var stem = Path()
        stem.move(to: CGPoint(x: g.cx, y: base))
        stem.addQuadCurve(to: tip, control: CGPoint(x: g.cx - g.s * 0.02, y: (base + tip.y) / 2))
        ctx.stroke(stem, with: .color(wilt ? trunkBase : stemColor), style: StrokeStyle(lineWidth: max(1, g.s * 0.035), lineCap: .round))
        // O ipê brota com folhas verdes; o amarelo vem nas flores.
        let light = species == .ipe ? Color(red: 0.55, green: 0.75, blue: 0.30) : leafLight
        let dark = species == .ipe ? Color(red: 0.40, green: 0.60, blue: 0.22) : leafDark
        let droop = wilt ? 0.9 : 0
        for (side, color) in [(-1.0, light), (1.0, dark)] {
            let angle = side < 0 ? 0.5 + droop : -0.5 - droop
            let center = CGPoint(x: tip.x + CGFloat(side) * g.s * 0.1, y: tip.y - g.s * 0.005)
            let leaf = ellipse(center, g.s * 0.22, g.s * 0.12, angle: angle)
            ctx.fill(leaf, with: .color(color))
            var vein = Path()
            vein.move(to: CGPoint(x: tip.x + CGFloat(side) * g.s * 0.015, y: tip.y))
            vein.addLine(to: CGPoint(x: center.x + CGFloat(side) * g.s * 0.07 * CGFloat(cos(angle)),
                                     y: center.y + CGFloat(side) * g.s * 0.07 * CGFloat(sin(angle))))
            ctx.stroke(vein, with: .color(dark.mixed(with: .black, amount: 0.25).opacity(0.55)),
                       style: StrokeStyle(lineWidth: max(0.6, g.s * 0.012), lineCap: .round))
        }
        if let bud, !wilt {
            ctx.fill(circle(CGPoint(x: tip.x, y: tip.y - g.s * 0.04), g.s * 0.032), with: .color(bud))
        }
    }

    // MARK: - Espécies

    /// Copa arredondada em forma de nuvem (carvalho, cerejeira, ipê): tronco curto e copa farta.
    private func drawRound(_ ctx: inout GraphicsContext, _ g: Geo, flatten: CGFloat, blossoms: Color? = nil) {
        let trunkTop = g.ground - g.h * 0.36
        drawTrunk(&ctx, g, width: g.s * (stage == .ancient ? 0.1 : 0.08), topY: trunkTop - g.h * 0.08)

        let center = CGPoint(x: g.cx, y: g.ground - g.h * 0.64)
        let rx = g.h * (stage == .young ? 0.38 : 0.42)
        let ry = g.h * 0.34 * flatten
        let bumps = stage == .young ? 7 : (stage == .mature ? 9 : 11)
        let canopy = cloudCanopy(center: center, rx: rx, ry: ry, bumps: bumps)
        shadeCanopy(&ctx, canopy, center: center, rx: rx, ry: ry)
        leafTicks(&ctx, center: center, rx: rx, ry: ry)

        if let blossoms, health == .healthy && season != .winter {
            for i in 0..<14 {
                let a = Double(i) * 2.39996
                let d = sqrt(Double(i + 1) / 14)
                let p = CGPoint(x: center.x + CGFloat(cos(a) * d) * rx * 0.85, y: center.y + CGFloat(sin(a) * d) * ry * 0.8)
                ctx.fill(circle(p, g.s * 0.014), with: .color(blossoms.opacity(0.95)))
            }
        } else if species == .oak && stage == .ancient && health == .healthy && season != .winter {
            // Carvalho ancestral dá frutinhos.
            for (dx, dy) in [(-0.5, 0.1), (-0.15, -0.35), (0.3, 0.2), (0.55, -0.15), (-0.05, 0.45)] {
                let p = CGPoint(x: center.x + rx * dx, y: center.y + ry * dy)
                ctx.fill(circle(p, g.s * 0.022), with: .color(Color(red: 0.93, green: 0.45, blue: 0.16)))
                ctx.fill(circle(CGPoint(x: p.x - g.s * 0.006, y: p.y - g.s * 0.006), g.s * 0.007), with: .color(.white.opacity(0.6)))
            }
        }
    }

    private func drawConifer(_ ctx: inout GraphicsContext, _ g: Geo, widthFactor: CGFloat, trunkShare: CGFloat) {
        drawTrunk(&ctx, g, width: g.s * (species == .sequoia ? 0.1 : 0.06) * (stage == .ancient ? 1.3 : 1),
                  topY: g.ground - g.h * (trunkShare + 0.15))

        let tiers = stage == .young ? 3 : (stage == .mature ? 4 : 5)
        let foliage = g.h * (1 - trunkShare)
        let step = foliage / CGFloat(tiers)
        let tierHeight = step * 1.6
        let highlight = leafLight.mixed(with: Color(red: 0.85, green: 1, blue: 0.95), amount: 0.25)
        for i in 0..<tiers {
            let t = CGFloat(i) / CGFloat(tiers)
            let baseY = g.ground - g.h * trunkShare - CGFloat(i) * step * 0.9
            let half = g.h * widthFactor * 0.5 * (1 - t * 0.6)
            let apex = CGPoint(x: g.cx, y: baseY - tierHeight)

            // Andar com laterais levemente estufadas e a borda de baixo em ondas arredondadas.
            var tier = Path()
            tier.move(to: apex)
            tier.addQuadCurve(to: CGPoint(x: g.cx + half, y: baseY),
                              control: CGPoint(x: g.cx + half * 0.5, y: apex.y + tierHeight * 0.6))
            let scallops = 4
            let w = 2 * half / CGFloat(scallops)
            for k in 0..<scallops {
                let x0 = g.cx + half - CGFloat(k) * w
                tier.addQuadCurve(to: CGPoint(x: x0 - w, y: baseY),
                                  control: CGPoint(x: x0 - w / 2, y: baseY + tierHeight * 0.17))
            }
            tier.addQuadCurve(to: apex, control: CGPoint(x: g.cx - half * 0.5, y: apex.y + tierHeight * 0.6))
            tier.closeSubpath()
            twoTone(&ctx, tier, axis: g.cx, light: leafLight, dark: leafDark)

            // Faixa de luz na borda esquerda e sombra do andar de cima.
            var inside = ctx
            inside.clip(to: tier)
            var glint = Path()
            glint.move(to: apex)
            glint.addLine(to: CGPoint(x: g.cx - half * 1.05, y: baseY + tierHeight * 0.1))
            glint.addLine(to: CGPoint(x: g.cx - half * 0.62, y: baseY + tierHeight * 0.1))
            glint.closeSubpath()
            inside.fill(glint, with: .color(highlight.opacity(0.55)))
            if i < tiers - 1 {
                inside.fill(Path(CGRect(x: g.cx - half, y: apex.y, width: half * 2, height: tierHeight * 0.32)),
                            with: .color(.black.opacity(0.1)))
            }

            if season == .winter && health == .healthy {
                let capH = tierHeight * 0.38
                let capHalf = half * 0.4
                var cap = Path()
                cap.move(to: apex)
                cap.addQuadCurve(to: CGPoint(x: g.cx + capHalf, y: apex.y + capH),
                                 control: CGPoint(x: g.cx + capHalf * 0.5, y: apex.y + capH * 0.6))
                cap.addQuadCurve(to: CGPoint(x: g.cx, y: apex.y + capH * 0.85),
                                 control: CGPoint(x: g.cx + capHalf * 0.5, y: apex.y + capH * 1.15))
                cap.addQuadCurve(to: CGPoint(x: g.cx - capHalf, y: apex.y + capH),
                                 control: CGPoint(x: g.cx - capHalf * 0.5, y: apex.y + capH * 1.15))
                cap.addQuadCurve(to: apex, control: CGPoint(x: g.cx - capHalf * 0.5, y: apex.y + capH * 0.6))
                cap.closeSubpath()
                twoTone(&ctx, cap, axis: g.cx, light: .white, dark: Color(red: 0.85, green: 0.9, blue: 0.96))
            }
        }
    }

    /// Árvore seca: tronco e galhos nus, como a árvore que morre no Forest.
    private func drawDead(_ ctx: inout GraphicsContext, _ g: Geo) {
        let width = max(1.2, g.s * 0.045)
        var trunk = Path()
        trunk.move(to: CGPoint(x: g.cx, y: g.ground))
        trunk.addLine(to: CGPoint(x: g.cx, y: g.top))
        ctx.stroke(trunk, with: .color(trunkBase), style: StrokeStyle(lineWidth: width, lineCap: .round))

        var branches = Path()
        let levels = stage == .young ? 3 : 4
        for i in 0..<levels {
            let y = g.ground - g.h * (0.35 + 0.17 * CGFloat(i))
            let length = g.h * (0.3 - 0.05 * CGFloat(i))
            for dir in [-1.0, 1.0] {
                let start = CGPoint(x: g.cx, y: y + (dir < 0 ? 0 : g.h * 0.05))
                branches.move(to: start)
                branches.addLine(to: CGPoint(x: g.cx + CGFloat(dir) * length * 0.7, y: start.y - length * 0.55))
            }
        }
        ctx.stroke(branches, with: .color(trunkBase), style: StrokeStyle(lineWidth: width * 0.6, lineCap: .round))
    }

    private func drawBonsai(_ ctx: inout GraphicsContext, _ g: Geo) {
        let potTop = g.ground - g.s * 0.12
        var pot = Path()
        pot.move(to: CGPoint(x: g.cx - g.s * 0.24, y: potTop))
        pot.addLine(to: CGPoint(x: g.cx + g.s * 0.24, y: potTop))
        pot.addLine(to: CGPoint(x: g.cx + g.s * 0.17, y: g.ground))
        pot.addLine(to: CGPoint(x: g.cx - g.s * 0.17, y: g.ground))
        pot.closeSubpath()
        twoTone(&ctx, pot, axis: g.cx, light: Color(red: 0.70, green: 0.38, blue: 0.25), dark: Color(red: 0.55, green: 0.28, blue: 0.18))

        let h = g.h * 0.9
        let top = CGPoint(x: g.cx + g.s * 0.1, y: potTop - h * 0.75)
        var trunk = Path()
        trunk.move(to: CGPoint(x: g.cx, y: potTop))
        trunk.addCurve(to: top, control1: CGPoint(x: g.cx - g.s * 0.18, y: potTop - h * 0.3),
                       control2: CGPoint(x: g.cx + g.s * 0.22, y: potTop - h * 0.45))
        ctx.stroke(trunk, with: .color(trunkDark), style: StrokeStyle(lineWidth: g.s * (stage == .ancient ? 0.07 : 0.05), lineCap: .round))

        guard health != .withered else { return }
        let pads: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.14, 0.5, 0.26, 0.1), (0.2, 0.55, 0.22, 0.09), (0.1, 0.8, 0.34, 0.13), (-0.02, 0.98, 0.22, 0.09),
        ]
        for (dx, dy, w, ph) in pads {
            let c = CGPoint(x: g.cx + dx * g.s, y: potTop - dy * h)
            twoTone(&ctx, ellipse(c, w * g.s, ph * g.s), axis: c.x, light: leafLight, dark: leafDark)
        }
    }

    private func drawWillow(_ ctx: inout GraphicsContext, _ g: Geo) {
        drawTrunk(&ctx, g, width: g.s * (stage == .ancient ? 0.11 : 0.08), topY: g.ground - g.h * 0.72)
        let crown = CGPoint(x: g.cx, y: g.ground - g.h * 0.76)
        let dome = Path(ellipseIn: CGRect(x: crown.x - g.h * 0.36, y: crown.y - g.h * 0.2, width: g.h * 0.72, height: g.h * 0.38))
        twoTone(&ctx, dome, axis: g.cx, light: leafLight, dark: leafDark)

        let strands = stage == .young ? 9 : 14
        for i in 0..<strands {
            let t = CGFloat(i) / CGFloat(strands - 1)
            let x = crown.x - g.h * 0.33 + t * g.h * 0.66
            let swing = animated ? CGFloat(sin(time * 1.1 + Double(i))) * g.s * 0.02 : 0
            let length = g.h * (0.32 + 0.22 * (1 - abs(t - 0.5) * 2))
            var p = Path()
            p.move(to: CGPoint(x: x, y: crown.y + g.h * 0.05))
            p.addQuadCurve(to: CGPoint(x: x + swing + (t - 0.5) * g.s * 0.06, y: crown.y + length),
                           control: CGPoint(x: x + (t - 0.5) * g.s * 0.1, y: crown.y + length * 0.4))
            ctx.stroke(p, with: .color(x < g.cx ? leafLight : leafDark), style: StrokeStyle(lineWidth: max(1, g.s * 0.022), lineCap: .round))
        }
    }

    private func drawCactus(_ ctx: inout GraphicsContext, _ g: Geo) {
        var cactus = ctx
        if health == .withered {
            cactus.translateBy(x: g.cx, y: g.ground)
            cactus.rotate(by: .radians(0.18))
            cactus.translateBy(x: -g.cx, y: -g.ground)
        }
        let w = g.s * (stage == .ancient ? 0.2 : 0.16)
        var body = Path(roundedRect: CGRect(x: g.cx - w / 2, y: g.top, width: w, height: g.h), cornerRadius: w / 2)
        let armW = w * 0.62
        func arm(_ dir: CGFloat, y: CGFloat, length: CGFloat) {
            let horizontalX = dir > 0 ? g.cx : g.cx - g.s * 0.2
            body.addPath(Path(roundedRect: CGRect(x: horizontalX, y: y, width: g.s * 0.2, height: armW), cornerRadius: armW / 2))
            let vx = dir > 0 ? g.cx + g.s * 0.2 - armW : g.cx - g.s * 0.2
            body.addPath(Path(roundedRect: CGRect(x: vx, y: y - length + armW, width: armW, height: length), cornerRadius: armW / 2))
        }
        arm(1, y: g.ground - g.h * 0.5, length: g.h * 0.35)
        if stage >= .mature { arm(-1, y: g.ground - g.h * 0.38, length: g.h * 0.28) }
        twoTone(&cactus, body, axis: g.cx, light: leafLight, dark: leafDark)

        if stage == .ancient && health == .healthy {
            cactus.fill(circle(CGPoint(x: g.cx, y: g.top - g.s * 0.01), g.s * 0.05), with: .color(Color(red: 0.98, green: 0.42, blue: 0.6)))
        }
    }

    private func drawBamboo(_ ctx: inout GraphicsContext, _ g: Geo) {
        let count = stage == .young ? 2 : (stage == .mature ? 3 : 5)
        for i in 0..<count {
            let offset = (CGFloat(i) - CGFloat(count - 1) / 2) * g.s * 0.09
            let height = g.h * (0.8 + 0.2 * CGFloat((i * 37) % 10) / 10)
            let w = g.s * 0.05
            let x = g.cx + offset
            let stalk = Path(roundedRect: CGRect(x: x - w / 2, y: g.ground - height, width: w, height: height), cornerRadius: w / 3)
            twoTone(&ctx, stalk, axis: x, light: leafLight, dark: leafDark)
            var nodes = Path()
            var y = g.ground - g.h * 0.14
            while y > g.ground - height + 4 {
                nodes.move(to: CGPoint(x: x - w / 2, y: y))
                nodes.addLine(to: CGPoint(x: x + w / 2, y: y))
                y -= g.h * 0.15
            }
            ctx.stroke(nodes, with: .color(leafDark.mixed(with: .black, amount: 0.25)), lineWidth: max(0.6, g.s * 0.01))
            guard health != .withered else { continue }
            let leafY = g.ground - height + g.h * 0.08
            ctx.fill(ellipse(CGPoint(x: x + g.s * 0.065, y: leafY), g.s * 0.14, g.s * 0.045, angle: -0.5), with: .color(leafDark))
            ctx.fill(ellipse(CGPoint(x: x - g.s * 0.06, y: leafY + g.h * 0.08), g.s * 0.13, g.s * 0.04, angle: 0.45), with: .color(leafLight))
        }
    }

    /// Palmeira: tronco curvo com anéis, folhas compridas em leque e cocos nas adultas.
    private func drawPalm(_ ctx: inout GraphicsContext, _ g: Geo) {
        let top = CGPoint(x: g.cx + g.s * 0.08, y: g.ground - g.h * 0.8)
        let bend = CGPoint(x: g.cx - g.s * 0.07, y: g.ground - g.h * 0.45)
        let tw = g.s * (stage == .ancient ? 0.06 : 0.045)

        var trunk = Path()
        trunk.move(to: CGPoint(x: g.cx - tw, y: g.ground))
        trunk.addQuadCurve(to: CGPoint(x: top.x - tw * 0.6, y: top.y), control: CGPoint(x: bend.x - tw, y: bend.y))
        trunk.addLine(to: CGPoint(x: top.x + tw * 0.6, y: top.y))
        trunk.addQuadCurve(to: CGPoint(x: g.cx + tw, y: g.ground), control: CGPoint(x: bend.x + tw, y: bend.y))
        trunk.closeSubpath()
        twoTone(&ctx, trunk, axis: g.cx - g.s * 0.01, light: trunkLight, dark: trunkDark)

        // Anéis ao longo do tronco, seguindo a mesma curva.
        var rings = Path()
        for i in 1..<6 {
            let t = CGFloat(i) / 6
            let x = (1 - t) * (1 - t) * g.cx + 2 * (1 - t) * t * bend.x + t * t * top.x
            let y = (1 - t) * (1 - t) * g.ground + 2 * (1 - t) * t * bend.y + t * t * top.y
            rings.move(to: CGPoint(x: x - tw * 0.8, y: y))
            rings.addLine(to: CGPoint(x: x + tw * 0.8, y: y + tw * 0.2))
        }
        ctx.stroke(rings, with: .color(trunkDark.mixed(with: .black, amount: 0.2)), lineWidth: max(0.6, g.s * 0.01))

        let length = g.h * 0.46
        let angles: [Double] = switch stage {
        case .young: [.pi + 0.35, .pi - 0.45, -0.35, 0.45, -.pi / 2]
        case .mature: [.pi + 0.45, .pi - 0.1, .pi - 0.7, -0.45, 0.1, 0.7]
        default: [.pi + 0.5, .pi - 0.05, .pi - 0.7, -0.5, 0.05, 0.7, -.pi / 2]
        }
        for angle in angles {
            let droop = sin(time * 1.2 + angle) * (animated ? 0.04 : 0)
            let a = angle + droop
            let center = CGPoint(x: top.x + cos(a) * length / 2, y: top.y + sin(a) * length / 2)
            let leaf = ellipse(center, length, g.h * 0.11, angle: a)
            if abs(cos(a)) < 0.2 {
                twoTone(&ctx, leaf, axis: top.x, light: leafLight, dark: leafDark)
            } else {
                ctx.fill(leaf, with: .color(cos(a) < 0 ? leafLight : leafDark))
            }
        }

        if stage >= .mature && health == .healthy {
            for dx in [-0.035, 0.0, 0.035] {
                ctx.fill(circle(CGPoint(x: top.x + g.s * dx, y: top.y + g.s * 0.04), g.s * 0.028),
                         with: .color(Color(red: 0.45, green: 0.30, blue: 0.16)))
            }
        }
    }

    /// Baobá: tronco largo em forma de garrafa, galhos curtos e tufos achatados no alto.
    private func drawBaobab(_ ctx: inout GraphicsContext, _ g: Geo) {
        let w = g.s * (stage == .ancient ? 0.34 : (stage == .mature ? 0.28 : 0.22))
        let trunkTop = g.ground - g.h * 0.68

        var trunk = Path()
        trunk.move(to: CGPoint(x: g.cx - w * 0.5, y: g.ground))
        trunk.addQuadCurve(to: CGPoint(x: g.cx - w * 0.28, y: trunkTop), control: CGPoint(x: g.cx - w * 0.78, y: g.ground - g.h * 0.38))
        trunk.addLine(to: CGPoint(x: g.cx + w * 0.28, y: trunkTop))
        trunk.addQuadCurve(to: CGPoint(x: g.cx + w * 0.5, y: g.ground), control: CGPoint(x: g.cx + w * 0.78, y: g.ground - g.h * 0.38))
        trunk.closeSubpath()
        twoTone(&ctx, trunk, axis: g.cx, light: trunkLight, dark: trunkDark)

        let tips: [CGPoint] = [
            CGPoint(x: g.cx - w * 0.75, y: trunkTop - g.h * 0.14),
            CGPoint(x: g.cx - w * 0.22, y: trunkTop - g.h * 0.24),
            CGPoint(x: g.cx + w * 0.25, y: trunkTop - g.h * 0.22),
            CGPoint(x: g.cx + w * 0.78, y: trunkTop - g.h * 0.12),
        ]
        var branches = Path()
        for tip in tips {
            branches.move(to: CGPoint(x: g.cx + (tip.x - g.cx) * 0.25, y: trunkTop + 2))
            branches.addLine(to: tip)
        }
        ctx.stroke(branches, with: .color(trunkDark), style: StrokeStyle(lineWidth: max(1.2, g.s * 0.04), lineCap: .round))

        guard health != .withered else { return }
        for tip in tips {
            twoTone(&ctx, ellipse(CGPoint(x: tip.x, y: tip.y - g.h * 0.02), g.h * 0.3, g.h * 0.11),
                    axis: tip.x, light: leafLight, dark: leafDark)
        }
    }

    private func drawBirch(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.075 : 0.06)
        let trunkTop = g.ground - g.h * 0.55
        drawTrunk(&ctx, g, width: tw, topY: trunkTop)
        var marks = Path()
        var y = g.ground - g.h * 0.08
        var flip = false
        while y > trunkTop + 4 {
            let x0 = g.cx + (flip ? 0 : -tw * 0.45)
            marks.move(to: CGPoint(x: x0, y: y))
            marks.addLine(to: CGPoint(x: x0 + tw * 0.4, y: y))
            y -= g.h * 0.09
            flip.toggle()
        }
        ctx.stroke(marks, with: .color(.black.opacity(0.7)), lineWidth: max(0.7, g.s * 0.012))

        // Copa alta e estreita, em nuvem.
        let center = CGPoint(x: g.cx, y: g.ground - g.h * 0.7)
        let rx = g.h * 0.24
        let ry = g.h * 0.3
        let canopy = cloudCanopy(center: center, rx: rx, ry: ry, bumps: 8)
        shadeCanopy(&ctx, canopy, center: center, rx: rx, ry: ry)
        leafTicks(&ctx, center: center, rx: rx, ry: ry)
    }

    private func drawFlowers(_ ctx: inout GraphicsContext, _ g: Geo) {
        let colors = [Color(red: 1, green: 0.85, blue: 0.3), .white, Color(red: 1, green: 0.6, blue: 0.75)]
        for (i, dx) in [-0.24, -0.16, 0.19, 0.27].enumerated() {
            ctx.fill(circle(CGPoint(x: g.cx + g.s * dx, y: g.ground - g.s * 0.01), g.s * 0.018), with: .color(colors[i % 3]))
        }
    }

    private func drawFallingLeaves(_ ctx: inout GraphicsContext, _ g: Geo) {
        let color = leafLight.mixed(with: .orange, amount: 0.3)
        for i in 0..<3 {
            let center: CGPoint
            let angle: Double
            if animated {
                let phase = (time * 0.25 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let x = g.cx + CGFloat(i - 1) * g.s * 0.18 + CGFloat(sin(time * 1.5 + Double(i))) * g.s * 0.05
                center = CGPoint(x: x, y: g.ground - g.h * 0.6 + CGFloat(phase) * g.h * 0.6)
                angle = time * 2 + Double(i)
            } else {
                center = CGPoint(x: g.cx + CGFloat(i - 1) * g.s * 0.2, y: g.ground - g.s * 0.01)
                angle = Double(i)
            }
            ctx.fill(ellipse(center, g.s * 0.06, g.s * 0.03, angle: angle), with: .color(color))
        }
    }
}
