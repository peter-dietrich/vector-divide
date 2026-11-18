import AppKit
import SceneKit
import SwiftUI

/// Real SceneKit geometry, depth-tested materials, directional lighting and
/// an orthographic 3/4 camera. All positions are projected from DivideEngine.
/// This view never owns gameplay state, scores, or persistence.
struct DivideModern3D: NSViewRepresentable {
    let engine: DivideEngine
    let capture: DivideCaptureFX?
    let poweredRelays: Set<Int>
    let empRemaining: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.backgroundColor = NSColor(red: 0.016, green: 0.025, blue: 0.048, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        context.coordinator.update(engine: engine, capture: capture,
                                   poweredRelays: poweredRelays, empRemaining: empRemaining)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.update(engine: engine, capture: capture,
                                   poweredRelays: poweredRelays, empRemaining: empRemaining)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        private let arena = SCNNode()
        private let capturedRoot = SCNNode()
        private let traceRoot = SCNNode()
        private let enemyRoot = SCNNode()
        private let relayRoot = SCNNode()
        private let player = SCNNode()
        private let waveRoot = SCNNode()
        private var fingerprint: UInt64 = 0
        private var previousTrail: [DividePoint] = []
        private var previousRelaySet = Set<Int>()
        private var lastCaptureTime = -1.0
        private var initialized = false
        private let steel = material(0.085, 0.16, 0.24, metal: 0.78)
        private let active = material(0.13, 0.42, 0.50, metal: 0.73, emission: (0.015, 0.11, 0.15))
        private let purple = material(0.31, 0.19, 0.45, metal: 0.70, emission: (0.06, 0.01, 0.11))
        private let cyan = material(0.21, 0.78, 0.93, metal: 0.25, emission: (0.18, 0.57, 0.72))
        private let amber = material(0.96, 0.49, 0.16, metal: 0.33, emission: (0.51, 0.12, 0.015))
        private let black = material(0.020, 0.038, 0.071, metal: 0.43)
        private let white = material(0.69, 0.96, 1.0, metal: 0.13, emission: (0.32, 0.64, 0.72))
        private var enemies = [SCNNode]()
        private var sentries = [SCNNode]()

        private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                     metal: CGFloat = 0.35,
                                     emission: (CGFloat, CGFloat, CGFloat) = (0,0,0)) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            m.metalness.contents = metal
            m.roughness.contents = 0.35
            m.emission.contents = NSColor(srgbRed: emission.0, green: emission.1,
                                          blue: emission.2, alpha: 1)
            m.lightingModel = .physicallyBased
            m.isDoubleSided = true
            return m
        }

        private static func location(_ x: Double, _ y: Double,
                                     elevation: Float = 0) -> SCNVector3 {
            SCNVector3(Float(x - 33.5), elevation, Float(y - 21.5))
        }

        private func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ m: SCNMaterial,
                         chamfer: CGFloat = 0) -> SCNNode {
            let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: chamfer)
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            node.castsShadow = true
            return node
        }

        private func cylinder(_ radius: CGFloat, _ height: CGFloat, _ m: SCNMaterial) -> SCNNode {
            let geometry = SCNCylinder(radius: radius, height: height)
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry)
            return node
        }

        private func orb(_ radius: CGFloat, _ m: SCNMaterial) -> SCNNode {
            let g = SCNSphere(radius: radius)
            g.segmentCount = 14
            g.materials = [m]
            return SCNNode(geometry: g)
        }

        private func torus(_ ring: CGFloat, _ pipe: CGFloat, _ m: SCNMaterial) -> SCNNode {
            let g = SCNTorus(ringRadius: ring, pipeRadius: pipe)
            g.materials = [m]
            return SCNNode(geometry: g)
        }

        private func buildScene() {
            initialized = true
            scene.background.contents = NSColor(red: 0.012, green: 0.022, blue: 0.048, alpha: 1)
            scene.rootNode.addChildNode(arena)
            for n in [capturedRoot, traceRoot, enemyRoot, relayRoot, waveRoot, player] {
                arena.addChildNode(n)
            }
            let base = box(69.5, 1.2, 45.5, steel, chamfer: 0.55)
            base.position.y = -0.90
            arena.addChildNode(base)

            // The unpowered floor is a sunken, dark, recessed physical surface.
            let void = box(66.2, 0.11, 42.2, black)
            void.position.y = -0.22
            arena.addChildNode(void)
            // Strong perimeter barricade and illuminated rails.
            for side in 0..<4 {
                let horizontal = side < 2
                let rail = box(horizontal ? 69 : 0.95, 1.08,
                               horizontal ? 0.95 : 45, steel, chamfer: 0.13)
                rail.position = horizontal
                    ? SCNVector3(0, 0.17, side == 0 ? -21.6 : 21.6)
                    : SCNVector3(side == 2 ? -33.6 : 33.6, 0.17, 0)
                arena.addChildNode(rail)
                let lightRail = box(horizontal ? 68.2 : 0.19, 0.12,
                                    horizontal ? 0.19 : 43.1, cyan)
                lightRail.position = SCNVector3(rail.position.x, 0.81, rail.position.z)
                arena.addChildNode(lightRail)
            }

            // Large reactor machinery stands around the perimeter and does not
            // occlude safe paths or become decorative "wallpaper" in captured regions.
            for corner in 0..<4 {
                let x: Float = corner % 2 == 0 ? -38 : 38
                let z: Float = corner / 2 == 0 ? -26 : 26
                let plinth = box(6, 4.4, 6, steel, chamfer: 0.35)
                plinth.position = SCNVector3(x, 0.1, z)
                arena.addChildNode(plinth)
                let chamber = cylinder(2.1, 5.6, black)
                chamber.position = SCNVector3(x, 4.5, z)
                arena.addChildNode(chamber)
                let cap = torus(2.05, 0.19, cyan)
                cap.position = SCNVector3(x, 7.3, z)
                arena.addChildNode(cap)
                let core = orb(0.88, amber)
                core.position = SCNVector3(x, 4.5, z)
                arena.addChildNode(core)
                core.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.27, z: 0, duration: 1.1),
                    .moveBy(x: 0, y: -0.27, z: 0, duration: 1.1)
                ])))
            }

            // Physical piping is outside the board so no capture cell is hidden.
            for z in [-25.0, 25.0] {
                for y in [0.3, 1.1] {
                    let pipe = cylinder(0.23, 71.0, steel)
                    pipe.eulerAngles.z = Float.pi / 2
                    pipe.position = SCNVector3(0, Float(y), Float(z))
                    arena.addChildNode(pipe)
                }
            }

            // 3/4 camera: orthographic prevents perspective mis-click illusion
            // while showing real height and side faces.
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 75
            camera.zNear = 0.1
            camera.zFar = 400
            camera.wantsHDR = true
            camera.bloomIntensity = 0.24
            camera.bloomThreshold = 1.2
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 87, 92)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)
            scene.rootNode.camera = cameraNode

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = NSColor(red: 0.43, green: 0.59, blue: 0.82, alpha: 1)
            ambient.intensity = 550
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)
            for (x,z,color) in [(-22.0,-13.0,NSColor.cyan),
                                (22.0,14.0,NSColor.systemOrange)] {
                let light = SCNLight()
                light.type = .omni
                light.color = color
                light.intensity = 760
                light.attenuationStartDistance = 8
                light.attenuationEndDistance = 105
                let lamp = SCNNode()
                lamp.light = light
                lamp.position = SCNVector3(Float(x), 24, Float(z))
                scene.rootNode.addChildNode(lamp)
            }
            let sun = SCNLight()
            sun.type = .directional
            sun.color = NSColor(white: 0.72, alpha: 1)
            sun.intensity = 900
            sun.castsShadow = true
            sun.shadowMode = .deferred
            sun.shadowSampleCount = 4
            let key = SCNNode()
            key.light = sun
            key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi/5, 0)
            scene.rootNode.addChildNode(key)

            // The player is a fully 3D hovering field architect, not a 2D token.
            let hull = SCNPyramid(width: 2.2, height: 1.35, length: 2.6)
            hull.materials = [steel]
            let body = SCNNode(geometry: hull)
            body.eulerAngles.x = Float.pi
            player.addChildNode(body)
            let ring = torus(1.20, 0.095, cyan)
            ring.position.y = 0.15
            player.addChildNode(ring)
            let cockpit = orb(0.46, white)
            cockpit.position.y = 0.64
            player.addChildNode(cockpit)
            for wingX in [-1.0, 1.0] {
                let thruster = cylinder(0.23, 0.36, cyan)
                thruster.position = SCNVector3(Float(wingX), -0.38, 0.17)
                player.addChildNode(thruster)
            }
            for (index, point) in DivideReactorRelays.positions.enumerated() {
                let relay = SCNNode()
                relay.name = "relay_\(index)"
                relay.position = Self.location(Double(point.x), Double(point.y))
                let bed = cylinder(2.20, 0.38, steel)
                bed.position.y = -0.03
                relay.addChildNode(bed)
                let tower = cylinder(1.0, 2.8, black)
                tower.position.y = 1.40
                relay.addChildNode(tower)
                let crown = torus(1.12, 0.20, amber)
                crown.position.y = 2.94
                crown.name = "crown"
                relay.addChildNode(crown)
                let nucleus = orb(0.69, amber)
                nucleus.position.y = 2.48
                nucleus.name = "nucleus"
                relay.addChildNode(nucleus)
                relayRoot.addChildNode(relay)
            }
        }

        private func updateFloor(_ engine: DivideEngine) {
            var hash: UInt64 = 1469598103934665603
            for c in engine.cells {
                hash = (hash ^ UInt64(c)) &* 1099511628211
            }
            if hash == fingerprint { return }
            fingerprint = hash
            capturedRoot.childNodes.forEach { $0.removeFromParentNode() }

            // Merge contiguous captured cells into long rectangular steel slabs.
            // This keeps the scene small even after 75% containment.
            for y in 1..<(DivideEngine.rows-1) {
                var x = 1
                while x < DivideEngine.columns-1 {
                    let tone = engine.tone(DividePoint(x: x, y: y))
                    if tone == 0 { x += 1; continue }
                    let first = x
                    while x < DivideEngine.columns-1 &&
                            engine.tone(DividePoint(x: x, y: y)) == tone { x += 1 }
                    let length = x - first
                    let slab = box(CGFloat(length), 0.36, 0.95,
                                   tone == 2 ? purple : active, chamfer: 0.045)
                    slab.position = Self.location(Double(first+x-1)/2, Double(y), elevation: 0.11)
                    capturedRoot.addChildNode(slab)
                    let highlight = box(CGFloat(length)*0.90, 0.035, 0.055,
                                        tone == 2 ? amber : cyan)
                    highlight.position = Self.location(Double(first+x-1)/2,
                                                       Double(y)+0.38, elevation: 0.32)
                    capturedRoot.addChildNode(highlight)
                }
            }
            // Industrial power plates are *activated* only when the underlying
            // 4x4 footprint is completely safe; these structures are physical.
            for y in stride(from: 4, to: 40, by: 8) {
                for x in stride(from: 5, to: 64, by: 11) {
                    var safe = true
                    for yy in y..<(y+4) {
                        for xx in x..<(x+4) {
                            if !engine.isSafe(DividePoint(x: xx, y: yy)) { safe = false }
                        }
                    }
                    guard safe else { continue }
                    let p = Self.location(Double(x)+1.5, Double(y)+1.5)
                    let housing = box(3.6, 0.42, 3.3, steel, chamfer: 0.18)
                    housing.position = SCNVector3(p.x, 0.50, p.z)
                    capturedRoot.addChildNode(housing)
                    let vent = box(2.8, 0.05, 1.0, black)
                    vent.position = SCNVector3(p.x, 0.76, p.z)
                    capturedRoot.addChildNode(vent)
                    for offset in [-0.65, 0.0, 0.65] {
                        let bar = box(0.13, 0.10, 0.85, cyan)
                        bar.position = SCNVector3(p.x + Float(offset), 0.80, p.z)
                        capturedRoot.addChildNode(bar)
                    }
                }
            }
        }

        private func updateTrail(_ engine: DivideEngine) {
            if engine.trail == previousTrail { return }
            previousTrail = engine.trail
            traceRoot.childNodes.forEach { $0.removeFromParentNode() }
            guard let start = engine.trailStart else { return }
            var points = [start]
            points.append(contentsOf: engine.trail)
            for index in 1..<points.count {
                let a = points[index-1], b = points[index]
                let horizontal = a.y == b.y
                let beam = box(horizontal ? CGFloat(abs(a.x-b.x))+0.34 : 0.34,
                               0.19, horizontal ? 0.34 : CGFloat(abs(a.y-b.y))+0.34,
                               engine.drawMode == .slow ? amber : cyan)
                beam.position = Self.location(Double(a.x+b.x)/2, Double(a.y+b.y)/2,
                                              elevation: 0.64)
                traceRoot.addChildNode(beam)
            }
        }

        private func makeHostile() -> SCNNode {
            let node = SCNNode()
            let body = orb(0.93, steel)
            node.addChildNode(body)
            let ring = torus(1.14, 0.13, amber)
            ring.eulerAngles.x = Float.pi * 0.16
            node.addChildNode(ring)
            let nucleus = orb(0.37, amber)
            nucleus.position.y = 0.35
            node.addChildNode(nucleus)
            for n in 0..<4 {
                let blade = box(0.25, 0.18, 1.05, amber, chamfer: 0.07)
                let angle = Float(n) * Float.pi/2
                blade.position = SCNVector3(sin(angle)*1.06, 0, cos(angle)*1.06)
                blade.eulerAngles.y = angle
                node.addChildNode(blade)
            }
            return node
        }

        private func updateActors(_ engine: DivideEngine, empRemaining: Double) {
            player.position = Self.location(Double(engine.player.x), Double(engine.player.y),
                                            elevation: 1.45)
            player.opacity = engine.invulnerable ? 0.68 : 1.0
            while enemies.count < engine.enemies.count {
                let node = makeHostile()
                enemyRoot.addChildNode(node)
                enemies.append(node)
            }
            while enemies.count > engine.enemies.count {
                enemies.removeLast().removeFromParentNode()
            }
            for (i, enemy) in engine.enemies.enumerated() {
                let node = enemies[i]
                node.position = Self.location(enemy.position.x, enemy.position.y,
                                              elevation: 1.48)
                node.eulerAngles.y = Float(enemy.spin)
                node.opacity = empRemaining > 0 ? 0.48 : 1.0
            }
            while sentries.count < engine.sparks.count {
                let node = SCNNode()
                node.addChildNode(orb(0.53, amber))
                let beacon = torus(0.72, 0.10, white)
                node.addChildNode(beacon)
                enemyRoot.addChildNode(node)
                sentries.append(node)
            }
            while sentries.count > engine.sparks.count {
                sentries.removeLast().removeFromParentNode()
            }
            for (i,spark) in engine.sparks.enumerated() {
                let p = engine.sparkPosition(spark)
                sentries[i].position = Self.location(Double(p.x), Double(p.y), elevation: 1.1)
            }
        }

        private func updateRelays(_ powered: Set<Int>) {
            guard powered != previousRelaySet else { return }
            let newlyPowered = powered.subtracting(previousRelaySet)
            previousRelaySet = powered
            for (index, relay) in relayRoot.childNodes.enumerated() {
                let on = powered.contains(index)
                if let crown = relay.childNode(withName: "crown", recursively: false) {
                    crown.geometry?.materials = [on ? cyan : amber]
                }
                if let orb = relay.childNode(withName: "nucleus", recursively: false) {
                    orb.geometry?.materials = [on ? white : amber]
                }
                if newlyPowered.contains(index) {
                    let burst = torus(1.2, 0.18, white)
                    burst.position.y = 2.75
                    relay.addChildNode(burst)
                    burst.runAction(.sequence([
                        .group([.scale(to: 5.4, duration: 0.8), .fadeOut(duration: 0.8)]),
                        .removeFromParentNode()
                    ]))
                }
            }
        }

        private func updateCapture(_ capture: DivideCaptureFX?) {
            guard let capture, capture.began != lastCaptureTime else { return }
            lastCaptureTime = capture.began
            waveRoot.childNodes.forEach { $0.removeFromParentNode() }
            let center = Self.location(Double(capture.origin.x), Double(capture.origin.y),
                                       elevation: 0.69)
            let wave = torus(1.1, 0.19, white)
            wave.position = center
            waveRoot.addChildNode(wave)
            wave.runAction(.sequence([
                .group([.scale(to: 31, duration: 0.90), .fadeOut(duration: 0.90)]),
                .removeFromParentNode()
            ]))
            // The actual new territory is always represented by solid new slabs.
        }

        func update(engine: DivideEngine, capture: DivideCaptureFX?,
                    poweredRelays: Set<Int>, empRemaining: Double) {
            if !initialized { buildScene() }
            updateFloor(engine)
            updateTrail(engine)
            updateActors(engine, empRemaining: empRemaining)
            updateRelays(poweredRelays)
            updateCapture(capture)
        }
    }
}
