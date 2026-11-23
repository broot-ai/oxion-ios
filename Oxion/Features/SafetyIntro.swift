import SwiftUI
import SensitiveContentAnalysis
import AVFoundation
import CoreLocation

// Безопасность и «экраны знакомства» в стиле iOS:
// • OxIntroSheet — большая иконка, заголовок, текст, «Продолжить» / «Не сейчас»
// • OxSettingsHeader — карточка-шапка экрана настроек (иконка в плитке, заголовок, описание)
// • SensitiveGuard — размытие откровенных фото в чатах и ленте (Apple SensitiveContentAnalysis, прямо на iPhone)
// • SafetyView — «Конфиденциальность и безопасность»

// MARK: - Шапка экрана настроек

struct OxSettingsHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .shadow(color: tint.opacity(0.25), radius: 12, y: 4)
            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

extension View {
    /// Шапка-карточка первой строкой списка настроек
    func oxHeaderRow() -> some View {
        listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Экран знакомства

enum OxIntro: String, CaseIterable {
    case sensitive, camera, location, notifications

    var icon: String {
        switch self {
        case .sensitive: "exclamationmark.bubble.fill"
        case .camera: "qrcode.viewfinder"
        case .location: "location.circle.fill"
        case .notifications: "bell.badge.fill"
        }
    }
    var tint: Color {
        switch self {
        case .sensitive: Color(hex: 0x3B8CF5)
        case .camera: Color.lime
        case .location: Color(hex: 0x3B8CF5)
        case .notifications: Color(hex: 0xFF5A4E)
        }
    }
    var title: String {
        switch self {
        case .sensitive: "Защита от откровенных изображений"
        case .camera: "Сканер QR-кодов"
        case .location: "Спортивные места рядом"
        case .notifications: "Не пропускайте важное"
        }
    }
    var lead: String {
        switch self {
        case .sensitive: "Oxion размывает фото, которые могут быть откровенными, прежде чем вы их увидите — в чатах и в ленте."
        case .camera: "Наведите камеру на QR-код тренера, зала или друга — Oxion сразу откроет нужную страницу."
        case .location: "Покажем залы, площадки и магазины спортпитания рядом с вами."
        case .notifications: "Сообщения от тренера, напоминания о тренировках и ответы в ленте — вовремя."
        }
    }
    var details: String {
        switch self {
        case .sensitive: "Проверка идёт прямо на iPhone с помощью технологии Apple. Фото никуда не отправляются, у Oxion и Apple нет к ним доступа. Размытое фото всегда можно открыть одним нажатием."
        case .camera: "Камера работает только пока открыт сканер. Изображение не сохраняется и не отправляется."
        case .location: "Геопозиция нужна только пока открыта карта. Мы не храним историю ваших перемещений."
        case .notifications: "Что именно присылать, можно настроить в Профиле → Уведомления."
        }
    }
    var points: [(String, String)] {
        switch self {
        case .sensitive: [("eye.slash.fill", "Размытие до просмотра"), ("iphone", "Анализ только на устройстве"), ("hand.raised.fill", "Вы решаете, что открыть")]
        case .camera: [("bolt.fill", "Мгновенное распознавание"), ("photo.on.rectangle", "Можно выбрать QR из фото"), ("flashlight.on.fill", "Фонарик в темноте")]
        case .location: [("dumbbell.fill", "Залы и площадки"), ("bag.fill", "Магазины, подтверждённые Oxion"), ("lock.fill", "Позиция не сохраняется")]
        case .notifications: [("message.fill", "Сообщения и группы"), ("alarm.fill", "Напоминания о тренировках"), ("slider.horizontal.3", "Гибкая настройка")]
        }
    }

    private var key: String { "intro.seen.\(rawValue)" }
    var seen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct OxIntroSheet: View {
    let intro: OxIntro
    var primary = "Продолжить"
    var onContinue: () -> Void
    var onLater: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: intro.icon)
                        .font(.system(size: 76))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(intro.tint.gradient)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)
                        .padding(.bottom, 18)
                        .scaleEffect(shown ? 1 : 0.6)
                        .opacity(shown ? 1 : 0)
                        .symbolEffect(.bounce, value: shown)
                    Text(intro.title)
                        .font(.system(size: 28, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(intro.lead)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(intro.points.enumerated()), id: \.offset) { i, p in
                            HStack(spacing: 14) {
                                Image(systemName: p.0)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(intro.tint)
                                    .frame(width: 38, height: 38)
                                    .background(intro.tint.opacity(0.14), in: Circle())
                                Text(p.1).font(.body.weight(.medium))
                            }
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 12)
                            .animation(.spring(duration: 0.5).delay(0.15 + Double(i) * 0.07), value: shown)
                        }
                    }
                    .padding(.vertical, 6)
                    Text(intro.details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    intro.seen = true
                    onContinue()
                } label: {
                    Text(primary).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(intro.tint == Color.lime ? Color.lime : intro.tint)
                .foregroundStyle(intro.tint == Color.lime ? Color.onLime : .white)
                Button {
                    intro.seen = true
                    onLater()
                } label: {
                    Text("Не сейчас").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 8)
            .background(alignment: .top) {
                LinearGradient(colors: [Color.oxBg.opacity(0), Color.oxBg], startPoint: .top, endPoint: .bottom)
                    .frame(height: 30).offset(y: -30).allowsHitTesting(false)
            }
        }
        .background(Color.oxBg)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.1)) { shown = true } }
    }
}

