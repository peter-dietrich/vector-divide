import AppKit
import SceneKit
import SwiftUI

/// Ephemeral renderer-only effect; never encoded into a saved game.
struct DivideCaptureFX {
    let began: Double
    let newCells: [DividePoint]
    let origin: DividePoint
    let gain: Double
    let award: Int
    let duration: Double = 1.55
}

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
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        context.coordinator.update(engine: engine, capture: capture,
                                   poweredRelays: poweredRelays, empRemaining: empRemaining)
        view.pointOfView = context.coordinator.cameraNode
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.update(engine: engine, capture: capture,
                                   poweredRelays: poweredRelays, empRemaining: empRemaining)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraNode = SCNNode()
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
        private let steel = Coordinator.material(0.085, 0.16, 0.24, metal: 0.78)
        private let active = Coordinator.material(0.13, 0.42, 0.50, metal: 0.73, emission: (0.015, 0.11, 0.15))
        private let purple = Coordinator.material(0.31, 0.19, 0.45, metal: 0.70, emission: (0.06, 0.01, 0.11))
        private let cyan = Coordinator.material(0.21, 0.78, 0.93, metal: 0.25, emission: (0.18, 0.57, 0.72))
        private let amber = Coordinator.material(0.96, 0.49, 0.16, metal: 0.33, emission: (0.51, 0.12, 0.015))
        private let black = Coordinator.material(0.020, 0.038, 0.071, metal: 0.43)
        private let cyanShield = Coordinator.shield(0.09, 0.62, 0.87)
        private let amberShield = Coordinator.shield(0.96, 0.48, 0.15)
        private let white = Coordinator.material(0.69, 0.96, 1.0, metal: 0.13, emission: (0.32, 0.64, 0.72))
        private let decking = Coordinator.material(0.16, 0.29, 0.35, metal: 0.72)
        private let seam = Coordinator.material(0.035, 0.075, 0.115, metal: 0.63)
        private let mutedLight = Coordinator.material(0.15, 0.39, 0.47, metal: 0.48,
                                                       emission: (0.02, 0.09, 0.11))
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

        /// A translucent energy membrane inside a real solid 3D wall frame.
        private static func shield(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = material(r, g, b, metal: 0.12,
                             emission: (r * 0.24, g * 0.37, b * 0.42))
            m.transparency = 0.56
            m.blendMode = .alpha
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

        /// Side-mounted power manifolds make the reactor architecture plausible.
        /// All housings remain beyond the original outer perimeter; relay towers
        /// inside the board retain the gameplay meaning of "power restoration".
        private func buildPerimeterInfrastructure() {
            let shell = Coordinator.material(0.105, 0.18, 0.245, metal: 0.81)
            let recess = Coordinator.material(0.027, 0.058, 0.098, metal: 0.54)
            let trim = Coordinator.material(0.18, 0.30, 0.36, metal: 0.82)
            for side in [-1.0, 1.0] {
                let x = CGFloat(side) * 36.8

                // Low, longitudinal transformer bank bolted to the side rail.
                let foundation = box(3.8, 0.75, 20, shell, chamfer: 0.19)
                foundation.position = SCNVector3(x, -0.10, 0)
                arena.addChildNode(foundation)
                let body = box(3.05, 1.45, 17.7, recess, chamfer: 0.18)
                body.position = SCNVector3(x, 0.85, 0)
                arena.addChildNode(body)

                // Real service modules, mounting collars, and power bus contacts.
                for slot in -2...2 {
                    let z = CGFloat(slot) * 3.35
                    let bay = box(2.65, 0.24, 2.65, trim, chamfer: 0.10)
                    bay.position = SCNVector3(x, 1.65, z)
                    arena.addChildNode(bay)
                    let bus = box(1.8, 0.055, 0.22,
                                  slot.isMultiple(of: 2) ? cyan : amber)
                    bus.position = SCNVector3(x, 1.80, z)
                    bus.castsShadow = false
                    arena.addChildNode(bus)
                    for offset in [-1.08, 1.08] {
                        let fastener = box(0.24, 0.26, 0.26, steel, chamfer: 0.04)
                        fastener.position = SCNVector3(x + CGFloat(offset), 1.78, z)
                        arena.addChildNode(fastener)
                    }
                }

                // Conduit risers visibly connect the modules to the arena.
                for z in [-8.5, 8.5] {
                    let riser = box(0.40, 1.4, 0.50, shell, chamfer: 0.06)
                    riser.position = SCNVector3(x - CGFloat(side) * 1.05, 1.2, CGFloat(z))
                    arena.addChildNode(riser)
                    let status = box(0.31, 0.16, 0.29, cyan)
                    status.position = SCNVector3(x - CGFloat(side) * 1.05, 1.98, CGFloat(z))
                    status.castsShadow = false
                    arena.addChildNode(status)
                }
            }

            // Rear power distribution gantry: functional-looking and well outside
            // the play area, with no enormous obstructions in the foreground.
            let rear = box(19, 1.8, 2.2, shell, chamfer: 0.24)
            rear.position = SCNVector3(0, 0.02, -24.8)
            arena.addChildNode(rear)
            let service = box(17.4, 0.65, 1.45, recess, chamfer: 0.12)
            service.position = SCNVector3(0, 1.10, -24.8)
            arena.addChildNode(service)
            for index in -4...4 {
                let x = CGFloat(index) * 1.82
                let light = box(0.70, 0.13, 0.26,
                                index.isMultiple(of: 3) ? amber : cyan,
                                chamfer: 0.025)
                light.position = SCNVector3(x, 1.52, -24.3)
                light.castsShadow = false
                arena.addChildNode(light)
            }
        }

        private func buildScene() {
            initialized = true
            scene.background.contents = NSColor.black
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
            // Recessed, unpowered servicing tracks are part of the physical deck,
            // not abstract fill or neon stripes.
            for z in [-13.5, 0.0, 13.5] {
                let trench = box(65.3, 0.05, 0.65, seam)
                trench.position = SCNVector3(0, -0.14, CGFloat(z))
                arena.addChildNode(trench)
                for n in -9...9 {
                    let bridge = box(0.85, 0.07, 0.56, steel, chamfer: 0.025)
                    bridge.position = SCNVector3(CGFloat(n) * 3.3, -0.09, CGFloat(z))
                    arena.addChildNode(bridge)
                }
            }
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

            // Integrated side-mounted systems replace the four disconnected
            // corner towers. Everything is outside the playable 68x44 grid.
            buildPerimeterInfrastructure()

            // Physical piping is outside the board so no capture cell is hidden.
            for z in [-25.0, 25.0] {
                for y in [0.3, 1.1] {
                    let pipe = cylinder(0.23, 71.0, steel)
                    pipe.eulerAngles.z = .pi / 2
                    pipe.position = SCNVector3(0, Float(y), Float(z))
                    arena.addChildNode(pipe)
                }
            }

            // 3/4 camera: orthographic prevents perspective mis-click illusion
            // while showing real height and side faces.
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            // Frame the entire reactor at ~90% of the available board width.
            // 3/4 quarter-angle: 37 degrees up, slight yaw exposes the
            // vertical face of walls running BOTH north/south and east/west.
            // Widen the view enough to retain every safe edge and both side bays.
            camera.orthographicScale = 29.5
            camera.zNear = 0.1
            camera.zFar = 400
            camera.wantsHDR = true
            camera.bloomIntensity = 0.24
            camera.bloomThreshold = 1.2
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(29, 80, 106)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = NSColor(red: 0.43, green: 0.59, blue: 0.82, alpha: 1)
            // Ambient fill preserves line readability; stronger key shadows
            // and side lighting reinforce the newly lowered camera.
            ambient.intensity = 390
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
            sun.intensity = 1180
            sun.castsShadow = true
            sun.shadowMode = .deferred
            sun.shadowSampleCount = 8
            sun.shadowRadius = 3
            let key = SCNNode()
            key.light = sun
            key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi/5, 0)
            scene.rootNode.addChildNode(key)

            // The player is a fully 3D hovering field architect, not a 2D token.
            let hull = SCNPyramid(width: 2.2, height: 1.35, length: 2.6)
            hull.materials = [steel]
            let body = SCNNode(geometry: hull)
            body.eulerAngles.x = .pi
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

        /// Build a raised 3D containment wall. The collision and capture rules
        /// remain entirely in the original 2D DivideEngine.
        private func wall(into parent: SCNNode, centerX: Double, centerY: Double,
                          horizontal: Bool, cells: Int, temporary: Bool,
                          slow: Bool = false) {
            guard cells > 0 else { return }
            let length = CGFloat(cells)
            let thickness: CGFloat = temporary ? 0.46 : 0.55
            let height: CGFloat = temporary ? 3.45 : 2.55
            let railMaterial = slow ? amber : cyan
            let glassMaterial = slow ? amberShield : cyanShield
            let width = horizontal ? length : thickness
            let depth = horizontal ? thickness : length
            let root = SCNNode()
            root.position = Self.location(centerX, centerY)
            parent.addChildNode(root)

            let footing = box(width, 0.58, depth, steel, chamfer: 0.09)
            footing.position.y = 0.35
            root.addChildNode(footing)
            let membrane = box(horizontal ? length : 0.17, height - 0.80,
                               horizontal ? 0.17 : length, glassMaterial, chamfer: 0.025)
            membrane.position.y = height * 0.49 + 0.20
            membrane.castsShadow = false
            root.addChildNode(membrane)

            let cap = box(width, 0.22, depth, railMaterial, chamfer: 0.07)
            cap.position.y = height - 0.10
            cap.castsShadow = false
            root.addChildNode(cap)
            let spine = box(horizontal ? length : 0.085, 0.075,
                            horizontal ? 0.085 : length, white)
            spine.position.y = height - 0.27
            spine.castsShadow = false
            root.addChildNode(spine)

            if cells >= 3 {
                let count = max(1, Int(ceil(Double(cells) / 9.0)))
                for i in 0...count {
                    let along = -length * 0.5 + CGFloat(i) * length / CGFloat(count)
                    let post = box(0.47, height, 0.47, steel, chamfer: 0.07)
                    post.position = horizontal
                        ? SCNVector3(along, height * 0.5, 0)
                        : SCNVector3(0, height * 0.5, along)
                    root.addChildNode(post)
                    let lamp = box(0.36, 0.19, 0.36, railMaterial, chamfer: 0.04)
                    lamp.position = SCNVector3(post.position.x, height, post.position.z)
                    lamp.castsShadow = false
                    root.addChildNode(lamp)
                }
            }
        }

        /// Run-length merge each safe/unsafe frontier into long, solid barrier
        /// segments rather than thousands of tiny overlapping cubes.
        private func updateBoundaryWalls(_ engine: DivideEngine) {
            // Horizontal runs between adjacent simulation rows.
            for y in 1..<(DivideEngine.rows - 2) {
                var x = 1
                while x < DivideEngine.columns - 1 {
                    let a = engine.isSafe(DividePoint(x: x, y: y))
                    let b = engine.isSafe(DividePoint(x: x, y: y + 1))
                    guard a != b else { x += 1; continue }
                    let first = x
                    repeat {
                        x += 1
                        if x >= DivideEngine.columns - 1 { break }
                    } while engine.isSafe(DividePoint(x: x, y: y)) !=
                            engine.isSafe(DividePoint(x: x, y: y + 1))
                    wall(into: capturedRoot,
                         centerX: Double(first + x - 1) * 0.5,
                         centerY: Double(y) + 0.5,
                         horizontal: true, cells: x - first, temporary: false)
                }
            }
            // Vertical runs between adjacent simulation columns.
            for x in 1..<(DivideEngine.columns - 2) {
                var y = 1
                while y < DivideEngine.rows - 1 {
                    let a = engine.isSafe(DividePoint(x: x, y: y))
                    let b = engine.isSafe(DividePoint(x: x + 1, y: y))
                    guard a != b else { y += 1; continue }
                    let first = y
                    repeat {
                        y += 1
                        if y >= DivideEngine.rows - 1 { break }
                    } while engine.isSafe(DividePoint(x: x, y: y)) !=
                            engine.isSafe(DividePoint(x: x + 1, y: y))
                    wall(into: capturedRoot,
                         centerX: Double(x) + 0.5,
                         centerY: Double(first + y - 1) * 0.5,
                         horizontal: false, cells: y - first, temporary: false)
                }
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

            // Broad, contiguous rows of solid plating, with dark structural
            // seams rather than a bright line drawn across every grid cell.
            for y in 1..<(DivideEngine.rows - 1) {
                var x = 1
                while x < DivideEngine.columns - 1 {
                    let tone = engine.tone(DividePoint(x: x, y: y))
                    if tone == 0 { x += 1; continue }
                    let first = x
                    while x < DivideEngine.columns - 1 &&
                          engine.tone(DividePoint(x: x, y: y)) == tone { x += 1 }
                    let length = x - first
                    let slab = box(CGFloat(length), 0.34, 1.01,
                                   tone == 2 ? purple : decking, chamfer: 0.035)
                    slab.position = Self.location(Double(first + x - 1) * 0.5, Double(y),
                                                  elevation: 0.10)
                    capturedRoot.addChildNode(slab)
                }
            }

            // Deliberately spacious armored service bays. They appear only once
            // their entire 6x5 footprint is restored and cannot obstruct movement.
            let bayCentersX = [8, 20, 32, 44, 56]
            let bayCentersY = [7, 18, 29, 38]
            for (rowIndex, y) in bayCentersY.enumerated() {
                for (columnIndex, x) in bayCentersX.enumerated() {
                    var complete = true
                    for yy in (y - 2)...(y + 2) {
                        for xx in (x - 3)...(x + 2) {
                            if !engine.isSafe(DividePoint(x: xx, y: yy)) {
                                complete = false
                                break
                            }
                        }
                        if !complete { break }
                    }
                    guard complete else { continue }
                    let center = Self.location(Double(x) - 0.5, Double(y))
                    let frame = box(6.0, 0.22, 5.1, steel, chamfer: 0.18)
                    frame.position = SCNVector3(center.x, 0.36, center.z)
                    capturedRoot.addChildNode(frame)
                    let recess = box(5.1, 0.08, 4.0, seam, chamfer: 0.11)
                    recess.position = SCNVector3(center.x, 0.50, center.z)
                    capturedRoot.addChildNode(recess)
                    let variant = (columnIndex + rowIndex * 3) % 3
                    switch variant {
                    case 0:
                        // Power-routing panel: three thick protected bus bars.
                        for lane in [-1.10, 0.0, 1.10] {
                            let conduit = box(4.3, 0.12, 0.35, mutedLight, chamfer: 0.04)
                            conduit.position = SCNVector3(center.x, 0.59, center.z + CGFloat(lane))
                            capturedRoot.addChildNode(conduit)
                        }
                    case 1:
                        // Equipment hatch: a low, inset access panel, not a tower.
                        let hatch = box(3.3, 0.11, 2.4, decking, chamfer: 0.16)
                        hatch.position = SCNVector3(center.x, 0.60, center.z)
                        capturedRoot.addChildNode(hatch)
                        for side in [-1.0, 1.0] {
                            let grip = box(0.33, 0.06, 1.45, mutedLight)
                            grip.position = SCNVector3(center.x + CGFloat(side)*1.37,
                                                       0.69, center.z)
                            capturedRoot.addChildNode(grip)
                        }
                    default:
                        // Cooling grille with real recessed slots.
                        for lane in -2...2 {
                            let vent = box(4.30, 0.055, 0.36, black, chamfer: 0.025)
                            vent.position = SCNVector3(center.x, 0.57,
                                                       center.z + CGFloat(lane)*0.60)
                            capturedRoot.addChildNode(vent)
                        }
                    }
                    for side in [-1.0, 1.0] {
                        let screw = cylinder(0.14, 0.11, mutedLight)
                        screw.position = SCNVector3(center.x + CGFloat(side)*2.45, 0.64,
                                                   center.z - 1.86)
                        capturedRoot.addChildNode(screw)
                    }
                }
            }
            updateBoundaryWalls(engine)
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
                wall(into: traceRoot,
                     centerX: Double(a.x + b.x) / 2,
                     centerY: Double(a.y + b.y) / 2,
                     horizontal: horizontal,
                     cells: max(abs(a.x - b.x), abs(a.y - b.y)),
                     temporary: true, slow: engine.drawMode == .slow)
            }
        }

        private func makeHostile() -> SCNNode {
            let node = SCNNode()
            let body = orb(0.93, steel)
            node.addChildNode(body)
            let ring = torus(1.14, 0.13, amber)
            ring.eulerAngles.x = .pi * 0.16
            node.addChildNode(ring)
            let nucleus = orb(0.37, amber)
            nucleus.position.y = 0.35
            node.addChildNode(nucleus)
            for n in 0..<4 {
                let blade = box(0.25, 0.18, 1.05, amber, chamfer: 0.07)
                let angle = Float(n) * Float.pi/2
                blade.position = SCNVector3(sin(angle)*1.06, 0, cos(angle)*1.06)
                blade.eulerAngles.y = CGFloat(angle)
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
                node.eulerAngles.y = CGFloat(enemy.spin)
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
