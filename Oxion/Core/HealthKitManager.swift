import Foundation
import HealthKit
import Observation

/// «Здоровье» iPhone: спрашиваем доступ, читаем шаги, калории, дистанцию, сон, пульс покоя и вес,
/// показываем в приложении и отправляем на сервер Oxion (/hk/КЛЮЧ) — их увидит и тренер.
@MainActor
@Observable
final class HealthKitManager {
    static let shared = HealthKitManager()

    struct Day: Identifiable {
        let date: Date
        var steps: Double?
        var kcal: Double?
        var distanceKm: Double?
        var sleepMin: Double?
        var restHr: Double?
        var id: Date { date }
    }

    let store = HKHealthStore()
    var days: [Day] = []
    var weight: Double?
    var lastSync: Date?
    var loading = false

    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "hk_on") }
        set { UserDefaults.standard.set(newValue, forKey: "hk_on") }
    }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.restingHeartRate), HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
    }

    /// Системное окно iOS «Oxion запрашивает доступ к Здоровью»
    func requestAccess() async throws {
        guard available else { throw APIError(message: "«Здоровье» недоступно на этом устройстве", status: 0) }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        enabled = true
    }

    func load(days n: Int = 7) async {
        guard available, enabled else { return }
        loading = true
        defer { loading = false }
        let cal = Calendar.current
        let end = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(n - 1), to: end) ?? end)

        let steps = await stats(.stepCount, unit: .count(), option: .cumulativeSum, start: start, end: end)
        let kcal = await stats(.activeEnergyBurned, unit: .kilocalorie(), option: .cumulativeSum, start: start, end: end)
        let dist = await stats(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), option: .cumulativeSum, start: start, end: end)
        let hr = await stats(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), option: .discreteAverage, start: start, end: end)
        let sleep = await sleepMinutes(start: start, end: end)
        weight = await latestWeight()

        var out: [Day] = []
        for i in 0..<n {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let k = cal.startOfDay(for: d)
            out.append(Day(date: k, steps: steps[k], kcal: kcal[k], distanceKm: dist[k], sleepMin: sleep[k], restHr: hr[k]))
        }
        days = out
    }

    private func stats(_ id: HKQuantityTypeIdentifier, unit: HKUnit, option: HKStatisticsOptions, start: Date, end: Date) async -> [Date: Double] {
        let type = HKQuantityType(id)
        let pred = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let desc = HKStatisticsCollectionQueryDescriptor(predicate: pred, options: option, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let coll = try? await desc.result(for: store) else { return [:] }
        var out: [Date: Double] = [:]
        coll.enumerateStatistics(from: start, to: end) { st, _ in
            let q = option == .cumulativeSum ? st.sumQuantity() : st.averageQuantity()
            if let q { out[Calendar.current.startOfDay(for: st.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Сон: суммируем фазы «сплю» и относим к дню, когда проснулись
    private func sleepMinutes(start: Date, end: Date) async -> [Date: Double] {
        let type = HKCategoryType(.sleepAnalysis)
        let pred = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-12 * 3600), end: end)
        let desc = HKSampleQueryDescriptor(predicates: [.categorySample(type: type, predicate: pred)], sortDescriptors: [])
        guard let samples = try? await desc.result(for: store) else { return [:] }
        var out: [Date: Double] = [:]
        let skip: Set<Int> = [HKCategoryValueSleepAnalysis.inBed.rawValue, HKCategoryValueSleepAnalysis.awake.rawValue]
        for s in samples where !skip.contains(s.value) {
            let day = Calendar.current.startOfDay(for: s.endDate)
            out[day, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60
        }
        return out
    }

    private func latestWeight() async -> Double? {
        let desc = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
                                           sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        guard let s = try? await desc.result(for: store).first else { return nil }
        return s.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    /// Отправка на сервер Oxion через тот же адрес, что и команда «Здоровье • Oxion»
    func syncToServer() async {
        guard enabled, !days.isEmpty else { return }
        struct Key: Decodable { let url: String? }
        var key: Key? = try? await API.call("/health/key")
        if key?.url == nil { key = try? await API.call("/health/key", method: "POST") }
        guard let u = key?.url, let url = URL(string: u) else { return }
        let f = RU.dayFormatter
        for d in days {
            var body: [String: Any] = ["date": f.string(from: d.date)]
            if let v = d.steps { body["steps"] = Int(v) }
            if let v = d.kcal { body["kcal"] = Int(v) }
            if let v = d.distanceKm { body["distance"] = (v * 100).rounded() / 100 }
            if let v = d.sleepMin, v > 0 { body["sleep_min"] = Int(v) }
            if let v = d.restHr { body["rest_hr"] = Int(v.rounded()) }
            if Calendar.current.isDateInToday(d.date), let w = weight { body["weight"] = (w * 10).rounded() / 10 }
            guard body.count > 1, let data = try? JSONSerialization.data(withJSONObject: body) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            _ = try? await URLSession.shared.data(for: req)
        }
        lastSync = Date()
        UserDefaults.standard.set(Date(), forKey: "hk_last_sync")
    }

    /// Прочитать и отправить — вызывается при открытии экрана и при сворачивании приложения
    func refreshAndSync() async {
        await load()
        await syncToServer()
    }
}
