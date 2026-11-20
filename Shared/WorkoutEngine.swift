import Foundation
import ActivityKit
import UserNotifications
import Observation

/// Движок тренировки: состояния, таймеры по меткам времени, Live Activity, уведомление об окончании отдыха.
/// Состояние сохраняется на устройстве и переживает сворачивание и перезапуск приложения.
/// Кнопки в Dynamic Island (App Intents) выполняются в процессе приложения и вызывают этот же движок.
@MainActor
@Observable
final class WorkoutEngine {
    static let shared = WorkoutEngine()

    private(set) var state: WorkoutState?
    var lastError: String?

    /// События тренировки для голосового тренера, статистики и т.п. (подписывается приложение; в виджете пусто)
    enum Event { case started, setDone, restSkipped, paused, resumed, finished }
    static var onEvent: (@MainActor (Event, WorkoutState) -> Void)?
    private func emit(_ e: Event) { if let s = state { Self.onEvent?(e, s) } }

    private let key = "oxion_active_workout"
    private let restNotificationId = "oxion-rest-end"

    private init() { restore() }

    var isActive: Bool {
        guard let s = state else { return false }
        return s.phase != .finished && s.phase != .notStarted
    }

    var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: Хранение

    private func persist() {
        if let s = state, let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func restore() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(WorkoutState.self, from: d) else { return }
        state = s
        // Live Activity могла закончиться (лимит iOS ~8 ч) — поднимем заново, если тренировка ещё идёт
        if isActive { Task { await self.syncActivity() } }
    }

    // MARK: Действия

    func start(_ plan: WorkoutState) {
        var s = plan
        s.phase = .exercising
        s.startedAt = Date()
        s.pausedTotal = 0
        s.current = s.items.firstIndex(where: { !$0.done }) ?? 0
        state = s
        persist()
        requestNotificationPermission()
        Task { await startActivity() }
        emit(.started)
    }

    /// «Завершить подход»: сохраняем подход, запускаем отдых или переходим к следующему упражнению
    func completeSet(reps: Int? = nil, weight: Double? = nil) {
        guard var s = state, s.phase == .exercising || s.phase == .resting, var it = s.currentItem else { return }
        if s.phase == .resting { s.phase = .exercising }
        let r = reps ?? it.reps
        let w = weight ?? it.weight
        it.doneSets += 1
        if let reps { it.reps = reps }
        if let weight { it.weight = weight }
        s.items[s.current] = it
        s.pending.append(PendingSet(weId: it.weId,
                                    reps: it.type == "t" || it.type == "dt" ? nil : r,
                                    weight: it.type == "wr" ? w : nil,
                                    duration: it.type == "t" ? r : nil,
                                    distance: nil))
        let rest = TimeInterval(it.restSec)
        if it.done {
            // упражнение закончено → следующее несделанное
            if let next = s.items.indices.first(where: { $0 > s.current && !s.items[$0].done })
                ?? s.items.indices.first(where: { !s.items[$0].done }) {
                s.current = next
                beginRest(&s, seconds: rest)
            } else {
                state = s
                finish()
                return
            }
        } else {
            beginRest(&s, seconds: rest)
        }
        state = s
        persist()
        afterChange()
        emit(.setDone)
    }

    /// «Следующий подход» / «Пропустить отдых»
    func nextSet() {
        guard var s = state, s.phase == .resting else { return }
        s.phase = .exercising
        s.restEndsAt = nil
        state = s
        persist()
        cancelRestNotification()
        afterChange()
        emit(.restSkipped)
    }

    func skipRest() { nextSet() }

    func pause() {
        guard var s = state, s.phase == .exercising || s.phase == .resting else { return }
        s.pausedFrom = s.phase
        s.restLeftOnPause = s.phase == .resting ? s.restLeft() : nil
        s.pausedAt = Date()
        s.phase = .paused
        state = s
        persist()
        cancelRestNotification()
        afterChange()
        emit(.paused)
    }

