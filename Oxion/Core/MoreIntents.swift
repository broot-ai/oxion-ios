import Foundation
import AppIntents

// Ещё действия для приложения «Команды» и автоматизаций.
// Многие возвращают значение — его можно передать дальше: в сообщение, заметку, условие «Если…».

private func needLoginMore() throws {
    if API.token == nil { throw OxIntentError.notLoggedIn }
}

struct AskAICoachIntent: AppIntent {
    static var title: LocalizedStringResource = "Спросить ИИ-тренера"
    static var description = IntentDescription("Задаёт вопрос ИИ-тренеру OXION и возвращает ответ текстом")
    @Parameter(title: "Вопрос") var question: String
    static var parameterSummary: some ParameterSummary { Summary("Спросить ИИ-тренера: \(\.$question)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try needLoginMore()
        do {
            let r: AIReply = try await API.call("/ai/chat", method: "POST",
                                                body: ["text": question, "today": RU.dayFormatter.string(from: Date())])
            return .result(value: r.content, dialog: IntentDialog(stringLiteral: String(r.content.prefix(600))))
        } catch { throw OxIntentError.server(error.localizedDescription) }
    }
}

struct GetStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Узнать серию дней"
    static var description = IntentDescription("Сколько дней подряд вы держите режим тренировок")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        try needLoginMore()
        let a: AchievementsResponse
        do { a = try await API.call("/achievements") } catch { throw OxIntentError.server(error.localizedDescription) }
        let n = a.streak ?? 0
        return .result(value: n, dialog: IntentDialog(stringLiteral: n > 0 ? "Серия: \(n) \(RU.plural(n, "день", "дня", "дней")) подряд 🔥" : "Серии пока нет — самое время начать"))
    }
}

struct WeekReportIntent: AppIntent {
    static var title: LocalizedStringResource = "Отчёт за неделю"
    static var description = IntentDescription("Тренировки, подходы и калории за текущую неделю одной строкой")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try needLoginMore()
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let ws = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? now
        let f = RU.dayFormatter
        let st: Stats
        do { st = try await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": f.string(from: now)]) }
        catch { throw OxIntentError.server(error.localizedDescription) }
        let text = "Неделя: \(st.workouts ?? 0) из \(st.weekGoal ?? 3) тренировок, \(st.sets ?? 0) подходов, \(st.calories ?? 0) ккал."
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct SetWeekGoalIntent: AppIntent {
    static var title: LocalizedStringResource = "Цель тренировок в неделю"
    static var description = IntentDescription("Меняет цель: сколько тренировок в неделю")
    @Parameter(title: "Тренировок в неделю", inclusiveRange: (1, 7)) var count: Int
    static var parameterSummary: some ParameterSummary { Summary("Цель: \(\.$count) тренировок в неделю") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try needLoginMore()
        do { let _: OK = try await API.call("/me", method: "PATCH", body: ["week_goal": count]) }
        catch { throw OxIntentError.server(error.localizedDescription) }
        return .result(dialog: "Готово: \(count) \(RU.plural(count, "тренировка", "тренировки", "тренировок")) в неделю.")
    }
}

struct AddExerciseTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Добавить упражнение в тренировку"
    static var description = IntentDescription("Находит упражнение по названию и добавляет в тренировку на сегодня (создаст её, если нет)")
    @Parameter(title: "Упражнение", description: "Например: жим лёжа, присед") var name: String
    static var parameterSummary: some ParameterSummary { Summary("Добавить \(\.$name) в тренировку") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try needLoginMore()
        let r: ExercisesResponse
        do { r = try await API.call("/exercises") } catch { throw OxIntentError.server(error.localizedDescription) }
        let q = name.lowercased().replacingOccurrences(of: "ё", with: "е")
        let norm: (String) -> String = { $0.lowercased().replacingOccurrences(of: "ё", with: "е") }
        guard let e = r.items.first(where: { norm($0.name) == q }) ?? r.items.first(where: { norm($0.name).contains(q) })
                ?? r.items.first(where: { n in q.split(separator: " ").allSatisfy { norm(n.name).contains($0) } }) else {
            throw OxIntentError.server("Не нашёл упражнение «\(name)»")
        }
        do {
            try await WorkoutIntegrationManager.add(exercises: [e], groups: [e.muscle ?? "legs"], title: "Тренировка")
        } catch { throw OxIntentError.server(error.localizedDescription) }
        return .result(value: e.name, dialog: "Добавил «\(e.name)» в тренировку на сегодня.")
    }
}

struct SearchExercisesIntent: AppIntent {
    static var title: LocalizedStringResource = "Найти упражнения"
    static var description = IntentDescription("Список упражнений из справочника OXION по слову или группе мышц")
    @Parameter(title: "Слово") var query: String?
    @Parameter(title: "Группа мышц") var group: MuscleGroupEnum?

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        try needLoginMore()
        let r: ExercisesResponse
        do { r = try await API.call("/exercises") } catch { throw OxIntentError.server(error.localizedDescription) }
        let q = (query ?? "").lowercased()
        let keys = group?.keys
        let list = r.items.filter { e in
            (q.isEmpty || e.name.lowercased().contains(q)) && (keys == nil || keys!.contains(e.muscle ?? ""))
        }.map(\.name)
        let top = Array(list.prefix(30))
        return .result(value: top, dialog: IntentDialog(stringLiteral: top.isEmpty ? "Ничего не нашлось" : "Нашёл \(list.count): " + top.prefix(5).joined(separator: ", ")))
    }
}

struct OpenBody3DIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть OXION BODY 3D"
    static var description = IntentDescription("3D-фигура для выбора мышц на тренировку, AR и отслеживание движений")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("body")
        return .result()
    }
}

struct OpenRunIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть пробежку с картой"
    static var description = IntentDescription("Экран бега и ходьбы с GPS — маршрут виден на экране блокировки и в Dynamic Island")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("run")
        return .result()
    }
}

struct WorkoutCatalogIntent: AppIntent {
    static var title: LocalizedStringResource = "Каталог упражнений с видео"
    static var description = IntentDescription("Открывает каталог WorkoutDB с видео техники")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("exercises")
        return .result()
    }
}

struct SoundsIntent: AppIntent {
    static var title: LocalizedStringResource = "Звуки OXION"
    static var description = IntentDescription("Включает или выключает системные звуки OXION — удобно в автоматизации «Режим фокусирования»")
    @Parameter(title: "Звуки", default: true) var on: Bool
    static var parameterSummary: some ParameterSummary { Summary("Звуки OXION: \(\.$on)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(on, forKey: "sounds")
        return .result(dialog: on ? "Звуки включены" : "Звуки выключены")
    }
}
