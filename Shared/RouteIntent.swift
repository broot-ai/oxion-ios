import Foundation
import AppIntents

/// Куда перейти после запуска из Siri / Пункта управления / виджета (выполняется в процессе приложения)
enum PendingRoute {
    static let key = "oxion_pending_route"
    @MainActor static func go(_ route: String) {
        UserDefaults.standard.set(route, forKey: key)
        NotificationCenter.default.post(name: .oxionRoute, object: route)
    }
    static func take() -> String? {
        let r = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        return r
    }
}

extension Notification.Name {
    static let oxionRoute = Notification.Name("oxionRoute")
}

/// Открыть раздел OXION (для кнопок Пункта управления)
struct OpenOxionIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть OXION"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Раздел")
    var route: String

    init() { route = "home" }
    init(route: String) { self.route = route }

    func perform() async throws -> some IntentResult {
        await MainActor.run { PendingRoute.go(route) }
        return .result()
    }
}
