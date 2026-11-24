import SwiftUI
import UIKit
import Lottie

// Премиум-эмодзи как в Telegram: анимированные эмодзи прямо в тексте.
// В сообщении хранится метка [[e:набор/номер]]; в чате она рисуется живой анимацией в строке,
// в поле ввода — картинкой. Отправлять могут только владельцы Oxion Premium, видят все.

enum PremiumEmoji {
    static let packs: [StickerPacks.Pack] = [StickerPacks.Pack(id: "mashup", title: "Mashup Emoji", count: 120)]
    private static let re = try! NSRegularExpression(pattern: #"\[\[e:([a-z0-9_]{2,30}/\d{3})\]\]"#)

    static func token(_ ref: String) -> String { "[[e:\(ref)]]" }
    static func hasTokens(_ t: String?) -> Bool { (t ?? "").contains("[[e:") }
    static func isEmoji(_ ref: String) -> Bool { packs.contains { ref.hasPrefix($0.id + "/") } }

    /// текст по кусочкам: обычный текст и эмодзи
    enum Part { case text(String), emoji(String) }
    static func parts(_ t: String) -> [Part] {
        let ns = t as NSString
        var out: [Part] = []
        var last = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out.append(.text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))) }
            out.append(.emoji(ns.substring(with: m.range(at: 1))))
            last = m.range.location + m.range.length
        }
        if last < ns.length { out.append(.text(ns.substring(from: last))) }
        return out
    }

    /// только эмодзи (1–3 штуки) — показываем крупно без пузыря
    static func onlyEmoji(_ t: String?) -> [String]? {
        guard let t, hasTokens(t) else { return nil }
        var refs: [String] = []
        for p in parts(t.trimmingCharacters(in: .whitespacesAndNewlines)) {
            switch p {
            case .emoji(let r): refs.append(r)
            case .text(let s): if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            }
        }
        return (1...3).contains(refs.count) ? refs : nil
    }

    /// для превью и цитат
    static func plain(_ t: String?) -> String {
        guard let t else { return "" }
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

// MARK: - Картинка первого кадра (для поля ввода)

@MainActor
enum EmojiSnapshot {
    private static var cache: [String: UIImage] = [:]

    static func image(_ ref: String, size: CGFloat = 64) async -> UIImage? {
        if let i = cache[ref] { return i }
        guard let anim = await StickerCache.shared.animation(StickerPacks.file(ref)) else { return nil }
        let v = LottieAnimationView(animation: anim, configuration: LottieConfiguration(renderingEngine: .mainThread))
        v.frame = CGRect(x: 0, y: 0, width: size, height: size)
        v.contentMode = .scaleAspectFit
        v.currentProgress = 0.35
        v.layoutIfNeeded()
        v.forceDisplayUpdate()
        let img = UIGraphicsImageRenderer(size: v.bounds.size).image { ctx in v.layer.render(in: ctx.cgContext) }
        cache[ref] = img
        return img
    }
}

// MARK: - Вложения в текст

/// Эмодзи в тексте: хранит свою метку; в чате рисуется живой анимацией
final class EmojiAttachment: NSTextAttachment {
    var ref = ""
    var animated = false

    convenience init(ref: String, font: UIFont, animated: Bool) {
        self.init(data: nil, ofType: nil)
        self.ref = ref
        self.animated = animated
        let h = font.lineHeight * 1.12
        bounds = CGRect(x: 0, y: font.descender - 1, width: h, height: h)
        if !animated { image = UIImage() }
    }

    override func viewProvider(for parentView: UIView?, location: NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        guard animated else { return nil }
        let p = EmojiViewProvider(textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location)
        p.tracksTextAttachmentViewBounds = true
        return p
    }
}

final class EmojiViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let ref = (textAttachment as? EmojiAttachment)?.ref ?? ""
        let v = LottieAnimationView()
        v.contentMode = .scaleAspectFit
        v.loopMode = .loop
        v.backgroundBehavior = .pauseAndRestore
        view = v
        Task { @MainActor in
            guard let a = await StickerCache.shared.animation(StickerPacks.file(ref)) else { return }
            v.animation = a
            v.play()
        }
    }
}

enum EmojiText {
    /// текст с метками → строка с эмодзи-вложениями
    static func attributed(_ t: String, font: UIFont, color: UIColor, animated: Bool, linkColor: UIColor? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for p in PremiumEmoji.parts(t) {
            switch p {
            case .text(let s): out.append(NSAttributedString(string: s, attributes: attrs))
            case .emoji(let r):
                let a = EmojiAttachment(ref: r, font: font, animated: animated)
                let s = NSMutableAttributedString(attachment: a)
                s.addAttributes(attrs, range: NSRange(location: 0, length: s.length))
                out.append(s)
            }
        }
        return out
    }

