import SwiftUI
import UIKit

// MARK: - Обновление после долгого фона
// Если OXION был в фоне 10 минут и дольше — при возвращении показываем фирменный экран загрузки
// и заново тянем профиль, подписку, достижения, тренировки и уведомления. Меньше 10 минут —
// пользователь просто возвращается на тот же экран. Авторизация (токен в Keychain) и открытые
// экраны не трогаются: экраны получают сигнал .oxionDataRefreshed и сами перечитывают данные.

extension Notification.Name {
    static let oxionDataRefreshed = Notification.Name("oxionDataRefreshed")
}

@MainActor
@Observable
final class AppResume {
    static let shared = AppResume()

    /// через сколько секунд в фоне нужно обновление
    static let threshold: TimeInterval = 10 * 60

    var showing = false
    var progress: Double = 0
    var step = ""
    var error: String?
    var finished = false

    private var running = false
    private weak var model: AppModel?

    private var backgroundAt: Date? {
        get { UserDefaults.standard.object(forKey: "resume.bgAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "resume.bgAt") }
    }

    func didEnterBackground() {
        backgroundAt = Date()
    }

    /// Вызывается при возврате в приложение
    func didBecomeActive(model: AppModel) {
        defer { backgroundAt = nil }
        guard let at = backgroundAt, model.me != nil, API.token != nil else { return }
        guard Date().timeIntervalSince(at) >= Self.threshold else { return }   // меньше 10 минут — ничего не делаем
        start(model: model)
    }

    func start(model: AppModel) {
        guard !running else { return }
        self.model = model
        running = true
        error = nil
        finished = false
        progress = 0
        step = "Подключаемся к OXION…"
        withAnimation(.easeOut(duration: 0.25)) { showing = true }
        OverlayWindows.shared.update()
        Task { await run() }
    }

    func retry() {
        guard let model, !running else { return }
        running = false
        start(model: model)
    }

    /// Продолжить со старыми данными
    func skip() {
        running = false
        close()
    }

    private func run() async {
        let started = Date()
        guard let model else { return }
        typealias Step = (title: String, critical: Bool, work: () async throws -> Void)
        let steps: [Step] = [
            ("Обновляем профиль…", true, { try await model.refreshMe() }),
            ("Синхронизируем тренировки…", false, {
                await WorkoutSync.flush()
                await WorkoutEngine.shared.syncActivity()
                await WidgetSync.refresh()
            }),
            ("Проверяем достижения…", false, { let _: AchResponse = try await API.call("/achievements") }),
            ("Проверяем подписку…", false, { await PremiumStatus.shared.refresh(force: true) }),
            ("Загружаем уведомления и записи…", false, {
                InboxStore.shared.refresh()
                if model.me?.mode == "trainer" { BookingStore.shared.refreshTrainer() }
            })
        ]
        for (i, s) in steps.enumerated() {
            step = s.title
            do {
                try await s.work()
            } catch {
                // нет сети или сервер не ответил: важный шаг — показываем ошибку с повтором
                if s.critical {
                    if let e = error as? APIError, e.status == 401 { running = false; close(); return }  // токен протух — экран входа покажет AppModel
                    withAnimation(.snappy) { self.error = error.localizedDescription }
                    Haptic.error()
                    running = false
                    return
                }
            }
            withAnimation(.easeInOut(duration: 0.35)) { progress = Double(i + 1) / Double(steps.count) }
        }
        // экран не должен мелькать — минимум ~0,9 с
        let spent = Date().timeIntervalSince(started)
        if spent < 0.9 { try? await Task.sleep(for: .seconds(0.9 - spent)) }
        step = "Готово"
        withAnimation(.spring(duration: 0.4)) { finished = true }
        NotificationCenter.default.post(name: .oxionDataRefreshed, object: nil)
        Haptic.success()
        try? await Task.sleep(for: .milliseconds(450))
        running = false
        close()
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.35)) { showing = false }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            OverlayWindows.shared.update()
        }
    }
}

/// ответ /achievements — нужен только для проверки, что сервер отдаёт данные
private struct AchResponse: Decodable { let done: Int? }

extension View {
    /// Перечитать данные экрана после долгого фона
    func onOxionRefresh(_ action: @escaping () async -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .oxionDataRefreshed)) { _ in
            Task { await action() }
        }
    }
}

// MARK: - Экран загрузки

struct ResumeLoadingView: View {
    @State private var r = AppResume.shared
    @State private var glow = false
    @State private var appear = false

