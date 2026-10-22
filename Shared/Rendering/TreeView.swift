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
                case .cherry: drawRound(&tree, g, flatten: 0.85, blossoms: true)
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
        default:
            let wilt = health == .withered
            let tip = CGPoint(x: g.cx + (wilt ? g.s * 0.06 : 0), y: g.top + (wilt ? g.h * 0.25 : 0))
            var stem = Path()
            stem.move(to: CGPoint(x: g.cx, y: g.ground))
            stem.addQuadCurve(to: tip, control: CGPoint(x: g.cx - g.s * 0.02, y: g.ground - g.h * 0.5))
            ctx.stroke(stem, with: .color(wilt ? trunkBase : leafDark), style: StrokeStyle(lineWidth: max(1, g.s * 0.035), lineCap: .round))
            let droop = wilt ? 0.9 : 0
            // Folha esquerda clara, direita escura: a assinatura do estilo.
            ctx.fill(ellipse(CGPoint(x: tip.x - g.s * 0.085, y: tip.y), g.s * 0.18, g.s * 0.085, angle: 0.45 + droop), with: .color(leafLight))
            ctx.fill(ellipse(CGPoint(x: tip.x + g.s * 0.085, y: tip.y - g.s * 0.01), g.s * 0.18, g.s * 0.085, angle: -0.45 - droop), with: .color(leafDark))
            if species == .cherry && !wilt {
                ctx.fill(circle(CGPoint(x: tip.x, y: tip.y - g.s * 0.035), g.s * 0.03), with: .color(.white))
            }
        }
    }

    // MARK: - Espécies

    /// Copa arredondada (carvalho, cerejeira).
    private func drawRound(_ ctx: inout GraphicsContext, _ g: Geo, flatten: CGFloat, blossoms: Bool = false) {
        let trunkTop = g.ground - g.h * 0.42
        drawTrunk(&ctx, g, width: g.s * (stage == .ancient ? 0.11 : 0.085), topY: trunkTop - g.h * 0.1)

        let r = g.h * 0.3
        let center = CGPoint(x: g.cx, y: g.ground - g.h * 0.64)
        var canopy = Path()
        let lobes: [(CGFloat, CGFloat, CGFloat)] = stage == .young
            ? [(0, -0.2, 0.95), (-0.5, 0.15, 0.7), (0.5, 0.15, 0.7)]
            : [(0, -0.3, 0.95), (-0.55, 0.05, 0.78), (0.55, 0.05, 0.78), (-0.25, 0.35, 0.7), (0.25, 0.35, 0.7)]
        for (dx, dy, k) in lobes {
            canopy.addPath(Path(ellipseIn: CGRect(x: center.x + dx * r * 1.25 - r * k * 1.15,
                                                  y: center.y + dy * r * flatten - r * k * flatten,
                                                  width: r * k * 2.3, height: r * k * 2 * flatten)))
        }
        twoTone(&ctx, canopy, axis: g.cx, light: leafLight, dark: leafDark)

        // Pequenas marcas de textura nas folhas.
        for (dx, dy) in [(-0.45, -0.1), (-0.15, 0.3), (0.35, -0.25), (0.5, 0.25)] {
            let p = CGPoint(x: center.x + dx * r, y: center.y + dy * r)
            ctx.fill(ellipse(p, r * 0.22, r * 0.09, angle: -0.5), with: .color(dx < 0 ? leafDark.opacity(0.35) : leafLight.opacity(0.35)))
        }

        if blossoms && health == .healthy && season != .winter {
            for i in 0..<12 {
                let a = Double(i) * 2.39996
                let d = r * 1.1 * sqrt(Double(i + 1) / 12)
                let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d * 0.7)
                ctx.fill(circle(p, g.s * 0.013), with: .color(.white.opacity(0.95)))
            }
        }
    }

    private func drawConifer(_ ctx: inout GraphicsContext, _ g: Geo, widthFactor: CGFloat, trunkShare: CGFloat) {
        drawTrunk(&ctx, g, width: g.s * (species == .sequoia ? 0.1 : 0.06) * (stage == .ancient ? 1.3 : 1),
                  topY: g.ground - g.h * (trunkShare + 0.15))

        let tiers = stage == .young ? 3 : (stage == .mature ? 4 : 5)
        let foliage = g.h * (1 - trunkShare)
        let step = foliage / CGFloat(tiers)
        let tierHeight = step * 1.55
        for i in 0..<tiers {
            let t = CGFloat(i) / CGFloat(tiers)
            let baseY = g.ground - g.h * trunkShare - CGFloat(i) * step * 0.92
            let half = g.h * widthFactor * 0.5 * (1 - t * 0.62)
            let apex = CGPoint(x: g.cx, y: baseY - tierHeight)

            var tier = Path()
            tier.move(to: apex)
            tier.addLine(to: CGPoint(x: g.cx + half, y: baseY))
            let teeth = 6
            for k in 1..<teeth {
                let x = g.cx + half - CGFloat(k) * (2 * half / CGFloat(teeth))
                tier.addLine(to: CGPoint(x: x, y: baseY - (k.isMultiple(of: 2) ? 0 : tierHeight * 0.12)))
            }
            tier.addLine(to: CGPoint(x: g.cx - half, y: baseY))
            tier.closeSubpath()
            twoTone(&ctx, tier, axis: g.cx, light: leafLight, dark: leafDark)

            if season == .winter && health == .healthy {
                let capH = tierHeight * 0.38
                let capHalf = half * 0.38
                var cap = Path()
                cap.move(to: apex)
                cap.addLine(to: CGPoint(x: g.cx + capHalf, y: apex.y + capH))
                cap.addLine(to: CGPoint(x: g.cx + capHalf * 0.3, y: apex.y + capH * 0.8))
                cap.addLine(to: CGPoint(x: g.cx - capHalf * 0.3, y: apex.y + capH * 1.05))
                cap.addLine(to: CGPoint(x: g.cx - capHalf, y: apex.y + capH))
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

    private func drawBirch(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.08 : 0.06)
        let trunkTop = g.ground - g.h * 0.6
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

        var canopy = Path()
        let levels: [(CGFloat, CGFloat)] = [(0.55, 0.36), (0.75, 0.3), (0.92, 0.2)]
        for (at, width) in levels {
            canopy.addPath(Path(ellipseIn: CGRect(x: g.cx - g.h * width / 2, y: g.ground - g.h * at - g.h * 0.12,
                                                  width: g.h * width, height: g.h * 0.26)))
        }
        twoTone(&ctx, canopy, axis: g.cx, light: leafLight, dark: leafDark)
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
