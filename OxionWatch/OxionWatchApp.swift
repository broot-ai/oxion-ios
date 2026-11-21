import SwiftUI
import WatchConnectivity
import HealthKit
import WatchKit

// MARK: - OXION для Apple Watch
// Показывает текущую тренировку с iPhone: упражнение, подход, отдых с обратным отсчётом.
// Кнопки на часах управляют тренировкой на телефоне. Пульс снимается часами и уходит на iPhone.

@main
struct OxionWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .tint(.lime)
        }
    }
}

extension Color {
    static let lime = Color(red: 0.698, green: 0.933, blue: 0.216)
    static let oxRed = Color(red: 1, green: 0.353, blue: 0.306)
}

/// Тренировка в том виде, в каком её присылает iPhone
struct WatchWorkout: Equatable {
    var active = false
    var title = ""
    var exercise = ""
    var setNo = 0
    var sets = 0
    var reps = 0
    var weight: Double = 0
    var unit = ""
    var type = ""
    var phase = ""
    var restEndsAt: Date?
    var startedAt: Date?
    var pausedTotal: Double = 0
    var setsDone = 0
    var setsTotal = 0
    var next = ""

    init() {}
    init(_ d: [String: Any]) {
        active = d["active"] as? Bool ?? false
        title = d["title"] as? String ?? ""
        exercise = d["exercise"] as? String ?? ""
        setNo = d["setNo"] as? Int ?? 0
        sets = d["sets"] as? Int ?? 0
        reps = d["reps"] as? Int ?? 0
        weight = d["weight"] as? Double ?? 0
        unit = d["unit"] as? String ?? ""
        type = d["type"] as? String ?? ""
        phase = d["phase"] as? String ?? ""
        let r = d["restEndsAt"] as? Double ?? 0
        restEndsAt = r > 0 ? Date(timeIntervalSince1970: r) : nil
        let st = d["startedAt"] as? Double ?? 0
        startedAt = st > 0 ? Date(timeIntervalSince1970: st) : nil
        pausedTotal = d["pausedTotal"] as? Double ?? 0
        setsDone = d["setsDone"] as? Int ?? 0
        setsTotal = d["setsTotal"] as? Int ?? 0
        next = d["next"] as? String ?? ""
    }

    var resting: Bool { phase == "resting" && (restEndsAt ?? .distantPast) > Date() }
    var paused: Bool { phase == "paused" }

    var target: String {
        switch type {
        case "t": return reps >= 60 ? "\(reps / 60) мин \(reps % 60) с" : "\(reps) с"
        case "dt": return ""
        case "wr" where weight > 0:
            let w = weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weight)) : String(format: "%.1f", weight)
            return "\(reps) × \(w) \(unit)"
        default: return "\(reps) повт."
        }
    }
}

// MARK: Связь с iPhone

@MainActor
@Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()
    var w = WatchWorkout()
    var reachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Команда телефону: complete, next, pause, resume, finish
    func send(_ cmd: String) {
        let s = WCSession.default
        if s.isReachable {
            s.sendMessage(["cmd": cmd], replyHandler: nil) { _ in s.transferUserInfo(["cmd": cmd]) }
        } else {
            s.transferUserInfo(["cmd": cmd])
        }
        WKInterfaceDevice.current().play(.click)
    }

    func sendHeartRate(_ bpm: Int) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["hr": bpm], replyHandler: nil, errorHandler: nil)
    }

    private func apply(_ ctx: [String: Any]) {
        let old = w
        w = WatchWorkout(ctx)
        if w.active && !old.active {
            WKInterfaceDevice.current().play(.start)
            Task { await HeartRate.shared.start() }
        }
        if !w.active && old.active {
            WKInterfaceDevice.current().play(.success)
            Task { await HeartRate.shared.stop() }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let r = session.isReachable
        Task { @MainActor in
            self.reachable = r
            self.apply(ctx)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
}

// MARK: Пульс (HealthKit, тренировочная сессия часов)

@MainActor
@Observable
final class HeartRate: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = HeartRate()
    var bpm = 0
    var running = false
    var denied = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() async {
        guard HKHealthStore.isHealthDataAvailable(), !running else { return }
        let hr = HKQuantityType(.heartRate)
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [hr])
        } catch {
            denied = true
            return
        }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .traditionalStrengthTraining
        cfg.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            s.startActivity(with: Date())
            try await b.beginCollection(at: Date())
            running = true
        } catch {
            running = false
        }
    }

    /// Тренировку в «Здоровье» записывает iPhone — на часах сессию не сохраняем, чтобы не было дублей
    func stop() async {
        guard running else { return }
        session?.end()
        try? await builder?.endCollection(at: Date())
        builder?.discardWorkout()
        running = false
        bpm = 0
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let q = workoutBuilder.statistics(for: hr)?.mostRecentQuantity() else { return }
        let v = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in
            self.bpm = v
            PhoneLink.shared.sendHeartRate(v)
        }
    }
}

