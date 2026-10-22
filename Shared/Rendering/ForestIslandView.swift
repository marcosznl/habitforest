import SwiftUI

/// Uma árvore plantada num lote da ilha.
struct IslandTree: Hashable {
    var species: TreeSpecies
    var stage: GrowthStage
    var health: TreeHealth
    var tint: Color?

    func hash(into hasher: inout Hasher) {
        hasher.combine(species)
        hasher.combine(stage)
        hasher.combine(health)
    }

    static func == (lhs: IslandTree, rhs: IslandTree) -> Bool {
        lhs.species == rhs.species && lhs.stage == rhs.stage && lhs.health == rhs.health
    }
}

/// Ilha isométrica de terra e grama com a floresta plantada em lotes, no estilo dos blocos do Forest.
/// O terreno muda com a estação: grama na primavera e no verão, areia clara no outono, neve no inverno.
struct ForestIslandView: View {
    /// Árvores em ordem de plantio; são distribuídas pelos lotes de forma natural.
    var trees: [IslandTree]
    var season: Season
    var animated = false

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: 0)
        }
    }

    /// Lado da grade: cresce com a floresta, entre 4×4 e 10×10.
    static func gridSide(for count: Int) -> Int {
        min(10, max(4, Int(ceil(sqrt(Double(count) * 1.25)))))
    }

    private func canvas(time: Double) -> some View {
        Canvas { ctx, size in
            IslandPainter(trees: trees, season: season, time: time, animated: animated).draw(in: &ctx, size: size)
        }
    }
}

private struct IslandPainter {
    let trees: [IslandTree]
    let season: Season
    let time: Double
    let animated: Bool

    private struct Palette {
        var top: Color
        var topAlt: Color
        var rim: Color
        var fringe: Color
        var dirtLeft: Color
        var dirtRight: Color
    }

