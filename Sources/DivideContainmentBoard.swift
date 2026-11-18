import SwiftUI

/// A transient visual event. It is intentionally NOT part of DivideEngine or the saved game.
/// Restoring a save therefore never changes gameplay physics or persisted data.
struct DivideCaptureFX {
    let began: Double
    let newCells: [DividePoint]
    let origin: DividePoint
    let gain: Double
    let award: Int
    let duration: Double = 1.55
}

/// Modern / Containment: an illuminated, opaque reactor that is visibly restored by capture.
/// Every coordinate and every collision still belongs to the unmodified DivideEngine.
struct DivideContainmentBoard: View {
    let engine: DivideEngine
    let clock: Double
    let capture: DivideCaptureFX?

    private let cyan = Color(red: 0.27, green: 0.91, blue: 1.0)
    private let glacier = Color(red: 0.60, green: 0.96, blue: 1.0)
    private let purple = Color(red: 0.53, green: 0.43, blue: 0.98)
    private let orange = Color(red: 1.0, green: 0.39, blue: 0.23)
    private let amber = Color(red: 1.0, green: 0.77, blue: 0.38)
    private let steel = Color(red: 0.12, green: 0.22, blue: 0.34)
    private let midnight = Color(red: 0.016, green: 0.027, blue: 0.061)

    var body: some View {
        Canvas(opaque: true) { context, size in
            render(context, size: size)
        }
        .background(midnight)
        .accessibilityLabel("Reactor core containment arena: secure territory to activate solid armored flooring.")
    }

    private func point(_ x: CGFloat, _ y: CGFloat, _ cell: CGSize) -> CGPoint {
        CGPoint(x: (x + 0.5) * cell.width, y: (y + 0.5) * cell.height)
    }

    private func rect(_ x: Int, _ y: Int, _ cell: CGSize) -> CGRect {
        CGRect(x: CGFloat(x) * cell.width, y: CGFloat(y) * cell.height,
               width: cell.width + 0.25, height: cell.height + 0.25)
    }

