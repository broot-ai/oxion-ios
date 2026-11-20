import SwiftUI
import Observation

extension Color {
    /// Фирменный лаймовый цвет Oxion
    static let lime = Color(red: 0.651, green: 1.0, blue: 0.227)
}

@main
struct OxionApp: App {
    @State private var model = AppModel()

    init() {
        AppSettings.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(.lime)
                .onReceive(NotificationCenter.default.publisher(for: .oxionUnauthorized)) { _ in
                    model.logoutLocal()
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
        .task { await model.start() }
    }
}

enum AppTab: Hashable {
    case feed, trainers, diary, profile, search
}

struct MainTabView: View {
    @State private var tab: AppTab = .feed

    var body: some View {
        TabView(selection: $tab) {
            Tab("Лента", systemImage: "flame.fill", value: AppTab.feed) {
                FeedView()
            }
            Tab("Тренеры", systemImage: "figure.strengthtraining.traditional", value: AppTab.trainers) {
                TrainersView()
            }
            Tab("Дневник", systemImage: "chart.bar.fill", value: AppTab.diary) {
                DiaryView()
            }
            Tab("Профиль", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
            Tab(value: AppTab.search, role: .search) {
                ExercisesView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: tab) { Haptic.tap(.soft) }
    }
}
