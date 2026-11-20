import UIKit
import BackgroundTasks
import WidgetKit

/// Делегат приложения: меню при удержании иконки (быстрые действия) и фоновое обновление контента.
final class OxAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshId = "ru.oxion.app.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshId, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            OxAppDelegate.handle(t)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // запуск «с нуля» через пункт меню иконки
        if let item = options.shortcutItem {
            MainActor.assumeIsolated { QuickActions.perform(item) }
        }
        let c = UISceneConfiguration(name: nil, sessionRole: session.role)
        c.delegateClass = OxSceneDelegate.self
        return c
    }

    // MARK: Обновление контента в фоне (виджеты и наклейка с непрочитанными)

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: refreshId)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            if API.token != nil, let r: ChatsResponse = try? await API.call("/chats") {
                let n = r.items.filter { $0.muted != true && $0.archived != true }
                    .reduce(0) { $0 + max($1.unread ?? 0, $1.marked == true ? 1 : 0) }
                AppBadge.set(n)
                QuickActions.update(unread: n)
            }
            await WidgetSync.refresh()
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

/// Нажатие пункта меню, когда OXION уже запущен
final class OxSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActions.perform(shortcutItem)
        completionHandler(true)
    }
}

/// Пункты при удержании иконки: 3 постоянных (Info.plist) + 1 меняющийся
enum QuickActions {
    @MainActor static func perform(_ item: UIApplicationShortcutItem) {
        PendingRoute.go(item.type.replacingOccurrences(of: "ru.oxion.", with: ""))
    }

    @MainActor static func update(unread: Int? = nil) {
        let item: UIApplicationShortcutItem
        if WorkoutEngine.shared.isActive {
            item = UIApplicationShortcutItem(type: "ru.oxion.workout", localizedTitle: "Продолжить тренировку",
                                             localizedSubtitle: WorkoutEngine.shared.state?.currentItem?.name,
                                             icon: UIApplicationShortcutIcon(systemImageName: "play.circle.fill"))
        } else if let unread, unread > 0 {
            item = UIApplicationShortcutItem(type: "ru.oxion.chats", localizedTitle: "Чаты",
                                             localizedSubtitle: "\(unread) \(RU.plural(unread, "непрочитанное", "непрочитанных", "непрочитанных"))",
                                             icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right.fill"))
        } else {
            item = UIApplicationShortcutItem(type: "ru.oxion.vision", localizedTitle: "Счёт повторов",
                                             localizedSubtitle: "Камера считает приседания",
                                             icon: UIApplicationShortcutIcon(systemImageName: "camera.viewfinder"))
        }
        UIApplication.shared.shortcutItems = [item]
    }
}
