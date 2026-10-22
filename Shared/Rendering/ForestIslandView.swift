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
        min(10, max(4, Int(ceil(sqrt(Double(count) * 1.6)))))
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
        let width = min(size.width * 0.94, size.height * 1.45)
        let tileW = width / CGFloat(n)
        let tileH = tileW / 2
        let depth = width * 0.12
        let cx = size.width / 2
        let topY = size.height - (CGFloat(n) * tileH + depth) - size.height * 0.03
        let colors = palette

        let top = CGPoint(x: cx, y: topY)
        let right = CGPoint(x: cx + width / 2, y: topY + CGFloat(n) * tileH / 2)
        let bottom = CGPoint(x: cx, y: topY + CGFloat(n) * tileH)
        let left = CGPoint(x: cx - width / 2, y: right.y)
        let down = CGSize(width: 0, height: depth)

        // Laterais de terra com degradê: mais clara junto à grama, escurecendo para baixo.
        let leftFace = polygon([left, bottom, bottom + down, left + down])
        let rightFace = polygon([bottom, right, right + down, bottom + down])
        ctx.fill(leftFace, with: .linearGradient(Gradient(colors: [colors.dirtLeft, colors.dirtLeft.mixed(with: .black, amount: 0.22)]),
                                                 startPoint: left, endPoint: left + down))
        ctx.fill(rightFace, with: .linearGradient(Gradient(colors: [colors.dirtRight, colors.dirtRight.mixed(with: .black, amount: 0.25)]),
                                                  startPoint: right, endPoint: right + down))
        drawPebbles(&ctx, left: left, bottom: bottom, right: right, depth: depth, colors: colors)
        // Quina da frente com um filete de luz.
        var edge = Path()
        edge.move(to: bottom)
        edge.addLine(to: bottom + down)
        ctx.stroke(edge, with: .color(.white.opacity(0.12)), lineWidth: max(1, tileW * 0.03))

        // Franja de grama (ou neve) escorrendo pelas laterais.
        let fringeDepth = depth * 0.42
        let rounded = season == .winter
        ctx.fill(fringe(from: left, to: bottom, depth: fringeDepth, teeth: n * 3, rounded: rounded), with: .color(colors.fringe))
        ctx.fill(fringe(from: bottom, to: right, depth: fringeDepth, teeth: n * 3, rounded: rounded),
                 with: .color(colors.fringe.mixed(with: .black, amount: season == .winter ? 0.07 : 0.14)))

        // Topo: degradê do fundo (iluminado) para a frente, com xadrez bem sutil por lote.
        let topFace = polygon([top, right, bottom, left])
        ctx.fill(topFace, with: .linearGradient(Gradient(colors: [colors.rim.mixed(with: colors.top, amount: 0.45), colors.top,
                                                                 colors.top.mixed(with: colors.fringe, amount: 0.25)]),
                                                startPoint: top, endPoint: bottom))
        for r in 0..<n {
            for c in 0..<n where (r + c).isMultiple(of: 2) {
                ctx.fill(polygon(tileCorners(r: r, c: c, cx: cx, topY: topY, tileW: tileW, tileH: tileH)),
                         with: .color(colors.topAlt.opacity(0.35)))
            }
        }
        drawGrassTexture(&ctx, n: n, cx: cx, topY: topY, tileW: tileW, tileH: tileH, colors: colors)
        var rim = Path()
        rim.move(to: left)
        rim.addLine(to: top)
        rim.addLine(to: right)
        ctx.stroke(rim, with: .color(colors.rim), lineWidth: max(1, tileW * 0.05))
        var lip = Path()
        lip.move(to: left)
        lip.addLine(to: bottom)
        lip.addLine(to: right)
        ctx.stroke(lip, with: .color(colors.rim.opacity(0.6)), lineWidth: max(0.8, tileW * 0.03))

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
        // Covinha de terra fofa onde a árvore foi plantada.
        let patch = CGRect(x: center.x - tileW * 0.3, y: center.y - tileW * 0.12, width: tileW * 0.6, height: tileW * 0.26)
        ctx.fill(Path(ellipseIn: patch), with: .color(palette.fringe.opacity(season == .winter ? 0.0 : 0.35)))
        if season == .winter {
            ctx.fill(Path(ellipseIn: patch), with: .color(Color(red: 0.78, green: 0.84, blue: 0.94).opacity(0.5)))
        }
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

    /// Pedras arredondadas encravadas na terra, como paralelepípedos irregulares.
    private func drawPebbles(_ ctx: inout GraphicsContext, left: CGPoint, bottom: CGPoint, right: CGPoint, depth: CGFloat, colors: Palette) {
        for i in 0..<40 {
            let onLeft = i.isMultiple(of: 2)
            let t = (CGFloat((i * 37) % 100) + 2) / 104
            let start = onLeft ? left : bottom
            let end = onLeft ? bottom : right
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t + depth * (0.45 + CGFloat((i * 29) % 45) / 100)
            let r = depth * (0.09 + CGFloat((i * 17) % 7) / 100)
            let base = onLeft ? colors.dirtLeft : colors.dirtRight
            let stone = Path(ellipseIn: CGRect(x: x - r * 1.3, y: y - r * 0.7, width: r * 2.6, height: r * 1.4))
            ctx.fill(stone, with: .color(base.mixed(with: .black, amount: 0.16)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 1.1, y: y - r * 0.7, width: r * 2, height: r * 0.9)),
                     with: .color(base.mixed(with: .white, amount: 0.08)))
        }
    }

    /// Tufinhos de grama (ou brilhos de neve) espalhados pelo topo.
    private func drawGrassTexture(_ ctx: inout GraphicsContext, n: Int, cx: CGFloat, topY: CGFloat, tileW: CGFloat, tileH: CGFloat, colors: Palette) {
        let dark = colors.fringe.opacity(season == .winter ? 0.25 : 0.45)
        let light = colors.rim.opacity(0.7)
        for i in 0..<(n * n * 2) {
            let u = CGFloat((i * 53) % 97) / 97, v = CGFloat((i * 71) % 89) / 89
            let x = cx + (u - v) * CGFloat(n) * tileW / 2
            let y = topY + (u + v) * CGFloat(n) * tileH / 2
            let w = tileW * 0.05
            var tuft = Path()
            tuft.move(to: CGPoint(x: x - w, y: y))
            tuft.addLine(to: CGPoint(x: x - w * 0.4, y: y - w * 1.3))
            tuft.addLine(to: CGPoint(x: x, y: y - w * 0.2))
            tuft.addLine(to: CGPoint(x: x + w * 0.5, y: y - w * 1.5))
            tuft.addLine(to: CGPoint(x: x + w, y: y))
            tuft.closeSubpath()
            ctx.fill(tuft, with: .color(i.isMultiple(of: 3) ? light : dark))
        }
    }

    // MARK: - Geometria

    private func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    /// Faixa logo abaixo da aresta superior de uma lateral: pontas de grama irregulares ou ondas de neve.
    private func fringe(from a: CGPoint, to b: CGPoint, depth: CGFloat, teeth: Int, rounded: Bool) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        func point(_ t: CGFloat, _ drop: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + drop)
        }
        p.addLine(to: point(1, depth * 0.5))
        for k in stride(from: teeth, to: 0, by: -1) {
            let t0 = CGFloat(k) / CGFloat(teeth), t1 = CGFloat(k - 1) / CGFloat(teeth)
            let mid = (t0 + t1) / 2
            let length = depth * (0.75 + CGFloat((k * 37) % 50) / 100)
            if rounded {
                p.addQuadCurve(to: point(t1, depth * 0.5), control: point(mid, length * 1.4))
            } else {
                p.addLine(to: point(mid + (t0 - t1) * 0.1, length))
                p.addLine(to: point(t1, depth * 0.45))
            }
        }
        p.closeSubpath()
        return p
    }
}

private func + (point: CGPoint, offset: CGSize) -> CGPoint {
    CGPoint(x: point.x + offset.width, y: point.y + offset.height)
}
