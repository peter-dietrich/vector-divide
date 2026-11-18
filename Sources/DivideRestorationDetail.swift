import SwiftUI

/// Production-art pass for the Modern board: captured cells uncover machinery and
/// re-energize deck sectors. Every path is clipped to real safe terrain. No game rules,
/// saved data, image downloads, or commercial textures are involved.
struct DivideRestorationDetail {
    private let ice = Color(red: 0.51, green: 0.94, blue: 1.0)
    private let bronze = Color(red: 0.96, green: 0.69, blue: 0.34)
    private let violet = Color(red: 0.58, green: 0.39, blue: 0.89)
    private let blackSteel = Color(red: 0.055, green: 0.11, blue: 0.18)
    private let blueSteel = Color(red: 0.15, green: 0.31, blue: 0.43)

    private func circle(_ at: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: at.x-radius, y: at.y-radius,
                                width: radius*2, height: radius*2))
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func cellMask(engine: DivideEngine, cell: CGSize) -> Path {
        // Merge adjacent horizontal safe cells before clipping; avoids thousands
        // of tiny draw calls for the captured side of a nearly full reactor.
        var mask = Path()
        for y in 1..<(DivideEngine.rows-1) {
            var x = 1
            while x < DivideEngine.columns-1 {
                if !engine.isSafe(DividePoint(x: x, y: y)) {
                    x += 1
                    continue
                }
                let first = x
                while x < DivideEngine.columns-1 &&
                    engine.isSafe(DividePoint(x: x, y: y)) {
                    x += 1
                }
                mask.addRect(CGRect(x: CGFloat(first)*cell.width,
                                    y: CGFloat(y)*cell.height,
                                    width: CGFloat(x-first)*cell.width,
                                    height: cell.height+0.2))
            }
        }
        return mask
    }

    func paint(_ context: GraphicsContext, size: CGSize,
               engine: DivideEngine, clock: Double) {
        guard engine.percentClaimed > 0 else { return }
        let cell = CGSize(width: size.width / CGFloat(DivideEngine.columns),
                          height: size.height / CGFloat(DivideEngine.rows))
        var ctx = context
        ctx.clip(to: cellMask(engine: engine, cell: cell))
        let sweep = (sin(clock*1.7) + 1) * 0.5

        // Wide, deliberately irregular armor bays break up the old spreadsheet grid.
        // Each secured bay exposes a different arrangement of paneling and hardware.
        let baysAcross = 7
        let baysDown = 4
        let dx = size.width / CGFloat(baysAcross)
        let dy = size.height / CGFloat(baysDown)
        for y in 0..<baysDown {
            for x in 0..<baysAcross {
                let seed = x*31 + y*17
                let left = CGFloat(x)*dx + 4
                let top = CGFloat(y)*dy + 4
                let right = left + dx - 8
                let bottom = top + dy - 8
                let cut = CGFloat(8 + seed % 12)
                let bay = polygon([
                    CGPoint(x: left+cut, y: top),
                    CGPoint(x: right-cut*0.30, y: top),
                    CGPoint(x: right, y: top+cut*0.60),
                    CGPoint(x: right, y: bottom-cut),
                    CGPoint(x: right-cut, y: bottom),
                    CGPoint(x: left+cut*0.18, y: bottom),
                    CGPoint(x: left, y: bottom-cut*0.52),
                    CGPoint(x: left, y: top+cut)
                ])
                let material = seed % 4
                let upper: Color = material == 0 ? Color(red: 0.31, green: 0.45, blue: 0.51)
                                  : material == 1 ? Color(red: 0.19, green: 0.34, blue: 0.44)
                                  : material == 2 ? Color(red: 0.20, green: 0.31, blue: 0.42)
                                  : Color(red: 0.25, green: 0.32, blue: 0.43)
                ctx.fill(bay, with: .linearGradient(
                    Gradient(colors: [upper.opacity(0.92), blueSteel, blackSteel]),
                    startPoint: CGPoint(x: left, y: top),
                    endPoint: CGPoint(x: right, y: bottom)))
                ctx.stroke(bay, with: .color(.black.opacity(0.83)), lineWidth: 5.5)
                ctx.stroke(bay, with: .color(ice.opacity(0.26)), lineWidth: 1.1)
                let inset = CGRect(x: left+cut*0.45, y: top+cut*0.42,
                                   width: dx-cut*1.1-8, height: dy-cut*0.95-8)
                if inset.width > 10 && inset.height > 10 {
                    ctx.stroke(Path(roundedRect: inset, cornerRadius: 5),
                               with: .color(.black.opacity(0.40)), lineWidth: 2.5)
                }

                // A mixture of visible power transformers, vent arrays,
                // access hatches and cable junctions rather than uniform squares.
                switch material {
                case 0:
                    let c = CGPoint(x: (left+right)*0.5, y: (top+bottom)*0.5)
                    let radius = min(dx, dy)*0.29
                    ctx.fill(circle(CGPoint(x: c.x+2, y: c.y+4), radius*1.04),
                             with: .color(.black.opacity(0.74)))
                    ctx.fill(circle(c, radius), with: .radialGradient(
                        Gradient(colors: [Color(red: 0.08, green: 0.29, blue: 0.34),
                                          Color(red: 0.025, green: 0.08, blue: 0.16)]),
                        center: c, startRadius: 0, endRadius: radius))
                    ctx.stroke(circle(c, radius), with: .color(ice.opacity(0.37)), lineWidth: 3.0)
                    ctx.stroke(circle(c, radius*0.68), with: .color(.black.opacity(0.72)), lineWidth: 6)
                    for i in 0..<8 {
                        let angle = Double(i)*Double.pi/4 + clock*0.13
                        let a = CGPoint(x: c.x+CGFloat(cos(angle))*radius*0.40,
                                        y: c.y+CGFloat(sin(angle))*radius*0.40)
                        let b = CGPoint(x: c.x+CGFloat(cos(angle+0.32))*radius*0.83,
                                        y: c.y+CGFloat(sin(angle+0.32))*radius*0.83)
                        ctx.stroke(line(a,b), with: .color(ice.opacity(0.40+sweep*0.22)), lineWidth: 3.1)
                    }
                    ctx.fill(circle(c, radius*0.28), with: .color(ice.opacity(0.31+sweep*0.30)))
                case 1:
                    let count = 6
                    for i in 0..<count {
                        let slotY = top + 13 + CGFloat(i)*(dy-24)/CGFloat(count)
                        let slot = CGRect(x: left+dx*0.13, y: slotY,
                                          width: dx*0.70, height: max(3.5, dy/CGFloat(count)*0.46))
                        ctx.fill(Path(roundedRect: slot, cornerRadius: 2),
                                 with: .color(.black.opacity(0.65)))
                        ctx.fill(Path(CGRect(x: slot.minX+2, y: slot.minY+2,
                                            width: slot.width*0.63, height: 1.7)),
                                 with: .color(i % 3 == 0 ? bronze.opacity(0.64) : ice.opacity(0.37)))
                    }
                case 2:
                    let c = CGPoint(x: (left+right)/2, y: (top+bottom)/2)
                    ctx.fill(Path(roundedRect: CGRect(x: c.x-dx*0.29, y: c.y-dy*0.25,
                                                       width: dx*0.58, height: dy*0.50),
                                  cornerRadius: 6), with: .color(blackSteel))
                    for i in 0..<4 {
                        let xx = c.x-dx*0.23 + CGFloat(i)*dx*0.15
                        ctx.fill(Path(roundedRect: CGRect(x: xx, y: c.y-dy*0.18,
                                                           width: dx*0.10, height: dy*0.36),
                                      cornerRadius: 3),
                                 with: .linearGradient(
                                    Gradient(colors: [
                                        Color(red: 0.21, green: 0.45, blue: 0.54),
                                        Color(red: 0.035, green: 0.13, blue: 0.23)]),
                                    startPoint: CGPoint(x: xx, y: top),
                                    endPoint: CGPoint(x: xx, y: bottom)))
                        ctx.fill(Path(CGRect(x: xx+2, y: c.y-dy*0.13, width: 2, height: dy*0.25)),
                                 with: .color(ice.opacity(0.37)))
                    }
                default:
                    for i in 0..<4 {
                        let yy = top+14+CGFloat(i)*(dy-22)/4
                        ctx.stroke(line(CGPoint(x: left+16, y: yy),
                                        CGPoint(x: right-15, y: yy)),
                                   with: .color(.black.opacity(0.71)), lineWidth: 7.0)
                        ctx.stroke(line(CGPoint(x: left+18, y: yy-2),
                                        CGPoint(x: right-17, y: yy-2)),
                                   with: .color((i+seed) % 3 == 0 ? bronze.opacity(0.49)
                                                       : ice.opacity(0.24)), lineWidth: 1.6)
                    }
                }

                // Physical fastening points with subtle illuminated identification.
                for corner in 0..<4 {
                    let px = corner % 2 == 0 ? left+10 : right-10
                    let py = corner/2 == 0 ? top+10 : bottom-10
                    ctx.fill(circle(CGPoint(x: px,y:py), 3.0),
                             with: .color(.black.opacity(0.82)))
                    ctx.fill(circle(CGPoint(x: px,y:py), 1.35),
                             with: .color((seed + corner) % 7 == 0 ? bronze : ice.opacity(0.49)))
                }
            }
        }

        // Two energized arteries link the reclaimed sectors. Pulses travel along
        // real machinery under the armor rather than along the gameplay grid.
        for lane in 0..<3 {
            let yy = size.height * CGFloat(0.20 + 0.30*Double(lane))
            ctx.stroke(line(CGPoint(x: -20, y: yy),
                            CGPoint(x: size.width+20, y: yy)),
                       with: .color(.black.opacity(0.72)), lineWidth: 12)
            ctx.stroke(line(CGPoint(x: -20, y: yy-1),
                            CGPoint(x: size.width+20, y: yy-1)),
                       with: .color(ice.opacity(0.27)), lineWidth: 2.5)
            for p in 0..<18 {
                let xx = (CGFloat(p)+CGFloat(clock*3.2)
                          .truncatingRemainder(dividingBy: 18))*size.width/18
                let spark = CGRect(x: xx-3, y: yy-3.4, width: 7, height: 4.6)
                ctx.fill(Path(roundedRect: spark, cornerRadius: 1.5),
                         with: .color(p.isMultiple(of: 4) ? bronze.opacity(0.75)
                                          : ice.opacity(0.63+sweep*0.20)))
            }
        }

        // A restrained moving light sweep adds life after reconstruction.
        let scanX = CGFloat((clock*0.045).truncatingRemainder(dividingBy: 1.0))
                     * (size.width+240)-120
        ctx.fill(Path(CGRect(x: scanX-70, y: 0, width: 140, height: size.height)),
                 with: .linearGradient(
                    Gradient(colors: [.clear, ice.opacity(0.045), .clear]),
                    startPoint: CGPoint(x: scanX-70, y: 0),
                    endPoint: CGPoint(x: scanX+70, y: 0)))
    }
}
