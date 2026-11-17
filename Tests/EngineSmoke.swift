import Foundation

@main
struct EngineSmoke {
    static func main() {
        var game = DivideEngine()
        precondition(game.phase == .ready)
        precondition(game.percentClaimed == 0)
        precondition(game.isSafe(DividePoint(x: 0, y: 0)))
        precondition(!game.isSafe(DividePoint(x: 2, y: 2)))
        game.start(.cadet)
        precondition(game.lives == 5)
        precondition(game.phase == .playing)

        // A vertical split captures the side without an enemy, not the enemy's side.
        game.enemies = [DivideEnemy(position: DivideVector(x: 10, y: 20),
                                    velocity: DivideVector(x: 1, y: 1), spin: 0)]
        game.drawMode = .fast
        game.trail = (1..<(DivideEngine.rows - 1)).map { DividePoint(x: 33, y: $0) }
        game.finishTrail()
        precondition(game.percentClaimed > 45 && game.percentClaimed < 55,
                     "Split should capture roughly half the arena")
        precondition(game.isSafe(DividePoint(x: 55, y: 22)))
        precondition(!game.isSafe(DividePoint(x: 10, y: 20)))
        precondition(game.score > 0)

        // A fresh field with an adversary on both sides retains both open regions.
        game.start(.veteran)
        game.enemies = [
            DivideEnemy(position: DivideVector(x: 10, y: 20), velocity: DivideVector(x: 1, y: 1), spin: 0),
            DivideEnemy(position: DivideVector(x: 55, y: 20), velocity: DivideVector(x: 1, y: 1), spin: 0)
        ]
        game.drawMode = .slow
        game.trail = (1..<(DivideEngine.rows - 1)).map { DividePoint(x: 33, y: $0) }
        game.finishTrail()
        precondition(game.percentClaimed < 2, "With enemies on both sides only the divider fills")
        precondition(game.phase == .playing)

        game.togglePause()
        precondition(game.phase == .paused)
        game.togglePause()
        precondition(game.phase == .playing)
        // Actual input-driven route: draw a line top to bottom and close it.
        var playable = DivideEngine()
        playable.start(.cadet)
        playable.enemies = []
        for _ in 0..<350 {
            playable.tick(1.0 / 60.0, direction: .down, request: .fast)
            if playable.phase == .levelClear { break }
        }
        precondition(playable.phase == .levelClear, "A top-to-bottom draw should complete capture")
        precondition(playable.percentClaimed >= DivideEngine.target)
        let firstScore = playable.score
        playable.nextLevel()
        precondition(playable.level == 2 && playable.score == firstScore)
        precondition(playable.phase == .playing && playable.percentClaimed == 0)

        // Leaving an exposed trace unattended triggers the fuse and loses a life.
        var fuseTest = DivideEngine()
        fuseTest.start(.veteran)
        fuseTest.enemies = []
        for _ in 0..<70 { fuseTest.tick(1.0 / 60.0, direction: .down, request: .fast) }
        precondition(fuseTest.isDrawing)
        let beforeFuse = fuseTest.lives
        for _ in 0..<250 { fuseTest.tick(1.0 / 60.0, direction: nil, request: nil) }
        precondition(fuseTest.lives == beforeFuse - 1, "Fuse should terminate a stalled line")
        // v0.2.0: initial movement is faster, configurable, and Codable for saves.
        let baseline = DivideEngine()
        var normal = baseline
        normal.start(.veteran)
        let defaultVelocity = hypot(normal.enemies[0].velocity.x, normal.enemies[0].velocity.y)
        precondition(abs(defaultVelocity - 7.1) < 0.0001, "Starting enemy speed must be 7.1")
        var tuned = DivideEngine()
        tuned.start(.veteran, rules: DivideRules(extraLives: 2, enemySpeed: 1.5, extraEnemies: 1,
                                                  sparkSpeed: 1.2, targetPercent: 65,
                                                  drawSpeed: 1.1, fuseDelay: 1.8))
        precondition(tuned.lives == 5 && tuned.enemies.count == 2)
        precondition(abs(hypot(tuned.enemies[0].velocity.x, tuned.enemies[0].velocity.y)
                         - defaultVelocity * 1.5) < 0.0001)
        let snapshot = try! JSONEncoder().encode(tuned)
        let recovered = try! JSONDecoder().decode(DivideEngine.self, from: snapshot)
        precondition(recovered.validSnapshot && recovered.lives == tuned.lives)
        precondition(recovered.rules.targetPercent == 65 && recovered.enemies.count == 2)
        precondition(recovered.phase == .playing)
        // Invalid imported preferences should be clamped to safe gameplay bounds.
        let wild = DivideRules(extraLives: 100, enemySpeed: 500,
                               extraEnemies: 99, sparkSpeed: -40,
                               targetPercent: 150, drawSpeed: 0.01, fuseDelay: -3)
        let validated = wild.validated()
        precondition(validated.extraLives == 6 && validated.enemySpeed == 2.5)
        precondition(validated.targetPercent == 95 && validated.fuseDelay == 0.4)
        print("PASS — Vector Divide: capture, enemies, levels, fuse, Codable saves, custom rules, speed")
    }
}
