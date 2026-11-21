import SwiftUI
import AVFoundation

/// Карточки в сообщениях чата (как «виджеты» в PWA): тренировка, рекорд, прогресс, вес, итоги недели и др.
struct ChatCard: View {
    let kind: String
    let card: JSONValue?
    let mine: Bool
    /// внутри сообщения с текстом — без собственного фона
    var embedded = false
    var messageId: Int? = nil

    private var onLime: Bool { mine && embedded }
    private var fg: Color { onLime ? Color.onLime : .primary }
    private var sub: Color { onLime ? Color.onLime.opacity(0.6) : Color.oxHint }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !["product", "call", "voice", "vnote", "video", "file", "photos"].contains(kind) {
            HStack(spacing: 8) {
                Text(String((Kinds.label[kind] ?? "📎").prefix(2)))
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .background((onLime ? Color.onLime.opacity(0.12) : Color.lime.opacity(0.16)), in: Circle())
                Text(String((Kinds.label[kind] ?? "Карточка").dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sub)
                    .textCase(.uppercase)
            }
            }
            content
        }
        .padding(embedded ? 4 : 14)
        .frame(width: embedded ? nil : 250, alignment: .leading)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color.oxCard2, Color.oxCard], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let c = card
        switch kind {
        case "workout", "plan":
            VStack(alignment: .leading, spacing: 6) {
                Text(c?["title"]?.string ?? "Тренировка")
                    .font(.headline)
                    .foregroundStyle(fg)
                if let d = c?["date"]?.string {
                    Text(RU.human(d)).font(.caption).foregroundStyle(sub)
                }
                ForEach(Array((c?["exercises"]?.array ?? []).enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(e["name"]?.string ?? "")
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(e["sets"]?.int ?? 0) подх.")
                            .font(.caption)
                            .foregroundStyle(sub)
                    }
                    .foregroundStyle(fg)
                }
                if let more = c?["more"]?.int, more > 0 {
                    Text("и ещё \(more)").font(.caption).foregroundStyle(sub)
                }
                HStack(spacing: 14) {
                    metric("\(c?["sets"]?.int ?? 0)", "подходов")
                    if let v = c?["volume"]?.int, v > 0 { metric("\(v)", "кг объём") }
                }
            }
        case "record":
            VStack(alignment: .leading, spacing: 4) {
                Text(c?["exercise"]?.string ?? "")
                    .font(.headline)
                    .foregroundStyle(fg)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("🏆")
                    Text(c?["value"]?.string ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(c?["unit"]?.string ?? "")
                        .font(.subheadline)
                }
                .foregroundStyle(fg)
                if let e = c?["e1rm"]?.string {
                    Text("Расчётный максимум: \(e) кг").font(.caption).foregroundStyle(sub)
                }
            }
        case "progress", "weight":
            let pts = (c?["points"]?.array ?? []).compactMap { $0["v"]?.number }
            VStack(alignment: .leading, spacing: 6) {
                if kind == "progress" {
                    Text(c?["exercise"]?.string ?? "").font(.headline).foregroundStyle(fg)
                }
                HStack(spacing: 14) {
                    metric(c?["first"]?.string ?? "—", "было")
                    metric(c?["last"]?.string ?? "—", "стало")
                    if let b = c?["best"]?.string { metric(b, "лучший") }
                }
                if pts.count > 1 {
                    Sparkline(values: pts, color: onLime ? Color.onLime : Color.limeInk)
                        .frame(height: 44)
                }
            }
        case "week":
            HStack(spacing: 14) {
                metric("\(c?["workouts"]?.int ?? 0)/\(c?["goal"]?.int ?? 0)", "тренировок")
                metric("\(c?["sets"]?.int ?? 0)", "подходов")
                if let s = c?["streak"]?.int, s > 0 { metric("\(s)", "недель подряд") }
            }
        case "voice":
            VoiceMessageView(url: API.media(c?["url"]?.string), seconds: c?["dur"]?.int ?? 0, wave: c?["wave"]?.string ?? "",
                             tint: fg, messageId: messageId, transcript: c?["tr"]?.string)
        case "vnote":
            VideoNoteView(url: API.media(c?["url"]?.string), seconds: c?["dur"]?.int ?? 0)
        case "video":
            ChatVideoView(url: API.media(c?["url"]?.string), seconds: c?["dur"]?.int ?? 0)
        case "file":
            FileCardView(name: c?["name"]?.string ?? "Файл", ext: c?["ext"]?.string ?? "", size: c?["size"]?.int ?? 0,
                         url: API.media(c?["url"]?.string), fg: fg, sub: sub)
        case "photos":
            PhotoReportView(card: c, fg: fg, sub: sub)
        case "sticker":
            Text("🎨").font(.system(size: 54))
        case "product":
            productBody(c)
        case "call":
            callBody(c)
        default:
            VStack(alignment: .leading, spacing: 4) {
                if let t = c?["title"]?.string ?? c?["text"]?.string ?? c?["name"]?.string {
                    Text(t).font(.headline).foregroundStyle(fg)
                }
                Text("Подробнее — в полной версии чата").font(.caption).foregroundStyle(sub)
            }
        }
    }

    // MARK: товар и звонок

    @ViewBuilder
    private func productBody(_ c: JSONValue?) -> some View {
        let price = (c?["price_kop"]?.number ?? 0) / 100
        let old = (c?["old_price_kop"]?.number).map { $0 / 100 }
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: API.media(c?["photo"]?.string), icon: "bag.fill")
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let old, old > price {
                        Text("−\(Int(((old - price) / old * 100).rounded()))%")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: 0xFF5A4E), in: Capsule())
                            .padding(5)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.rub(price)).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(fg)
                    if let old, old > price {
                        Text(Self.rub(old)).font(.caption).strikethrough().foregroundStyle(sub)
                    }
                }
                Text(c?["title"]?.string ?? "Товар")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(fg)
                    .lineLimit(2)
                Text([c?["brand"]?.string, c?["store"]?.string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(sub).lineLimit(1)
                if let r = c?["rating"]?.number, r > 0 {
                    Label("\(r.formatted(.number.precision(.fractionLength(0...1)))) · \(c?["rating_count"]?.int ?? 0) отз.", systemImage: "star.fill")
                        .font(.caption).foregroundStyle(sub)
                }
                if c?["in_stock"]?.bool == false {
                    Text("Нет в наличии").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func callBody(_ c: JSONValue?) -> some View {
        let video = c?["video"]?.bool == true
        let dur = c?["dur"]?.int ?? 0
        let missed = dur == 0
        let title: String = {
            let what = video ? "видеозвонок" : "звонок"
            if mine { return missed ? "Отменённый \(what)" : "Исходящий \(what)" }
            return missed ? "Пропущенный \(what)" : "Входящий \(what)"
        }()
        HStack(spacing: 12) {
            Image(systemName: video ? "video.fill" : "phone.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(missed && !mine ? Color(hex: 0xFF5A4E) : Color.lime)
                .frame(width: 42, height: 42)
                .background((missed && !mine ? Color(hex: 0xFF5A4E) : Color.lime).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title.prefix(1).uppercased() + title.dropFirst())
                    .font(.subheadline.bold())
                    .foregroundStyle(missed && !mine ? Color(hex: 0xFF5A4E) : fg)
                Text(missed ? (mine ? "Без ответа" : "Нажмите, чтобы перезвонить") : String(format: "%d:%02d", dur / 60, dur % 60))
                    .font(.caption).foregroundStyle(sub)
            }
        }
    }

    static func rub(_ v: Double) -> String {
        v.formatted(.number.grouping(.automatic).precision(.fractionLength(0...2))) + " ₽"
    }

    /// Кнопки под карточкой (как inline-кнопки в Telegram)
    static func buttons(kind: String, card: JSONValue?, mine: Bool) -> [InlineBtn] {
        switch kind {
        case "product":
            guard let id = card?["pid"]?.int else { return [] }
            return [InlineBtn(title: "Открыть товар", icon: "bag", action: .product(id))]
        case "call":
            let video = card?["video"]?.bool == true
            let missed = (card?["dur"]?.int ?? 0) == 0
            return [InlineBtn(title: missed && !mine ? "Перезвонить" : "Позвонить ещё", icon: video ? "video" : "phone", action: .call(video: video))]
        default:
            return []
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline).foregroundStyle(fg)
            Text(label).font(.caption2).foregroundStyle(sub)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = .lime

    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(0.0001, hi - lo)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = g.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1))
                    let y = g.size.height * (1 - CGFloat((v - lo) / span))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct VoicePlayer: View {
    let url: URL?
    let seconds: Int
    var tint: Color = .primary
    @State private var player: AVPlayer?
    @State private var playing = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 2) {
                ForEach(0..<18, id: \.self) { i in
                    Capsule().frame(width: 3, height: CGFloat(6 + (i * 7) % 18))
                }
            }
            .opacity(0.6)
            Text(String(format: "%ld:%02ld", seconds / 60, seconds % 60))
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(tint)
        .onDisappear { player?.pause(); playing = false }
    }

    private func toggle() {
        guard let url else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = AVPlayer(url: url)
        }
        if playing { player?.pause() } else { player?.seek(to: .zero); player?.play() }
        playing.toggle()
    }
}