private struct OxIntroOnce: ViewModifier {
    let intro: OxIntro
    var when: () -> Bool = { true }
    var onContinue: () -> Void = {}
    var onLater: () -> Void = {}
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !intro.seen, when() else { return }
                try? await Task.sleep(for: .milliseconds(600))
                show = true
            }
            .sheet(isPresented: $show) {
                OxIntroSheet(intro: intro, onContinue: { show = false; onContinue() }, onLater: { show = false; onLater() })
            }
    }
}

extension View {
    /// Один раз показать экран знакомства с функцией
    func oxIntro(_ intro: OxIntro, when: @escaping () -> Bool = { true }, onContinue: @escaping () -> Void = {}, onLater: @escaping () -> Void = {}) -> some View {
        modifier(OxIntroOnce(intro: intro, when: when, onContinue: onContinue, onLater: onLater))
    }
}

// MARK: - Откровенные фото

@MainActor
final class SensitiveGuard {
    static let shared = SensitiveGuard()
    static let enabledKey = "ox.sensitive.blur"

    private let analyzer = SCSensitivityAnalyzer()
    private var cache: [URL: Bool] = [:]

    /// Пользователь включил размытие в Oxion (по умолчанию — да)
    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// iOS разрешает анализ: включено «Предупреждение о деликатном контенте» или «Безопасность общения»
    var systemReady: Bool { analyzer.analysisPolicy != .disabled }
    var descriptive: Bool { analyzer.analysisPolicy == .descriptiveInterventions }

    func cached(_ url: URL) -> Bool? { cache[url] }

    func check(_ image: UIImage, url: URL) async -> Bool {
        if let c = cache[url] { return c }
        guard enabled, systemReady, let cg = image.cgImage else { return false }
        let r = (try? await analyzer.analyzeImage(cg))?.isSensitive ?? false
        cache[url] = r
        return r
    }
}

/// Размытие поверх фото с кнопкой «Показать»
struct SensitiveCover: View {
    var compact = false
    var onShow: () -> Void
    @State private var ask = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: compact ? 6 : 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: compact ? 20 : 28, weight: .semibold))
                if !compact {
                    Text("Может быть откровенным").font(.subheadline.bold())
                    Text("Фото скрыто, чтобы вы решили сами").font(.caption).foregroundStyle(.secondary)
                }
                Button("Показать") { ask = true }
                    .font(.subheadline.bold())
                    .buttonStyle(.glass)
                    .controlSize(compact ? .small : .regular)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .confirmationDialog("Показать фото?", isPresented: $ask, titleVisibility: .visible) {
            Button("Показать") { withAnimation(.easeOut(duration: 0.35)) { onShow() } }
            Button("Не показывать", role: .cancel) {}
        } message: {
            Text("Это фото может содержать обнажённое тело. Вы можете не смотреть его — это нормально.")
        }
    }
}

