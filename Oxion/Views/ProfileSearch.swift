import SwiftUI

// Поиск по разделам приложения, как в «Настройках» iPhone: стеклянная строка внизу экрана.
// Находит раздел по любому подходящему слову — названию, синонимам, разговорным словам («видос», «кружки»),
// даже с одной опечаткой.

struct OxSearchItem: Identifiable {
    enum Kind {
        case push(() -> AnyView)
        case run(() -> Void)
    }
    let id: String
    let title: String
    let path: String
    let icon: String
    let tint: Color
    let keywords: [String]
    let kind: Kind

    init(_ title: String, _ path: String, _ icon: String, _ tint: Color, _ keywords: [String], push: @escaping () -> some View) {
        id = path + "/" + title
        self.title = title; self.path = path; self.icon = icon; self.tint = tint; self.keywords = keywords
        kind = .push { AnyView(push()) }
    }
    init(_ title: String, _ path: String, _ icon: String, _ tint: Color, _ keywords: [String], run: @escaping () -> Void) {
        id = path + "/" + title
        self.title = title; self.path = path; self.icon = icon; self.tint = tint; self.keywords = keywords
        kind = .run(run)
    }
}

enum OxSearch {
    static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }
    }

    static func words(_ s: String) -> [String] { norm(s).split(separator: " ").map(String.init) }

    /// Расстояние Левенштейна, но не больше limit+1 (быстро для коротких слов)
    static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            var best = cur[0]
            for j in 1...max(1, b.count) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                best = min(best, cur[j])
            }
            if best > limit { return limit + 1 }
            prev = cur
        }
        return prev[b.count]
    }

    /// Очки совпадения одного слова запроса со словами раздела
    private static func score(_ token: String, title: [String], other: [String]) -> Int {
        var best = 0
        func check(_ w: String, weight: Int) {
            if w == token { best = max(best, 100 * weight) }
            else if w.hasPrefix(token) { best = max(best, 70 * weight) }
            else if token.count >= 3, w.contains(token) { best = max(best, 45 * weight) }
            else if token.count >= 4, w.count >= 4 {
                // корень слова: «видосы» ~ «видео», «тренеровка» ~ «тренировка»
                let stem = String(token.prefix(max(3, token.count - 2)))
                if w.hasPrefix(stem) { best = max(best, 30 * weight) }
                else if distance(token, String(w.prefix(token.count + 1)), limit: 1) <= 1 || distance(token, w, limit: 1) <= 1 {
                    best = max(best, 22 * weight)
                }
            }
        }
        for w in title { check(w, weight: 2) }
        for w in other { check(w, weight: 1) }
        return best
    }

    static func search(_ q: String, in items: [OxSearchItem]) -> [OxSearchItem] {
        let tokens = words(q)
        guard !tokens.isEmpty else { return [] }
        let phrase = norm(q).trimmingCharacters(in: .whitespaces)
        var scored: [(OxSearchItem, Int)] = []
        for it in items {
            let t = words(it.title)
            let o = words(it.path) + it.keywords.flatMap { words($0) }
            var total = 0
            var ok = true
            for tok in tokens {
                let s = score(tok, title: t, other: o)
                if s == 0 { ok = false; break }
                total += s
            }
            // целая фраза из синонимов («видео сообщения», «экранное время»)
            if !ok, phrase.count >= 4, it.keywords.contains(where: { norm($0).contains(phrase) }) { ok = true; total = 80 }
            if ok { scored.append((it, total)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }.map(\.0)
    }
}

/// Строка результата
struct OxSearchRow: View {
    let item: OxSearchItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(item.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).foregroundStyle(.primary)
                Text(item.path).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Стеклянная строка поиска внизу экрана, как в «Настройках» iOS 26
struct OxBottomSearchBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var prompt = "Поиск"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.body.weight(.semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = ""; Haptic.tap() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            if focused.wrappedValue {
                Button("Отмена") { text = ""; focused.wrappedValue = false }
                    .font(.body.weight(.medium))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: text.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: focused.wrappedValue)
    }
}
