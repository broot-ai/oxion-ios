import SwiftUI
import GameKit

/// Game Center: рейтинг по числу тренировок и достижения.
/// Нужен платный аккаунт: в приложении без него Game Center ответит ошибкой, приложение просто покажет причину.
@MainActor
@Observable
final class GameHub {
    static let shared = GameHub()

    static let boardWorkouts = "oxion.workouts.total"
    static let boardSets = "oxion.sets.week"

    var authenticated = false
    var playerName = ""
    var errorText: String?

    private let countKey = "oxion_gc_workouts"
    var workoutsDone: Int { UserDefaults.standard.integer(forKey: countKey) }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, error in
            Task { @MainActor in
                guard let self else { return }
                if let vc {
                    Self.topController()?.present(vc, animated: true)
                    return
                }
                self.authenticated = GKLocalPlayer.local.isAuthenticated
                self.playerName = GKLocalPlayer.local.displayName
                self.errorText = error?.localizedDescription
            }
        }
    }

    /// Вызывается из движка тренировки
    func workoutFinished(_ s: WorkoutState) {
        let n = workoutsDone + 1
        UserDefaults.standard.set(n, forKey: countKey)
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let sets = s.items.reduce(0) { $0 + $1.sets }
        Task {
            try? await GKLeaderboard.submitScore(n, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.boardWorkouts])
            try? await GKLeaderboard.submitScore(sets, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.boardSets])
            var list: [GKAchievement] = []
            for (id, goal) in [("oxion.first", 1), ("oxion.ten", 10), ("oxion.fifty", 50), ("oxion.hundred", 100)] {
                let a = GKAchievement(identifier: id)
                a.percentComplete = min(100, Double(n) / Double(goal) * 100)
                a.showsCompletionBanner = true
                list.append(a)
            }
            try? await GKAchievement.report(list)
        }
    }

    func openDashboard(_ state: GKGameCenterViewControllerState = .dashboard) {
        GKAccessPoint.shared.trigger(state: state) {}
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

struct GameCenterView: View {
    @State private var hub = GameHub.shared

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title2)
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hub.authenticated ? hub.playerName : "Game Center").font(.headline)
                        Text(hub.authenticated ? "Подключено" : "Не подключено").font(.subheadline).foregroundStyle(Color.oxHint)
                    }
                }
                if !hub.authenticated {
                    Button("Войти в Game Center") { hub.authenticate() }
                }
                if let e = hub.errorText {
                    Text(e).font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Каждая завершённая тренировка попадает в общий рейтинг и открывает достижения: 1, 10, 50 и 100 тренировок.")
            }
            Section {
                LabeledContent("Тренировок на этом iPhone", value: "\(hub.workoutsDone)")
                Button { hub.openDashboard(.leaderboards) } label: { Label("Рейтинг", systemImage: "list.number") }
                Button { hub.openDashboard(.achievements) } label: { Label("Достижения", systemImage: "rosette") }
            }
            .disabled(!hub.authenticated)
        }
        .navigationTitle("Game Center")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !hub.authenticated { hub.authenticate() } }
    }
}
