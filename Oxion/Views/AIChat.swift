import SwiftUI

// OXION AI: круглая аватарка с «живыми» кружками, разметка ответов, живая печать, кнопки действий.

/// 12 кружков как на присланной анимации: 4 больших в центре и 8 маленьких вокруг.
/// В покое — мягко «дышат», когда ИИ думает — по ним бежит волна.
struct AIDots: View {
    var size: CGFloat
    var active = false

    private static let dots: [(CGFloat, CGFloat, Bool)] = {
        let a: CGFloat = 0.168, b: CGFloat = 0.418
        var d: [(CGFloat, CGFloat, Bool)] = [(-a, -a, true), (a, -a, true), (-a, a, true), (a, a, true)]
        d += [(-a, -b, false), (a, -b, false), (b, -a, false), (b, a, false), (a, b, false), (-a, b, false), (-b, a, false), (-b, -a, false)]
        return d
    }()

    var body: some View {
        let live = PowerSaver.allowsNow(.interface)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let s = min(sz.width, sz.height)
                for (x, y, big) in Self.dots {
                    let ang = atan2(Double(y), Double(x))
                    let speed = active ? 5.5 : 1.3
                    let phase = sin(t * speed - ang + (big ? 0.6 : 0))
                    let amp = active ? 0.32 : 0.1
                    let scale = 1 + amp * phase
                    let r = (big ? 0.082 : 0.055) * s * CGFloat(scale)
                    // цвет: лайм сверху-слева → бирюза снизу-справа
                    let k = Double((x + y) / 0.84 + 0.5)
                    let col = Color(red: 0.70 - 0.45 * k, green: 0.93 - 0.08 * k, blue: 0.22 + 0.58 * k)
                    let o = active ? 0.6 + 0.4 * (phase + 1) / 2 : 1
                    let rect = CGRect(x: c.x + x * s - r, y: c.y + y * s - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(col.opacity(o)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Круглая аватарка ИИ, как в Telegram: звёзды ИИ на зелёном градиенте.
/// `active` — ИИ думает/печатает: звёзды мягко пульсируют.
struct AIAvatar: View {
    var size: CGFloat = 40
    var active = false
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xC6F94A), Color(hex: 0x58F670), Color(hex: 0x22B8A6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B1407))
                .symbolEffect(.breathe.pulse.byLayer, options: .repeating, isActive: active)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.lime.opacity(active ? 0.45 : 0), radius: size * 0.22)
        .animation(.easeInOut(duration: 0.35), value: active)
        .accessibilityLabel("OXION AI")
    }
}

/// Живая печать без рывков: состояние печати живёт только внутри этого вида,
/// поэтому весь чат не перерисовывается на каждую букву. Текст раскрывается по словам.
struct AITypingText: View {
    let text: String
    var animate: Bool
    var onDone: () -> Void = {}
    @State private var shown = 0

    var body: some View {
        AIRichText(text: animate ? String(text.prefix(shown)) : text)
            .task(id: animate) {
                guard animate else { return }
                // границы слов
                var stops: [Int] = []
                var i = 0
                var prevSpace = false
                for ch in text {
                    let sp = ch == " " || ch == "\n"
                    if sp && !prevSpace { stops.append(i) }
                    prevSpace = sp
                    i += 1
                }
                stops.append(text.count)
                // ~30 мс на слово, но не дольше ~7 секунд на весь ответ
                let per = max(1, Int((Double(stops.count) / 230).rounded(.up)))
                var k = 0
                var lastHaptic = Date()
                while k < stops.count {
                    k = min(stops.count, k + per)
                    shown = stops[k - 1]
                    if Date().timeIntervalSince(lastHaptic) > 0.35 { Haptic.tap(.soft); lastHaptic = Date() }
                    try? await Task.sleep(for: .milliseconds(30))
                    if Task.isCancelled { return }
                }
                shown = text.count
                onDone()
            }
    }
}

// MARK: - Разметка ответа

struct AIRichText: View {
    let text: String

    private enum Block { case h(String), bullet(String), num(String, String), p(String), gap }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.p(para.joined(separator: "\n"))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { flush(); if case .gap? = out.last {} else if !out.isEmpty { out.append(.gap) }; continue }
            if l.hasPrefix("#") {
                flush(); out.append(.h(l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if l.hasPrefix("- ") || l.hasPrefix("• ") || l.hasPrefix("* ") || l.hasPrefix("— ") {
                flush(); out.append(.bullet(String(l.dropFirst(2))))
            } else if let r = l.range(of: #"^\d{1,2}[.)]\s"#, options: .regularExpression) {
                flush(); out.append(.num(String(l[r]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ")", with: "."), String(l[r.upperBound...])))
            } else {
                para.append(l)
            }
        }
        flush()
        if case .gap? = out.last { out.removeLast() }
        return out
    }

    static func md(_ s: String) -> AttributedString {
        if var a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // жирное — чуть ярче
            for run in a.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                a[run.range].foregroundColor = Color.primary
            }
            // голые ссылки тоже нажимаются и открываются во встроенном браузере
            Linkify.addLinks(&a, color: Color.limeInk)
            return a
        }
        // незакрытая разметка (во время печати) — просто убираем звёздочки
        return AttributedString(s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .h(let s):
                    Text(Self.md(s)).font(.headline).padding(.top, 2)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.body.bold()).foregroundStyle(Color.limeInk)
                        Text(Self.md(s))
                    }
                case .num(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(n).font(.body.bold().monospacedDigit()).foregroundStyle(Color.limeInk)
                        Text(Self.md(s))
                    }
                case .p(let s):
                    Text(Self.md(s))
                case .gap:
                    Color.clear.frame(height: 4)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}

// MARK: - Пузырь «думает»

struct AIThinkingBubble: View {
    var body: some View {
        AIDots(size: 34, active: true)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: TailBubbleShape(mine: false, radius: 18, tail: true))
            .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
    }
}

// MARK: - Кнопки действий от ИИ

struct AIButton: Decodable, Hashable { let title: String; let route: String }

struct AIActionButtons: View {
    let buttons: [AIButton]
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 6) {
            ForEach(buttons, id: \.self) { b in
                Button {
                    Haptic.tap()
                    model.handle(route: b.route)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon(b.route)).font(.subheadline.weight(.semibold))
                        Text(b.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.glass)
                .tint(Color.limeInk)
            }
        }
    }

    private func icon(_ r: String) -> String {
        switch r.split(separator: "/").first.map(String.init) ?? r {
        case "diary": "book.closed.fill"
        case "workout": "play.fill"
        case "progress": "chart.line.uptrend.xyaxis"
        case "body": "figure.stand"
        case "exercises": "play.rectangle.on.rectangle"
        case "vision": "camera.viewfinder"
        case "run": "figure.run"
        case "map": "map.fill"
        case "rest": "timer"
        case "devices": "dot.radiowaves.left.and.right"
        case "trainers", "trainer": "person.crop.circle.badge.checkmark"
        case "book": "calendar.badge.plus"
        case "favorites": "heart.fill"
        case "feed": "square.stack.fill"
        case "chats": "bubble.left.and.right.fill"
        case "qr": "qrcode"
        default: "arrow.up.right"
        }
    }
}