    var body: some View {
        ZStack {
            // тёмный фон с мягким мятным свечением
            Color(red: 0.02, green: 0.03, blue: 0.03).ignoresSafeArea()
            RadialGradient(colors: [Color.lime.opacity(glow ? 0.28 : 0.14), .clear],
                           center: .center, startRadius: 10, endRadius: glow ? 420 : 300)
                .ignoresSafeArea()
                .blur(radius: 30)
            LinearGradient(colors: [.clear, Color.lime.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()
                FlameMark(size: 96)
                    .scaleEffect(r.finished ? 1.08 : (appear ? 1 : 0.8))
                    .shadow(color: Color.lime.opacity(0.45), radius: glow ? 40 : 22)
                Text(verbatim: "OXION")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(LinearGradient(colors: [.white, Color.lime], startPoint: .leading, endPoint: .trailing))
                    .opacity(appear ? 1 : 0)
                Spacer()
                card
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
                    .offset(y: appear ? 0 : 40)
                    .opacity(appear ? 1 : 0)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appear = true }
            withAnimation(.easeInOut(duration: 1.8).repeatForever()) { glow = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Обновляем данные OXION"))
    }

    @ViewBuilder
    private var card: some View {
        VStack(spacing: 14) {
            if let e = r.error {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.lime)
                Text("Не удалось обновить данные").font(.headline).foregroundStyle(.white)
                Text(e).font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center).lineLimit(3)
                HStack(spacing: 10) {
                    Button { AppResume.shared.skip() } label: {
                        Text("Продолжить").frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.glass)
                    Button { AppResume.shared.retry() } label: {
                        Label("Повторить", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime)
                    .foregroundStyle(Color.onLime)
                }
                .font(.headline)
            } else {
                HStack {
                    Text(r.step)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: r.step)
                    Spacer()
                    Text(verbatim: "\(Int(r.progress * 100))%")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color.lime)
                        .contentTransition(.numericText())
                }
                ResumeProgressBar(value: r.progress)
                    .frame(height: 8)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Color.lime.opacity(0.08)), in: .rect(cornerRadius: 28))
    }
}

/// Полоска прогресса с бегущим бликом
struct ResumeProgressBar: View {
    let value: Double
    @State private var shine: CGFloat = -1

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Color.lime.opacity(0.7), Color.lime], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, g.size.width * value))
                    .overlay {
                        LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 50)
                            .offset(x: shine * g.size.width)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(Capsule())
                    .shadow(color: Color.lime.opacity(0.6), radius: 6)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { shine = 1 }
        }
    }
}

// MARK: - Отдельные окна поверх приложения
// Экран загрузки и плашка под Dynamic Island живут в своих UIWindow — так они видны поверх
// листов и полноэкранных окон, не ломают навигацию и не перехватывают касания.

@MainActor
final class OverlayWindows {
    static let shared = OverlayWindows()
    private var resumeWindow: UIWindow?
    private var islandWindow: OxPassWindow?
    private weak var scene: UIWindowScene?

    func install() {
        guard let s = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        if scene !== s {
            scene = s
            resumeWindow = nil
            islandWindow = nil
        }
        update()
    }

    func update() {
        guard let scene else { return }
        // экран загрузки
        if AppResume.shared.showing {
            if resumeWindow == nil {
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                let vc = UIHostingController(rootView: ResumeLoadingView())
                vc.view.backgroundColor = .clear
                w.rootViewController = vc
                resumeWindow = w
            }
            resumeWindow?.isHidden = false
        } else if let w = resumeWindow, !w.isHidden {
            w.isHidden = true
            resumeWindow = nil
        }
        updateIsland()
    }

    /// Плашка с логотипом под Dynamic Island / вырезом
    func updateIsland() {
        guard let scene else { return }
        let enabled = UserDefaults.standard.object(forKey: "island.brand") as? Bool ?? true
        guard enabled, let rect = IslandGeometry.rect(in: scene) else {
            islandWindow?.isHidden = true
            islandWindow = nil
            return
        }
        if islandWindow == nil {
            let w = OxPassWindow(windowScene: scene)
            w.windowLevel = .statusBar + 1
            w.backgroundColor = .clear
            let vc = UIHostingController(rootView: IslandBrandView(kind: rect.kind))
            // окно лежит в зоне выреза: без этого SwiftUI сдвигает содержимое вниз на высоту «безопасной зоны»
            vc.safeAreaRegions = []
            vc.view.backgroundColor = .clear
            vc.view.insetsLayoutMarginsFromSafeArea = false
            w.rootViewController = vc
            islandWindow = w
        }
        (islandWindow?.rootViewController as? UIHostingController<IslandBrandView>)?.rootView = IslandBrandView(kind: rect.kind)
        islandWindow?.frame = rect.frame
        islandWindow?.isHidden = false
    }
}

