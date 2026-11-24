import SwiftUI

// MARK: - Языки приложения: русский (исходный), английский, французский, немецкий.
// Строки-литералы в Text/Label/Button переводятся SwiftUI сам по Localizable.strings.
// Строки из переменных (заголовки из enum, тексты алертов, данные сервера) переводятся
// перегрузками ниже: если такой ключ есть в словаре — показываем перевод.

enum L10n {
    struct Lang: Identifiable, Hashable {
        let code: String
        let name: String
        let flag: String
        var id: String { code }
    }
    static let all: [Lang] = [
        Lang(code: "ru", name: "Русский", flag: "🇷🇺"),
        Lang(code: "en", name: "English", flag: "🇬🇧"),
        Lang(code: "fr", name: "Français", flag: "🇫🇷"),
        Lang(code: "de", name: "Deutsch", flag: "🇩🇪")
    ]

    /// Текущий язык интерфейса (ru / en / fr / de)
    static let lang: String = {
        let code = Bundle.main.preferredLocalizations.first ?? "ru"
        return all.contains { $0.code == code } ? code : String(code.prefix(2))
    }()
    static var isRussian: Bool { lang == "ru" }
    static let locale = Locale(identifier: lang)

    /// Выбранный вручную язык (nil — как в системе)
    static var chosen: String? {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first.map { String($0.prefix(2)) }
    }

    /// Сменить язык: действует после перезапуска приложения
    static func set(_ code: String?) {
        if let code { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
    }

    private static let cache = NSCache<NSString, NSString>()

    /// Перевод строки по словарю; если перевода нет — исходная строка
    static func tr(_ s: String) -> String {
        if isRussian || s.isEmpty || s.count > 400 { return s }
        let k = s as NSString
        if let v = cache.object(forKey: k) { return v as String }
        let v = Bundle.main.localizedString(forKey: s, value: s, table: nil)
        cache.setObject(v as NSString, forKey: k)
        return v
    }
}

extension String {
    /// Перевод на язык интерфейса
    var loc: String { L10n.tr(self) }
}

// Перегрузки для строк-переменных. @_disfavoredOverload — чтобы литералы по-прежнему шли через LocalizedStringKey.
extension Text {
    @_disfavoredOverload
    init(_ content: String) { self.init(verbatim: L10n.tr(content)) }
}

extension Label where Title == Text, Icon == Image {
    @_disfavoredOverload
    init(_ title: String, systemImage: String) {
        self.init { Text(verbatim: L10n.tr(title)) } icon: { Image(systemName: systemImage) }
    }
}

extension Button where Label == Text {
    @_disfavoredOverload
    init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(verbatim: L10n.tr(title)) }
    }
    @_disfavoredOverload
    init(_ title: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(verbatim: L10n.tr(title)) }
    }
}

extension View {
    @_disfavoredOverload
    func navigationTitle(_ title: String) -> some View {
        navigationTitle(Text(verbatim: L10n.tr(title)))
    }
}

// MARK: - Экран выбора языка

struct LanguageSettingsView: View {
    @State private var picked: String? = L10n.chosen
    @State private var askRestart = false

    var body: some View {
        List {
            Section {
                ForEach(L10n.all) { l in
                    Button {
                        Haptic.tap()
                        picked = l.code
                        L10n.set(l.code)
                        askRestart = l.code != L10n.lang
                    } label: {
                        HStack(spacing: 14) {
                            Text(l.flag).font(.title2)
                            Text(verbatim: l.name).foregroundStyle(.primary)
                            Spacer()
                            if (picked ?? L10n.lang) == l.code {
                                Image(systemName: "checkmark").font(.headline).foregroundStyle(Color.limeInk)
                            }
                        }
                    }
                }
            } footer: {
                Text("Язык меняется после перезапуска приложения. Названия упражнений и тексты от других пользователей остаются на языке оригинала.")
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Язык в настройках iPhone", systemImage: "gear")
                }
            }
        }
        .navigationTitle("Язык")
        .alert("Перезапустить приложение?", isPresented: $askRestart) {
            Button("Перезапустить") { exit(0) }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Чтобы применить язык, приложение закроется — откройте его снова.")
        }
    }
}