    private var palette: Palette {
        let dirtLeft = Color(red: 0.55, green: 0.36, blue: 0.17)
        let dirtRight = Color(red: 0.43, green: 0.27, blue: 0.12)
        switch season {
        case .spring:
            return Palette(top: Color(red: 0.62, green: 0.84, blue: 0.29), topAlt: Color(red: 0.58, green: 0.80, blue: 0.27),
                           rim: Color(red: 0.72, green: 0.90, blue: 0.38), fringe: Color(red: 0.42, green: 0.68, blue: 0.18),
                           dirtLeft: dirtLeft, dirtRight: dirtRight)
        case .summer:
            return Palette(top: Color(red: 0.49, green: 0.77, blue: 0.22), topAlt: Color(red: 0.45, green: 0.73, blue: 0.20),
                           rim: Color(red: 0.62, green: 0.86, blue: 0.30), fringe: Color(red: 0.30, green: 0.58, blue: 0.14),
                           dirtLeft: dirtLeft, dirtRight: dirtRight)
        case .autumn:
            return Palette(top: Color(red: 0.97, green: 0.91, blue: 0.76), topAlt: Color(red: 0.95, green: 0.88, blue: 0.71),
                           rim: Color(red: 0.99, green: 0.95, blue: 0.85), fringe: Color(red: 0.24, green: 0.60, blue: 0.26),
                           dirtLeft: Color(red: 0.20, green: 0.50, blue: 0.24), dirtRight: Color(red: 0.15, green: 0.40, blue: 0.20))
        case .winter:
            return Palette(top: Color(red: 0.95, green: 0.96, blue: 0.98), topAlt: Color(red: 0.92, green: 0.94, blue: 0.97),
                           rim: .white, fringe: Color(red: 0.96, green: 0.97, blue: 0.99),
                           dirtLeft: dirtLeft, dirtRight: dirtRight)
        }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let n = ForestIslandView.gridSide(for: trees.count)
        let width = min(size.width * 0.94, size.height * 1.55)
        let tileW = width / CGFloat(n)
        let tileH = tileW / 2
        let depth = width * 0.075
        let cx = size.width / 2
        let topY = size.height - (CGFloat(n) * tileH + depth) - size.height * 0.03
        let colors = palette

        let top = CGPoint(x: cx, y: topY)
        let right = CGPoint(x: cx + width / 2, y: topY + CGFloat(n) * tileH / 2)
        let bottom = CGPoint(x: cx, y: topY + CGFloat(n) * tileH)
        let left = CGPoint(x: cx - width / 2, y: right.y)
        let down = CGSize(width: 0, height: depth)

        // Laterais de terra.
        ctx.fill(polygon([left, bottom, bottom + down, left + down]), with: .color(colors.dirtLeft))
        ctx.fill(polygon([bottom, right, right + down, bottom + down]), with: .color(colors.dirtRight))
        drawPebbles(&ctx, left: left, bottom: bottom, right: right, depth: depth, colors: colors)

        // Franja de grama (ou neve) escorrendo pelas laterais.
        let fringeDepth = depth * 0.38
        ctx.fill(fringe(from: left, to: bottom, depth: fringeDepth, teeth: n * 2), with: .color(colors.fringe))
        ctx.fill(fringe(from: bottom, to: right, depth: fringeDepth, teeth: n * 2),
                 with: .color(colors.fringe.mixed(with: .black, amount: season == .winter ? 0.06 : 0.12)))

        // Topo com xadrez sutil por lote.
        ctx.fill(polygon([top, right, bottom, left]), with: .color(colors.top))
        for r in 0..<n {
            for c in 0..<n where (r + c).isMultiple(of: 2) {
                ctx.fill(polygon(tileCorners(r: r, c: c, cx: cx, topY: topY, tileW: tileW, tileH: tileH)), with: .color(colors.topAlt))
            }
        }
        var rim = Path()
        rim.move(to: left)
        rim.addLine(to: top)
        rim.addLine(to: right)
        ctx.stroke(rim, with: .color(colors.rim), lineWidth: max(1, tileW * 0.04))

        // Árvores e enfeites, de trás para frente.
        let slots = Self.slotOrder(n: n)
        var occupant: [Int: IslandTree] = [:]
        for (index, tree) in trees.suffix(n * n).enumerated() { occupant[slots[index]] = tree }

        for diagonal in 0..<(2 * n - 1) {
            for r in 0..<n {
                let c = diagonal - r
                guard c >= 0 && c < n else { continue }
                let center = CGPoint(x: cx + CGFloat(c - r) * tileW / 2, y: topY + CGFloat(c + r + 1) * tileH / 2)
                if let tree = occupant[r * n + c] {
                    drawTree(&ctx, tree, at: center, tileW: tileW, seed: r * n + c)
                } else {
                    drawDecoration(&ctx, at: center, tileW: tileW, seed: r * n + c)
                }
            }
        }
    }

    // MARK: - Lotes

    /// Ordem pseudoaleatória estável dos lotes, preenchendo do centro para as bordas.
    static func slotOrder(n: Int) -> [Int] {
        let mid = Double(n - 1) / 2
        return (0..<(n * n)).sorted { a, b in
            func score(_ i: Int) -> Double {
                let r = Double(i / n), c = Double(i % n)
                let jitter = Double((i * 7_919) % 97) / 97 * 1.6
                return hypot(r - mid, c - mid) + jitter
            }
            return score(a) < score(b)
        }
    }

    private func tileCorners(r: Int, c: Int, cx: CGFloat, topY: CGFloat, tileW: CGFloat, tileH: CGFloat) -> [CGPoint] {
        let x = cx + CGFloat(c - r) * tileW / 2
        let y = topY + CGFloat(c + r) * tileH / 2
        return [CGPoint(x: x, y: y), CGPoint(x: x + tileW / 2, y: y + tileH / 2),
                CGPoint(x: x, y: y + tileH), CGPoint(x: x - tileW / 2, y: y + tileH / 2)]
    }

