import Foundation

// Original grid territory game engine. No UI or macOS dependencies: the same
// simulation will power both the classic and future graphical editions.
struct DividePoint: Hashable, Codable {
    var x: Int
    var y: Int
    func offset(_ direction: DivideDirection) -> DividePoint {
        DividePoint(x: x + direction.dx, y: y + direction.dy)
    }
}

struct DivideVector: Codable {
    var x: Double
    var y: Double
}

enum DivideDirection: String, CaseIterable, Codable {
    case up, down, left, right
    var dx: Int {
        switch self { case .left: return -1; case .right: return 1; default: return 0 }
    }
    var dy: Int {
        switch self { case .up: return -1; case .down: return 1; default: return 0 }
    }
}

enum DivideDrawMode: String, Codable {
    case fast, slow
    var cellTone: UInt8 { self == .slow ? 2 : 1 }
    var pointsPerPercent: Double { self == .slow ? 250 : 125 }
    var moveInterval: Double { self == .slow ? 0.137 : 0.071 }
}

enum DividePhase: String, Codable {
    case ready, playing, paused, levelClear, gameOver
}

enum DivideDifficulty: String, CaseIterable, Codable {
    case cadet = "Cadet", veteran = "Veteran", ace = "Ace"
    var speed: Double {
        switch self { case .cadet: return 0.75; case .veteran: return 1.0; case .ace: return 1.32 }
    }
    var initialLives: Int { self == .cadet ? 5 : 3 }
}

struct DivideEnemy: Codable {
    var position: DivideVector
    var velocity: DivideVector
    var spin: Double
}

struct DivideSpark: Codable {
    // Along the original outside border: an active hazard even while tracing a safe line.
    var progress: Double
    var speed: Double
}

/// Tunable arcade rules. Defaults retain the game's classic 75% territory objective.
struct DivideRules: Codable, Equatable {
    var extraLives = 0
    var enemySpeed = 2.5
    var extraEnemies = 0
    var sparkSpeed = 1.0
    var targetPercent = 75.0
    var drawSpeed = 1.0
    var fuseDelay = 1.15

    func validated() -> DivideRules {
        var copy = self
        copy.extraLives = max(-2, min(6, extraLives))
        copy.enemySpeed = enemySpeed.isFinite ? max(0.5, min(4.0, enemySpeed)) : 2.5
        copy.extraEnemies = max(0, min(3, extraEnemies))
        copy.sparkSpeed = sparkSpeed.isFinite ? max(0.5, min(2.5, sparkSpeed)) : 1
        copy.targetPercent = targetPercent.isFinite ? max(50, min(95, targetPercent)) : 75
        copy.drawSpeed = drawSpeed.isFinite ? max(0.6, min(1.7, drawSpeed)) : 1
        copy.fuseDelay = fuseDelay.isFinite ? max(0.4, min(3.5, fuseDelay)) : 1.15
        return copy
    }

    var isDefault: Bool { self == DivideRules() }
}

/// Fixed power-relay objectives shared with the modern scene and rules.
/// The relays occupy the simulation plane but do not block movement.
enum DivideReactorRelays {
    static let positions: [DividePoint] = [
        DividePoint(x: 14, y: 10), DividePoint(x: 53, y: 10),
        DividePoint(x: 14, y: 33), DividePoint(x: 53, y: 33)
    ]
}

struct DivideEngine: Codable {
    static let columns = 68
    static let rows = 44
    static let target = 75.0

    private(set) var cells: [UInt8] = Array(repeating: 0, count: columns * rows)
    private(set) var player = DividePoint(x: columns / 2, y: 0)
    var trail: [DividePoint] = []
    private(set) var trailStart: DividePoint?
    var drawMode: DivideDrawMode?
    var enemies: [DivideEnemy] = []
    private(set) var sparks: [DivideSpark] = []
    private(set) var fuseIndex: Int?
    private(set) var phase: DividePhase = .ready
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var level = 1
    private(set) var difficulty: DivideDifficulty = .veteran
    private(set) var rules = DivideRules()
    private(set) var lastGain = 0.0
    private(set) var lastAward = 0