/// Окно, которое никогда не забирает касания
final class OxPassWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

// MARK: - Плашка под Dynamic Island (как у 2ГИС)
// Чёрная капсула точно под «островом» с мятным огоньком и надписью OXION.
// На самом iPhone её закрывает аппаратный вырез — пользователь видит обычный Dynamic Island.
// На скриншотах iOS вырез не рисуется, поэтому там остаётся логотип OXION.
// Это обычный контент приложения в системной зоне: никаких приватных API.

enum IslandGeometry {
    enum Kind { case island, notch }

    /// Код модели: "iPhone17,2" и т.п. (в симуляторе — модель, которую он изображает)
    static let model: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()

    /// Верх Dynamic Island от края экрана (pt) по модели. nil — у модели «чёлка» или выреза нет.
    /// 14 Pro, 15, 15 Plus, 15 Pro (Max), 16, 16 Plus — 11 pt; 16 Pro (Max), 17, 17 Pro (Max), Air — 14 pt.
    static func islandTop(for m: String) -> CGFloat?? {
        switch m {
        case "iPhone15,2", "iPhone15,3",                       // 14 Pro, 14 Pro Max
             "iPhone15,4", "iPhone15,5",                       // 15, 15 Plus
             "iPhone16,1", "iPhone16,2",                       // 15 Pro, 15 Pro Max
             "iPhone17,3", "iPhone17,4":                       // 16, 16 Plus
            return .some(11)
        case "iPhone17,1", "iPhone17,2",                       // 16 Pro, 16 Pro Max
             "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4":   // 17 Pro, 17 Pro Max, 17, Air
            return .some(14)
        case "iPhone17,5":                                     // 16e — «чёлка»
            return .some(nil)
        default:
            if m.hasPrefix("iPhone10") || m.hasPrefix("iPhone11") || m.hasPrefix("iPhone12")
                || m.hasPrefix("iPhone13") || m.hasPrefix("iPhone14") { return .some(nil) }   // X … 14 — «чёлка» или без выреза
            return nil                                          // неизвестная (новая) модель — решаем по безопасной зоне
        }
    }

    static func rect(in scene: UIWindowScene) -> (frame: CGRect, kind: Kind)? {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
        guard let win = scene.windows.first(where: { !($0 is OxPassWindow) && $0.windowLevel == .normal }) ?? scene.windows.first else { return nil }
        let size = win.bounds.size
        guard size.height > size.width else { return nil }               // только портрет
        let top: CGFloat
        switch islandTop(for: model) {
        case .some(.some(let t)): top = t
        case .some(.none): return nil                                     // «чёлка» — не показываем
        case .none:
            // новая модель: есть Dynamic Island, если безопасная зона сверху ≥ 59 pt
            let inset = win.safeAreaInsets.top
            guard inset >= 59 else { return nil }
            top = inset >= 62 ? 14 : 11
        }
        // сам остров ≈126×37 pt; капсула заметно меньше и по центру острова —
        // со всех сторон ~3 pt запаса, чтобы ни один пиксель не выглядывал из-под выреза
        let islandW: CGFloat = 126, islandH: CGFloat = 37
        let w: CGFloat = 118, h: CGFloat = 31
        let x = (size.width - w) / 2
        let y = top + (islandH - h) / 2
        _ = islandW
        return (CGRect(x: x, y: y, width: w, height: h), .island)
    }
}

struct IslandBrandView: View {
    let kind: IslandGeometry.Kind

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack {
                // фирменная капсула, как у 2ГИС: на экране её целиком закрывает остров
                Group {
                    if kind == .island {
                        Capsule().fill(Color.lime)
                    } else {
                        UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(Color.lime)
                    }
                }
                HStack(spacing: 6) {
                    // мятный огонёк в тёмном кружке
                    Image(systemName: "flame.fill")
                        .font(.system(size: h * 0.42, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.62, green: 1, blue: 0.78), Color.lime],
                                                        startPoint: .top, endPoint: .bottom))
                        .frame(width: h * 0.74, height: h * 0.74)
                        .background(Circle().fill(Color.black))
                    Text(verbatim: "OXION")
                        .font(.system(size: h * 0.42, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.black)
                }
                .offset(y: kind == .notch ? -1 : 0)
            }
            .frame(width: g.size.width, height: h)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
