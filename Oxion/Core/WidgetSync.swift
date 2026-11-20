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
        await addDashboard(&snap)
        snap.updatedAt = Date()
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.snapshotKey)
        WidgetShared.defaults?.removeObject(forKey: WidgetShared.tokenKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Данные для панели: тренер дня, рекомендации, избранные, статистика недели, план, достижения
    private static func addDashboard(_ s: inout WidgetSnapshot) async {
        let f = RU.dayFormatter
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let ws = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? now
        func wt(_ t: Trainer) -> WTrainer {
            WTrainer(id: t.userId, name: t.name ?? "Тренер", info: (t.directions ?? []).prefix(2).joined(separator: " · "), price: t.price, rating: t.rating)
        }
        if let st: Stats = try? await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": f.string(from: now)]) {
            s.weekSets = st.sets ?? 0
            s.weekKcal = st.calories ?? 0
            s.weekDone = st.workouts ?? s.weekDone
            s.weekGoal = st.weekGoal ?? s.weekGoal
        }
        if let t: TrainersResponse = try? await API.call("/trainers", query: ["sort": "match"]) {
            s.trainers = t.items.prefix(4).map(wt)
            if let first = t.items.first {
                s.trainerId = first.userId
                s.trainerName = first.name
                s.trainerInfo = (first.directions ?? []).prefix(2).joined(separator: " · ")
                s.trainerPrice = first.price
            }
        }
        if let fav: TrainersResponse = try? await API.call("/favorites") {
            s.favorites = fav.items.prefix(4).map(wt)
        }
        if let w: WorkoutsResponse = try? await API.call("/workouts", query: ["from": f.string(from: cal.date(byAdding: .day, value: -14, to: now) ?? now),
                                                                              "to": f.string(from: cal.date(byAdding: .day, value: 7, to: now) ?? now)]) {
            let today = f.string(from: now)
            s.upcoming = w.items.filter { $0.date >= today }.sorted { $0.date < $1.date }.prefix(4).map {
                WPlanned(id: $0.id, title: $0.title ?? "Тренировка", when: RU.human($0.date) + ($0.time.map { ", \($0)" } ?? ""))
            }
            if let last = w.items.filter({ $0.date <= today && ($0.exCount ?? 0) > 0 }).max(by: { $0.date < $1.date }) {
                s.lastWorkout = RU.human(last.date) + " · " + (last.title ?? "Тренировка")
            }
        }
        if let a: AchievementsResponse = try? await API.call("/achievements") {
            s.achievementsDone = a.done ?? 0
            s.achievementsTotal = a.total ?? 0
            s.streak = a.streak ?? 0
        }
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