    private func drawTree(_ ctx: inout GraphicsContext, _ tree: IslandTree, at center: CGPoint, tileW: CGFloat, seed: Int) {
        let side = tileW * 1.12
        var local = ctx
        local.translateBy(x: center.x - side / 2, y: center.y - side * 0.9 + tileW * 0.05)
        TreePainter(species: tree.species, stage: tree.stage, health: tree.health, tint: tree.tint, season: season,
                    time: time + Double(seed) * 0.37, animated: animated, showsGround: true)
            .draw(in: &local, size: CGSize(width: side, height: side))
    }

    private func drawDecoration(_ ctx: inout GraphicsContext, at center: CGPoint, tileW: CGFloat, seed: Int) {
        switch (seed * 31 + 7) % 9 {
        case 0, 1:
            // Tufo de grama.
            let color = season == .winter ? Color.white : palette.fringe
            for dx in [-0.08, 0, 0.08] {
                var blade = Path()
                blade.move(to: CGPoint(x: center.x + tileW * dx - tileW * 0.03, y: center.y))
                blade.addLine(to: CGPoint(x: center.x + tileW * dx, y: center.y - tileW * 0.13))
                blade.addLine(to: CGPoint(x: center.x + tileW * dx + tileW * 0.03, y: center.y))
                blade.closeSubpath()
                ctx.fill(blade, with: .color(color))
            }
        case 2:
            // Pedrinha.
            let rock = CGRect(x: center.x - tileW * 0.08, y: center.y - tileW * 0.07, width: tileW * 0.16, height: tileW * 0.1)
            ctx.fill(Path(ellipseIn: rock), with: .color(Color(red: 0.62, green: 0.62, blue: 0.6)))
            ctx.fill(Path(ellipseIn: rock.insetBy(dx: tileW * 0.03, dy: tileW * 0.02).offsetBy(dx: -tileW * 0.02, dy: -tileW * 0.01)),
                     with: .color(Color(red: 0.75, green: 0.75, blue: 0.73)))
        case 3 where season != .winter:
            // Florzinhas.
            let colors = [Color(red: 1, green: 0.85, blue: 0.3), .white, Color(red: 1, green: 0.6, blue: 0.75)]
            for (i, offset) in [CGPoint(x: -0.06, y: 0), CGPoint(x: 0.05, y: -0.03), CGPoint(x: 0.02, y: 0.04)].enumerated() {
                let p = CGPoint(x: center.x + tileW * offset.x, y: center.y + tileW * offset.y)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - tileW * 0.025, y: p.y - tileW * 0.025, width: tileW * 0.05, height: tileW * 0.05)),
                         with: .color(colors[(seed + i) % 3]))
            }
        default:
            break
        }
    }

    private func drawPebbles(_ ctx: inout GraphicsContext, left: CGPoint, bottom: CGPoint, right: CGPoint, depth: CGFloat, colors: Palette) {
        for i in 0..<14 {
            let onLeft = i.isMultiple(of: 2)
            let t = CGFloat((i * 37) % 100) / 100
            let start = onLeft ? left : bottom
            let end = onLeft ? bottom : right
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t + depth * (0.5 + CGFloat((i * 13) % 40) / 100)
            let r = depth * 0.07
            let base = onLeft ? colors.dirtLeft : colors.dirtRight
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2)),
                     with: .color(base.mixed(with: .black, amount: 0.18)))
        }
    }

    // MARK: - Geometria

    private func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    /// Faixa serrilhada logo abaixo da aresta superior de uma lateral.
    private func fringe(from a: CGPoint, to b: CGPoint, depth: CGFloat, teeth: Int) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x, y: b.y + depth * 0.6))
        for k in stride(from: teeth * 2, through: 0, by: -1) {
            let t = CGFloat(k) / CGFloat(teeth * 2)
            let x = a.x + (b.x - a.x) * t
            let y = a.y + (b.y - a.y) * t + (k.isMultiple(of: 2) ? depth : depth * 0.45)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }
}

private func + (point: CGPoint, offset: CGSize) -> CGPoint {
    CGPoint(x: point.x + offset.width, y: point.y + offset.height)
}