    private var movementClock = 0.0
    private var inactivityClock = 0.0
    private var fuseClock = 0.0
    private var invulnerableTime = 0.0
    private var levelAwarded = false

    init() { resetField() }

    var percentClaimed: Double {
        let claimed = cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } - perimeterLength
        return max(0, Double(claimed) / Double((Self.columns - 2) * (Self.rows - 2)) * 100)
    }
    var isDrawing: Bool { !trail.isEmpty }
    var invulnerable: Bool { invulnerableTime > 0 }
    var fusePoint: DividePoint? {
        guard let index = fuseIndex, trail.indices.contains(index) else { return nil }
        return trail[index]
    }

    private var perimeterLength: Int { 2 * (Self.columns + Self.rows - 2) }
    func isSafe(_ point: DividePoint) -> Bool {
        inBounds(point) && cells[point.y * Self.columns + point.x] != 0
    }
    func tone(_ point: DividePoint) -> UInt8 {
        guard inBounds(point) else { return 0 }
        return cells[point.y * Self.columns + point.x]
    }
    private func inBounds(_ point: DividePoint) -> Bool {
        (0..<Self.columns).contains(point.x) && (0..<Self.rows).contains(point.y)
    }

    mutating func start(_ difficulty: DivideDifficulty, rules: DivideRules = DivideRules()) {
        self.difficulty = difficulty
        self.rules = rules.validated()
        level = 1
        score = 0
        lives = max(1, difficulty.initialLives + self.rules.extraLives)
        resetField()
        phase = .playing
    }

    mutating func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused: phase = .playing
        default: break
        }
    }

    mutating func nextLevel() {
        guard phase == .levelClear else { return }
        level += 1
        resetField()
        phase = .playing
    }

    private mutating func resetField() {
        cells = Array(repeating: 0, count: Self.columns * Self.rows)
        for y in 0..<Self.rows {
            for x in 0..<Self.columns where x == 0 || y == 0 || x == Self.columns - 1 || y == Self.rows - 1 {
                cells[y * Self.columns + x] = 3
            }
        }
        player = DividePoint(x: Self.columns / 2, y: 0)
        trail = []
        trailStart = nil
        drawMode = nil
        fuseIndex = nil
        inactivityClock = 0
        fuseClock = 0
        movementClock = 0
        invulnerableTime = 1.1
        lastGain = 0
        lastAward = 0
        levelAwarded = false
        let enemyCount = min(6, 1 + (level - 1) / 3 + rules.extraEnemies)
        enemies = (0..<enemyCount).map { index in
            let x = Double(Self.columns) * (0.20 + Double(index % 5) * 0.15)
            let y = Double(Self.rows) * (0.30 + Double(index % 3) * 0.18)
            let angle = (0.68 + Double(index) * 1.88)
            // Standard Veteran now starts at 2.5× the previous movement rate.
        let speed = (7.1 + Double(level - 1) * 0.42) * difficulty.speed * rules.enemySpeed
            return DivideEnemy(position: DivideVector(x: x, y: y),
                               velocity: DivideVector(x: cos(angle) * speed, y: sin(angle) * speed),
                               spin: Double(index))
        }
        sparks = [DivideSpark(progress: 0, speed: 5.0 + Double(level) * 0.4),
                  DivideSpark(progress: Double(perimeterLength / 2), speed: -4.2 - Double(level) * 0.32)]
    }

    // Keys are supplied by the UI as a held direction and optional draw modifier.
    // Once an exposed line starts, the marker can turn corners without holding the modifier.
    mutating func tick(_ dt: Double, direction: DivideDirection?,
                       request: DivideDrawMode?, modern: Bool = false,
                       empActive: Bool = false) {
        guard phase == .playing else { return }
        let delta = max(0, min(dt, 1.0 / 20.0))
        invulnerableTime = max(0, invulnerableTime - delta)
        movementClock += delta
        let interval = (drawMode?.moveInterval ?? 0.064) / rules.drawSpeed
        var walked = false
        var steps = 0
        while movementClock >= interval && steps < 3 {
            movementClock -= interval
            steps += 1
            if let direction { walked = move(direction, request: request) || walked }
            if phase != .playing { return }
        }
        if isDrawing {
            inactivityClock = walked ? 0 : inactivityClock + delta
            if inactivityClock > rules.fuseDelay {
                fuseClock += delta
                while fuseClock > 0.095 {
                    fuseClock -= 0.095
                    let next = (fuseIndex ?? -1) + 1
                    fuseIndex = next
                    if next >= trail.count - 1 { loseLife(force: true); return }
                }
            }
        } else {
            inactivityClock = 0
            fuseIndex = nil
            fuseClock = 0
        }
        // Modern-only EMP freezes anomaly movement for a short window when
        // a captured field powers a relay. Classic physics remain unchanged.
        if !modern || !empActive { moveEnemies(delta, hunter: modern) }
        moveSparks(delta)
        detectHits()
    }

    @discardableResult
    private mutating func move(_ direction: DivideDirection, request: DivideDrawMode?) -> Bool {
        let target = player.offset(direction)
        guard inBounds(target) else { return false }
        if trail.isEmpty {
            if isSafe(target) {
                player = target
                return true
            }
            guard let request else { return false }
            drawMode = request
            trailStart = player
            trail = [target]
            player = target
            return true
        }
        if isSafe(target) {
            // The first safe tile crossed closes the circuit and captures isolated territory.
            player = target
            finishTrail()
            return true
        }
        if trail.contains(target) {
            loseLife(force: true) // A live line cannot intersect itself.
            return true
        }
        trail.append(target)
        player = target
        return true
    }

    // Every unclaimed connected component containing an enemy stays open.
    // The rest become captured; this handles bends, multiple regions, and later multi-enemy waves.
    mutating func finishTrail() {
        guard !trail.isEmpty else { return }
        let before = percentClaimed
        let tint = drawMode?.cellTone ?? 1
        for point in trail { cells[point.y * Self.columns + point.x] = tint }
        var visited = Array(repeating: false, count: cells.count)
        for y in 1..<(Self.rows - 1) {
            for x in 1..<(Self.columns - 1) {
                let start = y * Self.columns + x
                guard cells[start] == 0 && !visited[start] else { continue }
                var region = [start]
                visited[start] = true
                var cursor = 0
                while cursor < region.count {
                    let index = region[cursor]
                    cursor += 1
                    let xx = index % Self.columns
                    let yy = index / Self.columns
                    for neighbor in [DividePoint(x: xx - 1, y: yy), DividePoint(x: xx + 1, y: yy),
                                     DividePoint(x: xx, y: yy - 1), DividePoint(x: xx, y: yy + 1)] {
                        guard inBounds(neighbor) else { continue }
                        let ni = neighbor.y * Self.columns + neighbor.x
                        if cells[ni] == 0 && !visited[ni] {
                            visited[ni] = true
                            region.append(ni)
                        }
                    }
                }
                let containsEnemy = enemies.contains { enemy in
                    let p = DividePoint(x: Int(enemy.position.x.rounded()),
                                        y: Int(enemy.position.y.rounded()))
                    return region.contains(p.y * Self.columns + p.x)
                }
                if !containsEnemy { for index in region { cells[index] = tint } }
            }
        }
        trail = []
        trailStart = nil
        drawMode = nil
        fuseIndex = nil
        inactivityClock = 0
        fuseClock = 0
        let gain = max(0, percentClaimed - before)
        lastGain = gain
        lastAward = Int((gain * (tint == 2 ? 250.0 : 125.0)).rounded())
        score += lastAward
        if percentClaimed >= rules.targetPercent && !levelAwarded {
            levelAwarded = true
            let extra = max(0, Int(percentClaimed - rules.targetPercent))
            score += extra * 1000
            phase = .levelClear
        }
    }

    private func canOccupy(_ x: Double, _ y: Double) -> Bool {
        let p = DividePoint(x: Int(x.rounded()), y: Int(y.rounded()))
        return inBounds(p) && !isSafe(p)
    }

    private mutating func moveEnemies(_ dt: Double, hunter: Bool) {
        for i in enemies.indices {
            var enemy = enemies[i]
            // One Modern anomaly actively intercepts exposed traces instead of
            // passively bouncing. It remains subject to the original collision
            // and safe-cell occupancy rules, and does not affect Classic.
            if hunter && i == 0 && !trail.isEmpty {
                let target = trail[trail.count - 1]
                let dx = Double(target.x) - enemy.position.x
                let dy = Double(target.y) - enemy.position.y
                let distance = hypot(dx, dy)
                if distance > 0.25 && distance < 28 {
                    let speed = hypot(enemy.velocity.x, enemy.velocity.y)
                    let desiredX = dx / distance * speed
                    let desiredY = dy / distance * speed
                    let steer = min(1.0, dt * 1.85)
                    let x = enemy.velocity.x * (1 - steer) + desiredX * steer
                    let y = enemy.velocity.y * (1 - steer) + desiredY * steer
                    let length = hypot(x, y)
                    if length > 0.01 {
                        enemy.velocity.x = x / length * speed
                        enemy.velocity.y = y / length * speed
                    }
                }
            }
            let nx = enemy.position.x + enemy.velocity.x * dt
            let ny = enemy.position.y + enemy.velocity.y * dt
            if canOccupy(nx, enemy.position.y) { enemy.position.x = nx }
            else { enemy.velocity.x *= -1 }
            if canOccupy(enemy.position.x, ny) { enemy.position.y = ny }
            else { enemy.velocity.y *= -1 }
            enemy.spin += dt * (2.8 + Double(level) * 0.1)
            enemies[i] = enemy
        }
    }

    func sparkPosition(_ spark: DivideSpark) -> DividePoint {
        let width = Self.columns - 1
        let height = Self.rows - 1
        let distance = ((Int(spark.progress.rounded()) % perimeterLength) + perimeterLength) % perimeterLength
        if distance < width { return DividePoint(x: distance, y: 0) }
        if distance < width + height { return DividePoint(x: width, y: distance - width) }
        if distance < width * 2 + height { return DividePoint(x: width * 2 + height - distance, y: height) }
        return DividePoint(x: 0, y: perimeterLength - distance)
    }

    private mutating func moveSparks(_ dt: Double) {
        for i in sparks.indices { sparks[i].progress += sparks[i].speed * dt * difficulty.speed * rules.sparkSpeed }
    }

    private mutating func detectHits() {
        guard !invulnerable else { return }
        if trail.isEmpty {
            if sparks.contains(where: { spark in
                let point = sparkPosition(spark)
                return abs(point.x - player.x) <= 1 && abs(point.y - player.y) <= 1
            }) { loseLife() }
            return
        }
        for enemy in enemies {
            for cell in trail {
                let dx = enemy.position.x - Double(cell.x)
                let dy = enemy.position.y - Double(cell.y)
                if dx * dx + dy * dy <= 2.1 { loseLife(); return }
            }
        }
    }

    private mutating func loseLife(force: Bool = false) {
        guard force || !invulnerable else { return }
        lives -= 1
        trail = []
        trailStart = nil
        drawMode = nil
        fuseIndex = nil
        inactivityClock = 0
        fuseClock = 0
        player = DividePoint(x: Self.columns / 2, y: 0)
        invulnerableTime = 1.7
        if lives <= 0 { phase = .gameOver }
    }
    /// Only accept geometrically valid persisted snapshots; saved-game data is untrusted.
    var validSnapshot: Bool {
        guard cells.count == Self.columns * Self.rows,
              (1...9999).contains(level), (0...99).contains(lives),
              score >= 0, score < 1_000_000_000,
              inBounds(player),
              trail.count <= cells.count,
              trail.allSatisfy({ inBounds($0) }),
              trailStart.map({ inBounds($0) }) ?? true,
              enemies.count <= 20,
              enemies.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite &&
                                  $0.velocity.x.isFinite && $0.velocity.y.isFinite &&
                                  $0.spin.isFinite }),
              sparks.count <= 20,
              sparks.allSatisfy({ $0.progress.isFinite && $0.speed.isFinite }),
              movementClock.isFinite, inactivityClock.isFinite,
              fuseClock.isFinite, invulnerableTime.isFinite else { return false }
        return true
    }
}
