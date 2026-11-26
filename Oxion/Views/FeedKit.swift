import SwiftUI
import UIKit

// MARK: - События ленты: удаление видно сразу на всех экранах

extension Notification.Name {
    /// object: Int — id удалённой ветки
    static let oxPostDeleted = Notification.Name("oxPostDeleted")
    /// object: Post — только что опубликованная ветка (для вставки в начало ленты)
    static let oxPostCreated = Notification.Name("oxPostCreated")
    /// перезагрузить ленту (например, удаление не прошло на сервере)
    static let oxionRefreshFeed = Notification.Name("oxionRefreshFeed")
}

// MARK: - Ссылка на ветку: …/t/123 (открывается в приложении, в мессенджерах — с превью)

enum PostLink {
    static func url(_ id: Int) -> URL {
        URL(string: AppSettings.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/t/\(id)")!
    }
}

// MARK: - Тренировка из поста: состав и «Сохранить себе»

struct PostWorkoutSheet: View {
    let postId: Int
    let w: JSONValue
    var author: String?
    /// куда сохранять (по умолчанию — копия из ветки)
    var saveURL: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var saving = false

    var body: some View {
        let ex = w["exercises"]?.array ?? []
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        MuscleThumb(key: (w["groups"]?.array ?? []).compactMap(\.string).first, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w["title"]?.string ?? "Тренировка").font(.title3.bold())
                            Text(PostWorkoutCard.summary(w)).font(.subheadline).foregroundStyle(Color.oxHint)
                            if let a = author { Text("Автор: \(a)").font(.caption).foregroundStyle(Color.oxHint) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                ForEach(Array(ex.enumerated()), id: \.offset) { i, e in
                    Section {
                        let sets = e["sets"]?.array ?? []
                        if sets.isEmpty {
                            Text("Без подходов").foregroundStyle(Color.oxHint)
                        }
                        ForEach(Array(sets.enumerated()), id: \.offset) { j, s in
                            HStack {
                                Text("\(j + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.oxHint).frame(width: 24, alignment: .leading)
                                Text(Self.setText(s)).font(.subheadline.monospacedDigit())
                                Spacer()
                            }
                        }
                    } header: {
                        Text("\(i + 1). \(e["name"]?.string ?? "Упражнение")").font(.subheadline.weight(.semibold)).textCase(nil)
                    }
                }
            }
            .navigationTitle("Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await save() } } label: {
                    HStack(spacing: 8) {
                        if saving { ProgressView().tint(Color.onLime) } else { Image(systemName: "square.and.arrow.down") }
                        Text("Сохранить себе").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.lime)
                .foregroundStyle(Color.onLime)
                .disabled(saving)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    static func setText(_ s: JSONValue) -> String {
        var parts: [String] = []
        if let w = s["w"]?.number, w > 0 { parts.append("\(w.formatted()) кг") }
        if let r = s["r"]?.int, r > 0 { parts.append("× \(r)") }
        if let d = s["d"]?.int, d > 0 { parts.append(String(format: "%d:%02d", d / 60, d % 60)) }
        if let km = s["km"]?.number, km > 0 { parts.append("\(km.formatted()) км") }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private func save() async {
        saving = true
        defer { saving = false }
        struct R: Decodable { let workoutId: Int; let skipped: [String]? }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        do {
            let r: R = try await API.call(saveURL ?? "/feed/posts/\(postId)/copy", method: "POST", body: ["date": f.string(from: Date())])
            Haptic.success()
            let skipped = r.skipped ?? []
            let wid = r.workoutId
            dismiss()
            OxAlert.show(icon: "checkmark.circle.fill", title: "Тренировка сохранена",
                         message: skipped.isEmpty ? "Она в дневнике на сегодня" : "Не нашли в каталоге: \(skipped.prefix(3).joined(separator: ", "))",
                         buttons: [OxAlertButton(title: "Открыть", role: .primary) { model.workoutBox = AppModel.IdBox(id: wid) },
                                   OxAlertButton(title: "Позже", role: .cancel)])
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

// MARK: - Карусель фото: при перелистывании пальцем фото «сшиваются» в одну ленту

struct PhotoCarousel: View {
    let urls: [URL]
    var spoiler = false
    var height: CGFloat = 280
    var onTap: () -> Void = {}
    var onDoubleTap: () -> Void = {}

    @State private var dragging = false

    var body: some View {
        let gap: CGFloat = dragging ? 0 : 6
        let r: CGFloat = 16
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: gap) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                    let first = i == 0, last = i == urls.count - 1
                    // во время листания внутренние углы прямые — фото сливаются в одну панораму
                    let inner: CGFloat = dragging ? 0 : r
                    SpoilerMedia(on: spoiler) { RemoteImage(url: u) }
                        .frame(width: 230, height: height)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: first ? r : inner, bottomLeadingRadius: first ? r : inner,
                                                          bottomTrailingRadius: last ? r : inner, topTrailingRadius: last ? r : inner,
                                                          style: .continuous))
                        .contentShape(Rectangle())
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.15), value: dragging)
        }
        .onScrollPhaseChange { _, phase in
            let on = phase == .interacting || phase == .tracking || phase == .decelerating
            if on != dragging { dragging = on }
        }
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
    }
}

// MARK: - Спойлер для фото (как в Threads): сильное размытие + мерцающие искры, нажатие — открыть

/// Мерцающие точки на всю площадь (для фото-спойлера)
struct SparkleDust: UIViewRepresentable {
    final class V: UIView {
        let e = CAEmitterLayer()
        private var lastSize: CGSize = .zero
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            e.emitterShape = .rectangle
            e.emitterMode = .surface
            e.renderMode = .unordered
            layer.addSublayer(e)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.size != lastSize else { return }
            lastSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            e.frame = bounds
            e.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            e.emitterSize = bounds.size
            // ВАЖНО: частота задаётся при создании ячеек (через keyPath по индексу она не менялась — частиц не было)
            e.emitterCells = SpoilerDust.cells(area: bounds.width * bounds.height, color: .white, density: 0.55)
            e.beginTime = CACurrentMediaTime() - 1.5
            CATransaction.commit()
        }
    }
    func makeUIView(context: Context) -> V { V() }
    func updateUIView(_ uiView: V, context: Context) {}
}

/// Фото под спойлером: открывается своим нажатием, не открывая ветку
struct SpoilerMedia<Content: View>: View {
    let on: Bool
    @ViewBuilder var content: Content
    @State private var revealed = false

