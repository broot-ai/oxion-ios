import Foundation
import AppIntents

// Передача данных в OXION из приложения «Команды», Siri и автоматизаций.
// Все действия работают без открытия приложения (кроме тех, где нужен экран).

enum MuscleGroupEnum: String, AppEnum {
    case chest, back, legs, shoulders, arms, abs, cardio, full
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Группа мышц"
    static var caseDisplayRepresentations: [MuscleGroupEnum: DisplayRepresentation] = [
        .chest: "Грудь", .back: "Спина", .legs: "Ноги", .shoulders: "Плечи", .arms: "Руки", .abs: "Пресс", .cardio: "Кардио", .full: "Всё тело",
    ]
    var keys: [String] {
        switch self {
        case .arms: ["biceps", "triceps"]
        case .full: ["chest", "back", "legs"]
        default: [rawValue]
        }
    }
}

private func needLogin() throws {
    if API.token == nil { throw OxIntentError.notLoggedIn }
}

enum OxIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notLoggedIn, noWorkout, noTrainer, server(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notLoggedIn: "Сначала войдите в OXION"
        case .noWorkout: "Сейчас нет активной тренировки"
        case .noTrainer: "У вас пока нет подключённого тренера"
        case .server(let s): "\(s)"
        }
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Записать вес"
    static var description = IntentDescription("Сохраняет вес тела в дневник OXION на сегодня")
    @Parameter(title: "Вес, кг", inclusiveRange: (20, 400)) var kg: Double
    static var parameterSummary: some ParameterSummary { Summary("Записать вес \(\.$kg) кг") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try needLogin()
        do {
            let _: OK = try await API.call("/weights", method: "POST", body: ["date": RU.dayFormatter.string(from: Date()), "kg": kg])
        } catch { throw OxIntentError.server(error.localizedDescription) }
        return .result(dialog: "Записал: \(kg.formatted(.number.precision(.fractionLength(0...1)))) кг.")
    }
}

struct LogWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Добавить тренировку"
    static var description = IntentDescription("Добавляет в дневник тренировку на сегодня: название, мышцы, калории, заметку")
    @Parameter(title: "Название", default: "Тренировка") var name: String
    @Parameter(title: "Группа мышц", default: .full) var group: MuscleGroupEnum
    @Parameter(title: "Калории") var calories: Int?
    @Parameter(title: "Заметка") var note: String?
    static var parameterSummary: some ParameterSummary {
        Summary("Добавить «\(\.$name)» (\(\.$group))") { \.$calories; \.$note }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try needLogin()
        var body: [String: Any] = ["date": RU.dayFormatter.string(from: Date()), "title": name, "groups": group.keys]
        if let calories { body["calories"] = calories }
        if let note, !note.isEmpty { body["note"] = note }
        do { let _: WorkoutFull = try await API.call("/workouts", method: "POST", body: body) }
        catch { throw OxIntentError.server(error.localizedDescription) }
        return .result(dialog: "Тренировка «\(name)» добавлена в дневник.")
    }
}

struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Записать подход"
    static var description = IntentDescription("Отмечает подход в идущей тренировке: повторы и вес")
    @Parameter(title: "Повторы") var reps: Int?
    @Parameter(title: "Вес, кг") var weight: Double?
    static var parameterSummary: some ParameterSummary { Summary("Подход: \(\.$reps) повт. × \(\.$weight) кг") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let e = WorkoutEngine.shared
        guard e.isActive, let name = e.state?.currentItem?.name else { throw OxIntentError.noWorkout }
        e.completeSet(reps: reps, weight: weight)
        return .result(dialog: "Записал подход: \(name)\(reps.map { ", \($0) повт." } ?? "")\(weight.map { ", \($0.formatted()) кг" } ?? "").")
    }
}

struct MessageTrainerIntent: AppIntent {
    static var title: LocalizedStringResource = "Написать тренеру"
    static var description = IntentDescription("Отправляет сообщение вашему тренеру в чат OXION")
    @Parameter(title: "Текст") var text: String
    static var parameterSummary: some ParameterSummary { Summary("Написать тренеру: \(\.$text)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try needLogin()
        let my: CoachMy = try await API.call("/coach/my")
        guard let t = (my.trainers ?? []).first(where: { $0.status == "active" }) ?? my.trainers?.first else { throw OxIntentError.noTrainer }
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": t.id])
            let _: Message = try await API.call("/chats/\(r.id)/messages", method: "POST", body: ["text": text])
        } catch { throw OxIntentError.server(error.localizedDescription) }
        return .result(dialog: "Отправил \(t.name ?? "тренеру").")
    }
}

struct NextSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Ближайшее занятие с тренером"
    static var description = IntentDescription("Скажет, когда и где ваша следующая тренировка с тренером")

    func perform() async throws -> some IntentResult & ReturnsValue<Date?> & ProvidesDialog {
        try needLogin()
        let my: CoachMy = try await API.call("/coach/my")
        guard let b = (my.bookings ?? []).filter({ $0.date > Date() }).min(by: { $0.date < $1.date }) else {
            return .result(value: nil, dialog: "Записей к тренеру нет.")
        }
        let place = b.place.map { ", \($0)" } ?? ""
        return .result(value: b.date, dialog: "\(BookingFormat.when(b.date)) с \(b.trainer?.name ?? "тренером")\(place).")
    }
}

struct BookTrainerIntent: AppIntent {
    static var title: LocalizedStringResource = "Записаться к тренеру"
    static var description = IntentDescription("Открывает запись к вашему тренеру")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go("book") }
        return .result()
    }
}

struct TodayStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Статистика за сегодня"
    static var description = IntentDescription("Возвращает тренировки, подходы и калории за сегодня — можно передать дальше в «Командах»")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try needLogin()
        let cal = Calendar(identifier: .iso8601)
        let ws = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? Date()
        let f = RU.dayFormatter
        let st: Stats = try await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": f.string(from: Date())])
        let t = st.today
        let s = "Сегодня: тренировок \(t?.workouts ?? 0), подходов \(t?.sets ?? 0), ккал \(t?.calories ?? 0). За неделю: \(st.workouts ?? 0) из \(st.weekGoal ?? 3)."
        return .result(value: s, dialog: "\(s)")
    }
}
