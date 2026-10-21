import SwiftUI

/// Procedurally drawn tree: species × growth stage × health, optionally animated (sway, falling leaves).
struct TreeView: View {
    var species: TreeSpecies
    var stage: GrowthStage
    var health: TreeHealth = .healthy
    var tint: Color? = nil
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
            TreePainter(species: species, stage: stage, health: health, tint: tint,
                        time: time, animated: animated, showsGround: showsGround)
                .draw(in: &ctx, size: size)
        }
        .accessibilityLabel("\(species.title), \(stage.title), \(health.title)")
    }
}

/// Dry stump drawn for missed days in the Everyday matrix.
struct StumpView: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2, ground = size.height * 0.82
            ctx.fill(Path(ellipseIn: CGRect(x: cx - s * 0.3, y: ground - s * 0.05, width: s * 0.6, height: s * 0.12)),
                     with: .color(Color(red: 0.55, green: 0.45, blue: 0.33).opacity(0.6)))
            let stump = CGRect(x: cx - s * 0.12, y: ground - s * 0.22, width: s * 0.24, height: s * 0.24)
            ctx.fill(Path(roundedRect: stump, cornerRadius: s * 0.03), with: .color(Color(red: 0.45, green: 0.36, blue: 0.27)))
            ctx.fill(Path(ellipseIn: CGRect(x: stump.minX, y: stump.minY - s * 0.04, width: stump.width, height: s * 0.08)),
                     with: .color(Color(red: 0.72, green: 0.60, blue: 0.44)))
        }
    }
}

struct TreePainter {
    let species: TreeSpecies
    let stage: GrowthStage
    let health: TreeHealth
    let tint: Color?
    let time: Double
    let animated: Bool
    let showsGround: Bool

    private let witheredLeaf = Color(red: 0.58, green: 0.46, blue: 0.31)
    private let witheredTrunk = Color(red: 0.43, green: 0.37, blue: 0.31)

    private var leaf: Color {
        let base = tint.map { species.leafColor.mixed(with: $0, amount: 0.35) } ?? species.leafColor
        switch health {
        case .healthy: return base
        case .struggling: return base.mixed(with: Color(red: 0.93, green: 0.70, blue: 0.22), amount: 0.55)
        case .withered: return witheredLeaf
        }
    }

    private var trunk: Color { health == .withered ? witheredTrunk : species.trunkColor }

    /// Fraction of foliage drawn; dry trees keep only a few leaves.
    private var density: Double {
        switch health {
        case .healthy: 1
        case .struggling: 0.75
        case .withered: 0.25
        }
    }

