import SwiftUI
import Observation

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    /// Цвета как в PWA Oxion (app.css)
    static let lime = Color(hex: 0xB2EE37)
    static let oxBg = Color(hex: 0x0F1012)
    static let oxCard = Color(hex: 0x18191C)
    static let oxCard2 = Color(hex: 0x202124)
    static let oxHint = Color(hex: 0x8A8A83)
}

@main
struct OxionApp: App {
    @UIApplicationDelegateAdaptor(OxAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppSettings.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    // ссылки из виджетов и Live Activity: oxion://diary, oxion://trainer/15 …
                    let route = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/")
                    model.handle(route: route)
                }
                .preferredColorScheme(.dark)
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
                .onChange(of: scenePhase) {
                    if scenePhase == .active, let r = PendingRoute.take() { model.handle(route: r) }
                    if scenePhase == .background {
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
    var me: Me?
    var meta: Meta?
    var selectedTab: AppTab = .home
    var showActiveWorkout = false
    var openTrainerId: Int?
    var showFavorites = false
    /// Экраны поверх вкладок (из меню иконки, Siri, ссылок)
    var sheet: AppSheet?
    var showVision = false

    enum AppSheet: String, Identifiable {
        case qr, compose, progress, permissions
        var id: String { rawValue }
    }

    /// Переходы из виджетов, Пункта управления, Siri: oxion://home, diary, workout, trainers, trainer/ID, favorites, chats, feed
    func handle(route: String) {
        let parts = route.split(separator: "/").map(String.init)
        switch parts.first ?? "" {
        case "workout":
            if WorkoutEngine.shared.state != nil { showActiveWorkout = true } else { selectedTab = .diary }
        case "diary": selectedTab = .diary
        case "feed": selectedTab = .feed
        case "chats": selectedTab = .chats
        case "trainers": selectedTab = .trainers
        case "favorites":
            selectedTab = .trainers
            showFavorites = true
        case "qr": sheet = .qr
        case "compose":
            selectedTab = .feed
            sheet = .compose
        case "progress": sheet = .progress
        case "permissions": sheet = .permissions
        case "vision": showVision = true
        case "trainer":
            selectedTab = .trainers
            if parts.count > 1, let id = Int(parts[1]), id > 0 { openTrainerId = id }
        default: selectedTab = .home
        }
    }
    var trainerQuery = ""

    func start() async {
        if API.token == nil {
            phase = .loggedOut
            return
        }
        await loadMe()
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
    }

    func logout() async {
        let _: OK? = try? await API.call("/logout", method: "POST")
        logoutLocal()
    }

    func logoutLocal() {
        WidgetSync.clear()
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

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Главная", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Тренеры", systemImage: "figure.strengthtraining.traditional", value: AppTab.trainers) {
                TrainersView()
            }
            Tab("Лента", systemImage: "flame.fill", value: AppTab.feed) {
                FeedView()
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
        .onChange(of: model.selectedTab) { Haptic.tap(.soft) }
        .onReceive(NotificationCenter.default.publisher(for: .oxionShake)) { _ in
            guard AppSettings.shakeCard, !showCard else { return }
            Haptic.success()
            showCard = true
        }
        .sheet(isPresented: $showCard) { MyCardSheet() }
        .sheet(item: $model.sheet) { s in
            switch s {
            case .qr: MyCardSheet()
            case .compose: ComposerView(request: ComposeRequest()) { _ in }
            case .progress: NavigationStack { ProgressHubView() }
            case .permissions: NavigationStack { PermissionsView() }
            }
        }
        .fullScreenCover(isPresented: $model.showVision) { VisionCoachView() }
        .onChange(of: chats.unread) { QuickActions.update(unread: chats.unread) }
        .overlay(alignment: .bottom) {
            ActiveWorkoutBar { model.showActiveWorkout = true }
                .padding(.bottom, 92)
        }
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
