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
                    // ссылки из виджета: oxion://home, oxion://diary, oxion://goals
                    switch url.host {
                    case "diary": model.selectedTab = .diary
                    case "feed": model.selectedTab = .feed
                    case "chats": model.selectedTab = .chats
                    default: model.selectedTab = .home
                    }
                }
                .preferredColorScheme(.dark)
                .tint(.lime)
                .onReceive(NotificationCenter.default.publisher(for: .oxionUnauthorized)) { _ in
                    model.logoutLocal()
                }
                .onChange(of: scenePhase) {
                    // свернули приложение — обновляем виджет свежими данными
                    if scenePhase == .background, model.me != nil { Task { await WidgetSync.refresh() } }
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
        .task {
            // счётчик непрочитанных на вкладке «Чаты»
            while !Task.isCancelled {
                await chats.load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
