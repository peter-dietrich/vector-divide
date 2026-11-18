import SwiftUI

/// A read-only real-time representation of the actual 68 × 44 simulation.
/// Terrain, hostile positions and the player always come from DivideEngine.
struct DivideTacticalMap: View {
    let engine: DivideEngine

    var body: some View {
        Canvas(opaque: true) { ctx, size in
            let sx = size.width / CGFloat(DivideEngine.columns)
            let sy = size.height / CGFloat(DivideEngine.rows)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.025, green: 0.05, blue: 0.10)))
            var safe = Path(), slow = Path()
            for y in 1..<(DivideEngine.rows - 1) {
                var start = 1
                while start < DivideEngine.columns-1 {
                    let value = engine.tone(DividePoint(x: start, y: y))
                    if value == 0 { start += 1; continue }
                    var end = start+1
                    while end < DivideEngine.columns-1 &&
                        engine.tone(DividePoint(x: end, y: y)) == value {
                        end += 1
                    }
                    let r = CGRect(x: CGFloat(start)*sx, y: CGFloat(y)*sy,
                                   width: CGFloat(end-start)*sx+0.1, height: sy+0.1)
                    if value == 2 { slow.addRect(r) } else { safe.addRect(r) }
                    start = end
                }
            }
            ctx.fill(safe, with: .color(Color(red: 0.13, green: 0.48, blue: 0.61)))
            ctx.fill(slow, with: .color(Color(red: 0.55, green: 0.34, blue: 0.69)))
            ctx.stroke(Path(CGRect(x: sx*0.5, y: sy*0.5,
                                  width: size.width-sx, height: size.height-sy)),
                       with: .color(Color(red: 0.34, green: 0.87, blue: 0.96)), lineWidth: 1.4)
            if !engine.trail.isEmpty {
                var trail = Path()
                if let start = engine.trailStart {
                    trail.move(to: CGPoint(x: (CGFloat(start.x)+0.5)*sx,
                                           y: (CGFloat(start.y)+0.5)*sy))
                }
                for cell in engine.trail {
                    trail.addLine(to: CGPoint(x: (CGFloat(cell.x)+0.5)*sx,
                                              y: (CGFloat(cell.y)+0.5)*sy))
                }
                ctx.stroke(trail, with: .color(.white), lineWidth: 1.8)
            }
            for enemy in engine.enemies {
                let x = (CGFloat(enemy.position.x)+0.5)*sx
                let y = (CGFloat(enemy.position.y)+0.5)*sy
                ctx.fill(Path(ellipseIn: CGRect(x: x-3.2, y: y-3.2,
                                                width: 6.4, height: 6.4)),
                         with: .color(Color(red: 1, green: 0.42, blue: 0.25)))
            }
            for spark in engine.sparks {
                let p = engine.sparkPosition(spark)
                let x = (CGFloat(p.x)+0.5)*sx
                let y = (CGFloat(p.y)+0.5)*sy
                ctx.fill(Path(ellipseIn: CGRect(x: x-2, y: y-2, width: 4, height: 4)),
                         with: .color(Color(red: 1, green: 0.77, blue: 0.31)))
            }
            let p = engine.player
            let x = (CGFloat(p.x)+0.5)*sx
            let y = (CGFloat(p.y)+0.5)*sy
            ctx.fill(Path(ellipseIn: CGRect(x: x-3.5, y: y-3.5, width: 7, height: 7)),
                     with: .color(.white))
        }
        .accessibilityLabel("Live tactical map: cyan captured area, orange enemy anomalies, white player drone")
    }
}
