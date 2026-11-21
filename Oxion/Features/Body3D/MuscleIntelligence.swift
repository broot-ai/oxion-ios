import SwiftUI
import Observation

// MUSCLE INTELLIGENCE — нагрузка по истории тренировок OXION.
// Измерено: записанные подходы и тренировки (с сервера).
// Оценка: «восстановлена / высокая нагрузка» — простое правило по дням и подходам, не медицинский показатель.

struct MuscleLoad: Decodable, Hashable {
    let key: String
    let sets7: Int
    let sets30: Int
    let sessions7: Int
    let sessions30: Int
    let last: String?
    let weeks: [Int]
}

struct MuscleLoadResponse: Decodable { let today: String; let items: [MuscleLoad] }

enum MuscleStatus: String {
    case natural, high, low, recovered
    var title: String {
        switch self {
        case .natural: "Обычная нагрузка"
        case .high: "Высокая недавняя нагрузка"
        case .low: "Мало тренировок"
        case .recovered: "Скорее восстановлена"
        }
    }
    var icon: String {
        switch self {
        case .natural: "circle.dotted"
        case .high: "flame.fill"
        case .low: "moon.zzz.fill"
        case .recovered: "leaf.fill"
        }
    }
    var color: Color {
        switch self {
        case .natural: Color(hex: 0xE8B898)
        case .high: Color(hex: 0xFF9F43)
        case .low: Color(hex: 0x8E9297)
        case .recovered: Color(hex: 0x3DDC84)
        }
    }
    var ui: UIColor {
        switch self {
        case .natural: UIColor(red: 0.91, green: 0.72, blue: 0.60, alpha: 1)
        case .high: UIColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1)
        case .low: UIColor(red: 0.56, green: 0.57, blue: 0.59, alpha: 1)
        case .recovered: UIColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        }
    }
}

@MainActor
@Observable
final class MuscleIntelligenceManager {
    static let shared = MuscleIntelligenceManager()
    private(set) var loads: [String: MuscleLoad] = [:]
    private(set) var loaded = false
    private(set) var errorText: String?
    private var today = Date()

    func refresh() async {
        do {
            let r: MuscleLoadResponse = try await API.call("/me/muscle-load", query: ["today": RU.dayFormatter.string(from: Date())])
            loads = Dictionary(uniqueKeysWithValues: r.items.map { ($0.key, $0) })
            today = RU.dayFormatter.date(from: r.today) ?? Date()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        loaded = true
    }

    func load(for group: String) -> MuscleLoad? { loads[group] }

    func daysSince(_ group: String) -> Int? {
        guard let l = loads[group]?.last, let d = RU.dayFormatter.date(from: l) else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: today).day
    }

    /// Расчётная оценка (правило, а не измерение)
    func status(for group: String) -> MuscleStatus {
        guard let l = loads[group] else { return .natural }
        let days = daysSince(group)
        if let days, days <= 2, l.sets7 >= 8 { return .high }
        if l.sessions30 == 0 || (days ?? 99) > 14 { return .low }
        if let days, days >= 3, days <= 10 { return .recovered }
        return .natural
    }

    /// Доля группы в общем объёме за 30 дней
    var distribution: [(String, Double)] {
        let total = Double(loads.values.reduce(0) { $0 + $1.sets30 })
        guard total > 0 else { return [] }
        return loads.values.filter { $0.key != "cardio" && $0.sets30 > 0 }
            .sorted { $0.sets30 > $1.sets30 }
            .map { ($0.key, Double($0.sets30) / total) }
    }
}

// MARK: - Интеграция с тренировками

@MainActor
enum WorkoutIntegrationManager {
    /// Добавить упражнения в тренировку на сегодня (последнюю за день) или создать новую
    @discardableResult
    static func add(exercises: [Exercise], groups: [String], title: String) async throws -> Int {
        let today = RU.dayFormatter.string(from: Date())
        var wid: Int
        let list: WorkoutsResponse = try await API.call("/workouts", query: ["from": today, "to": today])
        if let w = list.items.last {
            wid = w.id
        } else {
            let w: WorkoutFull = try await API.call("/workouts", method: "POST",
                                                    body: ["date": today, "title": title, "groups": groups])
            wid = w.id
        }
        for e in exercises {
            let _: WorkoutFull = try await API.call("/workouts/\(wid)/exercises", method: "POST", body: ["exercise_id": e.id])
        }
        return wid
    }

    static func exercises(for info: MuscleInfo) async -> [Exercise] {
        guard let r: ExercisesResponse = try? await API.call("/exercises") else { return [] }
        let list = r.items.filter { $0.muscle == info.group }
        func score(_ e: Exercise) -> Int {
            let n = e.name.lowercased()
            return info.keywords.contains { n.contains($0) } ? 0 : 1
        }
        return list.sorted { (score($0), $0.name) < (score($1), $1.name) }
    }
}
