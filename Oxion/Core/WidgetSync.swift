import Foundation
import WidgetKit

/// Приложение собирает данные для виджета и кладёт их в общее хранилище App Group.
/// Сначала спрашивает сервер (/api/widget), если его нет — считает само из /goals, /stats, /workouts.
enum WidgetSync {
    static func refresh() async {
        // токен и адрес — чтобы виджет мог обновляться сам, без открытия приложения
        if let d = WidgetShared.defaults {
            d.set(API.token, forKey: WidgetShared.tokenKey)
            d.set(AppSettings.serverURL.absoluteString, forKey: WidgetShared.serverKey)
        }
        var snap: WidgetSnapshot
        if let r: WidgetAPIResponse = try? await API.call("/widget") {
            snap = r.snapshot()
        } else {
            snap = await localSnapshot()
        }
        snap.updatedAt = Date()
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.snapshotKey)
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.tokenKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func localSnapshot() async -> WidgetSnapshot {
        let q = WidgetSnapshot.localQuote()
        var s = WidgetSnapshot(quote: q.0, quoteAuthor: q.1, reminder: "Время тренироваться 💪")
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let ws = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? now
        let f = RU.dayFormatter
        let today = f.string(from: now)
        if let st: Stats = try? await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": today]) {
            s.weekDone = st.workouts ?? 0
            s.weekGoal = st.weekGoal ?? 3
        }
        if let g: GoalsResponse = try? await API.call("/goals"), let goal = g.items.first(where: { $0.status == "active" }) {
            s.goalTitle = goal.title ?? goal.exercise ?? "Цель"
            s.goalPct = goal.pct
            if let c = goal.current, let t = goal.target { s.goalDetail = "\(Int(c)) из \(Int(t)) \(goal.unit ?? "")" }
        }
        if let w: WorkoutsResponse = try? await API.call("/workouts", query: ["from": today, "to": today]), let first = w.items.first {
            s.todayTitle = first.title ?? "Тренировка"
            s.todayTime = first.time
            s.reminder = "Сегодня: \(s.todayTitle ?? "тренировка")" + (first.time.map { " в \($0)" } ?? "")
        } else if s.weekDone >= s.weekGoal {
            s.reminder = "Цель недели выполнена — можно отдохнуть 🔥"
        } else {
            let left = s.weekGoal - s.weekDone
            s.reminder = "До цели недели: \(left) \(RU.plural(left, "тренировка", "тренировки", "тренировок"))"
        }
        return s
    }
}
