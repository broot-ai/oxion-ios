import SwiftUI
import AVFoundation

/// Карточки в сообщениях чата (как «виджеты» в PWA): тренировка, рекорд, прогресс, вес, итоги недели и др.
struct ChatCard: View {
    let kind: String
    let card: JSONValue?
    let mine: Bool

    private var fg: Color { mine ? .black : .primary }
    private var sub: Color { mine ? Color.black.opacity(0.6) : Color.oxHint }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Kinds.label[kind] ?? "Карточка")
                .font(.caption.bold())
                .foregroundStyle(sub)
            content
        }
        .padding(12)
        .frame(minWidth: 200, alignment: .leading)
        .background((mine ? Color.white.opacity(0.35) : Color.white.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    Sparkline(values: pts, color: mine ? .black : Color.lime)
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
            VoicePlayer(url: API.media(c?["url"]?.string), seconds: c?["dur"]?.int ?? 0, tint: fg)
        case "sticker":
            Text("🎨").font(.system(size: 54))
        default:
            VStack(alignment: .leading, spacing: 4) {
                if let t = c?["title"]?.string ?? c?["text"]?.string ?? c?["name"]?.string {
                    Text(t).font(.headline).foregroundStyle(fg)
                }
                Text("Подробнее — в полной версии чата").font(.caption).foregroundStyle(sub)
            }
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