    private var stageHeight: CGFloat {
        switch stage {
        case .seed: 0.12
        case .sprout: 0.3
        case .young: 0.52
        case .mature: 0.72
        case .ancient: 0.86
        }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let cx = size.width / 2
        let ground = size.height * 0.9
        let height = s * stageHeight * species.heightFactor

        if showsGround {
            let soil = health == .withered ? Color(red: 0.66, green: 0.55, blue: 0.40) : Color(red: 0.35, green: 0.27, blue: 0.18)
            let width = s * (0.35 + CGFloat(stage.rawValue) * 0.1)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - width / 2, y: ground - s * 0.035, width: width, height: s * 0.08)),
                     with: .color(soil.opacity(0.75)))
        }

        var tree = ctx
        if animated && health != .withered {
            let sway = sin(time * 1.3 + Double(species.rawValue.count)) * (health == .struggling ? 0.045 : 0.025)
            tree.translateBy(x: cx, y: ground)
            tree.rotate(by: .radians(sway))
            tree.translateBy(x: -cx, y: -ground)
        }

        if stage == .ancient && health == .healthy {
            let glow = Gradient(colors: [Color.yellow.opacity(0.22), .clear])
            let center = CGPoint(x: cx, y: ground - height * 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - height * 0.7, y: center.y - height * 0.7, width: height * 1.4, height: height * 1.4)),
                     with: .radialGradient(glow, center: center, startRadius: 0, endRadius: height * 0.7))
        }

        let geo = Geo(s: s, cx: cx, ground: ground, h: height)
        switch stage {
        case .seed: drawSeed(&tree, geo)
        case .sprout: drawSprout(&tree, geo)
        default:
            switch species {
            case .oak: drawOak(&tree, geo)
            case .pine: drawConifer(&tree, geo, widthFactor: 0.62, trunkShare: 0.18)
            case .sequoia: drawConifer(&tree, geo, widthFactor: 0.36, trunkShare: 0.38)
            case .bonsai: drawBonsai(&tree, geo)
            case .cherry: drawCherry(&tree, geo)
            case .willow: drawWillow(&tree, geo)
            case .cactus: drawCactus(&tree, geo)
            case .bamboo: drawBamboo(&tree, geo)
            case .birch: drawBirch(&tree, geo)
            }
        }

        if health == .struggling { drawFallingLeaves(&ctx, geo) }
    }

    // MARK: - Geometry helpers

    private struct Geo {
        let s: CGFloat, cx: CGFloat, ground: CGFloat, h: CGFloat
        var top: CGFloat { ground - h }
    }

    private func ellipse(_ center: CGPoint, _ w: CGFloat, _ h: CGFloat, angle: Double = 0) -> Path {
        Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }

    private func trunkPath(_ g: Geo, bottomWidth: CGFloat, topWidth: CGFloat, topY: CGFloat, lean: CGFloat = 0) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: g.cx - bottomWidth / 2, y: g.ground))
        p.addQuadCurve(to: CGPoint(x: g.cx + lean - topWidth / 2, y: topY),
                       control: CGPoint(x: g.cx - bottomWidth * 0.3, y: (g.ground + topY) / 2))
        p.addLine(to: CGPoint(x: g.cx + lean + topWidth / 2, y: topY))
        p.addQuadCurve(to: CGPoint(x: g.cx + bottomWidth / 2, y: g.ground),
                       control: CGPoint(x: g.cx + bottomWidth * 0.3, y: (g.ground + topY) / 2))
        p.closeSubpath()
        return p
    }

    /// Canopy made of overlapping blobs; `offsets` are (dx, dy, scale) relative to `radius`.
    private func blobs(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                       offsets: [(CGFloat, CGFloat, CGFloat)], color: Color) {
        let visible = max(1, Int((Double(offsets.count) * density).rounded()))
        for (dx, dy, scale) in offsets.prefix(visible) {
            let r = radius * scale
            let c = CGPoint(x: center.x + dx * radius, y: center.y + dy * radius)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            if health != .withered {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.75, width: r * 0.9, height: r * 0.9)),
                         with: .color(.white.opacity(0.12)))
            }
        }
    }

    private func bareBranches(_ ctx: inout GraphicsContext, _ g: Geo, from y: CGFloat, spread: CGFloat) {
        var p = Path()
        for (i, dir) in [-1.0, 1.0, -0.6, 0.7].enumerated() {
            let startY = y + CGFloat(i) * g.h * 0.06
            p.move(to: CGPoint(x: g.cx, y: startY))
            p.addLine(to: CGPoint(x: g.cx + CGFloat(dir) * spread, y: startY - g.h * 0.22))
        }
        ctx.stroke(p, with: .color(trunk), style: StrokeStyle(lineWidth: max(1, g.s * 0.025), lineCap: .round))
    }

    private func roots(_ ctx: inout GraphicsContext, _ g: Geo, width: CGFloat) {
        guard stage == .ancient else { return }
        var p = Path()
        for dir in [-1.0, 1.0] {
            p.move(to: CGPoint(x: g.cx + CGFloat(dir) * width * 0.3, y: g.ground - 2))
            p.addQuadCurve(to: CGPoint(x: g.cx + CGFloat(dir) * width * 1.4, y: g.ground + 1),
                           control: CGPoint(x: g.cx + CGFloat(dir) * width, y: g.ground - width * 0.4))
        }
        ctx.stroke(p, with: .color(trunk), style: StrokeStyle(lineWidth: max(1, width * 0.25), lineCap: .round))
    }

    // MARK: - Early stages

    private func drawSeed(_ ctx: inout GraphicsContext, _ g: Geo) {
        let mound = CGRect(x: g.cx - g.s * 0.16, y: g.ground - g.s * 0.08, width: g.s * 0.32, height: g.s * 0.12)
        ctx.fill(Path(ellipseIn: mound), with: .color(Color(red: 0.45, green: 0.33, blue: 0.22)))
        ctx.fill(ellipse(CGPoint(x: g.cx, y: g.ground - g.s * 0.08), g.s * 0.1, g.s * 0.065, angle: -0.4),
                 with: .color(Color(red: 0.80, green: 0.66, blue: 0.42)))
        if health == .healthy {
            var sprout = Path()
            sprout.move(to: CGPoint(x: g.cx, y: g.ground - g.s * 0.1))
            sprout.addQuadCurve(to: CGPoint(x: g.cx + g.s * 0.03, y: g.ground - g.s * 0.17),
                                control: CGPoint(x: g.cx - g.s * 0.02, y: g.ground - g.s * 0.15))
            ctx.stroke(sprout, with: .color(leaf), style: StrokeStyle(lineWidth: max(1, g.s * 0.02), lineCap: .round))
        }
    }

    private func drawSprout(_ ctx: inout GraphicsContext, _ g: Geo) {
        switch species {
        case .cactus:
            let body = CGRect(x: g.cx - g.s * 0.08, y: g.ground - g.h * 0.75, width: g.s * 0.16, height: g.h * 0.75)
            ctx.fill(Path(roundedRect: body, cornerRadius: g.s * 0.08), with: .color(leaf))
        case .bamboo:
            let shoot = CGRect(x: g.cx - g.s * 0.025, y: g.top, width: g.s * 0.05, height: g.h)
            ctx.fill(Path(roundedRect: shoot, cornerRadius: g.s * 0.02), with: .color(leaf))
            ctx.fill(ellipse(CGPoint(x: g.cx + g.s * 0.07, y: g.top + g.h * 0.2), g.s * 0.14, g.s * 0.05, angle: -0.5), with: .color(leaf))
        default:
            var stem = Path()
            stem.move(to: CGPoint(x: g.cx, y: g.ground))
            let tip = CGPoint(x: g.cx + (health == .withered ? g.s * 0.08 : 0), y: g.top + (health == .withered ? g.h * 0.25 : 0))
            stem.addQuadCurve(to: tip, control: CGPoint(x: g.cx - g.s * 0.04, y: g.ground - g.h * 0.5))
            ctx.stroke(stem, with: .color(health == .withered ? witheredTrunk : leaf.mixed(with: .black, amount: 0.15)),
                       style: StrokeStyle(lineWidth: max(1, g.s * 0.035), lineCap: .round))
            let droop = health == .withered ? 1.0 : 0
            ctx.fill(ellipse(CGPoint(x: tip.x - g.s * 0.08, y: tip.y + g.s * 0.02), g.s * 0.17, g.s * 0.08, angle: 0.5 + droop), with: .color(leaf))
            ctx.fill(ellipse(CGPoint(x: tip.x + g.s * 0.08, y: tip.y + g.s * 0.01), g.s * 0.17, g.s * 0.08, angle: -0.5 - droop), with: .color(leaf))
            if species == .cherry && health == .healthy {
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - g.s * 0.03, y: tip.y - g.s * 0.05, width: g.s * 0.06, height: g.s * 0.06)),
                         with: .color(.white))
            }
        }
    }

    // MARK: - Species

    private func drawOak(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.13 : 0.09)
        roots(&ctx, g, width: tw)
        ctx.fill(trunkPath(g, bottomWidth: tw, topWidth: tw * 0.55, topY: g.ground - g.h * 0.55), with: .color(trunk))
        if health == .withered { bareBranches(&ctx, g, from: g.ground - g.h * 0.5, spread: g.h * 0.3) }
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 1), (-0.6, 0.2, 0.75), (0.6, 0.2, 0.75), (-0.32, -0.42, 0.72), (0.34, -0.4, 0.7), (0, 0.35, 0.65)]
        blobs(&ctx, center: CGPoint(x: g.cx, y: g.ground - g.h * 0.72), radius: g.h * 0.27, offsets: offsets, color: leaf)
    }

    private func drawConifer(_ ctx: inout GraphicsContext, _ g: Geo, widthFactor: CGFloat, trunkShare: CGFloat) {
        let tw = g.s * (species == .sequoia ? 0.1 : 0.05) * (stage == .ancient ? 1.3 : 1)
        roots(&ctx, g, width: tw)
        ctx.fill(trunkPath(g, bottomWidth: tw, topWidth: tw * 0.5, topY: g.top + g.h * 0.1), with: .color(trunk))
        let tiers = stage == .young ? 3 : (stage == .mature ? 4 : 5)
        let visible = max(1, Int((Double(tiers) * density).rounded()))
        let foliageHeight = g.h * (1 - trunkShare)
        let tierHeight = foliageHeight / CGFloat(tiers) * 1.45
        for i in 0..<visible {
            let t = CGFloat(i) / CGFloat(tiers)
            let baseY = g.ground - g.h * trunkShare - CGFloat(i) * foliageHeight / CGFloat(tiers) * 0.95
            let halfWidth = g.h * widthFactor * 0.5 * (1 - t * 0.65)
            var tri = Path()
            tri.move(to: CGPoint(x: g.cx - halfWidth, y: baseY))
            tri.addLine(to: CGPoint(x: g.cx, y: baseY - tierHeight))
            tri.addLine(to: CGPoint(x: g.cx + halfWidth, y: baseY))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(leaf.mixed(with: .black, amount: Double(tiers - i) * 0.03)))
        }
        if health == .withered { bareBranches(&ctx, g, from: g.ground - g.h * 0.45, spread: g.h * 0.2) }
    }

    private func drawBonsai(_ ctx: inout GraphicsContext, _ g: Geo) {
        let potTop = g.ground - g.s * 0.12
        var pot = Path()
        pot.move(to: CGPoint(x: g.cx - g.s * 0.24, y: potTop))
        pot.addLine(to: CGPoint(x: g.cx + g.s * 0.24, y: potTop))
        pot.addLine(to: CGPoint(x: g.cx + g.s * 0.17, y: g.ground))
        pot.addLine(to: CGPoint(x: g.cx - g.s * 0.17, y: g.ground))
        pot.closeSubpath()
        ctx.fill(pot, with: .color(Color(red: 0.62, green: 0.32, blue: 0.22)))
        ctx.fill(Path(CGRect(x: g.cx - g.s * 0.26, y: potTop - g.s * 0.02, width: g.s * 0.52, height: g.s * 0.03)),
                 with: .color(Color(red: 0.52, green: 0.26, blue: 0.18)))

        let h = g.h * 0.9
        var trunkLine = Path()
        trunkLine.move(to: CGPoint(x: g.cx, y: potTop))
        trunkLine.addCurve(to: CGPoint(x: g.cx + g.s * 0.1, y: potTop - h * 0.75),
                           control1: CGPoint(x: g.cx - g.s * 0.18, y: potTop - h * 0.3),
                           control2: CGPoint(x: g.cx + g.s * 0.22, y: potTop - h * 0.45))
        ctx.stroke(trunkLine, with: .color(trunk), style: StrokeStyle(lineWidth: g.s * (stage == .ancient ? 0.07 : 0.05), lineCap: .round))

        let pads: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.1, 0.8, 0.34, 0.13), (-0.14, 0.5, 0.26, 0.1), (0.2, 0.52, 0.22, 0.09), (-0.02, 0.98, 0.22, 0.09),
        ]
        let visible = max(1, Int((Double(pads.count) * density).rounded()))
        for (dx, dy, w, ph) in pads.prefix(visible) {
            ctx.fill(ellipse(CGPoint(x: g.cx + dx * g.s, y: potTop - dy * h), w * g.s, ph * g.s), with: .color(leaf))
        }
    }

    private func drawCherry(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.1 : 0.07)
        roots(&ctx, g, width: tw)
        ctx.fill(trunkPath(g, bottomWidth: tw, topWidth: tw * 0.5, topY: g.ground - g.h * 0.55, lean: g.s * 0.03), with: .color(trunk))
        bareBranches(&ctx, g, from: g.ground - g.h * 0.5, spread: g.h * 0.28)
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.9), (-0.7, 0.15, 0.7), (0.7, 0.1, 0.72), (-0.3, -0.45, 0.65), (0.35, -0.4, 0.66), (0, 0.3, 0.6)]
        let center = CGPoint(x: g.cx + g.s * 0.03, y: g.ground - g.h * 0.72)
        blobs(&ctx, center: center, radius: g.h * 0.27, offsets: offsets, color: leaf)
        guard health == .healthy else { return }
        for i in 0..<14 {
            let a = Double(i) * 2.39996
            let r = g.h * 0.32 * sqrt(Double(i) / 14)
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.75)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - g.s * 0.012, y: p.y - g.s * 0.012, width: g.s * 0.024, height: g.s * 0.024)),
                     with: .color(.white.opacity(0.9)))
        }
    }

    private func drawWillow(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.12 : 0.08)
        roots(&ctx, g, width: tw)
        ctx.fill(trunkPath(g, bottomWidth: tw, topWidth: tw * 0.6, topY: g.ground - g.h * 0.7), with: .color(trunk))
        let crown = CGPoint(x: g.cx, y: g.ground - g.h * 0.78)
        ctx.fill(ellipse(crown, g.h * 0.7, g.h * 0.36), with: .color(leaf.opacity(health == .withered ? 0.4 : 1)))
        let strands = Int(Double(stage == .young ? 9 : 14) * density)
        var p = Path()
        for i in 0..<strands {
            let t = CGFloat(i) / CGFloat(max(1, strands - 1))
            let x = crown.x - g.h * 0.34 + t * g.h * 0.68
            let swing = animated ? CGFloat(sin(time * 1.1 + Double(i))) * g.s * 0.02 : 0
            let length = g.h * (0.35 + 0.2 * (1 - abs(t - 0.5) * 2))
            p.move(to: CGPoint(x: x, y: crown.y))
            p.addQuadCurve(to: CGPoint(x: x + swing + (t - 0.5) * g.s * 0.08, y: crown.y + length),
                           control: CGPoint(x: x + (t - 0.5) * g.s * 0.12, y: crown.y + length * 0.4))
        }
        ctx.stroke(p, with: .color(leaf.mixed(with: .black, amount: 0.1)), style: StrokeStyle(lineWidth: max(1, g.s * 0.018), lineCap: .round))
    }

    private func drawCactus(_ ctx: inout GraphicsContext, _ g: Geo) {
        var cactus = ctx
        if health == .withered {
            cactus.translateBy(x: g.cx, y: g.ground)
            cactus.rotate(by: .radians(0.18))
            cactus.translateBy(x: -g.cx, y: -g.ground)
        }
        let w = g.s * (stage == .ancient ? 0.2 : 0.16)
        let body = CGRect(x: g.cx - w / 2, y: g.top, width: w, height: g.h)
        cactus.fill(Path(roundedRect: body, cornerRadius: w / 2), with: .color(leaf))

        func arm(_ dir: CGFloat, at y: CGFloat, length: CGFloat) {
            let armW = w * 0.62
            let horizontal = CGRect(x: dir > 0 ? g.cx : g.cx - g.s * 0.2, y: y, width: g.s * 0.2, height: armW)
            cactus.fill(Path(roundedRect: horizontal, cornerRadius: armW / 2), with: .color(leaf))
            let vx = dir > 0 ? g.cx + g.s * 0.2 - armW : g.cx - g.s * 0.2
            let vertical = CGRect(x: vx, y: y - length + armW, width: armW, height: length)
            cactus.fill(Path(roundedRect: vertical, cornerRadius: armW / 2), with: .color(leaf))
        }
        arm(1, at: g.ground - g.h * 0.5, length: g.h * 0.35)
        if stage >= .mature { arm(-1, at: g.ground - g.h * 0.38, length: g.h * 0.28) }

        var ribs = Path()
        for dx in [-0.22, 0, 0.22] {
            ribs.move(to: CGPoint(x: g.cx + w * dx, y: g.top + w * 0.4))
            ribs.addLine(to: CGPoint(x: g.cx + w * dx, y: g.ground - 2))
        }
        cactus.stroke(ribs, with: .color(.black.opacity(0.15)), lineWidth: max(0.5, g.s * 0.008))
        if stage == .ancient && health == .healthy {
            cactus.fill(Path(ellipseIn: CGRect(x: g.cx - g.s * 0.05, y: g.top - g.s * 0.06, width: g.s * 0.1, height: g.s * 0.1)),
                        with: .color(Color(red: 0.98, green: 0.4, blue: 0.6)))
        }
    }

    private func drawBamboo(_ ctx: inout GraphicsContext, _ g: Geo) {
        let count = stage == .young ? 2 : (stage == .mature ? 3 : 5)
        let stalkColor = health == .withered ? Color(red: 0.72, green: 0.65, blue: 0.40) : leaf
        for i in 0..<count {
            let offset = (CGFloat(i) - CGFloat(count - 1) / 2) * g.s * 0.09
            let height = g.h * (0.8 + 0.2 * CGFloat((i * 37) % 10) / 10)
            let w = g.s * 0.045
            let x = g.cx + offset
            ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: g.ground - height, width: w, height: height), cornerRadius: w / 3),
                     with: .color(stalkColor))
            var nodes = Path()
            var y = g.ground - g.h * 0.14
            while y > g.ground - height + 4 {
                nodes.move(to: CGPoint(x: x - w / 2, y: y))
                nodes.addLine(to: CGPoint(x: x + w / 2, y: y))
                y -= g.h * 0.15
            }
            ctx.stroke(nodes, with: .color(.black.opacity(0.22)), lineWidth: max(0.6, g.s * 0.01))
            if health != .withered || i == 0 {
                let leafY = g.ground - height + g.h * 0.08
                ctx.fill(ellipse(CGPoint(x: x + g.s * 0.06, y: leafY), g.s * 0.13, g.s * 0.04, angle: -0.5),
                         with: .color(leaf.mixed(with: .black, amount: 0.15)))
                ctx.fill(ellipse(CGPoint(x: x - g.s * 0.055, y: leafY + g.h * 0.08), g.s * 0.12, g.s * 0.035, angle: 0.45),
                         with: .color(leaf.mixed(with: .black, amount: 0.15)))
            }
        }
    }

    private func drawBirch(_ ctx: inout GraphicsContext, _ g: Geo) {
        let tw = g.s * (stage == .ancient ? 0.08 : 0.06)
        let trunkTop = g.ground - g.h * 0.75
        ctx.fill(trunkPath(g, bottomWidth: tw, topWidth: tw * 0.6, topY: trunkTop), with: .color(trunk))
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
        if health == .withered { bareBranches(&ctx, g, from: trunkTop + g.h * 0.1, spread: g.h * 0.22) }
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.8), (-0.55, 0.35, 0.6), (0.55, 0.3, 0.6), (0, -0.55, 0.6), (-0.3, 0.75, 0.5), (0.3, 0.8, 0.5)]
        blobs(&ctx, center: CGPoint(x: g.cx, y: g.ground - g.h * 0.78), radius: g.h * 0.2, offsets: offsets, color: leaf)
    }

    private func drawFallingLeaves(_ ctx: inout GraphicsContext, _ g: Geo) {
        let color = leaf.mixed(with: .orange, amount: 0.3)
        for i in 0..<3 {
            let center: CGPoint
            let angle: Double
            if animated {
                let phase = (time * 0.25 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let x = g.cx + CGFloat(i - 1) * g.s * 0.18 + CGFloat(sin(time * 1.5 + Double(i))) * g.s * 0.05
                let y = g.ground - g.h * 0.6 + CGFloat(phase) * g.h * 0.6
                center = CGPoint(x: x, y: y)
                angle = time * 2 + Double(i)
            } else {
                center = CGPoint(x: g.cx + CGFloat(i - 1) * g.s * 0.2, y: g.ground - g.s * 0.01)
                angle = Double(i)
            }
            ctx.fill(ellipse(center, g.s * 0.06, g.s * 0.03, angle: angle), with: .color(color))
        }
    }
}
