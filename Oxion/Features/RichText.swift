import SwiftUI
import UIKit

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
        let total = a.characters.count
        for x in sp where !revealed.contains(x.id) {
            // защита от выхода за границы (составные символы/эмодзи на стыке разметки)
            let l = min(max(0, x.range.lowerBound), total), u = min(max(l, x.range.upperBound), total)
            guard u > l else { continue }
            let lo = a.characters.index(a.startIndex, offsetBy: l)
            let hi = a.characters.index(a.startIndex, offsetBy: u)
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
    var uiStyle: UIFont.TextStyle = .body
    var linkColor: Color? = Color.limeInk
    var onTap: (() -> Void)?

    @State private var revealed: Set<Int> = []
    @Environment(\.openURL) private var outer

    var body: some View {
        if text.contains("||") && !RichText.parse(text).1.isEmpty {
            // есть спойлер — UIKit-текст с «атомами»
            SpoilerText(text: text, style: uiStyle, linkColor: linkColor ?? Color.limeInk, onTap: onTap)
        } else {
            plain
        }
    }

    @ViewBuilder private var plain: some View {
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

// MARK: - Спойлер «из атомов», как в Telegram
// Скрытый текст закрыт облаком мерцающих частиц (CAEmitterLayer). Нажатие — частицы рассыпаются, текст проявляется.

extension RichText {
    /// Разметка → NSAttributedString для UIKit + диапазоны спойлеров (UTF-16)
    static func ns(_ s: String, style: UIFont.TextStyle, linkColor: UIColor) -> (NSMutableAttributedString, [(Int, NSRange)]) {
        var (a, sp) = parse(s)
        linkify(&a, color: nil)
        let plain = String(a.characters)
        // смещение символа → смещение UTF-16
        var u16: [Int] = [0]
        u16.reserveCapacity(plain.count + 1)
        var acc = 0
        for ch in plain { acc += ch.utf16.count; u16.append(acc) }
        let base = UIFont.preferredFont(forTextStyle: style)
        let out = NSMutableAttributedString(string: plain, attributes: [.font: base, .foregroundColor: UIColor.label])
        for run in a.runs {
            let lo = min(a.characters.distance(from: a.startIndex, to: run.range.lowerBound), u16.count - 1)
            let hi = min(max(lo, a.characters.distance(from: a.startIndex, to: run.range.upperBound)), u16.count - 1)
            let r = NSRange(location: u16[lo], length: u16[hi] - u16[lo])
            guard r.length > 0, NSMaxRange(r) <= out.length else { continue }
            if let i = run.inlinePresentationIntent {
                if i.contains(.code) {
                    out.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.94, weight: .regular), range: r)
                    out.addAttribute(.backgroundColor, value: UIColor.label.withAlphaComponent(0.08), range: r)
                } else {
                    var t: UIFontDescriptor.SymbolicTraits = []
                    if i.contains(.stronglyEmphasized) { t.insert(.traitBold) }
                    if i.contains(.emphasized) { t.insert(.traitItalic) }
                    if !t.isEmpty, let d = base.fontDescriptor.withSymbolicTraits(t) { out.addAttribute(.font, value: UIFont(descriptor: d, size: base.pointSize), range: r) }
                }
            }
            if run.strikethroughStyle != nil { out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            if let l = run.link { out.addAttribute(.link, value: l, range: r) }
        }
        let ranges: [(Int, NSRange)] = sp.compactMap { x in
            let l = min(max(0, x.range.lowerBound), u16.count - 1), u = min(max(l, x.range.upperBound), u16.count - 1)
            let r = NSRange(location: u16[l], length: u16[u] - u16[l])
            return r.length > 0 && NSMaxRange(r) <= out.length ? (x.id, r) : nil
        }
        return (out, ranges)
    }
}

/// Облако частиц для спойлера (общая настройка для ленты и поля ввода)
enum SpoilerDust {
    static let dot: CGImage? = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 4, height: 4))
        }.cgImage
    }()

    static func layer(frame rect: CGRect, color: UIColor) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.frame = rect
        e.emitterPosition = CGPoint(x: rect.width / 2, y: rect.height / 2)
        e.emitterSize = rect.size
        e.emitterShape = .rectangle
        e.emitterMode = .surface
        e.renderMode = .unordered
        e.masksToBounds = true
        let c = CAEmitterCell()
        c.contents = dot
        c.contentsScale = UIScreen.main.scale
        c.color = color.cgColor
        c.birthRate = Float(max(60, rect.width * rect.height / 3.5))
        c.lifetime = 1.2
        c.lifetimeRange = 0.6
        c.velocity = 6
        c.velocityRange = 8
        c.emissionRange = .pi * 2
        c.scale = 1
        c.scaleRange = 0.4
        c.alphaSpeed = -0.5
        c.alphaRange = 0.3
        e.emitterCells = [c]
        e.beginTime = CACurrentMediaTime() - 1.5    // сразу «облако», без пустого старта
        return e
    }
}

