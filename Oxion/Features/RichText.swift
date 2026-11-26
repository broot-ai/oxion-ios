import SwiftUI

// MARK: - Форматирование текста публикаций (как в Telegram)
// Разметка хранится прямо в тексте:
//   **жирный**   __курсив__   ~~зачёркнутый~~   `моноширинный`   ||спойлер||
// Спойлер скрыт серой плашкой, пока его не нажмут.

enum RichText {
    struct Spoiler { let id: Int; let range: Range<Int> }   // в символах итоговой строки

    private static let re = try? NSRegularExpression(
        pattern: #"\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|`([^`\n]+?)`|\|\|(.+?)\|\|"#,
        options: [.dotMatchesLineSeparators])

    /// Есть ли в тексте разметка (чтобы не тратить время на обычный текст)
    static func hasMarkup(_ s: String) -> Bool {
        s.contains("**") || s.contains("__") || s.contains("~~") || s.contains("`") || s.contains("||")
    }

    /// Текст без служебных символов — для превью, уведомлений и копирования
    static func plain(_ s: String) -> String {
        guard hasMarkup(s) else { return s }
        var sp: [Spoiler] = []
        var n = 0
        var chars = Array(String(build(s, spoilers: &sp, counter: &n).characters))
        // спойлер в превью не раскрываем
        for x in sp { for i in x.range where i < chars.count && !chars[i].isWhitespace { chars[i] = "•" } }
        return String(chars)
    }

    /// Разбор разметки: строка с атрибутами + места спойлеров
    static func parse(_ s: String) -> (AttributedString, [Spoiler]) {
        var sp: [Spoiler] = []
        var n = 0
        let a = build(s, spoilers: &sp, counter: &n)
        return (a, sp)
    }

    private static func build(_ s: String, spoilers: inout [Spoiler], counter: inout Int, base: Int = 0) -> AttributedString {
        guard let re, hasMarkup(s) else { return AttributedString(s) }
        let ns = s as NSString
        var out = AttributedString()
        var len = 0                       // длина out в символах
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                let chunk = ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out += AttributedString(chunk)
                len += chunk.count
            }
            var g = 1
            while g <= 5 && m.range(at: g).location == NSNotFound { g += 1 }
            let inner = ns.substring(with: m.range(at: g))
            var piece: AttributedString
            if g == 4 {
                piece = AttributedString(inner)
            } else {
                piece = build(inner, spoilers: &spoilers, counter: &counter, base: base + len)
            }
            let start = base + len
            let cnt = piece.characters.count
            switch g {
            case 1: piece.inlinePresentationIntent = (piece.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            case 2: piece.inlinePresentationIntent = (piece.inlinePresentationIntent ?? []).union(.emphasized)
            case 3: piece.strikethroughStyle = .single
            case 4:
                piece.inlinePresentationIntent = .code
                piece.backgroundColor = Color.primary.opacity(0.08)
            default:
                spoilers.append(Spoiler(id: counter, range: start..<(start + cnt)))
                counter += 1
            }
            out += piece
            len += cnt
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            out += AttributedString(ns.substring(from: last))
        }
        return out
    }

    /// Готовая строка для показа: разметка + ссылки и @упоминания + скрытые спойлеры
    static func render(_ s: String, linkColor: Color?, revealed: Set<Int>) -> (AttributedString, hasSpoilers: Bool) {
        var (a, sp) = parse(s)
        linkify(&a, color: linkColor)
        for x in sp where !revealed.contains(x.id) {
            let lo = a.characters.index(a.startIndex, offsetBy: x.range.lowerBound)
            let hi = a.characters.index(a.startIndex, offsetBy: x.range.upperBound)
            a[lo..<hi].foregroundColor = .clear
            a[lo..<hi].backgroundColor = Color.gray.opacity(0.45)
            a[lo..<hi].strikethroughStyle = nil
            a[lo..<hi].link = URL(string: "oxspoiler://\(x.id)")
        }
        return (a, !sp.isEmpty)
    }

    /// Ссылки и @упоминания поверх уже размеченного текста
    static func linkify(_ a: inout AttributedString, color: Color?) {
        let s = String(a.characters)
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in det.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
                guard let u = m.url, let r = Range(m.range, in: s) else { continue }
                let lo = a.characters.index(a.startIndex, offsetBy: s.distance(from: s.startIndex, to: r.lowerBound))
                let hi = a.characters.index(lo, offsetBy: s.distance(from: r.lowerBound, to: r.upperBound))
                a[lo..<hi].link = u
                if let color { a[lo..<hi].foregroundColor = color }
            }
        }
        Linkify.addMentions(&a, color: color)
    }

    // MARK: правка в поле ввода

    /// Обернуть выделение маркером. Без выделения — вставить пару и встать между ними.
    /// Если выделение уже обёрнуто этим маркером — снять его.
    static func wrap(_ text: inout String, _ sel: inout TextSelection?, _ mk: String) {
        var range = text.endIndex..<text.endIndex
        if let s = sel, case .selection(let r) = s.indices,
           r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex { range = r }
        let lo = text.distance(from: text.startIndex, to: range.lowerBound)
        let inner = String(text[range])
        let n = inner.count
        let k = mk.count
        // снять: маркеры стоят вокруг выделения
        if lo >= k, text.distance(from: range.upperBound, to: text.endIndex) >= k,
           String(text[text.index(range.lowerBound, offsetBy: -k)..<range.lowerBound]) == mk,
           String(text[range.upperBound..<text.index(range.upperBound, offsetBy: k)]) == mk {
            let full = text.index(range.lowerBound, offsetBy: -k)..<text.index(range.upperBound, offsetBy: k)
            text.replaceSubrange(full, with: inner)
            let a = text.index(text.startIndex, offsetBy: lo - k)
            sel = TextSelection(range: a..<text.index(a, offsetBy: n))
            return
        }
        text.replaceSubrange(range, with: mk + inner + mk)
        let a = text.index(text.startIndex, offsetBy: lo + k)
        sel = TextSelection(range: a..<text.index(a, offsetBy: n))
    }

    /// Незаконченное «@имя» прямо перед курсором
    static func mentionToken(_ text: String, _ sel: TextSelection?) -> (range: Range<String.Index>, query: String)? {
        var cur = text.endIndex
        if let s = sel, case .selection(let r) = s.indices {
            guard r.isEmpty, r.upperBound <= text.endIndex else { return nil }
            cur = r.upperBound
        }
        var i = cur
        while i > text.startIndex {
            let p = text.index(before: i)
            let c = text[p]
            if c == "@" {
                // перед @ — начало текста или пробел (не почта)
                if p > text.startIndex {
                    let b = text[text.index(before: p)]
                    guard b.isWhitespace || b == "(" else { return nil }
                }
                let q = String(text[text.index(after: p)..<cur])
                guard q.count <= 32 else { return nil }
                return (p..<cur, q)
            }
            guard c.isASCII && (c.isLetter || c.isNumber || c == "_") else { return nil }
            i = p
        }
        return nil
    }
}

