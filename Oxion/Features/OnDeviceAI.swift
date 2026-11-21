import Foundation
import FoundationModels
import Observation

// MARK: - ИИ-тренер на iPhone (Apple Intelligence, iOS 26)
// Модель работает прямо на телефоне: бесплатно, без интернета, вопросы не уходят на сервер.

@MainActor
@Observable
final class OnDeviceCoach {
    static let shared = OnDeviceCoach()

    /// Пользователь выбрал «На iPhone»
    var useLocal: Bool {
        didSet { UserDefaults.standard.set(useLocal, forKey: "ai_local") }
    }
    private var session: LanguageModelSession?

    private init() {
        useLocal = UserDefaults.standard.bool(forKey: "ai_local")
    }

    static let instructions = """
    Ты — фитнес-тренер приложения OXION. Отвечай по-русски, коротко и по делу, дружелюбно.
    Помогаешь с тренировками, техникой упражнений, восстановлением и питанием для здоровых взрослых.
    Не ставь диагнозов и не назначай лекарства; при боли, травме или болезни советуй обратиться к врачу.
    Если просят тренировку — дай список упражнений с подходами и повторениями.
    """

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    var supportsRussian: Bool {
        SystemLanguageModel.default.supportsLocale(Locale(identifier: "ru_RU"))
    }

    /// Почему недоступно — простыми словами
    var reason: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return supportsRussian ? "" : "Модель на iPhone пока не поддерживает русский язык — ответы могут быть на английском."
        case .unavailable(let r):
            switch r {
            case .deviceNotEligible: return "Этот iPhone не поддерживает Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Включите Apple Intelligence: Настройки → Apple Intelligence и Siri."
            case .modelNotReady: return "Модель ещё загружается на iPhone. Подключитесь к Wi‑Fi и попробуйте позже."
            @unknown default: return "Apple Intelligence сейчас недоступен."
            }
        }
    }

    /// Ответ с потоковым выводом: onPartial получает текст по мере генерации
    func ask(_ text: String, onPartial: @escaping (String) -> Void) async throws -> String {
        if session == nil { session = LanguageModelSession(instructions: Self.instructions) }
        guard let session else { return "" }
        var last = ""
        for try await part in session.streamResponse(to: text) {
            last = part.content
            onPartial(last)
        }
        return last
    }

    func reset() { session = nil }
}
