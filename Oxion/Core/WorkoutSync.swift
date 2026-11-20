import Foundation

/// Отправка завершённых подходов на сервер Oxion (Cloudflare Worker): POST /api/we/{id}/sets.
/// Таймер сервер не трогает — только факт подхода, по одному запросу на подход.
/// Если сети нет, подходы ждут в очереди и уйдут при следующем открытии приложения.
enum WorkoutSync {
    @MainActor private static var running = false

    @MainActor
    static func flush() async {
        guard !running else { return }
        running = true
        defer { running = false }
        let engine = WorkoutEngine.shared
        var done = Set<UUID>()
        for p in engine.takePending() {
            var body: [String: Any] = [:]
            if let v = p.weight { body["weight"] = v }
            if let v = p.reps { body["reps"] = v }
            if let v = p.duration { body["duration"] = v }
            if let v = p.distance { body["distance"] = v }
            do {
                let _: OK = try await API.call("/we/\(p.weId)/sets", method: "POST", body: body)
                done.insert(p.id)
            } catch let e as APIError where e.status >= 400 && e.status < 500 {
                // сервер отказал (например, упражнение удалили) — не повторяем бесконечно
                done.insert(p.id)
            } catch {
                break
            }
        }
        if !done.isEmpty {
            engine.markSynced(done)
            await WidgetSync.refresh()
        }
    }
}
