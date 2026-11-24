import SwiftUI

// Премиум-эмодзи убраны (тормозили чаты). В старых сообщениях метки [[e:набор/номер]]
// заменяем на обычный значок, чтобы не было «мусора» в тексте.

enum PremiumEmoji {
    private static let re = try! NSRegularExpression(pattern: #"\[\[e:([a-z0-9_]{2,30}/\d{3})\]\]"#)
    static func plain(_ t: String?) -> String {
        guard let t else { return "" }
        guard t.contains("[[e:") else { return t }
        return re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "✨")
    }
}

/// Есть ли Premium у меня — проверяем на сервере при открытии панели
@MainActor @Observable
final class PremiumStatus {
    static let shared = PremiumStatus()
    var active = false
    private var checked: Date?
    func refresh(force: Bool = false) async {
        if !force, let c = checked, Date().timeIntervalSince(c) < 60 { return }
        if let i: PremiumInfo = try? await API.call("/premium") {
            active = i.active
            checked = Date()
        }
    }
}

