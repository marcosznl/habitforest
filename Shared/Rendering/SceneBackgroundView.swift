import SwiftUI

/// Landscape behind the forest: sky by time of day, hills by season and weather particles.
struct SceneBackgroundView: View {
    var animated = true
    var showsHills = true

    var body: some View {
        if animated {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                SceneLayers(scenery: Scenery(date: context.date), animated: true, showsHills: showsHills)
            }
        } else {
            SceneLayers(scenery: Scenery(), animated: false, showsHills: showsHills)
        }
    }
}

struct SceneLayers: View {
    let scenery: Scenery
    var animated: Bool
    var showsHills: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(scenery.skyGradient)
            CelestialLayer(time: scenery.time)
            if showsHills { HillsLayer(scenery: scenery) }
            if animated && scenery.weather != .clear {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    WeatherCanvas(weather: scenery.weather, time: context.date.timeIntervalSinceReferenceDate)
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
    }
}

private struct CelestialLayer: View {
    let time: TimeOfDay

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            switch time {
            case .night:
                for i in 0..<60 {
                    let x = (Double((i * 7919) % 997) / 997) * w
                    let y = (Double((i * 104_729) % 991) / 991) * h * 0.55
                    let r = 0.6 + Double(i % 3) * 0.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.8)))
                }
                let moon = CGRect(x: w * 0.78, y: h * 0.08, width: min(w, h) * 0.09, height: min(w, h) * 0.09)
                ctx.fill(Path(ellipseIn: moon.insetBy(dx: -8, dy: -8)), with: .color(.white.opacity(0.08)))
                ctx.fill(Path(ellipseIn: moon), with: .color(Color(red: 0.96, green: 0.95, blue: 0.86)))
            default:
                let position: CGPoint = switch time {
                case .morning: CGPoint(x: w * 0.18, y: h * 0.32)
                case .afternoon: CGPoint(x: w * 0.55, y: h * 0.12)
                default: CGPoint(x: w * 0.82, y: h * 0.48)
                }
                let r = min(w, h) * (time == .sunset ? 0.10 : 0.07)
                let sunColor = time == .sunset ? Color(red: 1, green: 0.62, blue: 0.3) : Color(red: 1, green: 0.93, blue: 0.62)
                let glow = Gradient(colors: [sunColor.opacity(0.55), sunColor.opacity(0)])
                ctx.fill(Path(ellipseIn: CGRect(x: position.x - r * 3, y: position.y - r * 3, width: r * 6, height: r * 6)),
                         with: .radialGradient(glow, center: position, startRadius: 0, endRadius: r * 3))
                ctx.fill(Path(ellipseIn: CGRect(x: position.x - r, y: position.y - r, width: r * 2, height: r * 2)),
                         with: .color(sunColor))
            }
        }
    }
}

private struct HillsLayer: View {
    let scenery: Scenery

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var back = Path()
            back.move(to: CGPoint(x: 0, y: h * 0.72))
            back.addCurve(to: CGPoint(x: w, y: h * 0.66),
                          control1: CGPoint(x: w * 0.3, y: h * 0.58),
                          control2: CGPoint(x: w * 0.65, y: h * 0.78))
            back.addLine(to: CGPoint(x: w, y: h))
            back.addLine(to: CGPoint(x: 0, y: h))
            back.closeSubpath()
            ctx.fill(back, with: .color(scenery.hills.back))

            var front = Path()
            front.move(to: CGPoint(x: 0, y: h * 0.84))
            front.addCurve(to: CGPoint(x: w, y: h * 0.80),
                           control1: CGPoint(x: w * 0.35, y: h * 0.76),
                           control2: CGPoint(x: w * 0.7, y: h * 0.90))
            front.addLine(to: CGPoint(x: w, y: h))
            front.addLine(to: CGPoint(x: 0, y: h))
            front.closeSubpath()
            ctx.fill(front, with: .color(scenery.hills.front))
        }
    }
}

private struct WeatherCanvas: View {
    let weather: Weather
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let count = weather == .rain ? 90 : 36
            for i in 0..<count {
                let seed = Double((i * 7_331) % 1_000) / 1_000
                let seed2 = Double((i * 3_571) % 1_000) / 1_000
                switch weather {
                case .rain:
                    let phase = (time * (1.2 + seed2) + seed).truncatingRemainder(dividingBy: 1)
                    let x = seed * w + phase * 20
                    let y = phase * h
                    var drop = Path()
                    drop.move(to: CGPoint(x: x, y: y))
                    drop.addLine(to: CGPoint(x: x - 3, y: y + 12))
                    ctx.stroke(drop, with: .color(.white.opacity(0.35)), lineWidth: 1)
                case .snow:
                    let phase = (time * (0.05 + seed2 * 0.06) + seed).truncatingRemainder(dividingBy: 1)
                    let x = seed * w + sin(time * 0.8 + seed * 10) * 14
                    let y = phase * h
                    let r = 1.5 + seed2 * 2.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.85)))
                case .fallingLeaves, .petals:
                    let phase = (time * (0.04 + seed2 * 0.05) + seed).truncatingRemainder(dividingBy: 1)
                    let x = (seed * w + phase * w * 0.3).truncatingRemainder(dividingBy: w)
                    let y = phase * h
                    let angle = time * (1 + seed2) + seed * 6
                    let color: Color = weather == .petals
                        ? Color(red: 1, green: 0.78, blue: 0.86)
                        : [Color.orange, Color(red: 0.8, green: 0.3, blue: 0.15), Color.yellow][i % 3]
                    let leaf = Path(ellipseIn: CGRect(x: -4, y: -2, width: 8, height: 4))
                        .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: x, y: y)))
                    ctx.fill(leaf, with: .color(color.opacity(0.85)))
                case .fireflies:
                    let x = seed * w + sin(time * 0.5 + seed * 20) * 30
                    let y = h * 0.45 + seed2 * h * 0.45 + cos(time * 0.4 + seed2 * 20) * 20
                    let glow = (sin(time * 2 + seed * 30) + 1) / 2
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)),
                             with: .color(Color(red: 0.95, green: 1, blue: 0.5).opacity(glow)))
                case .clear:
                    break
                }
            }
        }
    }
}
