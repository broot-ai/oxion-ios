import SwiftUI
import CoreSpotlight
import Observation

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    /// Цвет, который сам меняется для светлой и тёмной темы
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { t in
            let h = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        })
    }
    /// Цвета как в PWA Oxion (app.css) + светлая тема
    static let lime = Color(hex: 0xB2EE37)                              // заливки: кнопки, пузыри — яркий в обеих темах
    static let limeInk = Color(light: 0x4E8A06, dark: 0xB2EE37)          // текст и значки «лаймом» — темнее на светлом фоне
    static let onLime = Color(hex: 0x0F1012)                            // текст на лаймовой заливке
    static let oxBg = Color(light: 0xF2F2F7, dark: 0x0F1012)
    static let oxCard = Color(light: 0xFFFFFF, dark: 0x18191C)
    static let oxCard2 = Color(light: 0xE9EAEE, dark: 0x202124)
    static let oxHint = Color(light: 0x7C7C80, dark: 0x8A8A83)
    static let oxBubble = Color(light: 0xFFFFFF, dark: 0x1F2124)        // чужой пузырь в чате
}

enum OxTheme: String, CaseIterable {
    case system, light, dark
    var title: String { switch self { case .system: "Как на iPhone"; case .light: "Светлая"; case .dark: "Тёмная" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    static var current: OxTheme { OxTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "system") ?? .system }
    var uiStyle: UIUserInterfaceStyle { switch self { case .system: .unspecified; case .light: .light; case .dark: .dark } }

    /// Тема ставится на все окна приложения. «Как на iPhone» — окна сами следуют за системой
    /// (через preferredColorScheme это не работает: после ручной темы iOS «залипает»).
    @MainActor static func apply() {
        let style = current.uiStyle
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows where w.overrideUserInterfaceStyle != style {
                UIView.transition(with: w, duration: 0.3, options: .transitionCrossDissolve) {
                    w.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}

/// Применяет выбранную тему (используется и в отдельных окнах — алерты)
struct OxThemeModifier: ViewModifier {
    @AppStorage("theme") private var theme = OxTheme.system.rawValue
    func body(content: Content) -> some View {
        content
            .onAppear { OxTheme.apply() }
            .onChange(of: theme) { OxTheme.apply() }
    }
}

@main
struct OxionApp: App {
    @UIApplicationDelegateAdaptor(OxAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppSettings.register()
        OxAlarms.attach()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modifier(AppTextSize())
                // ссылки открываются во встроенном браузере, как в Telegram
                .modifier(InAppBrowserLinks())
                .onReceive(NotificationCenter.default.publisher(for: .oxionOpenRoute)) { n in
                    if let r = n.object as? String { model.handle(route: r) }
                }
                .onOpenURL { url in
                    if let r = ProfileLink.route(for: url) { model.handle(route: r); return }
                    // ссылки из виджетов и Live Activity: oxion://diary, oxion://trainer/15 …
                    let route = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/")
                    model.handle(route: route)
                }
                // нажатие на OXION в поиске iPhone (Spotlight)
                .onContinueUserActivity(CSSearchableItemActionType) { a in
                    if let r = SpotlightIndex.route(for: a) { model.handle(route: r) }
                }
                // универсальные ссылки …/clip/trainer/34, …/clip/tag/<id> (QR и NFC в зале), если OXION уже установлен
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    guard let u = a.webpageURL else { return }
                    if let r = ProfileLink.route(for: u) { model.handle(route: r); return }
                    let p = u.pathComponents.filter { $0 != "/" }
                    guard let i = p.firstIndex(of: "clip"), p.count > i + 2 else { return }
                    switch p[i + 1] {
                    case "trainer": model.handle(route: "trainer/" + p[i + 2])
                    case "tag": model.handle(route: "checkin/" + p[i + 2])
                    default: model.handle(route: "diary")
                    }
                }
                .modifier(OxThemeModifier())
                .tint(.lime)
                .onReceive(NotificationCenter.default.publisher(for: .oxionUnauthorized)) { _ in
                    model.logoutLocal()
                }
                .onReceive(NotificationCenter.default.publisher(for: .oxionRoute)) { n in
                    if let r = n.object as? String {
                        _ = PendingRoute.take()
                        model.handle(route: r)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                    Task { try? await Task.sleep(for: .milliseconds(350)); OverlayWindows.shared.updateIsland() }
                }
                .task {
                    // окна поверх приложения: плашка под Dynamic Island и экран обновления
                    try? await Task.sleep(for: .milliseconds(300))
                    OverlayWindows.shared.install()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        OverlayWindows.shared.install()
                        AppResume.shared.didBecomeActive(model: model)
                    }
                    if scenePhase == .active, let r = PendingRoute.take() { model.handle(route: r) }
                    if scenePhase == .background {
                        AppResume.shared.didEnterBackground()
                        Task { await SmartNotify.reschedule() }
                        OxAppDelegate.schedule()
                        QuickActions.update()
                    }
                    if scenePhase == .active, model.me != nil {
                        Task {
                            await WorkoutSync.flush()
                            await WorkoutEngine.shared.syncActivity()
                        }
                    }
                    // свернули приложение — обновляем виджет свежими данными
                    if scenePhase == .background, model.me != nil {
                        Task { await WidgetSync.refresh() }
                        if HealthKitManager.shared.enabled { Task { await HealthKitManager.shared.refreshAndSync() } }
                    }
                }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case loggedOut
        case ready
        case failed(String)
    }

    var phase: Phase = .loading
    var isLoading: Bool { if case .loading = phase { return true } else { return false } }
    var me: Me?
    var meta: Meta?
    var selectedTab: AppTab = .home
    var showActiveWorkout = false
    var openTrainerId: Int?
    var showFavorites = false
    /// Экраны поверх вкладок (из меню иконки, Siri, ссылок)
    var sheet: AppSheet?
    var showVision = false
    var showMuscles = false
    var showMap = false
    var showCatalog = false
    var offerLoginKey = false
    var exerciseBox: IdBox?
    /// профиль, открытый по ссылке …/@имя или упоминанию @имя
    var profileBox: IdBox?

    struct IdBox: Identifiable { let id: Int }

    enum AppSheet: String, Identifiable {
        case qr, compose, progress, permissions, run, scanner, music, screenLock, devices, program, status, whatsNew
        var id: String { rawValue }
    }

    /// Переходы из виджетов, Пункта управления, Siri: oxion://home, diary, workout, trainers, trainer/ID, favorites, chats, feed
    func handle(route: String) {
        let parts = route.split(separator: "/").map(String.init)
        switch parts.first ?? "" {
        case "workout" where parts.count > 1 && parts[1] == "legs":
            selectedTab = .diary
            Task { await quickWorkout(title: "Ноги", groups: ["legs"]) }
        case "workout":
            if WorkoutEngine.shared.state != nil { showActiveWorkout = true } else { selectedTab = .diary }
        case "diary": selectedTab = .diary
        case "feed": selectedTab = .feed
        case "chats": selectedTab = .chats
        case "trainers": selectedTab = .trainers
        case "favorites":
            selectedTab = .trainers
            showFavorites = true
        case "checkin" where parts.count > 1:
            // отметка в клубе по ссылке с NFC-метки / QR
            let tag = "oxion:" + parts[1]
            Task {
                do {
                    let r: CheckinResult = try await API.call("/checkin", method: "POST", body: ["tag": tag])
                    OxHaptics.play(.setDone)
                    OxAlert.show(icon: "checkmark.seal.fill", title: r.repeat == true ? "Уже отмечены" : "Посещение засчитано",
                                 message: "\(r.place ?? "Клуб") · в этом месяце: \(r.month ?? 0)")
                } catch {
                    OxAlert.error(error.localizedDescription)
                }
            }
        case "qr": sheet = .qr
        case "compose":
            selectedTab = .feed
            sheet = .compose
        case "progress": sheet = .progress
        case "permissions": sheet = .permissions
        case "vision": showVision = true
        case "muscles", "body": showMuscles = true
        case "map": showMap = true
        case "program", "plan": sheet = .program
        case "status": sheet = .status
        case "whatsnew": sheet = .whatsNew
        case "exercises", "catalog": showCatalog = true
        case "run": sheet = .run
        case "devices": sheet = .devices
        case "book":
            Task {
                guard let my: CoachMy = try? await API.call("/coach/my"),
                      let t = (my.trainers ?? []).first(where: { $0.status == "active" }) ?? my.trainers?.first else {
                    selectedTab = .trainers
                    OxAlert.show(icon: "person.crop.circle.badge.questionmark", title: "Сначала выберите тренера", message: "Найдите тренера в каталоге — запись появится в его анкете")
                    return
                }
                bookTrainer = IdBox(id: t.id)
                bookTrainerName = t.name ?? "Тренер"
            }
        case "rest":
            let sec = parts.count > 1 ? Int(parts[1]) ?? 90 : 90
            Task {
                await OxAlarms.scheduleRest(seconds: sec, next: "")
                OxAlert.show(icon: "timer", title: "Отдых \(sec) с", message: "Сработает даже в беззвучном режиме")
            }
        case "exercise" where parts.count > 1:
            if let id = Int(parts[1]) { exerciseBox = IdBox(id: id) }
        case "trainer":
            selectedTab = .trainers
            if parts.count > 1, let id = Int(parts[1]), id > 0 { openTrainerId = id }
        case "user" where parts.count > 1:
            if let id = Int(parts[1]), id > 0 { profileBox = IdBox(id: id) }
        case "u" where parts.count > 1:
            let name = parts[1].replacingOccurrences(of: "@", with: "")
            struct R: Decodable { let id: Int }
            Task {
                do {
                    let r: R = try await API.call("/usernames/resolve/" + name)
                    OxHaptics.play(.select)
                    profileBox = IdBox(id: r.id)
                } catch {
                    OxAlert.show(icon: "person.crop.circle.badge.questionmark", tint: .orange,
                                 title: String(localized: "Пользователь не найден"),
                                 message: "@\(name) — " + String(localized: "возможно, имя изменили или освободили."))
                }
            }
        default: selectedTab = .home
        }
    }
    var trainerQuery = ""
    var workoutBox: IdBox?
    var bookTrainer: IdBox?
    var bookTrainerName = "Тренер"

    /// Быстро создать тренировку на сегодня (из Siri / «Команд») и открыть её
    func quickWorkout(title: String, groups: [String]) async {
        do {
            let w: WorkoutFull = try await API.call("/workouts", method: "POST",
                                                    body: ["date": RU.dayFormatter.string(from: Date()), "title": title, "groups": groups])
            workoutBox = IdBox(id: w.id)
            FX.play(.energyPulse)
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    func start() async {
        if API.token == nil {
            phase = .loggedOut
            return
        }
        await loadMe()
    }

    /// Тихо обновить профиль (без экрана загрузки и без выхода из аккаунта при сбое сети)
    func refreshMe() async throws {
        let m: Me = try await API.call("/me")
        me = m
        if let mt: Meta = try? await API.call("/meta") { meta = mt }
        Task { await Catalog.refresh { self.muscleName($0) } }
    }

    func loadMe() async {
        if me == nil { phase = .loading }
        do {
            let m: Me = try await API.call("/me")
            me = m
            Task { await WidgetSync.refresh() }
            if meta == nil {
                let mt: Meta? = try? await API.call("/meta")
                meta = mt
            }
            phase = .ready
            Task { await Catalog.refresh { self.muscleName($0) } }
        } catch let e as APIError where e.status == 401 {
            logoutLocal()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func loggedIn(token: String) async {
        API.token = token
        Haptic.success()
        await loadMe()
        await PushRegistrar.upload()
        if LoginKeyOfferSheet.shouldOffer {
            try? await Task.sleep(for: .seconds(1.2))
            offerLoginKey = true
        }
    }

    func logout() async {
        await PushRegistrar.remove()
        let _: OK? = try? await API.call("/logout", method: "POST")
        logoutLocal()
    }

    func logoutLocal() {
        WidgetSync.clear()
        SpotlightIndex.clear()
        API.token = nil
        me = nil
        phase = .loggedOut
    }

    func muscleName(_ key: String?) -> String {
        guard let key else { return "" }
        return meta?.muscles?.first(where: { $0.key == key })?.name ?? Muscles.fallback[key] ?? key
    }
}

enum Muscles {
    static let fallback: [String: String] = [
        "chest": "Грудь", "back": "Спина", "shoulders": "Дельты", "biceps": "Бицепс",
        "triceps": "Трицепс", "legs": "Ноги", "glutes": "Ягодицы", "abs": "Пресс", "cardio": "Кардио"
    ]
    static let order = ["chest", "back", "shoulders", "biceps", "triceps", "legs", "glutes", "abs", "cardio"]
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                SplashView()
            case .loggedOut:
                LoginView()
            case .failed(let message):
                ErrorStateView(message: message) {
                    Task { await model.loadMe() }
                }
            case .ready:
                if model.me?.registered == false {
                    NotRegisteredView()
                } else {
                    MainTabView()
                }
            }
        }
        .task {
            AlertWindow.attach()
            await model.start()
        }
    }
}

enum AppTab: Hashable {
    case home, trainers, feed, diary, chats
}

/// Вкладки как в PWA Oxion: Главная, Тренеры, Лента, Дневник, Чаты (Магазин и Профиль — с Главной).
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var chats = ChatsStore()
    @State private var showCard = false
    @State private var engine = WorkoutEngine.shared
    @State private var focusHideFeed = OxFocus.hideFeed
    @State private var hold: TabHold.Press?
    @State private var scanning = false
    @State private var welcome = false
    @State private var scanUser: AppModel.IdBox?
    @Environment(\.openURL) private var openURL

    private var tabOrder: [AppTab] {
        focusHideFeed ? [.home, .trainers, .diary, .chats] : [.home, .trainers, .feed, .diary, .chats]
    }

    private func holdActions(_ t: AppTab) -> [TabHoldAction] {
        switch t {
        case .home:
            return [
                .init(title: "Начать тренировку", icon: "play.fill") { model.handle(route: "workout") },
                .init(title: "Моя визитка и QR", icon: "qrcode") { showCard = true },
                .init(title: "Сканировать QR-код", icon: "qrcode.viewfinder") { scanning = true },
                .init(title: "Прогресс тела", icon: "chart.line.uptrend.xyaxis") { model.sheet = .progress },
            ]
        case .trainers:
            return [
                .init(title: "Избранные тренеры", icon: "heart.fill") { model.handle(route: "favorites") },
                .init(title: "Найти тренера", icon: "magnifyingglass") { model.selectedTab = .trainers },
                .init(title: "Сканировать QR тренера", icon: "qrcode.viewfinder") { scanning = true },
            ]
        case .feed:
            return [
                .init(title: "Новая публикация", icon: "square.and.pencil") { model.handle(route: "compose") },
                .init(title: "Мой профиль в ленте", icon: "person.crop.circle") { if let id = model.me?.id { model.profileBox = AppModel.IdBox(id: id) } },
                .init(title: "Моя визитка и QR", icon: "qrcode") { showCard = true },
            ]
        case .diary:
            return [
                .init(title: "Начать тренировку", icon: "play.fill") { model.handle(route: "workout") },
                .init(title: "Пробежка с GPS", icon: "figure.run") { model.sheet = .run },
                .init(title: "Сканер этикеток", icon: "text.viewfinder") { model.sheet = .scanner },
                .init(title: "Музыка для тренировки", icon: "music.note") { model.sheet = .music },
            ]
        case .chats:
            return [
                .init(title: "Прочитать все", icon: "checkmark.message.fill") { Task { await chats.readAll() } },
                .init(title: "Моя визитка и QR", icon: "qrcode") { showCard = true },
                .init(title: "Сканировать QR-код", icon: "qrcode.viewfinder") { scanning = true },
            ]
        }
    }

    private func scanned(_ code: String) {
        scanning = false
        switch QRLinks.parse(code) {
        case .trainer(let id): model.handle(route: "trainer/\(id)")
        case .user(let id): scanUser = AppModel.IdBox(id: id)
        case .url(let u): openURL(u)
        case .text(let t):
            UIPasteboard.general.string = t
            OxAlert.show(icon: "qrcode", title: "Текст из QR скопирован", message: t)
        }
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Главная", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Тренеры", systemImage: "figure.strengthtraining.traditional", value: AppTab.trainers) {
                TrainersView()
            }
            // фильтр фокусирования «скрыть ленту» (Настройки → Фокусирование → Фильтры → OXION)
            if !focusHideFeed {
                Tab("Лента", systemImage: "flame.fill", value: AppTab.feed) {
                    FeedView()
                }
            }
            Tab("Дневник", systemImage: "calendar", value: AppTab.diary) {
                DiaryView()
            }
            Tab("Чаты", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chats) {
                ChatsView()
            }
            .badge(chats.unread)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(chats)
        .overlay {
            if let hold, hold.index < tabOrder.count {
                TabHoldOverlay(press: hold, actions: holdActions(tabOrder[hold.index])) { self.hold = nil }
            }
        }
        .onChange(of: model.selectedTab) { TabHold.install { p in hold = p } }
        .onAppear {
            TabHold.install { p in hold = p }
            // свайп от края экрана — соседняя вкладка
            TabEdgeSwipe.install { dir in
                let order = tabOrder
                guard let i = order.firstIndex(of: model.selectedTab) else { return }
                let j = i + dir
                guard order.indices.contains(j) else { Haptic.tap(.soft); return }
                Haptic.tap(.light)
                withAnimation(.snappy) { model.selectedTab = order[j] }
            }
        }
        .fullScreenCover(isPresented: $welcome) {
            WelcomeFlow { Welcome.seen = true; WhatsNew.markSeen(); welcome = false }
        }
        .task {
            // приветствие в стиле Apple Фитнес — один раз; вместо него «Что нового» не показываем
            if !Welcome.seen {
                try? await Task.sleep(for: .seconds(0.6))
                welcome = true
                return
            }
            // «Что нового в Oxion» — один раз после обновления
            guard WhatsNew.shouldShow else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if model.sheet == nil { model.sheet = .whatsNew }
        }
        .fullScreenCover(isPresented: $scanning) { QRScanScreen { scanned($0) } }
        .sheet(item: $scanUser) { b in NavigationStack { UserProfileView(userId: b.id) } }
        .transaction { t in
            if !PowerSaver.allowsNow(.interface) { t.disablesAnimations = true; t.animation = nil }
        }
        .onChange(of: model.selectedTab) {
            Haptic.tap(.soft)
        }
        .onReceive(NotificationCenter.default.publisher(for: .oxionFocusChanged)) { _ in
            withAnimation { focusHideFeed = OxFocus.hideFeed }
            if focusHideFeed && model.selectedTab == .feed { model.selectedTab = .home }
            chats.focusChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .oxionShake)) { _ in
            guard AppSettings.shakeCard, !showCard else { return }
            Haptic.success()
            showCard = true
        }
        .fullScreenCover(isPresented: $showCard) { MyCardSheet() }
        .onChange(of: model.sheet) {
            if model.sheet == .qr { model.sheet = nil; showCard = true }
        }
        .sheet(item: $model.sheet) { s in
            switch s {
            case .qr: MyCardSheet()
            case .compose: ComposerView(request: ComposeRequest()) { _ in }
            case .progress: NavigationStack { ProgressHubView() }
            case .permissions: NavigationStack { PermissionsView() }
            case .run: NavigationStack { CardioHubView() }
            case .scanner: NavigationStack { LabelScannerView() }
            case .music: NavigationStack { WorkoutMusicView() }
            case .screenLock: NavigationStack { ScreenTimeLockView() }
            case .devices: NavigationStack { DevicePanelView() }
            case .program: NavigationStack { ProgramBuilderView() }
            case .status: NavigationStack { StatusView() }
            case .whatsNew: WhatsNewView()
            }
        }
        .fullScreenCover(isPresented: $model.showVision) { VisionCoachView() }
        .fullScreenCover(isPresented: $model.showMuscles) { Body3DScreen() }
        .fullScreenCover(isPresented: $model.showMap) { SportMapView() }
        .sheet(isPresented: $model.showCatalog) {
            NavigationStack {
                WorkoutDBCatalogView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { model.showCatalog = false } } }
            }
        }
        .sheet(isPresented: $model.offerLoginKey) { LoginKeyOfferSheet() }
        .sheet(item: $model.exerciseBox) { b in ExerciseSheet(id: b.id) }
        .sheet(item: $model.profileBox) { b in
            NavigationStack {
                UserProfileView(userId: b.id)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { model.profileBox = nil } } }
            }
        }
        .sheet(item: $model.workoutBox) { b in NavigationStack { WorkoutDetailView(workoutId: b.id, onChanged: {}) } }
        .sheet(item: $model.bookTrainer) { b in BookingSheet(trainerId: b.id, trainerName: model.bookTrainerName) }
        .onChange(of: chats.unread) { QuickActions.update(unread: chats.unread) }
        .modifier(WorkoutAccessory { model.showActiveWorkout = true })
        .fullScreenCover(isPresented: $model.showActiveWorkout) { ActiveWorkoutView() }
        .onAppear { WatchLink.shared.activate() }
        .onChange(of: engine.state?.phase) { WatchLink.shared.send(engine.state) }
        .onChange(of: engine.state?.setsDoneAll) { WatchLink.shared.send(engine.state) }
        .task {
            // счётчик непрочитанных на вкладке «Чаты»
            while !Task.isCancelled {
                await chats.load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