/// Текст публикации с разметкой и спойлерами
struct RichPostText: View {
    let text: String
    var font: Font = .body
    var linkColor: Color? = Color.limeInk
    var onTap: (() -> Void)?

    @State private var revealed: Set<Int> = []
    @Environment(\.openURL) private var outer

    var body: some View {
        let (attr, spoilers) = RichText.render(text, linkColor: linkColor, revealed: revealed)
        let tappable = spoilers || attr.runs.contains(where: { $0.link != nil })
        Text(attr)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture { if !tappable { onTap?() } }
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "oxspoiler", let id = Int(url.host() ?? "") {
                    withAnimation(.easeOut(duration: 0.35)) { _ = revealed.insert(id) }
                    Haptic.tap(.soft)
                    return .handled
                }
                outer(url)
                return .handled
            })
    }
}

// MARK: - Панель форматирования над клавиатурой

struct FormatBar: View {
    var onWrap: (String) -> Void
    var onMention: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            btn("bold", "**")
            btn("italic", "__")
            btn("strikethrough", "~~")
            btn("chevron.left.forwardslash.chevron.right", "`")
            Button { onWrap("||"); Haptic.tap(.soft) } label: {
                Image(systemName: "eye.slash").frame(width: 40, height: 34)
            }
            .accessibilityLabel("Спойлер")
            Spacer(minLength: 0)
            Button { onMention(); Haptic.tap(.soft) } label: {
                Image(systemName: "at").frame(width: 40, height: 34)
            }
            .accessibilityLabel("Упомянуть")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .glassEffect(.regular, in: .capsule)
    }

    private func btn(_ icon: String, _ mk: String) -> some View {
        Button { onWrap(mk); Haptic.tap(.soft) } label: {
            Image(systemName: icon).frame(width: 40, height: 34)
        }
    }
}

// MARK: - Подсказки @упоминаний

struct MentionUser: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let photo: String?
    let username: String
    let following: Bool?
}

private struct MentionResp: Codable { let users: [MentionUser] }

@MainActor @Observable
final class MentionSuggest {
    var users: [MentionUser] = []
    var query: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func update(_ q: String?) {
        guard q != query else { return }
        query = q
        task?.cancel()
        guard let q else { users = []; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(q.isEmpty ? 0 : 180))
            guard !Task.isCancelled else { return }
            if let r: MentionResp = try? await API.call("/feed/mention", query: ["q": q]), !Task.isCancelled, query == q {
                withAnimation(.smooth(duration: 0.2)) { users = r.users }
            }
        }
    }
}

struct MentionList: View {
    let users: [MentionUser]
    var onPick: (MentionUser) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(users) { u in
                Button { onPick(u) } label: {
                    HStack(spacing: 10) {
                        Avatar(url: API.media(u.photo), name: u.name ?? u.username, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.name ?? u.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("@" + u.username).font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                        }
                        Spacer()
                        if u.following == true {
                            Text("Вы подписаны").font(.caption2).foregroundStyle(Color.oxHint)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if u.id != users.last?.id { Divider().padding(.leading, 54) }
            }
        }
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
