import Foundation
import AppIntents
import ActivityKit

// Кнопки в Dynamic Island и на экране блокировки. LiveActivityIntent выполняется в процессе
// приложения (iOS запускает его в фоне), поэтому меняет настоящее состояние тренировки.

struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Завершить подход"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.completeSet() }
        return .result()
    }
}

struct NextSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Следующий подход"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.nextSet() }
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пропустить отдых"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.skipRest() }
        return .result()
    }
}

struct PauseWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пауза"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.pause() }
        return .result()
    }
}

struct ResumeWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Продолжить"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.resume() }
        return .result()
    }
}

struct FinishWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Завершить тренировку"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutEngine.shared.finish() }
        return .result()
    }
}
