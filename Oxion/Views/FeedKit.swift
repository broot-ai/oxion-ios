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
            let r: R = try await API.call("/feed/posts/\(postId)/copy", method: "POST", body: ["date": f.string(from: Date())])
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
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            e.emitterShape = .rectangle
            e.emitterMode = .surface
            e.renderMode = .additive
            let c = CAEmitterCell()
            c.contents = SpoilerDust.dot
            c.contentsScale = UIScreen.main.scale
            c.color = UIColor.white.cgColor
            c.lifetime = 1.6
            c.lifetimeRange = 0.8
            c.velocity = 3
            c.velocityRange = 4
            c.emissionRange = .pi * 2
            c.scale = 0.9
            c.scaleRange = 0.5
            c.alphaRange = 0.6
            c.alphaSpeed = -0.45
            e.emitterCells = [c]
            layer.addSublayer(e)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0 else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            e.frame = bounds
            e.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            e.emitterSize = bounds.size
            e.setValue(Float(max(40, bounds.width * bounds.height / 260)), forKeyPath: "emitterCells.0.birthRate")
            CATransaction.commit()
            if e.beginTime == 0 { e.beginTime = CACurrentMediaTime() - 1.5 }
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
            .blur(radius: hidden ? 34 : 0, opaque: true)
            .overlay {
                if hidden {
                    ZStack {
                        Color.black.opacity(0.18)
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
