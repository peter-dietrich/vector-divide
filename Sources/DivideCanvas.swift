import SwiftUI

struct DivideBoard: View {
    let engine: DivideEngine
    private let cyan = Color(red: 0.35, green: 0.91, blue: 0.96)
    private let orange = Color(red: 1, green: 0.62, blue: 0.24)
    private let pink = Color(red: 1, green: 0.38, blue: 0.69)

    var body: some View {
        Canvas(opaque: true) { context, size in
            render(context, size: size)
        }
        .background(.black)
        .accessibilityLabel("Vector Divide arcade playing field")
    }

    private func render(_ context: GraphicsContext, size: CGSize) {
        let ctx = context
        let cellWidth = size.width / CGFloat(DivideEngine.columns)
        let cellHeight = size.height / CGFloat(DivideEngine.rows)
        let scale = min(cellWidth, cellHeight)
        func center(_ point: DividePoint) -> CGPoint {
            CGPoint(x: (CGFloat(point.x) + 0.5) * cellWidth,
                    y: (CGFloat(point.y) + 0.5) * cellHeight)
        }
        func centerEnemy(_ vector: DivideVector) -> CGPoint {
            CGPoint(x: (CGFloat(vector.x) + 0.5) * cellWidth,
                    y: (CGFloat(vector.y) + 0.5) * cellHeight)
        }

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        var mesh = Path()
        for x in stride(from: 0, through: DivideEngine.columns, by: 4) {
            let gx = CGFloat(x) * cellWidth
            mesh.move(to: CGPoint(x: gx, y: 0))
            mesh.addLine(to: CGPoint(x: gx, y: size.height))
        }
        for y in stride(from: 0, through: DivideEngine.rows, by: 4) {
            let gy = CGFloat(y) * cellHeight
            mesh.move(to: CGPoint(x: 0, y: gy))
            mesh.addLine(to: CGPoint(x: size.width, y: gy))
        }
        ctx.stroke(mesh, with: .color(cyan.opacity(0.065)), lineWidth: 0.55)

        var fastTiles = Path()
        var slowTiles = Path()
        var contour = Path()
        for y in 1..<(DivideEngine.rows - 1) {
            for x in 1..<(DivideEngine.columns - 1) {
                let point = DividePoint(x: x, y: y)
                let value = engine.tone(point)
                guard value != 0 else { continue }
                let rect = CGRect(x: CGFloat(x) * cellWidth, y: CGFloat(y) * cellHeight,
                                  width: cellWidth + 0.2, height: cellHeight + 0.2)
                if value == 2 { slowTiles.addRect(rect) }
                else { fastTiles.addRect(rect) }
                let left = CGFloat(x) * cellWidth
                let top = CGFloat(y) * cellHeight
                let right = left + cellWidth
                let bottom = top + cellHeight
                if !engine.isSafe(DividePoint(x: x - 1, y: y)) {
                    contour.move(to: CGPoint(x: left, y: top)); contour.addLine(to: CGPoint(x: left, y: bottom))
                }
                if !engine.isSafe(DividePoint(x: x + 1, y: y)) {
                    contour.move(to: CGPoint(x: right, y: top)); contour.addLine(to: CGPoint(x: right, y: bottom))
                }
                if !engine.isSafe(DividePoint(x: x, y: y - 1)) {
                    contour.move(to: CGPoint(x: left, y: top)); contour.addLine(to: CGPoint(x: right, y: top))
                }
                if !engine.isSafe(DividePoint(x: x, y: y + 1)) {
                    contour.move(to: CGPoint(x: left, y: bottom)); contour.addLine(to: CGPoint(x: right, y: bottom))
                }
            }
        }
        ctx.fill(fastTiles, with: .color(Color(red: 0.065, green: 0.35, blue: 0.45)))
        ctx.fill(slowTiles, with: .color(Color(red: 0.47, green: 0.21, blue: 0.40)))
        ctx.stroke(contour, with: .color(cyan.opacity(0.92)), lineWidth: 1.1)
        ctx.stroke(Path(CGRect(x: cellWidth * 0.5, y: cellHeight * 0.5,
                             width: size.width - cellWidth, height: size.height - cellHeight)),
                   with: .color(cyan), lineWidth: 2.2)

        if let start = engine.trailStart, !engine.trail.isEmpty {
            var line = Path()
            line.move(to: center(start))
            for point in engine.trail { line.addLine(to: center(point)) }
            ctx.stroke(line, with: .color(engine.drawMode == .slow ? pink : cyan),
                       style: StrokeStyle(lineWidth: max(2.0, scale * 0.27), lineCap: .square, lineJoin: .miter))
            // Fuse appears after a stopped draw; it travels through the exposed line.
            if let fuse = engine.fusePoint {
                let p = center(fuse)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - scale * 0.45, y: p.y - scale * 0.45,
                                              width: scale * 0.9, height: scale * 0.9)),
                         with: .color(orange))
            }
        }

        for enemy in engine.enemies {
            let origin = centerEnemy(enemy.position)
            let rotation = enemy.spin
            // Original six-armed dancing energy glyph, not borrowed artwork.
            var body = Path()
            for spoke in 0..<6 {
                let a = rotation + Double(spoke) * Double.pi / 3.0
                let r1 = scale * (0.55 + 0.12 * CGFloat(spoke % 2))
                let r2 = scale * (1.45 + 0.21 * CGFloat(spoke % 3))
                let p1 = CGPoint(x: origin.x + CGFloat(cos(a)) * r1, y: origin.y + CGFloat(sin(a)) * r1)
                let p2 = CGPoint(x: origin.x + CGFloat(cos(a + 0.22)) * r2, y: origin.y + CGFloat(sin(a + 0.22)) * r2)
                let p3 = CGPoint(x: origin.x + CGFloat(cos(a + 0.55)) * r2 * 0.68, y: origin.y + CGFloat(sin(a + 0.55)) * r2 * 0.68)
                body.move(to: p1); body.addLine(to: p2); body.addLine(to: p3)
            }
            ctx.stroke(body, with: .color(pink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: origin.x - scale * 0.27, y: origin.y - scale * 0.27,
                                          width: scale * 0.54, height: scale * 0.54)), with: .color(.white))
        }

        for spark in engine.sparks {
            let p = center(engine.sparkPosition(spark))
            var star = Path()
            let radius = scale * 0.8
            star.move(to: CGPoint(x: p.x - radius, y: p.y)); star.addLine(to: CGPoint(x: p.x + radius, y: p.y))
            star.move(to: CGPoint(x: p.x, y: p.y - radius)); star.addLine(to: CGPoint(x: p.x, y: p.y + radius))
            ctx.stroke(star, with: .color(orange), lineWidth: 2.1)
        }

        let player = center(engine.player)
        let radius = scale * 0.68
        var diamond = Path()
        diamond.move(to: CGPoint(x: player.x, y: player.y - radius))
        diamond.addLine(to: CGPoint(x: player.x + radius, y: player.y))
        diamond.addLine(to: CGPoint(x: player.x, y: player.y + radius))
        diamond.addLine(to: CGPoint(x: player.x - radius, y: player.y))
        diamond.closeSubpath()
        let flash = engine.invulnerable ? 0.45 : 1.0
        ctx.fill(diamond, with: .color(Color.white.opacity(flash)))
        ctx.stroke(diamond, with: .color(cyan), lineWidth: 1.2)
    }
}
