import Foundation
import ActivityKit
import AppIntents
#if !WIDGET_EXT
import CoreLocation
#endif

// Пробежка / прогулка в Dynamic Island и на экране блокировке: время, дистанция, темп, пульс и мини-карта маршрута.
// Карту рисуем сами по точкам маршрута (MapKit в Live Activity недоступен): до 60 точек, сжатых в числа 0…1000.

struct OxionRunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var kind: String              // run / walk
        var paused: Bool
        var timerStart: Date          // начало с учётом пауз — таймер идёт сам
        var pausedElapsed: Int?
        var distance: Double          // метры
        var paceSec: Int?             // секунд на км
        var heartRate: Int?
        var calories: Int
        var route: [Int16]            // x0,y0,x1,y1… в квадрате 0…1000
        var goalKm: Double?

        var km: String { String(format: "%.2f", distance / 1000).replacingOccurrences(of: ".", with: ",") }
        var pace: String {
            guard let p = paceSec, p > 0, p < 3600 else { return "—" }
            return String(format: "%d'%02d\"", p / 60, p % 60)
        }
        var points: [(Double, Double)] {
            stride(from: 0, to: route.count - 1, by: 2).map { (Double(route[$0]) / 1000, Double(route[$0 + 1]) / 1000) }
        }
    }
    var title: String
}

/// Пауза / продолжить пробежку из Dynamic Island (выполняется в процессе приложения)
struct RunTogglePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пауза пробежки"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .oxRunTogglePause, object: nil) }
        return .result()
    }
}

extension Notification.Name {
    static let oxRunTogglePause = Notification.Name("ox.run.togglePause")
}

#if !WIDGET_EXT
@MainActor
enum RunIsland {
    private static var current: Activity<OxionRunAttributes>?
    private static var lastPush = Date.distantPast

    static func start(kind: String, title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for a in Activity<OxionRunAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        let st = OxionRunAttributes.ContentState(kind: kind, paused: false, timerStart: Date(), pausedElapsed: nil,
                                                 distance: 0, paceSec: nil, heartRate: nil, calories: 0, route: [], goalKm: nil)
        current = try? Activity.request(attributes: OxionRunAttributes(title: title),
                                        content: ActivityContent(state: st, staleDate: nil), pushType: nil)
        lastPush = .distantPast
    }

    /// Обновляем не чаще раза в 4 секунды (iOS ограничивает частоту обновлений)
    static func update(kind: String, paused: Bool, timerStart: Date, elapsed: Int, distance: Double,
                       heartRate: Int?, calories: Int, coords: [CLLocationCoordinate2D], force: Bool = false) {
        guard let a = current else { return }
        guard force || Date().timeIntervalSince(lastPush) > 4 else { return }
        lastPush = Date()
        let pace: Int? = distance > 50 ? Int(Double(elapsed) / (distance / 1000)) : nil
        let st = OxionRunAttributes.ContentState(kind: kind, paused: paused, timerStart: timerStart,
                                                 pausedElapsed: paused ? elapsed : nil, distance: distance, paceSec: pace,
                                                 heartRate: heartRate, calories: calories, route: pack(coords), goalKm: nil)
        Task { await a.update(ActivityContent(state: st, staleDate: nil)) }
    }

    static func end() {
        guard let a = current else { return }
        current = nil
        Task { await a.end(a.content, dismissalPolicy: .after(Date().addingTimeInterval(8))) }
    }

    /// Маршрут → до 60 точек в квадрате 0…1000 с сохранением пропорций
    static func pack(_ c: [CLLocationCoordinate2D]) -> [Int16] {
        guard c.count >= 2 else { return [] }
        let step = max(1, c.count / 60)
        var pts = stride(from: 0, to: c.count, by: step).map { c[$0] }
        if let l = c.last, pts.last.map({ $0.latitude != l.latitude || $0.longitude != l.longitude }) ?? true { pts.append(l) }
        let k = cos(pts[0].latitude * .pi / 180)
        let xs = pts.map { $0.longitude * k }, ys = pts.map { $0.latitude }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return [] }
        let span = max(x1 - x0, y1 - y0, 1e-6)
        let ox = (span - (x1 - x0)) / 2, oy = (span - (y1 - y0)) / 2
        var out: [Int16] = []
        out.reserveCapacity(pts.count * 2)
        for i in pts.indices {
            out.append(Int16(((xs[i] - x0 + ox) / span * 900 + 50).rounded()))
            out.append(Int16(((y1 - ys[i] + oy) / span * 900 + 50).rounded()))   // север сверху
        }
        return out
    }
}
#endif