/// «+» в чате: поделиться тренировкой, рекордом, прогрессом, весом, итогами недели.
struct AttachSheet: View {
    let chatId: Int
    var onSent: (Message) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var opts: AttachOptions?
    @State private var errorText: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            List {
                Section("Быстро") {
                    sendRow("📊 Итоги недели", sub: "Тренировки, подходы, серия") { await send(["kind": "week"]) }
                    sendRow("⚖️ Вес тела", sub: "График веса") { await send(["kind": "weight"]) }
                }
                if let ws = opts?.workouts, !ws.isEmpty {
                    Section("Тренировка") {
                        ForEach(ws) { w in
                            sendRow("🏋️ \(w.title ?? "Тренировка")", sub: "\(RU.human(w.date)) · \(w.sets ?? 0) подх.") {
                                await send(["kind": "workout", "ref": w.id])
                            }
                        }
                    }
                }
                if let ex = opts?.exercises, !ex.isEmpty {
                    Section("Рекорд в упражнении") {
                        ForEach(ex) { e in
                            sendRow("🏆 \(e.name)", sub: "Лучший результат") { await send(["kind": "record", "ref": e.id]) }
                        }
                    }
                    Section("Прогресс в упражнении") {
                        ForEach(ex) { e in
                            sendRow("📈 \(e.name)", sub: "График за последние тренировки") { await send(["kind": "progress", "ref": e.id]) }
                        }
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .overlay { if sending { ProgressView() } }
            .task {
                do { opts = try await API.call("/chats/\(chatId)/attach") } catch { errorText = error.localizedDescription }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sendRow(_ title: String, sub: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(sending)
    }

    private func send(_ body: [String: Any]) async {
        sending = true
        defer { sending = false }
        do {
            let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: body)
            Haptic.success()
            onSent(m)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}


struct InlineBtn: Identifiable {
    enum Action { case product(Int), call(video: Bool) }
    let id = UUID()
    let title: String
    let icon: String
    let action: Action
}

/// Ряд inline-кнопок под сообщением
struct InlineButtonsRow: View {
    let buttons: [InlineBtn]
    var radius: CGFloat = 14
    var onTap: (InlineBtn.Action) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(buttons) { b in
                Button {
                    Haptic.tap()
                    onTap(b.action)
                } label: {
                    Text(b.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(5)
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .buttonStyle(InlinePressStyle())
            }
        }
    }
}

private struct InlinePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Пузырь с закруглённым «хвостиком», как в Telegram
struct TailBubbleShape: Shape {
    var mine: Bool
    var radius: CGFloat
    var tail: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        let small = min(6, r)
        var p = Path()
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        // рисуем для своего сообщения (хвост справа внизу), чужое — зеркально
        p.move(to: CGPoint(x: minX + r, y: minY))
        p.addLine(to: CGPoint(x: maxX - r, y: minY))
        p.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
        if tail {
            p.addLine(to: CGPoint(x: maxX, y: maxY - 10))
            p.addCurve(to: CGPoint(x: maxX + 6, y: maxY),
                       control1: CGPoint(x: maxX, y: maxY - 3), control2: CGPoint(x: maxX + 3, y: maxY - 0.5))
            p.addCurve(to: CGPoint(x: maxX - 12, y: maxY - 1.5),
                       control1: CGPoint(x: maxX - 2, y: maxY + 0.8), control2: CGPoint(x: maxX - 8, y: maxY))
            p.addQuadCurve(to: CGPoint(x: maxX - r - 2, y: maxY), control: CGPoint(x: maxX - 15, y: maxY))
        } else {
            p.addLine(to: CGPoint(x: maxX, y: maxY - small))
            p.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - small, y: maxY), radius: small)
        }
        p.addLine(to: CGPoint(x: minX + r, y: maxY))
        p.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r), radius: r)
        p.addLine(to: CGPoint(x: minX, y: minY + r))
        p.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r, y: minY), radius: r)
        p.closeSubpath()
        if mine { return p }
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX * 2 + rect.width, ty: 0))
    }
}


struct FileCardView: View {
    let name: String
    let ext: String
    let size: Int
    let url: URL?
    let fg: Color
    let sub: Color
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 12) {
                Text(ext.uppercased().prefix(4))
                    .font(.caption.bold())
                    .foregroundStyle(Color.onLime)
                    .frame(width: 46, height: 46)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.bold()).foregroundStyle(fg).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.caption).foregroundStyle(sub)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PhotoReportView: View {
    let card: JSONValue?
    let fg: Color
    let sub: Color
    var body: some View {
        let ps = card?["photos"]?.array ?? []
        VStack(alignment: .leading, spacing: 8) {
            Label("Фотоотчёт", systemImage: "camera.fill").font(.caption.bold()).foregroundStyle(sub)
            HStack(spacing: 4) {
                ForEach(Array(ps.enumerated()), id: \.offset) { _, p in
                    RemoteImage(url: API.media(p["url"]?.string))
                        .frame(width: 80, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottom) {
                            Text(p["label"]?.string ?? "").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.45), in: Capsule()).padding(4)
                        }
                }
            }
            if let w = card?["weight"]?.string { Text("Вес: \(w) кг").font(.caption.bold()).foregroundStyle(fg) }
        }
    }
}