    var body: some View {
        let hidden = on && !revealed
        content
            .blur(radius: hidden ? 40 : 0, opaque: true)
            .overlay {
                if hidden {
                    ZStack {
                        Color.black.opacity(0.35)
                        SparkleDust()
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .highPriorityGesture(TapGesture().onEnded {
                withAnimation(.easeOut(duration: 0.45)) { revealed = true }
                Haptic.tap(.soft)
            }, including: hidden ? .all : .subviews)
            .accessibilityLabel(hidden ? "Скрытое фото. Нажмите, чтобы показать" : "")
    }
}

// MARK: - Исчезающая публикация (как в Threads)

/// Переключатель «курсор | призрак»: включено — белая капсула и чёрный кружок с призраком справа
struct EphemeralToggle: View {
    @Binding var on: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.32, bounce: 0.25)) { on.toggle() }
            Haptic.tap(.soft)
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? Color.white : Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(.white.opacity(on ? 0 : 0.15), lineWidth: 1))
                // подсказка на свободной половине
                Image(systemName: on ? "character.cursor.ibeam" : "face.dashed")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Color.black.opacity(0.7) : Color.oxHint)
                    .frame(width: 44, height: 44)
                    .frame(maxWidth: .infinity, alignment: on ? .leading : .trailing)
                    .padding(.horizontal, 6)
                Circle()
                    .fill(on ? Color.black : Color.white.opacity(0.22))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: on ? "face.dashed" : "character.cursor.ibeam")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(4)
            }
            .frame(width: 104, height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Исчезающая публикация включена" : "Сделать публикацию исчезающей")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Пунктирное «облачко» с хвостиком слева-сверху — для исчезающих публикаций
struct GhostBubble: View {
    var dashed = true
    var body: some View {
        GhostBubbleShape()
            .fill(Color.white.opacity(0.06))
            .overlay(GhostBubbleShape().stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [5, 4] : [])))
    }
}

struct GhostBubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        let rad = min(26, r.height / 2)
        var p = Path(roundedRect: r, cornerRadius: rad, style: .continuous)
        // хвостик
        var t = Path()
        t.move(to: CGPoint(x: r.minX + 14, y: r.minY + 2))
        t.addQuadCurve(to: CGPoint(x: r.minX - 2, y: r.minY - 8), control: CGPoint(x: r.minX + 2, y: r.minY - 1))
        t.addQuadCurve(to: CGPoint(x: r.minX + 26, y: r.minY), control: CGPoint(x: r.minX + 10, y: r.minY - 6))
        p.addPath(t)
        return p
    }
}