// MARK: Экраны

struct WatchRootView: View {
    @State private var link = PhoneLink.shared

    var body: some View {
        if link.w.active {
            TabView {
                WorkoutPage(w: link.w)
                ControlsPage(w: link.w)
            }
            .tabViewStyle(.verticalPage)
        } else {
            IdlePage(reachable: link.reachable)
        }
    }
}

private struct IdlePage: View {
    let reachable: Bool
    var body: some View {
        VStack(spacing: 10) {
            Image("ox-logo").resizable().scaledToFit().frame(width: 34, height: 44)
            Text("OXION").font(.headline)
            Text(reachable ? "Начните тренировку на iPhone — она появится здесь" : "Откройте OXION на iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct WorkoutPage: View {
    let w: WatchWorkout
    @State private var hr = HeartRate.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if let st = w.startedAt, !w.paused {
                    Text(st.addingTimeInterval(w.pausedTotal), style: .timer)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.lime)
                } else {
                    Text("Пауза").font(.caption.bold()).foregroundStyle(.secondary)
                }
                Spacer()
                if hr.bpm > 0 {
                    Label("\(hr.bpm)", systemImage: "heart.fill")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.oxRed)
                }
            }

            if w.resting, let end = w.restEndsAt {
                Text("Отдых").font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.lime)
                    .multilineTextAlignment(.center)
                if !w.exercise.isEmpty {
                    Text("Дальше: \(w.exercise)").font(.footnote).lineLimit(1).foregroundStyle(.secondary)
                }
                Button("Пропустить") { PhoneLink.shared.send("next") }
                    .tint(.gray)
                    .task(id: end) {
                        // сигнал на руку, когда отдых закончился
                        let left = end.timeIntervalSinceNow
                        guard left > 0 else { return }
                        try? await Task.sleep(for: .seconds(left))
                        if !Task.isCancelled { WKInterfaceDevice.current().play(.notification) }
                    }
            } else {
                Text(w.exercise).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                Text("Подход \(w.setNo) из \(w.sets)").font(.footnote).foregroundStyle(.secondary)
                if !w.target.isEmpty {
                    Text(w.target).font(.title3.bold().monospacedDigit()).foregroundStyle(Color.lime)
                }
                Button {
                    PhoneLink.shared.send("complete")
                } label: {
                    Label("Готово", systemImage: "checkmark").font(.headline)
                }
                .tint(.lime)
                .foregroundStyle(.black)
                .disabled(w.paused)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ControlsPage: View {
    let w: WatchWorkout
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 8) {
            Text("\(w.setsDone) из \(w.setsTotal) подходов").font(.footnote).foregroundStyle(.secondary)
            ProgressView(value: Double(w.setsDone), total: Double(max(1, w.setsTotal))).tint(.lime)
            Button {
                PhoneLink.shared.send(w.paused ? "resume" : "pause")
            } label: {
                Label(w.paused ? "Продолжить" : "Пауза", systemImage: w.paused ? "play.fill" : "pause.fill")
            }
            Button(role: .destructive) { confirm = true } label: {
                Label("Завершить", systemImage: "stop.fill")
            }
            .tint(.oxRed)
        }
        .padding(.horizontal, 4)
        .confirmationDialog("Завершить тренировку?", isPresented: $confirm) {
            Button("Завершить", role: .destructive) { PhoneLink.shared.send("finish") }
            Button("Отмена", role: .cancel) {}
        }
    }
}
