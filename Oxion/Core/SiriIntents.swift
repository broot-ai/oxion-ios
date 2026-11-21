import Foundation
import AppIntents

// Siri и «Быстрые команды». Фразы на русском; Siri также покажет их в Spotlight и приложении «Команды».

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Запустить тренировку"
    static var description = IntentDescription("Открывает текущую или сегодняшнюю тренировку в OXION")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go(WorkoutEngine.shared.isActive ? "workout" : "diary") }
        return .result()
    }
}

struct RestLeftIntent: AppIntent {
    static var title: LocalizedStringResource = "Сколько осталось отдыхать"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text: String = await MainActor.run {
            guard let s = WorkoutEngine.shared.state, s.phase != .finished else { return "Сейчас нет активной тренировки." }
            if s.phase == .resting {
                let left = Int(s.restLeft())
                return left > 0 ? "Отдых: осталось \(left / 60 > 0 ? "\(left / 60) мин \(left % 60) сек" : "\(left) сек")." : "Отдых окончен — пора делать подход."
            }
            if s.phase == .paused { return "Тренировка на паузе." }
            return "Сейчас идёт подход: \(s.currentItem?.name ?? "упражнение")."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct SiriCompleteSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Завершить подход"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text: String = await MainActor.run {
            let e = WorkoutEngine.shared
            guard let s = e.state, s.phase == .exercising || s.phase == .resting else { return "Нет активного подхода." }
            e.completeSet()
            guard let n = e.state else { return "Подход сохранён." }
            if n.phase == .finished { return "Тренировка завершена. Отличная работа!" }
            return "Подход сохранён. Отдых \(n.currentItem?.restSec ?? 0) секунд."
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct NextExerciseIntent: AppIntent {
    static var title: LocalizedStringResource = "Следующее упражнение"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text: String = await MainActor.run {
            let e = WorkoutEngine.shared
            guard let s = e.state, s.phase != .finished else { return "Сейчас нет активной тренировки." }
            if s.phase == .resting { e.nextSet() }
            let cur = e.state?.currentItem
            return "Сейчас: \(cur?.name ?? "упражнение"), подход \(min((cur?.doneSets ?? 0) + 1, cur?.sets ?? 1)) из \(cur?.sets ?? 0)." +
                (e.state?.nextItem.map { " Потом — \($0.name)." } ?? "")
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct WeekWorkoutsIntent: AppIntent {
    static var title: LocalizedStringResource = "Тренировки за неделю"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let f = RU.dayFormatter
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let ws = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? now
        guard let st: Stats = try? await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": f.string(from: now)]) else {
            return .result(dialog: "Не получилось связаться с OXION. Проверьте интернет.")
        }
        let w = st.workouts ?? 0, g = st.weekGoal ?? 3
        let text = "На этой неделе \(w) \(RU.plural(w, "тренировка", "тренировки", "тренировок")) из \(g). " +
            (w >= g ? "Цель выполнена!" : "Осталось \(g - w).") + " Подходов: \(st.sets ?? 0), калорий: \(st.calories ?? 0)."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct ShowStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Показать мою статистику"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go("diary") }
        return .result()
    }
}

struct OpenFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Избранные тренеры"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go("favorites") }
        return .result()
    }
}

struct OxionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(),
                    phrases: ["Запусти тренировку в \(.applicationName)", "Начни тренировку \(.applicationName)", "\(.applicationName) старт"],
                    shortTitle: "Начать тренировку", systemImageName: "figure.strengthtraining.traditional")
        AppShortcut(intent: RestLeftIntent(),
                    phrases: ["Сколько осталось отдыхать в \(.applicationName)", "\(.applicationName) отдых"],
                    shortTitle: "Сколько отдыхать", systemImageName: "timer")
        AppShortcut(intent: SiriCompleteSetIntent(),
                    phrases: ["Заверши подход в \(.applicationName)", "\(.applicationName) подход готов"],
                    shortTitle: "Завершить подход", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: NextExerciseIntent(),
                    phrases: ["Следующее упражнение в \(.applicationName)", "\(.applicationName) дальше"],
                    shortTitle: "Следующее упражнение", systemImageName: "forward.fill")
        AppShortcut(intent: ShowStatsIntent(),
                    phrases: ["Покажи мою статистику в \(.applicationName)", "Открой статистику \(.applicationName)"],
                    shortTitle: "Статистика", systemImageName: "chart.bar.fill")
        AppShortcut(intent: WeekWorkoutsIntent(),
                    phrases: ["Сколько тренировок я сделал за неделю в \(.applicationName)", "\(.applicationName) моя неделя"],
                    shortTitle: "Моя неделя", systemImageName: "calendar")
        AppShortcut(intent: OpenFavoritesIntent(),
                    phrases: ["Открой избранных тренеров в \(.applicationName)", "\(.applicationName) избранные"],
                    shortTitle: "Избранные тренеры", systemImageName: "heart.fill")
        AppShortcut(intent: OpenRepCounterIntent(),
                    phrases: ["Считай повторы в \(.applicationName)", "\(.applicationName) камера"],
                    shortTitle: "Счёт повторов", systemImageName: "camera.viewfinder")
        AppShortcut(intent: StartRunIntent(),
                    phrases: ["Начни пробежку в \(.applicationName)", "\(.applicationName) пробежка"],
                    shortTitle: "Пробежка", systemImageName: "figure.run")
    }
}
