import Foundation
import UserNotifications

/// Умные локальные уведомления OXION. Каждая категория включается отдельно (Профиль → Уведомления).
/// Пересчитываются при сворачивании приложения — никакого спама: по одному уведомлению на событие.
/// Серверные пуши (APNs через Cloudflare) подключатся после оформления аккаунта разработчика Apple.
enum SmartNotify {
    enum Category: String, CaseIterable, Identifiable {
        case planned, restEnd, weekGoal, inactive, records, trainers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .planned: return "Запланированная тренировка"
            case .restEnd: return "Конец отдыха"
            case .weekGoal: return "Цель недели почти выполнена"
            case .inactive: return "Давно не тренировались"
            case .records: return "Новые личные рекорды"
            case .trainers: return "Рекомендации тренеров"
            }
        }
        var icon: String {
            switch self {
            case .planned: return "calendar.badge.clock"
            case .restEnd: return "timer"
            case .weekGoal: return "target"
            case .inactive: return "moon.zzz.fill"
            case .records: return "trophy.fill"
            case .trainers: return "person.2.fill"
            }
        }
        var key: String { "notify_" + rawValue }
    }

    static func isOn(_ c: Category) -> Bool {
        UserDefaults.standard.object(forKey: c.key) as? Bool ?? (c != .trainers)
    }

    static func set(_ c: Category, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: c.key)
        if !on {
            UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
                let ids = reqs.map(\.identifier).filter { $0.hasPrefix("oxion-\(c.rawValue)") }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func add(_ id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let t = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: t))
    }

    static func record(text: String) {
        guard isOn(.records) else { return }
        let c = UNMutableNotificationContent()
        c.title = "🏆 Новый личный рекорд!"
        c.body = text
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "oxion-records-\(UUID().uuidString)", content: c,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// Пересчитать расписание по данным с сервера
    @MainActor
    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("oxion-planned") || $0.hasPrefix("oxion-weekGoal") || $0.hasPrefix("oxion-inactive") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let cal = Calendar.current
        let f = RU.dayFormatter
        let now = Date()
        let today = f.string(from: now)
        let in7 = f.string(from: cal.date(byAdding: .day, value: 7, to: now) ?? now)
        let ago30 = f.string(from: cal.date(byAdding: .day, value: -30, to: now) ?? now)

        guard let w: WorkoutsResponse = try? await API.call("/workouts", query: ["from": ago30, "to": in7]) else { return }

        // 1. запланированные тренировки — за 30 минут (или в 9:00, если время не указано)
        if isOn(.planned) {
            for x in w.items where x.date >= today && (x.exCount ?? 0) >= 0 {
                guard let day = f.date(from: x.date) else { continue }
                var at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                if let t = x.time, t.count >= 4 {
                    let p = t.split(separator: ":").compactMap { Int($0) }
                    if p.count == 2, let d = cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: day) {
                        at = d.addingTimeInterval(-30 * 60)
                    }
                }
                add("oxion-planned-\(x.id)", title: "Сегодня тренировка 💪",
                    body: "\(x.title ?? "Тренировка")" + (x.time.map { " в \($0)" } ?? ""), at: at)
            }
        }

        // 2. цель недели почти выполнена — вечером, если осталась одна тренировка
        if isOn(.weekGoal) {
            let iso = Calendar(identifier: .iso8601)
            let ws = iso.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let we = iso.date(byAdding: .day, value: 6, to: ws) ?? now
            if let st: Stats = try? await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": today]) {
                let left = (st.weekGoal ?? 3) - (st.workouts ?? 0)
                if left == 1, !(st.daysDone ?? []).contains(today),
                   let at = cal.date(bySettingHour: 18, minute: 30, second: 0, of: now) {
                    add("oxion-weekGoal", title: "Почти у цели 🎯", body: "До цели недели осталась одна тренировка. Сделаете сегодня?", at: at)
                }
            }
        }

        // 3. давно не тренировались — через 3 дня после последней тренировки
        if isOn(.inactive) {
            let last = w.items.filter { $0.date <= today && ($0.exCount ?? 0) > 0 }.map(\.date).max()
            if let last, let d = f.date(from: last),
               let at = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 3, to: d) ?? d) {
                add("oxion-inactive", title: "Вы давно не тренировались", body: "Три дня без тренировок. Короткая тренировка лучше, чем никакая 🔥", at: at)
            }
        }
    }
}
