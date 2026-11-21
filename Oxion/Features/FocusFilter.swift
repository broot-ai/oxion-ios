import SwiftUI
import AppIntents

// MARK: - Фильтр фокусирования: в режиме «Спорт» (или любом другом) OXION показывает только тренировки
// Настраивается в «Настройки → Фокусирование → (режим) → Фильтры фокусирования → OXION».

struct OxionFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Фокус OXION"
    static var description = IntentDescription("Во время фокусирования OXION скрывает ленту и показывает только чаты с тренерами")

    @Parameter(title: "Скрыть ленту", default: false)
    var hideFeed: Bool

    @Parameter(title: "Только чаты с тренерами", default: false)
    var trainerChatsOnly: Bool

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if hideFeed { parts.append("без ленты") }
        if trainerChatsOnly { parts.append("чаты с тренерами") }
        return DisplayRepresentation(title: "OXION", subtitle: "\(parts.isEmpty ? "без изменений" : parts.joined(separator: ", "))")
    }

    func perform() async throws -> some IntentResult {
        // При выключении фокусирования iOS вызывает фильтр со значениями по умолчанию (false) — всё возвращается
        let d = UserDefaults.standard
        d.set(hideFeed, forKey: "focus_hide_feed")
        d.set(trainerChatsOnly, forKey: "focus_trainer_chats")
        await MainActor.run { NotificationCenter.default.post(name: .oxionFocusChanged, object: nil) }
        return .result()
    }
}

extension Notification.Name {
    static let oxionFocusChanged = Notification.Name("oxionFocusChanged")
}

enum OxFocus {
    static var hideFeed: Bool { UserDefaults.standard.bool(forKey: "focus_hide_feed") }
    static var trainerChatsOnly: Bool { UserDefaults.standard.bool(forKey: "focus_trainer_chats") }
    static var active: Bool { hideFeed || trainerChatsOnly }
}
