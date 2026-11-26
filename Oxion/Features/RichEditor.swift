import SwiftUI
import UIKit

// MARK: - Поле ввода с форматированием «как в Telegram»
// Пользователь видит сразу жирный/курсив/зачёркнутый/моноширинный текст и спойлер — без значков ** и ||.
// Наружу (на сервер) уходит текст с разметкой: **жирный** __курсив__ ~~зачёркнутый~~ `код` ||спойлер||.
// Панель форматирования — над клавиатурой (inputAccessoryView), поэтому нажатия не сбивают фокус.
// Ещё форматирование есть в меню выделения: «Форматирование ›».

extension NSAttributedString.Key {
    static let oxSpoiler = NSAttributedString.Key("oxSpoiler")
}

struct RichFlags: OptionSet, Hashable {
    let rawValue: Int
    static let bold = RichFlags(rawValue: 1)
    static let italic = RichFlags(rawValue: 2)
    static let strike = RichFlags(rawValue: 4)
    static let code = RichFlags(rawValue: 8)
    static let spoiler = RichFlags(rawValue: 16)
}

/// Управление полем из SwiftUI: фокус, вставка упоминания, «@»
@MainActor
final class RichEditorController {
    weak var tv: RichTextView?
    func focus() { tv?.becomeFirstResponder() }
    func blur() { tv?.resignFirstResponder() }
    func insertMention(_ username: String) { tv?.insertMention(username) }
    func insertAt() { tv?.insertAtSign() }
}

/// Набор контроллеров для частей ветки
@MainActor
final class RichEditors {
    private var map: [UUID: RichEditorController] = [:]
    func of(_ id: UUID) -> RichEditorController {
        if let c = map[id] { return c }
        let c = RichEditorController()
        map[id] = c
        return c
    }
}

final class RichTextView: UITextView {
    var baseFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    var onChange: ((String) -> Void)?
    var onMention: ((String?) -> Void)?
    var onFocus: ((Bool) -> Void)?
    let placeholderLabel = UILabel()

