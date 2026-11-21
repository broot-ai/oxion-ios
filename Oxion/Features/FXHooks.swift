import Foundation

/// Когда показывать праздничные эффекты (один раз на событие)
@MainActor
enum Celebrate {
    private static func once(_ key: String) -> Bool {
        let d = UserDefaults.standard
        var seen = Set(d.stringArray(forKey: "fx_seen") ?? [])
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        d.set(Array(seen.suffix(300)), forKey: "fx_seen")
        return true
    }

    /// Цель недели выполнена
    static func weekGoal(done: Int, goal: Int) {
        guard done >= goal, goal > 0 else { return }
        let w = Calendar(identifier: .iso8601).dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        if once("week-\(w.yearForWeekOfYear ?? 0)-\(w.weekOfYear ?? 0)") { FX.play(.lightWaves) }
    }

    /// Личная цель (от тренера или своя) выполнена
    static func goal(id: Int) {
        if once("goal-\(id)") { FX.play(.lightWaves) }
    }

    /// Достижение: 1, 10, 50, 100… тренировок
    static func achievement(_ key: String) {
        if once("ach-" + key) { FX.play(.sparks) }
    }
}