// MARK: - Настройки «Конфиденциальность и безопасность»

struct SafetyView: View {
    @AppStorage(SensitiveGuard.enabledKey) private var blur = true
    @Environment(\.openURL) private var openURL
    @State private var ready = SensitiveGuard.shared.systemReady
    @State private var cam = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var loc = CLLocationManager().authorizationStatus
    @State private var intro: OxIntro?

    var body: some View {
        List {
            Section {
                OxSettingsHeader(icon: "hand.raised.fill", tint: Color(hex: 0x3B8CF5),
                                 title: "Конфиденциальность и безопасность",
                                 text: "Управляйте тем, что видите в Oxion, и доступом приложения к камере и геопозиции.")
                    .oxHeaderRow()
            }

            Section {
                Toggle(isOn: $blur) {
                    row("eye.slash.fill", Color(hex: 0x3B8CF5), "Размывать откровенные фото", sub: "Чаты и лента")
                }
                .tint(Color.lime)
                if blur && !ready {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Нужно включить в iOS", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("Распознавание работает через Apple. Откройте Настройки → Конфиденциальность и безопасность → Предупреждение о деликатном контенте и включите его.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Открыть Настройки") { open() }.font(.subheadline.bold())
                    }
                    .padding(.vertical, 4)
                }
                Button { intro = .sensitive } label: {
                    row("questionmark.circle.fill", Color(hex: 0x8E8E93), "Как это работает", sub: nil)
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Деликатный контент")
            } footer: {
                Text(ready ? "Включено в iOS. Анализ идёт на iPhone — фото никуда не отправляются." : "Пока предупреждение в iOS выключено, Oxion не может распознавать такие фото.")
            }

            Section("Доступ") {
                Button { cam == .notDetermined ? (intro = .camera) : open() } label: {
                    row("camera.fill", Color(hex: 0x58C770), "Камера", value: label(cam))
                }
                .foregroundStyle(.primary)
                Button { loc == .notDetermined ? (intro = .location) : open() } label: {
                    row("location.fill", Color(hex: 0x3478F6), "Геопозиция", value: label(loc))
                }
                .foregroundStyle(.primary)
            }

            Section {
                Button("Снова показывать подсказки") {
                    OxIntro.allCases.forEach { $0.seen = false }
                    Haptic.success()
                    OxAlert.show(icon: "checkmark.circle.fill", tint: .green, title: "Готово", message: "Экраны знакомства покажутся снова")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
        .sheet(item: $intro) { i in
            OxIntroSheet(intro: i, onContinue: {
                intro = nil
                Task { await request(i) }
            }, onLater: { intro = nil })
        }
    }

    private func refresh() {
        ready = SensitiveGuard.shared.systemReady
        cam = AVCaptureDevice.authorizationStatus(for: .video)
        loc = CLLocationManager().authorizationStatus
    }

    private func request(_ i: OxIntro) async {
        switch i {
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .location: CLLocationManager().requestWhenInUseAuthorization()
        case .sensitive: blur = true
        case .notifications: break
        }
        try? await Task.sleep(for: .milliseconds(500))
        refresh()
    }

    private func open() {
        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
    }

    private func label(_ s: AVAuthorizationStatus) -> String {
        switch s {
        case .authorized: "Разрешено"
        case .denied, .restricted: "Запрещено"
        default: "Не спрашивали"
        }
    }

    private func label(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: "При использовании"
        case .denied, .restricted: "Запрещено"
        default: "Не спрашивали"
        }
    }

    private func row(_ icon: String, _ c: Color, _ title: String, sub: String? = nil, value: String? = nil) -> some View {
        HStack(spacing: 14) {
            OxRowIcon(icon: icon, tint: c)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let sub { Text(sub).font(.footnote).foregroundStyle(.secondary) }
            }
            if let value {
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }
}

extension OxIntro: Identifiable { var id: String { rawValue } }
