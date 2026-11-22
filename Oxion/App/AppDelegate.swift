import UIKit
import BackgroundTasks
import WidgetKit
import UserNotifications

/// Делегат приложения: меню при удержании иконки (быстрые действия) и фоновое обновление контента.
final class OxAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshId = "ru.oxion.app.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OxSound.preload()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshId, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            OxAppDelegate.handle(t)
        }
        UNUserNotificationCenter.current().delegate = OxNotifDelegate.shared
        // токен для пушей Apple: окно разрешения не показывает, просто получает адрес устройства.
        // В тестовой версии (бесплатный Apple ID) iOS откажет — это нормально.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await PushRegistrar.save(hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistrar.lastError = error.localizedDescription }
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
        guard PowerSaver.allowsNow(.background) else { return }
        let r = BGAppRefreshTaskRequest(identifier: refreshId)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // минимум, который допускает iOS
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
                await LocalChatNotifier.notifyNew(r.items)
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

// MARK: - Пуши с сервера (APNs)

@MainActor
enum PushRegistrar {
    static var lastError: String?
    static var token: String? {
        get { UserDefaults.standard.string(forKey: "apns_token") }
        set { UserDefaults.standard.set(newValue, forKey: "apns_token") }
    }
    /// Пуши работают, только если приложение подписано аккаунтом разработчика ($99)
    static var available: Bool { token != nil }

    static func save(_ hex: String) async {
        token = hex
        lastError = nil
        await upload()
    }

    /// Отправить токен на сервер (после входа — тоже)
    static func upload() async {
        guard let t = token, API.token != nil else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let _: OK? = try? await API.call("/push/ios", method: "POST", body: ["token": t, "sandbox": sandbox])
    }

    /// При выходе из аккаунта — чтобы чужие уведомления не приходили на это устройство
    static func remove() async {
        guard let t = token else { return }
        let _: OK? = try? await API.call("/push/ios", method: "DELETE", query: ["token": t])
    }
}

/// Показ уведомлений, когда OXION открыт, и переход по нажатию
final class OxNotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OxNotifDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        var route = info["route"] as? String
        if route == nil, let url = info["url"] as? String {
            if url.contains("#chat") { route = "chats" }
            else if url.contains("#post") || url.contains("#feed") { route = "feed" }
            else if url.contains("#diary") { route = "diary" }
            else { route = "home" }
        }
        if let route { await MainActor.run { PendingRoute.go(route) } }
    }
}

/// Уведомления о новых сообщениях без пушей Apple (бесплатный Apple ID их не поддерживает):
/// при фоновом обновлении сравниваем последние сообщения с уже показанными и показываем локальное уведомление.
/// iOS сама решает, как часто будить приложение (обычно раз в 15 мин – несколько часов).
enum LocalChatNotifier {
    private static let key = "ox.notifiedLastIds"

    private static var seen: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Пользователь видел список чатов в приложении — по этим сообщениям уведомлять не нужно
    static func markSeen(_ items: [ChatItem]) {
        var s = seen
        for c in items { if let id = c.lastId { s[String(c.id)] = max(s[String(c.id)] ?? 0, id) } }
        seen = s
    }

    static func notifyNew(_ items: [ChatItem]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { markSeen(items); return }
        let s = seen
        let first = s.isEmpty
        for c in items where c.muted != true && c.archived != true && c.mine != true && (c.unread ?? 0) > 0 {
            guard let last = c.lastId, last > (s[String(c.id)] ?? 0), !first else { continue }
            let content = UNMutableNotificationContent()
            content.title = c.peer.name ?? "Новое сообщение"
            let n = c.unread ?? 1
            content.body = (c.last?.isEmpty == false ? c.last! : "Новое сообщение") + (n > 1 ? " (+\(n - 1))" : "")
            content.sound = .default
            content.threadIdentifier = "chat\(c.id)"
            content.userInfo = ["route": "chats", "url": "/#chat/\(c.id)"]
            let req = UNNotificationRequest(identifier: "chat\(c.id)-\(last)", content: content, trigger: nil)
            try? await center.add(req)
        }
        markSeen(items)
    }
}
