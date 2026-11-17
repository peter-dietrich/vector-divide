import SwiftUI

/// Modern reactor-containment visual layer. The gameplay engine is shared with Classic.
/// Coordinates, collision boundaries and saved-game formats remain unchanged.
struct DivideContainmentBoard: View {
    let engine: DivideEngine
    let clock: Double

    private let electric = Color(red: 0.13, green: 0.91, blue: 0.96)
    private let indigo = Color(red: 0.40, green: 0.43, blue: 0.99)
    private let heat = Color(red: 1.0, green: 0.39, blue: 0.27)
    private let gold = Color(red: 1.0, green: 0.75, blue: 0.35)

    var body: some View {
        Canvas(opaque: true) { context, size in
            paint(context, size: size)
        }
        .background(Color(red: 0.020, green: 0.032, blue: 0.069))
        .accessibilityLabel("Containment reactor arena. Capture territory to activate solid energy plates.")
    }

    private func paint(_ ctx: GraphicsContext, size: CGSize) {
        let w = size.width / CGFloat(DivideEngine.columns)
        let h = size.height / CGFloat(DivideEngine.rows)
        let scale = min(w, h)
        let pulse = 0.5 + 0.5 * sin(clock * 2.7)
        func center(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x + 0.5) * w, y: (y + 0.5) * h)
        }
        func tile(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: CGFloat(x) * w, y: CGFloat(y) * h, width: w + 0.25, height: h + 0.25)
        }
        func enemyCenter(_ e: DivideEnemy) -> CGPoint {
            center(CGFloat(e.position.x), CGFloat(e.position.y))
        }
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [
            Color(red: 0.025, green: 0.05, blue: 0.11),
            Color(red: 0.045, green: 0.035, blue: 0.095),
            Color(red: 0.009, green: 0.02, blue: 0.057)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

        // Deep structural slabs, ventilation channels and reactor pylons.
        for row in 0..<9 {
            let yy = CGFloat(row) * size.height / 8
            let band = CGRect(x: 0, y: yy - h * 0.34, width: size.width, height: h * 0.65)
            ctx.fill(Path(band), with: .color(Color(red: 0.07, green: 0.12, blue: 0.20).opacity(0.65)))
            var seam = Path()
            seam.move(to: CGPoint(x: 0, y: yy))
            seam.addLine(to: CGPoint(x: size.width, y: yy))
            ctx.stroke(seam, with: .color(indigo.opacity(0.20)), lineWidth: 1)
        }
        for column in 0..<12 {
            let x = CGFloat(column) * size.width / 11
            var seam = Path()
            seam.move(to: CGPoint(x: x, y: 0))
            seam.addLine(to: CGPoint(x: x + size.height * 0.11, y: size.height))
            ctx.stroke(seam, with: .color(electric.opacity(0.10)), lineWidth: 1)
        }

        // Large reactor hardware stays below every game element.
        let reactorLocations: [(CGFloat, CGFloat)] = [(0.19, 0.23), (0.80, 0.23),
            (0.19, 0.77), (0.80, 0.77), (0.5, 0.5)]
        for (index, pair) in reactorLocations.enumerated() {
            let p = CGPoint(x: pair.0 * size.width, y: pair.1 * size.height)
            let radius = min(size.width, size.height) * (index == 4 ? 0.115 : 0.072)
            let outer = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: outer), with: .color(Color(red: 0.015, green: 0.035, blue: 0.072)))
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: radius * 0.16, dy: radius * 0.16)),
                       with: .color(indigo.opacity(0.26)), lineWidth: max(2, scale * 0.3))
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: radius * 0.37, dy: radius * 0.37)),
                       with: .color(electric.opacity(0.14 + 0.08 * pulse)), lineWidth: 1.3)
            for n in 0..<8 {
                let angle = CGFloat(n) * .pi / 4
                let a = CGPoint(x: p.x + cos(angle) * radius * 0.72,
                                y: p.y + sin(angle) * radius * 0.72)
                let b = CGPoint(x: p.x + cos(angle) * radius * 0.95,
                                y: p.y + sin(angle) * radius * 0.95)
                var edge = Path()
                edge.move(to: a); edge.addLine(to: b)
                ctx.stroke(edge, with: .color(electric.opacity(0.24)), lineWidth: 2)
            }
        }

        // Captured cells form opaque continuous armor, with heavier recessed gridwork.
        var fast = Path(), slow = Path(), groove = Path(), perimeter = Path()
        var lineFast = Path(), lineSlow = Path()
        for y in 1..<(DivideEngine.rows - 1) {
            for x in 1..<(DivideEngine.columns - 1) {
                let value = engine.tone(DividePoint(x: x, y: y))
                if value == 0 { continue }
                let rect = tile(x, y)
                if value == 2 { slow.addRect(rect) } else { fast.addRect(rect) }

                // Recessed seams at regular intervals, avoiding a noisy per-cell grid.
                if x % 5 == 0 {
                    groove.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    groove.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                }
                if y % 5 == 0 {
                    groove.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    groove.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                }
                let left = engine.isSafe(DividePoint(x: x - 1, y: y))
                let right = engine.isSafe(DividePoint(x: x + 1, y: y))
                let up = engine.isSafe(DividePoint(x: x, y: y - 1))
                let down = engine.isSafe(DividePoint(x: x, y: y + 1))
                if !left {
                    perimeter.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    perimeter.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                }
                if !right {
                    perimeter.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    perimeter.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                if !up {
                    perimeter.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    perimeter.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                }
                if !down {
                    perimeter.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    perimeter.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                if value == 2 {
                    lineSlow.addRect(rect.insetBy(dx: 0.8, dy: 0.8))
                } else {
                    lineFast.addRect(rect.insetBy(dx: 0.8, dy: 0.8))
                }
            }
        }
        ctx.fill(fast, with: .linearGradient(Gradient(colors: [
            Color(red: 0.10, green: 0.27, blue: 0.41), Color(red: 0.06, green: 0.17, blue: 0.30)
        ]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: size.height)))
        ctx.fill(slow, with: .linearGradient(Gradient(colors: [
            Color(red: 0.33, green: 0.19, blue: 0.38), Color(red: 0.18, green: 0.12, blue: 0.30)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        ctx.stroke(groove, with: .color(Color.black.opacity(0.36)), lineWidth: 0.8)
        ctx.stroke(perimeter, with: .color(electric.opacity(0.14)), lineWidth: max(7, scale * 1.35))
        ctx.stroke(perimeter, with: .color(electric.opacity(0.95)), lineWidth: max(1.6, scale * 0.25))
        // Edge of the game is an armored, solid raceway.
        let frame = CGRect(x: w * 0.5, y: h * 0.5, width: size.width - w, height: size.height - h)
        ctx.stroke(Path(frame), with: .color(Color(red: 0.11, green: 0.29, blue: 0.42)), lineWidth: max(scale * 1.7, 5))
        ctx.stroke(Path(frame), with: .color(electric.opacity(0.76)), lineWidth: 2.4)
        for n in 0..<18 {
            let xx = CGFloat(n) * size.width / 17
            let signal = CGRect(x: xx - 2, y: h * 0.2, width: 4, height: h * 0.6)
            ctx.fill(Path(signal), with: .color(n % 3 == 0 ? gold : electric.opacity(0.62)))
        }

        // Active trace is intentionally much brighter than any background scenery.
        if let start = engine.trailStart, !engine.trail.isEmpty {
            var trace = Path()
            trace.move(to: center(CGFloat(start.x), CGFloat(start.y)))
            for cell in engine.trail {
                trace.addLine(to: center(CGFloat(cell.x), CGFloat(cell.y)))
            }
            let color = engine.drawMode == .slow ? Color(red: 1, green: 0.39, blue: 0.83) : electric
            ctx.stroke(trace, with: .color(color.opacity(0.22)), style: StrokeStyle(
                lineWidth: max(12, scale * 1.75), lineCap: .round, lineJoin: .round))
            ctx.stroke(trace, with: .color(color.opacity(0.9)), style: StrokeStyle(
                lineWidth: max(4.5, scale * 0.52), lineCap: .round, lineJoin: .round))
            ctx.stroke(trace, with: .color(.white), style: StrokeStyle(
                lineWidth: max(1.6, scale * 0.18), lineCap: .round, lineJoin: .round))
            if let fuse = engine.fusePoint {
                let p = center(CGFloat(fuse.x), CGFloat(fuse.y))
                let r = scale * (1.2 + 0.2 * pulse)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                         with: .color(heat.opacity(0.55)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x-r*0.47, y: p.y-r*0.47, width: r*0.94, height: r*0.94)),
                         with: .color(.white))
            }
        }

        // Independent mechanical anomaly drones with segmented armor, rotating blades and cores.
        for enemy in engine.enemies {
            let p = enemyCenter(enemy)
            let radius = scale * 1.85
            let halo = CGRect(x: p.x-radius*1.4, y: p.y-radius*1.4,
                              width: radius*2.8, height: radius*2.8)
            ctx.fill(Path(ellipseIn: halo), with: .radialGradient(
                Gradient(colors: [heat.opacity(0.30 + pulse*0.10), .clear]),
                center: p, startRadius: 0, endRadius: radius * 1.4))
            let shadow = CGRect(x: p.x-radius*0.89+2, y: p.y-radius*0.89+3,
                                width: radius*1.78, height: radius*1.78)
            ctx.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.7)))
            var hull = Path()
            for side in 0..<8 {
                let a = CGFloat(side) * .pi / 4 + CGFloat(enemy.spin * 0.22)
                let point = CGPoint(x: p.x + cos(a) * radius * 0.72,
                                    y: p.y + sin(a) * radius * 0.72)
                if side == 0 { hull.move(to: point) } else { hull.addLine(to: point) }
            }
            hull.closeSubpath()
            ctx.fill(hull, with: .color(Color(red: 0.14, green: 0.12, blue: 0.23)))
            ctx.stroke(hull, with: .color(heat), lineWidth: max(1.6, scale * 0.24))
            for spoke in 0..<4 {
                let a = CGFloat(enemy.spin) + CGFloat(spoke) * .pi / 2
                let inner = CGPoint(x: p.x + cos(a) * radius * 0.32,
                                    y: p.y + sin(a) * radius * 0.32)
                let outer = CGPoint(x: p.x + cos(a) * radius,
                                    y: p.y + sin(a) * radius)
                var blade = Path()
                blade.move(to: inner); blade.addLine(to: outer)
                ctx.stroke(blade, with: .color(gold.opacity(0.92)), lineWidth: max(2.5, scale * 0.33))
            }
            let coreR = scale * (0.46 + 0.12 * pulse)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x-coreR, y: p.y-coreR,
                                            width: coreR*2, height: coreR*2)), with: .color(heat))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x-coreR*0.40, y: p.y-coreR*0.40,
                                            width: coreR*0.8, height: coreR*0.8)), with: .color(.white))
        }

        // Animated sentry sparks, drawn above the protective perimeter.
        for spark in engine.sparks {
            let tilePoint = engine.sparkPosition(spark)
            let p = center(CGFloat(tilePoint.x), CGFloat(tilePoint.y))
            let r = scale * 1.05
            ctx.fill(Path(ellipseIn: CGRect(x: p.x-r*1.6, y: p.y-r*1.6,
                                            width: r*3.2, height: r*3.2)), with: .color(gold.opacity(0.18)))
            let square = CGRect(x: p.x-r*0.68, y: p.y-r*0.68, width: r*1.36, height: r*1.36)
            ctx.fill(Path(roundedRect: square, cornerRadius: 2), with: .color(Color(red: 0.21, green: 0.15, blue: 0.12)))
            ctx.stroke(Path(roundedRect: square, cornerRadius: 2), with: .color(gold), lineWidth: 2)
            ctx.fill(Path(ellipseIn: square.insetBy(dx: r*0.37, dy: r*0.37)), with: .color(.white))
        }

        // The player is an opaque command drone with a visible protective ring.
        let p = center(CGFloat(engine.player.x), CGFloat(engine.player.y))
        let r = scale * 1.2
        let attenuation = engine.invulnerable ? (0.38 + pulse * 0.62) : 1.0
        ctx.fill(Path(ellipseIn: CGRect(x: p.x-r*1.8, y: p.y-r*1.8,
                                        width: r*3.6, height: r*3.6)), with: .color(electric.opacity(0.12*attenuation)))
        var diamond = Path()
        diamond.move(to: CGPoint(x: p.x, y: p.y-r))
        diamond.addLine(to: CGPoint(x: p.x+r, y: p.y))
        diamond.addLine(to: CGPoint(x: p.x, y: p.y+r))
        diamond.addLine(to: CGPoint(x: p.x-r, y: p.y))
        diamond.closeSubpath()
        ctx.fill(diamond, with: .color(Color(red: 0.10, green: 0.24, blue: 0.36)))
        ctx.stroke(diamond, with: .color(electric.opacity(attenuation)), lineWidth: 2.6)
        let core = CGRect(x: p.x-r*0.28, y: p.y-r*0.28, width: r*0.56, height: r*0.56)
        ctx.fill(Path(ellipseIn: core), with: .color(.white.opacity(attenuation)))

        // Four reactor-style corner registration markers.
        for xSide in 0..<2 {
            for ySide in 0..<2 {
                let xx = xSide == 0 ? w * 2.6 : size.width - w * 2.6
                let yy = ySide == 0 ? h * 2.6 : size.height - h * 2.6
                let p = CGPoint(x: xx, y: yy)
                let mark = CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)
                ctx.fill(Path(mark), with: .color(gold.opacity(0.65 + 0.2*pulse)))
            }
        }
    }
}