final class SpoilerTextView: UITextView, UITextViewDelegate {
    var raw = ""
    var source = NSMutableAttributedString()
    var spoilers: [(Int, NSRange)] = []
    var revealed: Set<Int> = []
    var linkColor: UIColor = .systemBlue
    var onTap: (() -> Void)?
    var onOpen: ((URL) -> Void)?
    private var emitters: [CAEmitterLayer] = []
    private var lastSize: CGSize = .zero

    init() {
        // TextKit 1: нужны прямоугольники строк для частиц
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        super.init(frame: .zero, textContainer: tc)
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        delegate = self
        linkTextAttributes = [:]
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply() {
        let m = NSMutableAttributedString(attributedString: source)
        m.enumerateAttribute(.link, in: NSRange(location: 0, length: m.length)) { v, r, _ in
            if v != nil { m.addAttribute(.foregroundColor, value: linkColor, range: r) }
        }
        for (id, r) in spoilers where !revealed.contains(id) && NSMaxRange(r) <= m.length {
            m.addAttribute(.foregroundColor, value: UIColor.clear, range: r)
            m.removeAttribute(.link, range: r)
            m.removeAttribute(.backgroundColor, range: r)
            m.removeAttribute(.strikethroughStyle, range: r)
        }
        attributedText = m
        setNeedsLayout()
        lastSize = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { lastSize = bounds.size; rebuildParticles() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { lastSize = .zero; setNeedsLayout() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        rebuildParticles()
    }

    private static let dot: CGImage? = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6))
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 6, height: 6))
        }.cgImage
    }()

    private func rects(for r: NSRange) -> [CGRect] {
        guard r.length > 0, NSMaxRange(r) <= textStorage.length else { return [] }
        let g = layoutManager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        var out: [CGRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            out.append(rect.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top).insetBy(dx: -1, dy: 0))
        }
        return out
    }

    func rebuildParticles() {
        emitters.forEach { $0.removeFromSuperlayer() }
        emitters.removeAll()
        guard bounds.width > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let color = UIColor.label.resolvedColor(with: traitCollection)
        for (id, r) in spoilers where !revealed.contains(id) {
            // цвет частиц = цвет текста под спойлером (ссылка — цветом ссылки, как в Threads)
            let isLink = r.location < source.length && source.attribute(.link, at: r.location, effectiveRange: nil) != nil
            let c = isLink ? linkColor.resolvedColor(with: traitCollection) : color
            for rect in rects(for: r) where rect.width > 1 {
                let e = SpoilerDust.layer(frame: rect, color: c)
                e.name = "\(id)"
                layer.addSublayer(e)
                emitters.append(e)
            }
        }
    }

    private func spoilerAt(_ p: CGPoint) -> Int? {
        for e in emitters where e.frame.insetBy(dx: -4, dy: -4).contains(p) { return Int(e.name ?? "") }
        return nil
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        if let id = spoilerAt(p) {
            reveal(id)
            return
        }
        // по ссылке — сработает сама ссылка
        let i = layoutManager.characterIndex(for: CGPoint(x: p.x - textContainerInset.left, y: p.y - textContainerInset.top), in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        if i < attributedText.length, attributedText.attribute(.link, at: i, effectiveRange: nil) != nil { return }
        onTap?()
    }

    func reveal(_ id: Int) {
        guard !revealed.contains(id) else { return }
        revealed.insert(id)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // частицы разлетаются и гаснут, текст проявляется
        for e in emitters where e.name == "\(id)" {
            e.birthRate = 0
            e.emitterCells?.forEach { $0.velocity = 40 }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0; a.duration = 0.45
            e.opacity = 0
            e.add(a, forKey: "fade")
        }
        // текст проявляется плавно, частицы гаснут сами (они уже в слое)
        let fading = emitters.filter { $0.name == "\(id)" }
        emitters.removeAll { $0.name == "\(id)" }
        UIView.transition(with: self, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.apply()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fading.forEach { $0.removeFromSuperlayer() } }
    }

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        if case .link(let url) = textItem.content {
            return UIAction { [weak self] _ in self?.onOpen?(url) }
        }
        return defaultAction
    }
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? { nil }
}

struct SpoilerText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var linkColor: Color = Color.limeInk
    var onTap: (() -> Void)?
    @Environment(\.openURL) private var openURL

    func makeUIView(context: Context) -> SpoilerTextView {
        let v = SpoilerTextView()
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fill(v)
        return v
    }

    func updateUIView(_ v: SpoilerTextView, context: Context) {
        v.onTap = onTap
        v.onOpen = { u in openURL(u) }
        if v.raw != text { fill(v) }
    }

    private func fill(_ v: SpoilerTextView) {
        let (a, sp) = RichText.ns(text, style: style, linkColor: UIColor(linkColor))
        v.raw = text
        v.source = a
        v.spoilers = sp
        v.revealed = []
        v.linkColor = UIColor(linkColor)
        v.onTap = onTap
        v.onOpen = { u in openURL(u) }
        v.apply()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SpoilerTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 80
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: ceil(h))
    }
}