    /// строка с вложениями → текст с метками
    static func serialize(_ a: NSAttributedString) -> String {
        var out = ""
        a.enumerateAttribute(.attachment, in: NSRange(location: 0, length: a.length)) { v, r, _ in
            if let e = v as? EmojiAttachment {
                out += PremiumEmoji.token(e.ref)
            } else {
                out += (a.string as NSString).substring(with: r).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return out
    }
}

// MARK: - Текст сообщения с живыми эмодзи

struct EmojiMessageText: UIViewRepresentable {
    let text: String
    var fontSize: CGFloat
    var color: Color
    var linkColor: Color

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView(usingTextLayoutManager: true)
        v.isEditable = false
        v.isScrollEnabled = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = [.link, .phoneNumber]
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        let key = text + "|\(fontSize)"
        if context.coordinator.key != key {
            context.coordinator.key = key
            v.attributedText = EmojiText.attributed(text, font: .systemFont(ofSize: fontSize), color: UIColor(color), animated: true)
        }
        v.linkTextAttributes = [.foregroundColor: UIColor(linkColor), .underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = min(proposal.width ?? 260, 260)
        let s = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(min(s.width, w)), height: ceil(s.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var key = "" }
}

/// 1–3 эмодзи без текста — крупно, как в Telegram
struct BigEmojiRow: View {
    let refs: [String]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(refs.enumerated()), id: \.offset) { _, r in
                StickerView(ref: r, size: refs.count == 1 ? 110 : 76)
            }
        }
    }
}

// MARK: - Поле ввода, в котором видно эмодзи

struct EmojiComposer: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder = "Сообщение"
    var maxLines = 6

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView(usingTextLayoutManager: true)
        v.font = .preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.isScrollEnabled = false
        v.delegate = context.coordinator
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = v
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        // текст поменяли снаружи (отправили, вставили эмодзи) — перестраиваем
        if EmojiText.serialize(v.attributedText) != text {
            context.coordinator.rebuild(v, text)
        }
        if focused && !v.isFirstResponder {
            DispatchQueue.main.async { v.becomeFirstResponder() }
        } else if !focused && v.isFirstResponder {
            DispatchQueue.main.async { v.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 200
        let line = (uiView.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let full = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        let maxH = line * CGFloat(maxLines)
        let scroll = full > maxH + 1
        if uiView.isScrollEnabled != scroll { DispatchQueue.main.async { uiView.isScrollEnabled = scroll } }
        return CGSize(width: w, height: max(line, min(full, maxH)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EmojiComposer
        weak var textView: UITextView?
        init(parent: EmojiComposer) { self.parent = parent }

        func rebuild(_ v: UITextView, _ t: String) {
            let font = v.font ?? .preferredFont(forTextStyle: .body)
            let a = EmojiText.attributed(t, font: font, color: .label, animated: false)
            v.attributedText = a
            v.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
            v.selectedRange = NSRange(location: a.length, length: 0)
            // картинки эмодзи догружаем
            a.enumerateAttribute(.attachment, in: NSRange(location: 0, length: a.length)) { val, _, _ in
                guard let e = val as? EmojiAttachment else { return }
                Task { @MainActor in
                    if let img = await EmojiSnapshot.image(e.ref) {
                        e.image = img
                        v.textLayoutManager?.invalidateLayout(for: v.textLayoutManager!.documentRange)
                        v.setNeedsDisplay()
                    }
                }
            }
            v.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ v: UITextView) {
            let s = EmojiText.serialize(v.attributedText)
            if s != parent.text { parent.text = s }
            v.invalidateIntrinsicContentSize()
        }
        func textViewDidBeginEditing(_ v: UITextView) { if !parent.focused { parent.focused = true } }
        func textViewDidEndEditing(_ v: UITextView) { if parent.focused { parent.focused = false } }
    }
}

// MARK: - «Анимированные эмодзи» — предложение Premium

struct PremiumEmojiUpsell: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPremium = false
    private let sample = (1...12).map { String(format: "mashup/%03d", $0 * 9) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x6A5CFF), Color(hex: 0xC060F0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                    ForEach(sample, id: \.self) { r in StickerView(ref: r, size: 58) }
                }
                .padding(24)
            }
            .frame(height: 300)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .padding(16)
            }

            VStack(spacing: 8) {
                Text("Анимированные эмодзи").font(.title3.bold())
                Text("Отправляйте анимированные эмодзи из разных наборов в любые чаты Oxion.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.top, 18)

            Button { showPremium = true } label: {
                Label("Получить анимированные эмодзи", systemImage: "lock.fill")
                    .labelStyle(TrailingIcon())
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime).foregroundStyle(Color.onLime)
            .controlSize(.large)
            .padding(20)
        }
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .sheet(isPresented: $showPremium, onDismiss: { Task { await PremiumStatus.shared.refresh(force: true) } }) {
            NavigationStack { PremiumView() }
        }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}
