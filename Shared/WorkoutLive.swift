import Foundation
import ActivityKit

// MARK: - Данные Live Activity (общие для приложения и расширения)

struct OxionWorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// exercising, resting, paused, finished
        var phase: String
        var exercise: String
        var setIndex: Int          // номер текущего подхода (с 1)
        var setsTotal: Int
        var reps: Int
        var weight: Double?
        var unit: String
        var nextExercise: String?
        var exercisesDone: Int
        var exercisesTotal: Int
        var setsDoneAll: Int
        var setsTotalAll: Int
        /// начало тренировки с учётом пауз — таймер считает от этой метки
        var timerStart: Date
        /// конец отдыха (если отдыхаем)
        var restEnd: Date?
        /// при паузе: сколько секунд было на часах и сколько отдыха осталось
        var pausedElapsed: Int?
        var pausedRestLeft: Int?
        /// пульс с датчика по Bluetooth (если подключён)
        var heartRate: Int? = nil

        var progress: Double { setsTotalAll > 0 ? Double(setsDoneAll) / Double(setsTotalAll) : 0 }
        var setsLeft: Int { max(0, setsTotal - setIndex + 1) }
    }

    var title: String
    var workoutId: Int
}

// MARK: - Состояние тренировки

enum WorkoutPhase: String, Codable {
    case notStarted, exercising, resting, paused, finished
}

struct PlanItem: Codable, Hashable, Identifiable {
    var weId: Int
    var exerciseId: Int
    var name: String
    var type: String
    var unit: String
    var muscle: String?
    var sets: Int
    var reps: Int
    var weight: Double?
    var restSec: Int
    var doneSets: Int = 0
    var id: Int { weId }
    var done: Bool { doneSets >= sets }
}

struct PendingSet: Codable, Hashable {
    var id = UUID()
    var weId: Int
    var reps: Int?
    var weight: Double?
    var duration: Int?
    var distance: Double?
}

struct WorkoutState: Codable {
    var workoutId: Int
    var title: String
    var items: [PlanItem]
    var current: Int = 0
    var phase: WorkoutPhase = .notStarted
    var pausedFrom: WorkoutPhase?
    var startedAt: Date = Date()
    var pausedTotal: TimeInterval = 0
    var pausedAt: Date?
    var restEndsAt: Date?
    var restLeftOnPause: TimeInterval?
    var finishedAt: Date?
    var pending: [PendingSet] = []

    var currentItem: PlanItem? { items.indices.contains(current) ? items[current] : nil }
    var nextItem: PlanItem? { items.indices.contains(current + 1) ? items[current + 1] : nil }
    var setsDoneAll: Int { items.reduce(0) { $0 + min($1.doneSets, $1.sets) } }
    var setsTotalAll: Int { items.reduce(0) { $0 + $1.sets } }
    var exercisesDone: Int { items.filter(\.done).count }

    /// время тренировки без пауз — считается по меткам, без секундного цикла
    func elapsed(_ now: Date = Date()) -> TimeInterval {
        let end = finishedAt ?? (phase == .paused ? (pausedAt ?? now) : now)
        return max(0, end.timeIntervalSince(startedAt) - pausedTotal)
    }

    func restLeft(_ now: Date = Date()) -> TimeInterval {
        if phase == .paused { return restLeftOnPause ?? 0 }
        guard phase == .resting, let e = restEndsAt else { return 0 }
        return max(0, e.timeIntervalSince(now))
    }

    func restOver(_ now: Date = Date()) -> Bool { phase == .resting && restLeft(now) <= 0 }

    var liveState: OxionWorkoutAttributes.ContentState {
        let it = currentItem
        return .init(phase: phase.rawValue,
                     exercise: it?.name ?? "Тренировка",
                     setIndex: min((it?.doneSets ?? 0) + 1, it?.sets ?? 1),
                     setsTotal: it?.sets ?? 0,
                     reps: it?.reps ?? 0,
                     weight: it?.weight,
                     unit: it?.unit ?? "кг",
                     nextExercise: nextItem?.name,
                     exercisesDone: exercisesDone,
                     exercisesTotal: items.count,
                     setsDoneAll: setsDoneAll,
                     setsTotalAll: setsTotalAll,
                     timerStart: startedAt.addingTimeInterval(pausedTotal),
                     restEnd: phase == .resting ? restEndsAt : nil,
                     pausedElapsed: phase == .paused ? Int(elapsed()) : nil,
                     pausedRestLeft: phase == .paused && pausedFrom == .resting ? Int(restLeftOnPause ?? 0) : nil)
    }
}