    var baseAttrs: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: UIColor.label]
    }

    // MARK: атрибуты ↔ флаги
    static func flags(_ a: [NSAttributedString.Key: Any]) -> RichFlags {
        var f: RichFlags = []
        if let font = a[.font] as? UIFont {
            let t = font.fontDescriptor.symbolicTraits
            if t.contains(.traitMonoSpace) { f.insert(.code) }
            else {
                if t.contains(.traitBold) { f.insert(.bold) }
                if t.contains(.traitItalic) { f.insert(.italic) }
            }
        }
        if let s = a[.strikethroughStyle] as? Int, s != 0 { f.insert(.strike) }
        if a[.oxSpoiler] != nil { f.insert(.spoiler) }
        return f
    }

    func attrs(for f: RichFlags) -> [NSAttributedString.Key: Any] {
        var a = baseAttrs
        let size = baseFont.pointSize
        if f.contains(.code) {
            a[.font] = UIFont.monospacedSystemFont(ofSize: size * 0.94, weight: .regular)
            a[.backgroundColor] = UIColor.label.withAlphaComponent(0.08)
        } else {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if f.contains(.bold) { traits.insert(.traitBold) }
            if f.contains(.italic) { traits.insert(.traitItalic) }
            if !traits.isEmpty, let d = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                a[.font] = UIFont(descriptor: d, size: size)
            }
        }
        if f.contains(.strike) { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if f.contains(.spoiler) {
            a[.oxSpoiler] = true
            a[.backgroundColor] = UIColor.systemGray.withAlphaComponent(0.35)
        }
        return a
    }

    // MARK: применение формата
    func toggle(_ flag: RichFlags) {
        let r = selectedRange
        if r.length == 0 {
            // без выделения — меняем «текущий стиль» для следующих букв
            var f = Self.flags(typingAttributes)
            if f.contains(flag) { f.remove(flag) } else {
                f.insert(flag)
                if flag == .code { f.remove([.bold, .italic]) }
                if flag == .bold || flag == .italic { f.remove(.code) }
            }
            typingAttributes = attrs(for: f)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        // если весь фрагмент уже с этим стилем — снимаем, иначе ставим
        var all = true
        textStorage.enumerateAttributes(in: r) { a, _, _ in if !Self.flags(a).contains(flag) { all = false } }
        let m = NSMutableAttributedString(attributedString: attributedText)
        m.enumerateAttributes(in: r) { a, sub, _ in
            var f = Self.flags(a)
            if all { f.remove(flag) } else {
                f.insert(flag)
                if flag == .code { f.remove([.bold, .italic]) }
                if flag == .bold || flag == .italic { f.remove(.code) }
            }
            m.setAttributes(attrs(for: f), range: sub)
        }
        attributedText = m
        selectedRange = r
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        changed()
    }

    func clearFormat() {
        let r = selectedRange
        guard r.length > 0 else { typingAttributes = baseAttrs; return }
        let m = NSMutableAttributedString(attributedString: attributedText)
        m.setAttributes(baseAttrs, range: r)
        attributedText = m
        selectedRange = r
        changed()
    }

    // MARK: разметка для сервера
    var markup: String {
        let s = attributedText ?? NSAttributedString()
        var out = ""
        var runs: [(String, RichFlags)] = []
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { a, r, _ in
            let t = (s.string as NSString).substring(with: r)
            let f = Self.flags(a)
            if let last = runs.last, last.1 == f { runs[runs.count - 1].0 += t } else { runs.append((t, f)) }
        }
        for (t, f) in runs {
            if f.isEmpty { out += t; continue }
            // пробелы по краям — вне маркеров, иначе разметка «ломается»
            let lead = t.prefix(while: { $0.isWhitespace || $0.isNewline })
            let trail = t.reversed().prefix(while: { $0.isWhitespace || $0.isNewline })
            if lead.count >= t.count { out += t; continue }
            var core = String(t.dropFirst(lead.count).dropLast(trail.count))
            if f.contains(.code) { core = "`" + core.replacingOccurrences(of: "`", with: "'") + "`" }
            else {
                if f.contains(.strike) { core = "~~" + core + "~~" }
                if f.contains(.italic) { core = "__" + core + "__" }
                if f.contains(.bold) { core = "**" + core + "**" }
            }
            if f.contains(.spoiler) { core = "||" + core + "||" }
            out += String(lead) + core + String(trail.reversed())
        }
        return out
    }

    func changed() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
        onChange?(markup)
        invalidateIntrinsicContentSize()
        reportMention()
    }

    // MARK: @упоминания
    /// «@им» прямо перед курсором → диапазон и запрос
    func mentionToken() -> (NSRange, String)? {
        let r = selectedRange
        guard r.length == 0 else { return nil }
        let ns = (text ?? "") as NSString
        var i = r.location
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == 64 /* @ */ {
                if i - 1 > 0 {
                    let b = ns.character(at: i - 2)
                    guard let sc = Unicode.Scalar(b), CharacterSet.whitespacesAndNewlines.contains(sc) || b == 40 else { return nil }
                }
                let q = ns.substring(with: NSRange(location: i, length: r.location - i))
                return q.count <= 32 ? (NSRange(location: i - 1, length: r.location - i + 1), q) : nil
            }
            guard let sc = Unicode.Scalar(c), sc.isASCII, CharacterSet.alphanumerics.contains(sc) || c == 95 else { return nil }
            i -= 1
        }
        return nil
    }

    func reportMention() { onMention?(mentionToken()?.1) }

    func insertMention(_ username: String) {
        guard let (r, _) = mentionToken() else { return }
        let ins = NSAttributedString(string: "@" + username + " ", attributes: baseAttrs)
        textStorage.replaceCharacters(in: r, with: ins)
        selectedRange = NSRange(location: r.location + ins.length, length: 0)
        typingAttributes = baseAttrs
        changed()
    }

    func insertAtSign() {
        if !isFirstResponder { becomeFirstResponder() }
        let r = selectedRange
        let ns = (text ?? "") as NSString
        var s = "@"
        if r.location > 0, let sc = Unicode.Scalar(ns.character(at: r.location - 1)), !CharacterSet.whitespacesAndNewlines.contains(sc) { s = " @" }
        let ins = NSAttributedString(string: s, attributes: baseAttrs)
        textStorage.replaceCharacters(in: r, with: ins)
        selectedRange = NSRange(location: r.location + ins.length, length: 0)
        typingAttributes = baseAttrs
        changed()
    }

    // MARK: панель над клавиатурой
    func makeAccessory() -> UIView {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        bar.backgroundColor = .clear
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blur.layer.cornerRadius = 22
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            blur.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            blur.topAnchor.constraint(equalTo: bar.topAnchor, constant: 4),
            blur.heightAnchor.constraint(equalToConstant: 44)
        ])
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor)
        ])
        func btn(_ icon: String, _ label: String, _ act: @escaping () -> Void) -> UIButton {
            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            cfg.baseForegroundColor = .label
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            let b = UIButton(configuration: cfg, primaryAction: UIAction { _ in act() })
            b.accessibilityLabel = label
            return b
        }
        stack.addArrangedSubview(btn("bold", "Жирный") { [weak self] in self?.toggle(.bold) })
        stack.addArrangedSubview(btn("italic", "Курсив") { [weak self] in self?.toggle(.italic) })
        stack.addArrangedSubview(btn("strikethrough", "Зачёркнутый") { [weak self] in self?.toggle(.strike) })
        stack.addArrangedSubview(btn("chevron.left.forwardslash.chevron.right", "Моноширинный") { [weak self] in self?.toggle(.code) })
        stack.addArrangedSubview(btn("eye.slash", "Спойлер") { [weak self] in self?.toggle(.spoiler) })
        stack.addArrangedSubview(btn("at", "Упомянуть") { [weak self] in self?.insertAtSign() })
        stack.addArrangedSubview(btn("keyboard.chevron.compact.down", "Скрыть клавиатуру") { [weak self] in self?.resignFirstResponder() })
        return bar
    }
}

