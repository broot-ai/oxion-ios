import Foundation
import UIKit

/// Настройки, которые видны в приложении «Настройки» iPhone → Oxion (Settings.bundle).
enum AppSettings {
    static let defaultServer = "https://fit-app.brootai.workers.dev"

    static func register() {
        UserDefaults.standard.register(defaults: [
            "haptics": true,
            "autoload_photos": true,
            "start_feed": "foryou",
            "shake_card": true,
            "haptic_level": "normal",
            "sounds": true,
            "server_url": defaultServer
        ])
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        UserDefaults.standard.set("\(v) (\(b))", forKey: "app_version")
    }

    static var serverURL: URL {
        var s = (UserDefaults.standard.string(forKey: "server_url") ?? defaultServer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultServer }
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasPrefix("https://") && !s.hasPrefix("http://") { s = "https://" + s }
        return URL(string: s) ?? URL(string: defaultServer)!
    }

    static var haptics: Bool { UserDefaults.standard.bool(forKey: "haptics") }
    static var autoloadPhotos: Bool { UserDefaults.standard.bool(forKey: "autoload_photos") }
    static var shakeCard: Bool { UserDefaults.standard.bool(forKey: "shake_card") }
    static var startFeed: String { UserDefaults.standard.string(forKey: "start_feed") ?? "foryou" }
    static var version: String { UserDefaults.standard.string(forKey: "app_version") ?? "1.0" }
}

enum Haptic {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard AppSettings.haptics, PowerSaver.allowsNow(.haptics) else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() {
        guard AppSettings.haptics, PowerSaver.allowsNow(.haptics) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        guard AppSettings.haptics, PowerSaver.allowsNow(.haptics) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