    func resume() {
        guard var s = state, s.phase == .paused else { return }
        let now = Date()
        if let p = s.pausedAt { s.pausedTotal += now.timeIntervalSince(p) }
        s.pausedAt = nil
        if s.pausedFrom == .resting, let left = s.restLeftOnPause, left > 0 {
            s.phase = .resting
            s.restEndsAt = now.addingTimeInterval(left)
            scheduleRestNotification(at: s.restEndsAt!, next: s.currentItem?.name ?? "")
        } else {
            s.phase = .exercising
            s.restEndsAt = nil
        }
        s.pausedFrom = nil
        s.restLeftOnPause = nil
        state = s
        persist()
        afterChange()
        emit(.resumed)
    }

    /// «Завершить тренировку»
    func finish() {
        guard var s = state else { return }
        if s.phase == .paused, let p = s.pausedAt { s.pausedTotal += Date().timeIntervalSince(p) }
        s.phase = .finished
        s.finishedAt = Date()
        s.restEndsAt = nil
        state = s
        persist()
        cancelRestNotification()
        afterChange()
        emit(.finished)
    }

    /// Убрать завершённую тренировку (после экрана итогов)
    func clear() {
        state = nil
        persist()
        Task {
            for a in Activity<OxionWorkoutAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func beginRest(_ s: inout WorkoutState, seconds: TimeInterval) {
        guard seconds > 0 else {
            s.phase = .exercising
            s.restEndsAt = nil
            return
        }
        s.phase = .resting
        s.restEndsAt = Date().addingTimeInterval(seconds)
        let it = s.currentItem
        let label = (it?.doneSets ?? 0) == 0 ? "Следующее упражнение: \(it?.name ?? "")" : "Подход \((it?.doneSets ?? 0) + 1) из \(it?.sets ?? 0) — \(it?.name ?? "")"
        scheduleRestNotification(at: s.restEndsAt!, next: label)
    }

    private func afterChange() {
        Task { await syncActivity() }
        #if !WIDGET_EXT
        Task { await WorkoutSync.flush() }
        #endif
    }

    // MARK: Live Activity

    private func startActivity() async {
        guard let s = state else { return }
        for a in Activity<OxionWorkoutAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities выключены: Настройки → Oxion → Live Activities"
            return
        }
        do {
            let content = ActivityContent(state: s.liveState, staleDate: s.restEndsAt)
            _ = try Activity.request(attributes: OxionWorkoutAttributes(title: s.title, workoutId: s.workoutId),
                                     content: content, pushType: nil)
        } catch {
            lastError = "Не удалось показать тренировку в Dynamic Island: \(error.localizedDescription)"
        }
    }

    func syncActivity() async {
        guard let s = state else { return }
        let content = ActivityContent(state: s.liveState, staleDate: s.phase == .resting ? s.restEndsAt : nil)
        if s.phase == .finished {
            for a in Activity<OxionWorkoutAttributes>.activities {
                await a.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            }
            return
        }
        let list = Activity<OxionWorkoutAttributes>.activities
        if list.isEmpty {
            await startActivity()
        } else {
            for a in list { await a.update(content) }
        }
    }

    // MARK: Уведомление «Отдых окончен»

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleRestNotification(at date: Date, next: String) {
        guard UserDefaults.standard.object(forKey: "notify_restEnd") as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        c.title = "Отдых окончен 💪"
        c.body = next.isEmpty ? "Пора делать следующий подход" : next
        c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: restNotificationId, content: c, trigger: t))
    }

    private func cancelRestNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restNotificationId])
    }

    // MARK: Синхронизация (вызывается из приложения)

    func takePending() -> [PendingSet] { state?.pending ?? [] }

    func markSynced(_ ids: Set<UUID>) {
        guard var s = state else { return }
        s.pending.removeAll { ids.contains($0.id) }
        state = s
        persist()
    }
}