struct RichComposeField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let controller: RichEditorController
    var onFocus: (Bool) -> Void = { _ in }
    var onMention: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RichTextView {
        let tv = RichTextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = tv.baseFont
        tv.adjustsFontForContentSizeCategory = true
        tv.tintColor = UIColor(Color.limeInk)
        tv.typingAttributes = tv.baseAttrs
        tv.attributedText = NSAttributedString(string: text, attributes: tv.baseAttrs)
        tv.delegate = context.coordinator
        tv.inputAccessoryView = tv.makeAccessory()
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.placeholderLabel.text = placeholder
        tv.placeholderLabel.font = tv.baseFont
        tv.placeholderLabel.textColor = .placeholderText
        tv.placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(tv.placeholderLabel)
        NSLayoutConstraint.activate([
            tv.placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            tv.placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor)
        ])
        tv.placeholderLabel.isHidden = !text.isEmpty
        tv.onChange = { m in context.coordinator.parent.text = m }
        tv.onMention = { q in context.coordinator.parent.onMention(q) }
        controller.tv = tv
        return tv
    }

    func updateUIView(_ tv: RichTextView, context: Context) {
        context.coordinator.parent = self
        controller.tv = tv
        // текст сбросили снаружи (например, после отправки)
        if text.isEmpty && !(tv.text ?? "").isEmpty {
            tv.attributedText = NSAttributedString(string: "", attributes: tv.baseAttrs)
            tv.placeholderLabel.isHidden = false
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RichTextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 300
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: max(h, uiView.baseFont.lineHeight))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichComposeField
        init(_ p: RichComposeField) { parent = p }

        func textViewDidChange(_ tv: UITextView) { (tv as? RichTextView)?.changed() }
        func textViewDidChangeSelection(_ tv: UITextView) { (tv as? RichTextView)?.reportMention() }
        func textViewDidBeginEditing(_ tv: UITextView) { parent.onFocus(true); (tv as? RichTextView)?.reportMention() }
        func textViewDidEndEditing(_ tv: UITextView) { parent.onFocus(false); parent.onMention(nil) }

        // вставка: чужое форматирование не тащим, только текст
        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            guard t.count > 1, let r = tv as? RichTextView else { return true }
            let ins = NSAttributedString(string: t, attributes: r.typingAttributes)
            r.textStorage.replaceCharacters(in: range, with: ins)
            r.selectedRange = NSRange(location: range.location + ins.length, length: 0)
            r.changed()
            return false
        }

        // меню выделения: «Форматирование ›», как в Telegram
        func textView(_ tv: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let r = tv as? RichTextView else { return UIMenu(children: suggestedActions) }
            let f = UIMenu(title: "Форматирование", image: UIImage(systemName: "textformat"), children: [
                UIAction(title: "Жирный", image: UIImage(systemName: "bold")) { _ in r.toggle(.bold) },
                UIAction(title: "Курсив", image: UIImage(systemName: "italic")) { _ in r.toggle(.italic) },
                UIAction(title: "Зачёркнутый", image: UIImage(systemName: "strikethrough")) { _ in r.toggle(.strike) },
                UIAction(title: "Моноширинный", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { _ in r.toggle(.code) },
                UIAction(title: "Спойлер", image: UIImage(systemName: "eye.slash")) { _ in r.toggle(.spoiler) },
                UIAction(title: "Обычный", image: UIImage(systemName: "textformat.size.smaller")) { _ in r.clearFormat() }
            ])
            return UIMenu(children: [f] + suggestedActions)
        }
    }
}