    private func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r))
    }

    private func poly(_ corners: [CGPoint]) -> Path {
        var p = Path()
        guard let first = corners.first else { return p }
        p.move(to: first)
        for next in corners.dropFirst() { p.addLine(to: next) }
        p.closeSubpath()
        return p
    }

    private func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    private func glow(_ ctx: GraphicsContext, center p: CGPoint, radius r: CGFloat,
                      color: Color, intensity: Double) {
        guard r > 0 else { return }
        ctx.fill(disc(p, r), with: .radialGradient(
            Gradient(colors: [color.opacity(intensity), color.opacity(intensity * 0.21), .clear]),
            center: p, startRadius: 0, endRadius: r))
    }

    private func render(_ ctx: GraphicsContext, size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let cell = CGSize(width: size.width / CGFloat(DivideEngine.columns),
                          height: size.height / CGFloat(DivideEngine.rows))
        let scale = min(cell.width, cell.height)
        let oscillation = (sin(clock * 1.75) + 1) * 0.5
        drawFoundation(ctx, size: size, scale: scale)
        drawReactors(ctx, size: size, scale: scale, oscillation: oscillation)
        drawArmor(ctx, size: size, cell: cell, scale: scale, oscillation: oscillation)
        drawCapture(ctx, size: size, cell: cell, scale: scale)
        drawRaceway(ctx, size: size, cell: cell, scale: scale)
        drawTrace(ctx, cell: cell, scale: scale, oscillation: oscillation)
        drawEnemies(ctx, cell: cell, scale: scale, oscillation: oscillation)
        drawSentries(ctx, cell: cell, scale: scale, oscillation: oscillation)
        drawCommandDrone(ctx, cell: cell, scale: scale, oscillation: oscillation)
    }

    // Everything underneath the game is physical opaque machinery, not a transparent vector grid.
    private func drawFoundation(_ ctx: GraphicsContext, size: CGSize, scale: CGFloat) {
        let entire = CGRect(origin: .zero, size: size)
        ctx.fill(Path(entire), with: .linearGradient(Gradient(colors: [
            Color(red: 0.045, green: 0.087, blue: 0.15),
            Color(red: 0.045, green: 0.06, blue: 0.12),
            Color(red: 0.017, green: 0.035, blue: 0.080)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        glow(ctx, center: CGPoint(x: size.width * 0.50, y: size.height * 0.49),
             radius: size.height * 0.68, color: purple, intensity: 0.11)
        glow(ctx, center: CGPoint(x: size.width * 0.51, y: size.height * 0.40),
             radius: size.height * 0.43, color: cyan, intensity: 0.085)

        // Large individually bevelled hull plates. Strong solid fills avoid the old wireframe aesthetic.
        let pitchX = size.width / 11
        let pitchY = size.height / 7
        for y in 0..<7 {
            for x in 0..<11 {
                let l = CGFloat(x) * pitchX + 2.2
                let t = CGFloat(y) * pitchY + 2.2
                let plate = CGRect(x: l, y: t, width: pitchX - 4.4, height: pitchY - 4.4)
                let alternating = (x * 3 + y) % 4
                let base = alternating == 0
                    ? Color(red: 0.073, green: 0.13, blue: 0.22)
                    : Color(red: 0.045, green: 0.085, blue: 0.157)
                ctx.fill(Path(roundedRect: plate, cornerRadius: 2.5),
                         with: .linearGradient(Gradient(colors: [
                            base.opacity(0.93), midnight.opacity(0.94)]),
                            startPoint: CGPoint(x: l, y: t),
                            endPoint: CGPoint(x: l + pitchX, y: t + pitchY)))
                ctx.stroke(segment(CGPoint(x: l + 3, y: t + 2),
                                   CGPoint(x: l + pitchX - 8, y: t + 2)),
                           with: .color(cyan.opacity(0.12)), lineWidth: 1.2)
                ctx.stroke(segment(CGPoint(x: l + 2, y: t + 2),
                                   CGPoint(x: l + 2, y: t + pitchY - 8)),
                           with: .color(.white.opacity(0.055)), lineWidth: 1.2)
                let bolt = CGPoint(x: l + 8, y: t + 8)
                ctx.fill(disc(bolt, 1.7), with: .color(.black.opacity(0.72)))
                ctx.fill(disc(bolt, 0.65), with: .color(amber.opacity(0.28)))
                if (x + y * 7) % 5 == 0 {
                    let slot = CGRect(x: l + pitchX * 0.28, y: t + pitchY * 0.60,
                                      width: pitchX * 0.44, height: 3)
                    ctx.fill(Path(slot), with: .color(.black.opacity(0.65)))
                    ctx.fill(Path(CGRect(x: slot.minX, y: slot.minY, width: slot.width * 0.65,
                                         height: 1)), with: .color(cyan.opacity(0.23)))
                }
            }
        }

        // Recessed service trenches with double rails, warning studs and spaced bridge modules.
        for lane in [0.155, 0.845] {
            let yy = size.height * lane
            ctx.fill(Path(CGRect(x: 0, y: yy - 12, width: size.width, height: 24)),
                     with: .color(Color(red: 0.012, green: 0.026, blue: 0.052)))
            for offset in [-9.0, 9.0] {
                let rail = segment(CGPoint(x: 0, y: yy + offset),
                                   CGPoint(x: size.width, y: yy + offset))
                ctx.stroke(rail, with: .color(steel.opacity(0.95)), lineWidth: 3.5)
                ctx.stroke(rail, with: .color(cyan.opacity(0.25)), lineWidth: 0.7)
            }
            for stud in 0..<22 {
                let xx = (CGFloat(stud) + 0.5) * size.width / 22
                let block = CGRect(x: xx - 3, y: yy - 5, width: 6, height: 10)
                ctx.fill(Path(roundedRect: block, cornerRadius: 1), with: .color(steel))
                ctx.fill(Path(CGRect(x: xx - 1, y: yy - 3, width: 2, height: 6)),
                         with: .color(stud % 5 == 0 ? amber.opacity(0.65) : cyan.opacity(0.28)))
            }
        }
        // Heavy diagonal structural bracing, including metallic faces and inset highlights.
        for side in 0..<2 {
            let xBase = side == 0 ? size.width * 0.065 : size.width * 0.935
            for n in 0..<4 {
                let top = CGFloat(n) * size.height * 0.25
                let drift: CGFloat = side == 0 ? 26 : -26
                let face = poly([
                    CGPoint(x: xBase - 9, y: top),
                    CGPoint(x: xBase + 9, y: top),
                    CGPoint(x: xBase + drift + 9, y: top + size.height * 0.25),
                    CGPoint(x: xBase + drift - 9, y: top + size.height * 0.25)
                ])
                ctx.fill(face, with: .color(Color(red: 0.11, green: 0.19, blue: 0.29).opacity(0.68)))
                ctx.stroke(segment(CGPoint(x: xBase - 5, y: top + 5),
                                   CGPoint(x: xBase + drift - 5, y: top + size.height * 0.25 - 5)),
                           with: .color(glacier.opacity(0.12)), lineWidth: 1.5)
            }
        }
        // The core's safe area is intentionally brighter without obscuring active tracers.
        glow(ctx, center: CGPoint(x: size.width * 0.51, y: size.height * 0.50),
             radius: size.height * 0.36, color: cyan, intensity: 0.045)
    }

    private func drawReactors(_ ctx: GraphicsContext, size: CGSize,
                              scale: CGFloat, oscillation: Double) {
        let stations: [(CGFloat, CGFloat, CGFloat)] = [
            (0.22, 0.28, 0.092), (0.78, 0.28, 0.092),
            (0.22, 0.72, 0.092), (0.78, 0.72, 0.092),
            (0.50, 0.50, 0.205)
        ]
        for (index, unit) in stations.enumerated() {
            let p = CGPoint(x: size.width * unit.0, y: size.height * unit.1)
            let r = size.height * unit.2
            let active = index == 4
            glow(ctx, center: p, radius: r * 2.2, color: active ? cyan : purple,
                 intensity: (active ? 0.15 : 0.11) + oscillation * 0.045)
            ctx.fill(disc(CGPoint(x: p.x+4, y: p.y+7), r * 1.1),
                     with: .color(.black.opacity(0.72)))
            ctx.fill(disc(p, r), with: .radialGradient(Gradient(colors: [
                Color(red: 0.045, green: 0.13, blue: 0.20),
                Color(red: 0.014, green: 0.028, blue: 0.063),
                Color(red: 0.08, green: 0.14, blue: 0.24)]),
                center: CGPoint(x: p.x - r*0.25, y: p.y-r*0.30),
                startRadius: 0, endRadius: r))
            ctx.stroke(disc(p, r * 0.96), with: .color(steel), lineWidth: max(4, scale * 0.52))
            ctx.stroke(disc(p, r * 0.83), with: .color(cyan.opacity(0.30 + oscillation * 0.13)),
                       lineWidth: max(1.5, scale*0.16))
            ctx.stroke(disc(p, r * 0.67), with: .color(purple.opacity(0.62)),
                       lineWidth: max(3, scale*0.34))
            ctx.stroke(disc(p, r * 0.54), with: .color(.black.opacity(0.78)),
                       lineWidth: max(7, scale * 0.85))
            // Multiple staggered turbine blades rotate independently of enemy motion.
            for n in 0..<12 {
                let a = CGFloat(n) * .pi / 6 + CGFloat(clock * (active ? 0.22 : -0.12))
                let b = a + CGFloat(0.25)
                let turbine = poly([
                    CGPoint(x: p.x + cos(a)*r*0.32, y: p.y + sin(a)*r*0.32),
                    CGPoint(x: p.x + cos(a)*r*0.69, y: p.y + sin(a)*r*0.69),
                    CGPoint(x: p.x + cos(b)*r*0.77, y: p.y + sin(b)*r*0.77),
                    CGPoint(x: p.x + cos(b)*r*0.46, y: p.y + sin(b)*r*0.46)
                ])
                ctx.fill(turbine, with: .color(Color(red: 0.13, green: 0.25, blue: 0.37)
                    .opacity(n.isMultiple(of: 2) ? 0.90 : 0.58)))
                ctx.stroke(turbine, with: .color(glacier.opacity(0.16)), lineWidth: 0.9)
                let bolt = CGPoint(x: p.x + cos(a)*r*0.93, y: p.y + sin(a)*r*0.93)
                ctx.fill(disc(bolt, max(1.5, scale*0.18)),
                         with: .color(n.isMultiple(of: 3) ? amber : steel))
            }
            glow(ctx, center: p, radius: r * 0.58, color: cyan,
                 intensity: (active ? 0.21 : 0.11) + oscillation * 0.06)
            ctx.fill(disc(p, r*0.25), with: .radialGradient(Gradient(colors: [
                glacier.opacity(0.62), cyan.opacity(0.36), purple.opacity(0.18),
                Color(red: 0.02, green: 0.05, blue: 0.11)
            ]), center: p, startRadius: 0, endRadius: r*0.26))
            ctx.stroke(disc(p, r*0.29), with: .color(glacier.opacity(0.74)), lineWidth: 1.1)
            // Arc segments are real, opaque hardware rather than the previous unfilled rings.
            for n in 0..<8 {
                let a = CGFloat(n) * .pi / 4
                let q = CGPoint(x: p.x + cos(a)*r*1.03, y: p.y + sin(a)*r*1.03)
                ctx.fill(Path(roundedRect: CGRect(x: q.x-4, y: q.y-4, width: 8, height: 8),
                              cornerRadius: 1.5), with: .color(Color(red: 0.24, green: 0.35, blue: 0.46)))
                ctx.fill(disc(q, 1.35), with: .color(n.isMultiple(of: 2) ? amber : cyan))
            }
        }
    }

    private func drawArmor(_ ctx: GraphicsContext, size: CGSize,
                           cell: CGSize, scale: CGFloat, oscillation: Double) {
        var fast = Path(), slow = Path(), plateSeams = Path(), power = Path()
        var contour = Path(), bevel = Path(), gilded = Path()
        var studs = Path(), circuitry = Path()
        for y in 1..<(DivideEngine.rows-1) {
            for x in 1..<(DivideEngine.columns-1) {
                let tile = DividePoint(x: x, y: y)
                let value = engine.tone(tile)
                guard value != 0 else { continue }
                let r = rect(x, y, cell)
                if value == 2 { slow.addRect(r) } else { fast.addRect(r) }
                if x % 6 == 0 {
                    plateSeams.move(to: CGPoint(x: r.minX, y: r.minY))
                    plateSeams.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                }
                if y % 5 == 0 {
                    plateSeams.move(to: CGPoint(x: r.minX, y: r.minY))
                    plateSeams.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                }
                if y % 10 == 0 || x % 16 == 0 {
                    let ax = r.minX + r.width*0.25
                    let ay = r.minY + r.height*0.5
                    circuitry.move(to: CGPoint(x: ax, y: ay))
                    circuitry.addLine(to: CGPoint(x: r.maxX, y: ay))
                }
                if (x + 2*y) % 7 == 0 && y % 5 == 2 {
                    studs.addEllipse(in: CGRect(x: r.midX - 1.25, y: r.midY - 1.25,
                                                width: 2.5, height: 2.5))
                }
                if y % 8 == 0 && x % 3 == 0 {
                    power.move(to: CGPoint(x: r.minX, y: r.maxY - 2))
                    power.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2))
                }
                let left = !engine.isSafe(DividePoint(x: x-1, y: y))
                let right = !engine.isSafe(DividePoint(x: x+1, y: y))
                let above = !engine.isSafe(DividePoint(x: x, y: y-1))
                let below = !engine.isSafe(DividePoint(x: x, y: y+1))
                if left {
                    contour.move(to: CGPoint(x: r.minX, y: r.minY))
                    contour.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                    bevel.move(to: CGPoint(x: r.minX+2, y: r.minY))
                    bevel.addLine(to: CGPoint(x: r.minX+2, y: r.maxY))
                }
                if right {
                    contour.move(to: CGPoint(x: r.maxX, y: r.minY))
                    contour.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    gilded.move(to: CGPoint(x: r.maxX-3, y: r.minY))
                    gilded.addLine(to: CGPoint(x: r.maxX-3, y: r.maxY))
                }
                if above {
                    contour.move(to: CGPoint(x: r.minX, y: r.minY))
                    contour.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                    bevel.move(to: CGPoint(x: r.minX, y: r.minY+2))
                    bevel.addLine(to: CGPoint(x: r.maxX, y: r.minY+2))
                }
                if below {
                    contour.move(to: CGPoint(x: r.minX, y: r.maxY))
                    contour.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                    gilded.move(to: CGPoint(x: r.minX, y: r.maxY-3))
                    gilded.addLine(to: CGPoint(x: r.maxX, y: r.maxY-3))
                }
            }
        }
        ctx.fill(fast, with: .linearGradient(Gradient(colors: [
            Color(red: 0.25, green: 0.45, blue: 0.55),
            Color(red: 0.13, green: 0.29, blue: 0.42),
            Color(red: 0.08, green: 0.18, blue: 0.30)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width*0.7, y: size.height)))
        ctx.fill(slow, with: .linearGradient(Gradient(colors: [
            Color(red: 0.43, green: 0.31, blue: 0.56),
            Color(red: 0.25, green: 0.19, blue: 0.39),
            Color(red: 0.13, green: 0.14, blue: 0.28)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        ctx.stroke(plateSeams, with: .color(.black.opacity(0.69)), lineWidth: max(1.0, scale*0.17))
        ctx.stroke(plateSeams, with: .color(glacier.opacity(0.15)), lineWidth: 0.4)
        ctx.stroke(circuitry, with: .color(cyan.opacity(0.17 + oscillation*0.08)), lineWidth: 1.2)
        ctx.stroke(power, with: .color(amber.opacity(0.25 + oscillation*0.16)), lineWidth: 1.5)
        ctx.fill(studs, with: .color(glacier.opacity(0.46)))
        ctx.stroke(contour, with: .color(.black.opacity(0.86)), lineWidth: max(11, scale * 1.30))
        ctx.stroke(contour, with: .color(cyan.opacity(0.21)), lineWidth: max(9, scale * 0.95))
        ctx.stroke(contour, with: .color(cyan.opacity(0.90)), lineWidth: max(2, scale * 0.26))
        ctx.stroke(contour, with: .color(glacier.opacity(0.85)), lineWidth: 0.65)
        ctx.stroke(bevel, with: .color(glacier.opacity(0.33)), lineWidth: 1.1)
        ctx.stroke(gilded, with: .color(.black.opacity(0.48)), lineWidth: 1.5)
    }

    private func drawCapture(_ ctx: GraphicsContext, size: CGSize,
                             cell: CGSize, scale: CGFloat) {
        guard let capture else { return }
        let age = clock - capture.began
        guard age >= 0 && age < capture.duration, !capture.newCells.isEmpty else { return }
        let progress = age / capture.duration
        let fade = min(1.0, (capture.duration-age) / 0.38)
        let origin = point(CGFloat(capture.origin.x), CGFloat(capture.origin.y), cell)
        let maxDistance = hypot(size.width, size.height)
        let waveRadius = maxDistance * CGFloat(progress) * 1.05
        let ribbonWidth = max(scale * 2, 14)
        var bright = Path(), halo = Path(), aftermath = Path()
        for tile in capture.newCells {
            let p = point(CGFloat(tile.x), CGFloat(tile.y), cell)
            let d = hypot(p.x-origin.x, p.y-origin.y)
            if abs(d-waveRadius) < ribbonWidth*1.3 {
                halo.addRect(rect(tile.x, tile.y, cell))
            }
            if abs(d-waveRadius) < ribbonWidth*0.46 {
                bright.addRect(rect(tile.x, tile.y, cell))
            }
            if d < waveRadius && d > waveRadius - maxDistance*0.18 {
                aftermath.addRect(rect(tile.x, tile.y, cell))
            }
        }
        ctx.fill(aftermath, with: .color(cyan.opacity(0.06 * fade)))
        ctx.fill(halo, with: .color(cyan.opacity(0.32 * fade)))
        ctx.fill(bright, with: .color(glacier.opacity(0.72 * fade)))
        // A short-lived outward compression ring makes even a thin-line capture feel responsive.
        if age < 0.50 {
            let r = 8 + CGFloat(age) * 125
            ctx.stroke(disc(origin, r), with: .color(glacier.opacity((1-age/0.5)*0.50)),
                       lineWidth: max(2, scale*0.32))
        }
        // Deterministic debris flashes distributed only over actually claimed territory.
        for n in 0..<min(36, capture.newCells.count) {
            let index = (n * 101 + n*n * 7) % capture.newCells.count
            let tile = capture.newCells[index]
            let p = point(CGFloat(tile.x), CGFloat(tile.y), cell)
            let arrival = Double(hypot(p.x-origin.x, p.y-origin.y) / maxDistance) * (capture.duration / 1.05)
            let elapsed = age-arrival
            guard elapsed >= 0 && elapsed < 0.34 else { continue }
            let life = 1-elapsed/0.34
            let offset = CGFloat(elapsed) * CGFloat(10 + n % 14)
            let particle = CGPoint(x: p.x + CGFloat((n % 5)-2)*offset*0.25,
                                   y: p.y - offset)
            glow(ctx, center: particle, radius: max(3, scale*0.7),
                 color: n.isMultiple(of: 4) ? amber : glacier, intensity: life*0.46)
            ctx.fill(disc(particle, max(0.75, scale*0.09)),
                     with: .color(.white.opacity(life*0.85)))
        }
        if age < 1.25 {
            let caption = Text(capture.gain >= 1
                               ? String(format: "CONTAINMENT +%.1f%%", capture.gain)
                               : "CIRCUIT SEALED")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(glacier)
            let anchored = CGPoint(x: min(size.width - 145, max(145, origin.x)),
                                   y: max(40, origin.y - 32 - CGFloat(age*20)))
            ctx.draw(ctx.resolve(caption), at: anchored)
        }
    }

    private func drawRaceway(_ ctx: GraphicsContext, size: CGSize,
                             cell: CGSize, scale: CGFloat) {
        let border = CGRect(x: cell.width*0.5, y: cell.height*0.5,
                            width: size.width-cell.width, height: size.height-cell.height)
        ctx.stroke(Path(border), with: .color(.black.opacity(0.95)),
                   lineWidth: max(scale*2.9, 18))
        ctx.stroke(Path(border), with: .color(Color(red: 0.16, green: 0.32, blue: 0.42)),
                   lineWidth: max(scale*1.7, 9))
        ctx.stroke(Path(border), with: .color(cyan.opacity(0.35)), lineWidth: 4.5)
        ctx.stroke(Path(border), with: .color(glacier.opacity(0.89)), lineWidth: 1.45)
        for n in 0..<24 {
            let x = CGFloat(n) * (size.width-cell.width)/23 + cell.width*0.5
            let active = n % 4 == 0
            let rect = CGRect(x: x-2.2, y: cell.height*0.2,
                              width: 4.4, height: cell.height*0.70)
            ctx.fill(Path(rect), with: .color(active ? amber : cyan.opacity(0.71)))
            let bottom = CGRect(x: x-2.2, y: size.height-cell.height*0.90,
                                width: 4.4, height: cell.height*0.70)
            ctx.fill(Path(bottom), with: .color(active ? amber : cyan.opacity(0.71)))
        }
        for corner in 0..<4 {
            let right = corner % 2 == 1
            let bottom = corner / 2 == 1
            let x = right ? size.width-cell.width*0.5 : cell.width*0.5
            let y = bottom ? size.height-cell.height*0.5 : cell.height*0.5
            let signX: CGFloat = right ? -1 : 1
            let signY: CGFloat = bottom ? -1 : 1
            let mount = poly([CGPoint(x: x, y: y),
                              CGPoint(x: x+signX*32, y: y),
                              CGPoint(x: x+signX*20, y: y+signY*20),
                              CGPoint(x: x, y: y+signY*32)])
            ctx.fill(mount, with: .color(Color(red: 0.26, green: 0.34, blue: 0.41)))
            ctx.stroke(mount, with: .color(amber.opacity(0.67)), lineWidth: 1)
            ctx.fill(disc(CGPoint(x: x+signX*10, y: y+signY*10), 2.3),
                     with: .color(glacier))
        }
    }

    private func drawTrace(_ ctx: GraphicsContext, cell: CGSize,
                           scale: CGFloat, oscillation: Double) {
        guard let start = engine.trailStart, !engine.trail.isEmpty else { return }
        var p = Path()
        p.move(to: point(CGFloat(start.x), CGFloat(start.y), cell))
        for tile in engine.trail {
            p.addLine(to: point(CGFloat(tile.x), CGFloat(tile.y), cell))
        }
        let traceColor = engine.drawMode == .slow ? Color(red: 1, green: 0.40, blue: 0.88) : cyan
        ctx.stroke(p, with: .color(.black.opacity(0.94)), style: StrokeStyle(
            lineWidth: max(17, scale*1.9), lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(traceColor.opacity(0.20+oscillation*0.12)),
                   style: StrokeStyle(lineWidth: max(13, scale*1.45),
                                      lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(traceColor), style: StrokeStyle(
            lineWidth: max(5, scale*0.60), lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(.white), style: StrokeStyle(
            lineWidth: max(1.4, scale*0.20), lineCap: .round, lineJoin: .round))
        // Traveling energy packets clearly indicate exposure and direction of travel.
        for (i, tile) in engine.trail.enumerated() where i % 6 == Int(clock*10) % 6 {
            let center = point(CGFloat(tile.x), CGFloat(tile.y), cell)
            glow(ctx, center: center, radius: scale*1.1, color: traceColor, intensity: 0.35)
            ctx.fill(disc(center, scale*0.21), with: .color(.white))
        }
        if let fuse = engine.fusePoint {
            let p = point(CGFloat(fuse.x), CGFloat(fuse.y), cell)
            glow(ctx, center: p, radius: scale*3.1, color: orange, intensity: 0.56)
            ctx.fill(disc(p, scale*0.80), with: .color(orange))
            ctx.fill(disc(p, scale*0.35), with: .color(.white))
        }
    }

    private func drawEnemies(_ ctx: GraphicsContext, cell: CGSize,
                             scale: CGFloat, oscillation: Double) {
        for (index, enemy) in engine.enemies.enumerated() {
            let p = point(CGFloat(enemy.position.x), CGFloat(enemy.position.y), cell)
            let r = scale*(index.isMultiple(of: 3) ? 2.25 : 1.95)
            glow(ctx, center: p, radius: r*2.3, color: orange, intensity: 0.24+oscillation*0.10)
            ctx.fill(disc(CGPoint(x: p.x+2.8, y: p.y+4.5), r*0.91),
                     with: .color(.black.opacity(0.79)))
            let spin = CGFloat(enemy.spin)
            var hull = [CGPoint]()
            for n in 0..<8 {
                let a = CGFloat(n)*(.pi/4) + spin*0.18
                hull.append(CGPoint(x: p.x+cos(a)*r*0.85,
                                    y: p.y+sin(a)*r*0.85))
            }
            ctx.fill(poly(hull), with: .linearGradient(Gradient(colors: [
                Color(red: 0.37, green: 0.20, blue: 0.20),
                Color(red: 0.12, green: 0.10, blue: 0.17),
                Color(red: 0.22, green: 0.12, blue: 0.20)]),
                startPoint: CGPoint(x: p.x-r, y: p.y-r),
                endPoint: CGPoint(x: p.x+r, y: p.y+r)))
            ctx.stroke(poly(hull), with: .color(orange.opacity(0.95)),
                       lineWidth: max(1.7, scale*0.22))
            for n in 0..<4 {
                let a = spin + CGFloat(n)*(.pi/2)
                let blade = poly([
                    CGPoint(x: p.x+cos(a)*r*0.31, y: p.y+sin(a)*r*0.31),
                    CGPoint(x: p.x+cos(a-0.12)*r*0.81, y: p.y+sin(a-0.12)*r*0.81),
                    CGPoint(x: p.x+cos(a+0.33)*r*1.12, y: p.y+sin(a+0.33)*r*1.12),
                    CGPoint(x: p.x+cos(a+0.55)*r*0.50, y: p.y+sin(a+0.55)*r*0.50)
                ])
                ctx.fill(blade, with: .color(n.isMultiple(of: 2) ? amber : orange))
                ctx.stroke(blade, with: .color(.white.opacity(0.47)), lineWidth: 0.7)
            }
            ctx.fill(disc(p, r*0.51), with: .color(Color(red: 0.12, green: 0.10, blue: 0.16)))
            ctx.stroke(disc(p, r*0.47), with: .color(amber), lineWidth: 1.5)
            glow(ctx, center: p, radius: r*0.45, color: orange,
                 intensity: 0.50+oscillation*0.22)
            ctx.fill(disc(p, r*0.26), with: .color(orange))
            ctx.fill(disc(p, r*0.11), with: .color(.white))
            for n in 0..<3 {
                let a = CGFloat(n)*(.pi*2/3)-spin*0.6
                let probe = CGPoint(x: p.x+cos(a)*r*1.35, y: p.y+sin(a)*r*1.35)
                ctx.fill(disc(probe, max(1, scale*0.15)), with: .color(amber.opacity(0.83)))
            }
        }
    }

    private func drawSentries(_ ctx: GraphicsContext, cell: CGSize,
                              scale: CGFloat, oscillation: Double) {
        for (index, spark) in engine.sparks.enumerated() {
            let tile = engine.sparkPosition(spark)
            let p = point(CGFloat(tile.x), CGFloat(tile.y), cell)
            let r = scale*1.22
            glow(ctx, center: p, radius: r*2.0, color: amber,
                 intensity: 0.20+oscillation*0.12)
            ctx.fill(disc(CGPoint(x: p.x+2, y: p.y+3), r*0.90),
                     with: .color(.black.opacity(0.80)))
            let hull = poly([CGPoint(x:p.x, y:p.y-r),
                             CGPoint(x:p.x+r, y:p.y),
                             CGPoint(x:p.x, y:p.y+r),
                             CGPoint(x:p.x-r, y:p.y)])
            ctx.fill(hull, with: .color(Color(red: 0.30, green: 0.22, blue: 0.11)))
            ctx.stroke(hull, with: .color(amber), lineWidth: 1.9)
            for n in 0..<4 {
                let a = CGFloat(n)*(.pi/2)+CGFloat(clock*(index == 0 ? 1 : -1))
                let end = CGPoint(x:p.x+cos(a)*r*1.45, y:p.y+sin(a)*r*1.45)
                ctx.stroke(segment(p, end), with: .color(amber.opacity(0.82)), lineWidth: 1.3)
            }
            ctx.fill(disc(p, scale*0.30), with: .color(glacier))
        }
    }

    private func drawCommandDrone(_ ctx: GraphicsContext, cell: CGSize,
                                  scale: CGFloat, oscillation: Double) {
        let p = point(CGFloat(engine.player.x), CGFloat(engine.player.y), cell)
        let r = scale*1.33
        let visibility = engine.invulnerable ? 0.43+0.57*oscillation : 1.0
        glow(ctx, center: p, radius: r*2.3, color: cyan, intensity: 0.28*visibility)
        ctx.fill(disc(CGPoint(x:p.x+2, y:p.y+3), r*1.02),
                 with: .color(.black.opacity(0.88)))
        let hull = poly([
            CGPoint(x:p.x, y:p.y-r*1.20),
            CGPoint(x:p.x+r*0.84, y:p.y-r*0.30),
            CGPoint(x:p.x+r*1.10, y:p.y+r*0.32),
            CGPoint(x:p.x, y:p.y+r*1.09),
            CGPoint(x:p.x-r*1.10, y:p.y+r*0.32),
            CGPoint(x:p.x-r*0.84, y:p.y-r*0.30)
        ])
        ctx.fill(hull, with: .linearGradient(Gradient(colors: [
            Color(red: 0.28, green: 0.59, blue: 0.70),
            Color(red: 0.06, green: 0.20, blue: 0.30)]),
            startPoint: CGPoint(x:p.x-r, y:p.y-r),
            endPoint: CGPoint(x:p.x+r, y:p.y+r)))
        ctx.stroke(hull, with: .color(glacier.opacity(visibility)), lineWidth: 2.4)
        ctx.stroke(disc(p, r*0.75), with: .color(cyan.opacity(0.63*visibility)), lineWidth: 1.2)
        ctx.fill(disc(p, r*0.39), with: .color(Color(red: 0.01, green: 0.12, blue: 0.21)))
        ctx.fill(disc(p, r*0.20), with: .color(glacier.opacity(visibility)))
        for side in [-1.0, 1.0] {
            let x = p.x + CGFloat(side)*r*0.65
            let wing = poly([CGPoint(x:x, y:p.y-r*0.28),
                             CGPoint(x:x+CGFloat(side)*r*0.37, y:p.y),
                             CGPoint(x:x, y:p.y+r*0.38)])
            ctx.fill(wing, with: .color(cyan.opacity(0.65*visibility)))
        }
    }
}
