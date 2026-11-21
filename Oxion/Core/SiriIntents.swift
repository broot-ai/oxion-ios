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

// MARK: - Быстрые действия OS 2.0

struct StartLegWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Запустить тренировку ног"
    static var description = IntentDescription("Создаёт на сегодня тренировку «Ноги» и открывает её")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go("workout/legs") }
        return .result()
    }
}

struct ShowProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Посмотреть прогресс"
    static var description = IntentDescription("Открывает прогресс тела: вес, замеры, фото")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go("progress") }
        return .result()
    }
}

struct StartRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Начать таймер отдыха"
    static var description = IntentDescription("Ставит системный таймер отдыха — он сработает даже в беззвучном режиме")
    @Parameter(title: "Секунд", default: 90, inclusiveRange: (10, 900))
    var seconds: Int

    static var parameterSummary: some ParameterSummary { Summary("Таймер отдыха на \(\.$seconds) секунд") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await OxAlarms.scheduleRest(seconds: seconds, next: "")
        let m = seconds / 60, sec = seconds % 60
        return .result(dialog: "Отдых \(m > 0 ? "\(m) мин " : "")\(sec > 0 ? "\(sec) сек" : ""). Скажу, когда пора.")
    }
}

enum ReminderDays: String, AppEnum {
    case everyday, weekdays, weekends
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Дни"
    static var caseDisplayRepresentations: [ReminderDays: DisplayRepresentation] = [
        .everyday: "каждый день", .weekdays: "по будням", .weekends: "по выходным",
    ]
    var days: Set<Locale.Weekday> {
        switch self {
        case .everyday: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        case .weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        case .weekends: [.saturday, .sunday]
        }
    }
}

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Создать напоминание о тренировке"
    static var description = IntentDescription("Будильник-напоминание OXION в нужное время")
    @Parameter(title: "Время") var time: Date
    @Parameter(title: "Дни", default: .everyday) var days: ReminderDays

    static var parameterSummary: some ParameterSummary { Summary("Напоминать в \(\.$time) \(\.$days)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let ok = await OxAlarms.setReminder(hour: c.hour ?? 9, minute: c.minute ?? 0, days: days.days)
        return .result(dialog: ok ? "Готово: напомню в \(String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0))." : "Не получилось — разрешите OXION будильники в настройках.")
    }
}

/// Не больше 10 фраз-команд на приложение (ограничение iOS). Остальные действия всё равно есть в «Командах».
struct OxionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(),
                    phrases: ["Запусти тренировку в \(.applicationName)", "Начни тренировку \(.applicationName)", "\(.applicationName) старт"],
                    shortTitle: "Начать тренировку", systemImageName: "figure.strengthtraining.traditional")
        AppShortcut(intent: StartLegWorkoutIntent(),
                    phrases: ["Тренировка ног в \(.applicationName)", "Запусти тренировку ног \(.applicationName)", "\(.applicationName) ноги"],
                    shortTitle: "Тренировка ног", systemImageName: "figure.step.training")
        AppShortcut(intent: ShowStatsIntent(),
                    phrases: ["Покажи мою статистику в \(.applicationName)", "Открой статистику \(.applicationName)"],
                    shortTitle: "Статистика", systemImageName: "chart.bar.fill")
        AppShortcut(intent: StartRestTimerIntent(),
                    phrases: ["Таймер отдыха в \(.applicationName)", "Начни отдых \(.applicationName)", "\(.applicationName) отдых"],
                    shortTitle: "Таймер отдыха", systemImageName: "timer")
        AppShortcut(intent: ShowProgressIntent(),
                    phrases: ["Покажи прогресс в \(.applicationName)", "\(.applicationName) прогресс"],
                    shortTitle: "Прогресс", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: CreateReminderIntent(),
                    phrases: ["Напомни о тренировке в \(.applicationName)", "\(.applicationName) напоминание"],
                    shortTitle: "Напоминание", systemImageName: "alarm")
        AppShortcut(intent: SiriCompleteSetIntent(),
                    phrases: ["Заверши подход в \(.applicationName)", "\(.applicationName) подход готов"],
                    shortTitle: "Завершить подход", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: RestLeftIntent(),
                    phrases: ["Сколько осталось отдыхать в \(.applicationName)", "\(.applicationName) сколько отдыхать"],
                    shortTitle: "Сколько отдыхать", systemImageName: "hourglass")
        AppShortcut(intent: StartRunIntent(),
                    phrases: ["Начни пробежку в \(.applicationName)", "\(.applicationName) пробежка"],
                    shortTitle: "Пробежка", systemImageName: "figure.run")
        AppShortcut(intent: OpenRepCounterIntent(),
                    phrases: ["Считай повторы в \(.applicationName)", "\(.applicationName) камера"],
                    shortTitle: "Счёт повторов", systemImageName: "camera.viewfinder")
    }
}
