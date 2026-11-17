import Foundation

struct DivideRecord: Codable, Identifiable {
    var id = UUID()
    var initials: String
    var score: Int
    var level: Int
    var difficulty: String
    var achieved: Date = Date()
}
struct DividePreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var rules: DivideRules
}
struct DivideSave: Codable, Identifiable {
    var id = UUID()
    var name: String
    var snapshot: DivideEngine
    var saved: Date = Date()
}

/// All data is local. Existing v0.1.0 single-score data is imported once.
enum DivideStore {
    private static let recordsKey = "VectorDivide.Records.v2"
    private static let savesKey = "VectorDivide.Saves.v2"
    private static let presetsKey = "VectorDivide.Presets.v2"

    static func records() -> [DivideRecord] {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let records = try? JSONDecoder().decode([DivideRecord].self, from: data) {
            return records.sorted { $0.score > $1.score }.prefix(10).map { $0 }
        }
        let old = UserDefaults.standard.integer(forKey: "VectorDivide.HighScore.v1")
        guard old > 0 else { return [] }
        let initials = UserDefaults.standard.string(forKey: "VectorDivide.Initials.v1") ?? "---"
        let migrated = [DivideRecord(initials: initials, score: old, level: 1, difficulty: "Legacy")]
        persist(migrated, key: recordsKey)
        return migrated
    }
    @discardableResult static func submit(score: Int, level: Int, difficulty: DivideDifficulty,
                                         initials: String) -> Bool {
        guard score > 0 else { return false }
        var table = records()
        if table.count >= 10 && score <= (table.last?.score ?? 0) { return false }
        let name = String(initials.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(3))
        table.append(DivideRecord(initials: name.isEmpty ? "---" : name,
                                  score: score, level: level, difficulty: difficulty.rawValue))
        table.sort { $0.score > $1.score }
        persist(Array(table.prefix(10)), key: recordsKey)
        return true
    }
    static func qualifies(_ score: Int) -> Bool {
        let table = records()
        return score > 0 && (table.count < 10 || score > (table.last?.score ?? 0))
    }

    static func saves() -> [DivideSave] {
        guard let data = UserDefaults.standard.data(forKey: savesKey),
              let result = try? JSONDecoder().decode([DivideSave].self, from: data) else { return [] }
        return Array(result.filter { $0.snapshot.validSnapshot }.sorted { $0.saved > $1.saved }.prefix(8))
    }
    static func save(_ game: DivideEngine, name: String) -> Bool {
        guard game.validSnapshot, game.phase != .ready, game.phase != .gameOver else { return false }
        var data = saves()
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
        data.insert(DivideSave(name: clean.isEmpty ? "Level \(game.level) / \(game.score) pts" : clean,
                               snapshot: game), at: 0)
        persist(Array(data.prefix(8)), key: savesKey)
        return true
    }
    static func deleteSave(_ id: UUID) {
        persist(saves().filter { $0.id != id }, key: savesKey)
    }
    static func presets() -> [DividePreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let result = try? JSONDecoder().decode([DividePreset].self, from: data) else { return [] }
        return Array(result.prefix(16))
    }
    static func upsert(_ preset: DividePreset) {
        var items = presets().filter { $0.id != preset.id }
        items.insert(DividePreset(id: preset.id, name: String(preset.name.prefix(40)),
                                  rules: preset.rules.validated()), at: 0)
        persist(Array(items.prefix(16)), key: presetsKey)
    }
    static func removePreset(_ id: UUID) {
        persist(presets().filter { $0.id != id }, key: presetsKey)
    }
    private static func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
