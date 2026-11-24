import SwiftUI
import MapKit
import CoreLocation
import CoreMotion
import HealthKit

// MARK: - Кардио-тренировки в стиле «Фитнеса» iPhone:
// список видов с кнопкой ▶︎, цель, отсчёт «На старт! 3-2-1», крупные показатели,
// нижняя панель (пауза · секундомер · отрезок), шторка с «Завершить / Устройства / Поделиться / Заблокировать»,
// итог тренировки и сохранение в дневник и в «Здоровье».

enum CardioKind: String, CaseIterable, Identifiable {
    case outdoorWalk, outdoorRun, outdoorCycle, indoorWalk, indoorRun, indoorCycle, elliptical, stairs, rowing, hiit
    var id: String { rawValue }

    var title: String {
        switch self {
        case .outdoorWalk: "Ходьба на улице"
        case .outdoorRun: "Бег на улице"
        case .outdoorCycle: "Велосипед"
        case .indoorWalk: "Ходьба на дорожке"
        case .indoorRun: "Бег на дорожке"
        case .indoorCycle: "Велотренажёр"
        case .elliptical: "Эллипсоид"
        case .stairs: "Степпер"
        case .rowing: "Гребля"
        case .hiit: "Интервальная (HIIT)"
        }
    }
    var short: String {
        switch self {
        case .outdoorWalk, .indoorWalk: "Ходьба"
        case .outdoorRun, .indoorRun: "Бег"
        case .outdoorCycle, .indoorCycle: "Велосипед"
        default: title
        }
    }
    var icon: String {
        switch self {
        case .outdoorWalk: "figure.walk"
        case .outdoorRun: "figure.run"
        case .outdoorCycle: "figure.outdoor.cycle"
        case .indoorWalk: "figure.walk.treadmill"
        case .indoorRun: "figure.run.treadmill"
        case .indoorCycle: "figure.indoor.cycle"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stair.stepper"
        case .rowing: "figure.indoor.rowing"
        case .hiit: "figure.highintensity.intervaltraining"
        }
    }
    var outdoor: Bool { [.outdoorWalk, .outdoorRun, .outdoorCycle].contains(self) }
    var usesGPS: Bool { outdoor }
    /// дистанция по шагомеру iPhone (дорожка)
    var usesPedometer: Bool { self == .indoorWalk || self == .indoorRun }
    var hasDistance: Bool { usesGPS || usesPedometer }
    var isCycle: Bool { self == .outdoorCycle || self == .indoorCycle }
    var walkLike: Bool { self == .outdoorWalk || self == .indoorWalk }
    /// MET — сколько энергии тратится относительно покоя
    var met: Double {
        switch self {
        case .outdoorWalk, .indoorWalk: 3.8
        case .outdoorRun, .indoorRun: 9.8
        case .outdoorCycle: 7.5
        case .indoorCycle: 6.8
        case .elliptical: 5.0
        case .stairs: 9.0
        case .rowing: 7.0
        case .hiit: 8.0
        }
    }
    var hkType: HKWorkoutActivityType {
        switch self {
        case .outdoorWalk, .indoorWalk: .walking
        case .outdoorRun, .indoorRun: .running
        case .outdoorCycle, .indoorCycle: .cycling
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .rowing: .rowing
        case .hiit: .highIntensityIntervalTraining
        }
    }
}

enum CardioGoal: Equatable {
    case open
    case distance(Double)   // км
    case time(Int)          // минуты
    case kcal(Int)

    var label: String {
        switch self {
        case .open: "Открытая цель"
        case .distance(let k): String(format: "%g км", k).replacingOccurrences(of: ".", with: ",")
        case .time(let m): m >= 60 ? "\(m / 60) ч \(m % 60 > 0 ? "\(m % 60) мин" : "")" : "\(m) мин"
        case .kcal(let c): "\(c) ккал"
        }
    }
    var icon: String {
        switch self {
        case .open: "infinity"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .time: "timer"
        case .kcal: "flame.fill"
        }
    }
}

struct CardioLap: Identifiable {
    let id = UUID()
    let n: Int
    let time: TimeInterval
    let distance: Double
}

// MARK: - Движок

@MainActor
@Observable
final class CardioEngine: NSObject, CLLocationManagerDelegate {
    enum Phase { case idle, countdown, active, ended }

    var kind: CardioKind = .outdoorWalk
    var goal: CardioGoal = .open
    var phase: Phase = .idle
    var paused = false
    var startedAt: Date?
    var endedAt: Date?
    var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?

    var distance: Double = 0       // метры
    var coords: [CLLocationCoordinate2D] = []
    var laps: [CardioLap] = []
    private var lapStartTime: TimeInterval = 0
    private var lapStartDist: Double = 0
    var heartRate = 0
    var heartSamples: [Int] = []
    var hkActive: Double?          // ккал из «Здоровья», если сессия работает
    var gpsDenied = false
    var goalReached = false

    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private var pedLast: Double?
    private var last: CLLocation?
    private var tick: Timer?
    private var hk: AnyObject?     // HKSessionBox

    var weightKg: Double { HealthKitManager.shared.weight ?? UserDefaults.standard.object(forKey: "body.kg") as? Double ?? 70 }

    override init() {
        super.init()
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 5
        NotificationCenter.default.addObserver(forName: .oxRunTogglePause, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .active else { return }
                self.togglePause()
            }
        }
    }

    // MARK: время и показатели

    func elapsed(_ now: Date = Date()) -> TimeInterval {
        guard let s = startedAt else { return 0 }
        let end = endedAt ?? (paused ? (pausedAt ?? now) : now)
        return max(0, end.timeIntervalSince(s) - pausedTotal)
    }

    var totalKcal: Int {
        if let a = hkActive { return Int(a + weightKg * elapsed() / 3600 * 1.0) }
        return Int(kind.met * weightKg * elapsed() / 3600)
    }
    var activeKcal: Int {
        if let a = hkActive { return Int(a) }
        return Int(max(0, kind.met - 1) * weightKg * elapsed() / 3600)
    }
    /// сек/км
    var paceSec: Double? {
        guard distance > 50 else { return nil }
        return elapsed() / (distance / 1000)
    }
    var paceText: String {
        guard let p = paceSec, p < 3600 else { return "—'——\"" }
        return String(format: "%d'%02d\"", Int(p) / 60, Int(p) % 60)
    }
    var speedText: String {
        let e = elapsed()
        guard e > 5, distance > 20 else { return "0,0" }
        return String(format: "%.1f", distance / 1000 / (e / 3600)).replacingOccurrences(of: ".", with: ",")
    }
    var hrFresh: Bool { heartRate > 0 }
    var avgHeart: Int? { heartSamples.isEmpty ? nil : heartSamples.reduce(0, +) / heartSamples.count }

    var goalProgress: Double {
        switch goal {
        case .open: return 0
        case .distance(let k): return distance / 1000 / max(0.1, k)
        case .time(let m): return elapsed() / Double(max(1, m) * 60)
        case .kcal(let c): return Double(activeKcal) / Double(max(1, c))
        }
    }
    var goalLeftText: String? {
        switch goal {
        case .open: return nil
        case .distance(let k):
            let left = max(0, k * 1000 - distance)
            return left > 0 ? String(format: "осталось %.2f км", left / 1000).replacingOccurrences(of: ".", with: ",") : "цель выполнена"
        case .time(let m):
            let left = max(0, Double(m * 60) - elapsed())
            return left > 0 ? "осталось \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))" : "цель выполнена"
        case .kcal(let c):
            let left = max(0, c - activeKcal)
            return left > 0 ? "осталось \(left) ккал" : "цель выполнена"
        }
    }

    // MARK: управление

    func prepare(_ k: CardioKind, goal g: CardioGoal) {
        kind = k
        goal = g
        if k.usesGPS { askLocation() }
    }

    func start() {
        distance = 0; coords = []; laps = []; heartSamples = []; heartRate = 0
        lapStartTime = 0; lapStartDist = 0; pausedTotal = 0; pausedAt = nil
        last = nil; pedLast = nil; hkActive = nil; goalReached = false; endedAt = nil
        startedAt = Date()
        paused = false
        phase = .active
        if kind.usesGPS {
            let st = location.authorizationStatus
            if st == .denied || st == .restricted { gpsDenied = true }
            location.allowsBackgroundLocationUpdates = true
            location.showsBackgroundLocationIndicator = true
            location.pausesLocationUpdatesAutomatically = false
            location.startUpdatingLocation()
        }
        if kind.usesPedometer, CMPedometer.isDistanceAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                let d = data?.distance?.doubleValue
                Task { @MainActor in self?.pedometer(d) }
            }
        }
        startHealth()
        RunIsland.start(kind: kind.walkLike ? "walk" : "run", title: kind.title)
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everySecond() }
        }
        OxHaptics.play(.setDone)
    }

    private func pedometer(_ d: Double?) {
        guard let d else { return }
        defer { pedLast = d }
        guard let p = pedLast, phase == .active, !paused else { return }
        distance += max(0, d - p)
    }

    private func everySecond() {
        guard phase == .active else { return }
        let hub = BLEHub.shared
        if hub.hrFresh { heartRate = hub.heartRate }
        if heartRate > 0, !paused { heartSamples.append(heartRate) }
        if !goalReached, goal != .open, goalProgress >= 1 {
            goalReached = true
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "checkmark.seal.fill", title: "Цель выполнена!", message: goal.label)
        }
        pushIsland()
    }

    func togglePause() {
        guard phase == .active else { return }
        paused.toggle()
        if paused {
            pausedAt = Date()
            if kind.usesGPS { location.stopUpdatingLocation() }
        } else {
            pausedTotal += Date().timeIntervalSince(pausedAt ?? Date())
            pausedAt = nil
            last = nil
            if kind.usesGPS { location.startUpdatingLocation() }
        }
        pauseHealth(paused)
        OxHaptics.play(.select)
        pushIsland(force: true)
    }

    func lap() {
        guard phase == .active else { return }
        let t = elapsed()
        laps.append(CardioLap(n: laps.count + 1, time: t - lapStartTime, distance: distance - lapStartDist))
        lapStartTime = t
        lapStartDist = distance
        Haptic.tap(.medium)
    }
    var currentLapTime: TimeInterval { elapsed() - lapStartTime }

    func end() {
        guard phase == .active else { return }
        if paused { pausedTotal += Date().timeIntervalSince(pausedAt ?? Date()); paused = false; pausedAt = nil }
        endedAt = Date()
        if elapsed() - lapStartTime > 5 { laps.append(CardioLap(n: laps.count + 1, time: elapsed() - lapStartTime, distance: distance - lapStartDist)) }
        phase = .ended
        tick?.invalidate(); tick = nil
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        RunIsland.end()
        endHealth()
        OxHaptics.play(.workoutDone)
    }

    func cancel() {
        tick?.invalidate(); tick = nil
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        RunIsland.end()
        discardHealth()
        phase = .idle
    }

    private func pushIsland(force: Bool = false) {
        guard let s = startedAt else { return }
        RunIsland.update(kind: kind.walkLike ? "walk" : "run", paused: paused, timerStart: s.addingTimeInterval(pausedTotal),
                         elapsed: Int(elapsed()), distance: distance, heartRate: heartRate > 0 ? heartRate : nil,
                         calories: activeKcal, coords: coords, force: force)
    }

    // MARK: геопозиция

    func askLocation() {
        let st = location.authorizationStatus
        if st == .notDetermined { location.requestWhenInUseAuthorization() }
        gpsDenied = st == .denied || st == .restricted
        if location.accuracyAuthorization == .reducedAccuracy {
            location.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "run")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.phase == .active, !self.paused else { return }
            for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 35 {
                if let p = self.last {
                    let d = l.distance(from: p)
                    if d < (self.kind.isCycle ? 200 : 80) { self.distance += d }
                }
                self.last = l
                self.coords.append(l.coordinate)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in self.gpsDenied = st == .denied || st == .restricted }
    }

    // MARK: «Здоровье» — тренировочная сессия iPhone (iOS 26)

    private func startHealth() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let box = HKSessionBox(kind: kind) { [weak self] active, hr in
            Task { @MainActor in
                guard let self else { return }
                if let active { self.hkActive = active }
                if let hr, hr > 0, !BLEHub.shared.hrFresh { self.heartRate = hr }
            }
        }
        hk = box
        Task { await box.start() }
    }
    private func pauseHealth(_ p: Bool) { (hk as? HKSessionBox)?.pause(p) }
    private func endHealth() {
        guard let box = hk as? HKSessionBox else { return }
        let dist = distance, kcal = Double(activeKcal)
        Task { await box.finish(distance: dist, kcal: kcal) }
        hk = nil
    }
    private func discardHealth() {
        (hk as? HKSessionBox)?.discard()
        hk = nil
    }
}

/// Обёртка над HKWorkoutSession + HKLiveWorkoutBuilder: пульс и калории от часов/AirPods, тренировка в «Здоровье».
final class HKSessionBox: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    private let store = HKHealthStore()
    private let kind: CardioKind
    private let onData: (Double?, Int?) -> Void
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    init(kind: CardioKind, onData: @escaping (Double?, Int?) -> Void) {
        self.kind = kind
        self.onData = onData
    }

    func start() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate), HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }
            let cfg = HKWorkoutConfiguration()
            cfg.activityType = kind.hkType
            cfg.locationType = kind.outdoor ? .outdoor : .indoor
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
        } catch {
            session = nil
            builder = nil
        }
    }

    func pause(_ p: Bool) {
        guard let session else { return }
        p ? session.pause() : session.resume()
    }

    func finish(distance: Double, kcal: Double) async {
        guard let session, let builder else { return }
        session.end()
        do {
            let end = Date()
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {}
        self.session = nil
        self.builder = nil
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var active: Double?
        var hr: Int?
        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)),
           let q = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
            active = q.doubleValue(for: .kilocalorie())
        }
        if collectedTypes.contains(HKQuantityType(.heartRate)),
           let q = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
            hr = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }
        if active != nil || hr != nil { onData(active, hr) }
    }
}

// MARK: - Экран выбора («Тренировка»)

struct CardioHubView: View {
    @State private var goals: [CardioKind: CardioGoal] = [:]
    @State private var goalFor: CardioKind?
    @State private var launch: CardioKind?
    @State private var hideBanner = UserDefaults.standard.bool(forKey: "cardio.banner.hidden")
    @State private var devices = false
    private let hub = BLEHub.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !hideBanner && !hub.hrFresh {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "heart.fill").font(.title2).foregroundStyle(Color.lime)
                        Text("Чтобы видеть пульс и точнее считать калории, подключите Apple Watch, AirPods с датчиком пульса или нагрудный пульсометр.")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            withAnimation { hideBanner = true }
                            UserDefaults.standard.set(true, forKey: "cardio.banner.hidden")
                        } label: { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary) }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture { devices = true }
                }
                Text("На улице").font(.title3.bold()).padding(.top, 6)
                ForEach(CardioKind.allCases.filter(\.outdoor)) { card($0) }
                Text("В зале").font(.title3.bold()).padding(.top, 6)
                ForEach(CardioKind.allCases.filter { !$0.outdoor }) { card($0) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(Color.oxBg)
        .navigationTitle("Тренировка")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { devices = true } label: {
                    Image(systemName: hub.hrFresh ? "heart.circle.fill" : "sensor.tag.radiowaves.forward")
                }
                .accessibilityLabel("Устройства")
            }
        }
        .sheet(item: $goalFor) { k in
            CardioGoalSheet(kind: k, goal: goals[k] ?? .open) { goals[k] = $0 }
        }
        .sheet(isPresented: $devices) { NavigationStack { DevicePanelView() } }
        .fullScreenCover(item: $launch) { k in
            CardioSessionView(kind: k, goal: goals[k] ?? .open)
        }
    }

    private func card(_ k: CardioKind) -> some View {
        let g = goals[k] ?? .open
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: k.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.lime)
                    .frame(height: 40)
                Spacer()
                Button {
                    Haptic.tap(.medium)
                    launch = k
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.onLime)
                        .frame(width: 48, height: 48)
                        .background(Color.lime, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Начать: \(k.title)")
            }
            Text(k.title).font(.title3.bold())
            HStack(spacing: 8) {
                Button { goalFor = k } label: {
                    Label(g.label, systemImage: g.icon)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.lime.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Label(k.usesGPS ? "GPS" : (k.usesPedometer ? "Шагомер" : "Время"),
                      systemImage: k.usesGPS ? "location.fill" : (k.usesPedometer ? "shoeprints.fill" : "stopwatch"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 112)
                    .padding(.vertical, 10)
                    .background(Color.lime.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.lime.opacity(0.09), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { launch = k }
    }
}

struct CardioGoalSheet: View {
    let kind: CardioKind
    @State var goal: CardioGoal
    let done: (CardioGoal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var km = 3.0
    @State private var min = 30
    @State private var kcal = 300

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("", selection: $mode) {
                    Text("Открытая").tag(0)
                    if kind.hasDistance { Text("Дистанция").tag(1) }
                    Text("Время").tag(2)
                    Text("Калории").tag(3)
                }
                .pickerStyle(.segmented)
                Group {
                    switch mode {
                    case 1:
                        stepper(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ","), "км",
                                minus: { km = max(0.5, km - 0.5) }, plus: { km = Swift.min(100, km + 0.5) })
                    case 2:
                        stepper("\(min)", "мин", minus: { min = max(5, min - 5) }, plus: { min = Swift.min(600, min + 5) })
                    case 3:
                        stepper("\(kcal)", "ккал", minus: { kcal = max(50, kcal - 50) }, plus: { kcal = Swift.min(3000, kcal + 50) })
                    default:
                        VStack(spacing: 8) {
                            Image(systemName: "infinity").font(.system(size: 54, weight: .bold)).foregroundStyle(Color.lime)
                            Text("Без цели — просто записываем тренировку").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 150)
                Spacer()
            }
            .padding(20)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        switch mode {
                        case 1: done(.distance(km))
                        case 2: done(.time(min))
                        case 3: done(.kcal(kcal))
                        default: done(.open)
                        }
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                switch goal {
                case .open: mode = 0
                case .distance(let k): mode = 1; km = k
                case .time(let m): mode = 2; min = m
                case .kcal(let c): mode = 3; kcal = c
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func stepper(_ v: String, _ unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 24) {
            Button { Haptic.tap(); minus() } label: { Image(systemName: "minus").font(.title.bold()).frame(width: 60, height: 60) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            VStack(spacing: 0) {
                Text(v).font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(unit).font(.headline).foregroundStyle(.secondary)
            }
            .frame(minWidth: 130)
            Button { Haptic.tap(); plus() } label: { Image(systemName: "plus").font(.title.bold()).frame(width: 60, height: 60) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
        }
    }
}

// MARK: - Сессия: отсчёт → показатели → итог

struct CardioSessionView: View {
    let kind: CardioKind
    let goal: CardioGoal
    @Environment(\.dismiss) private var dismiss
    @State private var e = CardioEngine()
    @State private var count = 4            // 4 = «На старт!», потом 3-2-1
    @State private var ring: CGFloat = 1
    @State private var sheetOpen = false
    @State private var locked = false
    @State private var page = 0
    @State private var saving = false
    @State private var saved = false
    @State private var devices = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch e.phase {
            case .idle, .countdown: countdown
            case .active: live
            case .ended: summary
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear {
            e.prepare(kind, goal: goal)
            e.phase = .countdown
            runCountdown()
        }
        .onDisappear { if e.phase == .active { e.end() } }
        .sheet(isPresented: $devices) { NavigationStack { DevicePanelView() } }
        .persistentSystemOverlays(locked ? .hidden : .automatic)
    }

    // MARK: отсчёт

    private var countdown: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.lime.opacity(0.25), lineWidth: 16)
                Circle().trim(from: 0, to: ring)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(count == 4 ? "На старт!" : "\(count)")
                    .font(.system(size: count == 4 ? 38 : 110, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 250, height: 250)
            Text(kind.title).font(.title2.bold()).foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        .onTapGesture { count = 0; e.start() }   // нажатие — старт без отсчёта
        .overlay(alignment: .topLeading) {
            Button { e.cancel(); dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .padding(16)
        }
    }

    private func runCountdown() {
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            for n in [3, 2, 1] {
                guard e.phase == .countdown else { return }
                ring = 1
                withAnimation(.snappy) { count = n }
                Haptic.tap(.heavy)
                withAnimation(.linear(duration: 0.95)) { ring = 0.02 }
                try? await Task.sleep(for: .milliseconds(1000))
            }
            guard e.phase == .countdown else { return }
            e.start()
        }
    }

    // MARK: показатели

    private var live: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                metricsPage.tag(0)
                if kind.usesGPS { mapPage.tag(1) }
                lapsPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                if sheetOpen && !locked { actions.transition(.move(edge: .bottom).combined(with: .opacity)) }
                bar
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .top) { topRow }
        .overlay {
            if locked {
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { Haptic.tap(.light) }
            }
        }
    }

    private var topRow: some View {
        HStack {
            Image(systemName: kind.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.lime)
                .frame(width: 50, height: 50)
                .background(Color.lime.opacity(0.15), in: Circle())
            Spacer()
            if e.paused {
                Text("ПАУЗА").font(.caption.bold()).foregroundStyle(.yellow)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.yellow.opacity(0.15), in: Capsule())
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ZStack {
                    Circle().stroke(Color.red.opacity(0.25), lineWidth: 7)
                    Circle().trim(from: 0, to: min(1, goal == .open ? Double(e.activeKcal) / 300 : e.goalProgress))
                        .stroke(goal == .open ? Color.red : Color.lime, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: goal == .open ? "flame.fill" : goal.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(goal == .open ? Color.red : Color.lime)
                }
                .frame(width: 46, height: 46)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .opacity(locked ? 0.5 : 1)
    }

    private var metricsPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 30) {
                Spacer().frame(height: 70)
                if kind.hasDistance {
                    metric(distanceValue, distanceUnit, "Дистанция")
                    if kind.isCycle {
                        metric(e.speedText, "км/ч", "Средняя скорость")
                    } else {
                        metric(e.paceText, "", "Средний темп")
                    }
                } else {
                    metric(clockShort(e.elapsed()), "", "Время")
                }
                HStack(alignment: .top, spacing: 0) {
                    metric("\(e.activeKcal)", "ккал", "Активные килокалории", size: 50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    metric("\(e.totalKcal)", "ккал", "Всего килокалорий", size: 50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if e.hrFresh {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "heart.fill").foregroundStyle(.red).symbolEffect(.pulse)
                        Text("\(e.heartRate)").font(.system(size: 50, weight: .semibold, design: .rounded).monospacedDigit())
                        Text("уд/мин").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                if let left = e.goalLeftText {
                    Label(left, systemImage: goal.icon)
                        .font(.headline)
                        .foregroundStyle(e.goalReached ? Color.lime : .secondary)
                }
                if e.gpsDenied && kind.usesGPS {
                    Label("Нет доступа к геопозиции — дистанция не считается", systemImage: "location.slash")
                        .font(.footnote.bold()).foregroundStyle(.orange)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }

    private var distanceValue: String {
        e.distance < 1000 ? "\(Int(e.distance))" : String(format: "%.2f", e.distance / 1000).replacingOccurrences(of: ".", with: ",")
    }
    private var distanceUnit: String { e.distance < 1000 ? "м" : "км" }

    private func metric(_ v: String, _ unit: String, _ label: String, size: CGFloat = 86) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v).font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit.uppercased() == unit ? unit : unit).font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                }
            }
            Text(label).font(.headline).foregroundStyle(.secondary)
        }
    }

    private var mapPage: some View {
        Map {
            if e.coords.count > 1 {
                MapPolyline(coordinates: e.coords)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .ignoresSafeArea()
    }

    private var lapsPage: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 14) {
                Spacer().frame(height: 70)
                Text("Отрезки").font(.largeTitle.bold())
                HStack {
                    Text("Сейчас · \(e.laps.count + 1)").font(.headline).foregroundStyle(Color.lime)
                    Spacer()
                    Text(clockShort(e.currentLapTime)).font(.title2.bold().monospacedDigit())
                }
                .padding(14)
                .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(e.laps.reversed()) { l in lapRow(l) }
                    }
                }
                if e.laps.isEmpty {
                    Text("Нажмите кнопку справа внизу, чтобы отметить отрезок — например, каждый круг или километр.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
        }
    }

    private func lapRow(_ l: CardioLap) -> some View {
        HStack {
            Text("\(l.n)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            Text(clockShort(l.time)).font(.title3.bold().monospacedDigit())
            Spacer()
            if kind.hasDistance {
                Text(String(format: "%.2f км", l.distance / 1000).replacingOccurrences(of: ".", with: ","))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: нижняя панель и шторка

    private var bar: some View {
        VStack(spacing: 8) {
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 40, height: 5)
                .padding(.top, 8)
            HStack(spacing: 0) {
                if locked {
                    Button {
                        Haptic.tap(.medium)
                        withAnimation(.snappy) { locked = false }
                    } label: {
                        Label("Разблокировать", systemImage: "lock.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                } else {
                    Button { e.togglePause() } label: {
                        Image(systemName: e.paused ? "arrow.clockwise" : "pause.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(e.paused ? .yellow : .white)
                            .frame(width: 64, height: 64)
                            .background(Color.white.opacity(0.12), in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(e.paused ? "Продолжить" : "Пауза")
                    Spacer()
                    TimelineView(.animation(minimumInterval: 0.05, paused: e.paused)) { ctx in
                        Text(clockCenti(e.elapsed(ctx.date)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(e.paused ? Color.yellow.opacity(0.55) : .yellow)
                    }
                    Spacer()
                    Button { e.lap() } label: {
                        Text("\(e.laps.count + 1)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                            .frame(width: 64, height: 64)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .disabled(e.paused)
                    .accessibilityLabel("Отрезок")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 12).onEnded { v in
            guard !locked else { return }
            withAnimation(.spring(duration: 0.35)) { sheetOpen = v.translation.height < 0 }
        })
        .onTapGesture {
            guard !locked else { return }
            withAnimation(.spring(duration: 0.35)) { sheetOpen.toggle() }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            actionRow("Завершить тренировку", "xmark", tint: .red, filled: true) {
                withAnimation { sheetOpen = false }
                e.end()
            }
            actionRow("Подключённые устройства", "sensor.tag.radiowaves.forward", tint: .white) { devices = true }
            ShareLink(item: shareText) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .foregroundStyle(.white)
            actionRow("Заблокировать", "lock.fill", tint: .white) {
                withAnimation(.snappy) { sheetOpen = false; locked = true }
                Haptic.tap(.medium)
            }
        }
        .padding(14)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.bottom, 8)
    }

    private func actionRow(_ t: String, _ icon: String, tint: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(filled ? tint.opacity(0.16) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var shareText: String {
        var s = "\(kind.title) в Oxion: \(clockShort(e.elapsed()))"
        if kind.hasDistance { s += ", \(distanceValue) \(distanceUnit)" }
        s += ", \(e.activeKcal) ккал"
        return s
    }

    // MARK: итог

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: kind.icon).font(.title).foregroundStyle(Color.lime)
                        .frame(width: 56, height: 56).background(Color.lime.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.title2.bold())
                        if let s = e.startedAt {
                            Text(s.formatted(.dateTime.day().month(.wide).hour().minute())).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 24)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("Время", clockShort(e.elapsed()), .yellow)
                    if kind.hasDistance {
                        tile("Дистанция", "\(distanceValue) \(distanceUnit)", .cyan)
                        tile(kind.isCycle ? "Ср. скорость" : "Ср. темп", kind.isCycle ? "\(e.speedText) км/ч" : e.paceText, .cyan)
                    }
                    tile("Активные", "\(e.activeKcal) ккал", .red)
                    tile("Всего", "\(e.totalKcal) ккал", .red)
                    if let hr = e.avgHeart { tile("Ср. пульс", "\(hr) уд/мин", .pink) }
                }

                if kind.usesGPS, e.coords.count > 1 {
                    Map(interactionModes: []) {
                        MapPolyline(coordinates: e.coords)
                            .stroke(Color.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if e.laps.count > 1 {
                    Text("Отрезки").font(.title3.bold())
                    ForEach(e.laps) { lapRow($0) }
                }

                VStack(spacing: 10) {
                    Button { Task { await save() } } label: {
                        Label(saved ? "Сохранено" : "Сохранить в дневник", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                    .disabled(saving || saved)
                    Button(saved ? "Готово" : "Не сохранять") { dismiss() }
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func tile(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.subheadline).foregroundStyle(.secondary)
            Text(v).font(.title2.bold().monospacedDigit()).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func save() async {
        guard e.elapsed() >= 30 else {
            OxAlert.show(icon: kind.icon, title: "Слишком коротко", message: "Тренировки короче 30 секунд не сохраняем.")
            return
        }
        saving = true
        defer { saving = false }
        let start = e.startedAt ?? Date()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        var title = kind.title
        if kind.hasDistance, e.distance >= 100 {
            title = kind.short + " " + String(format: "%.1f км", e.distance / 1000).replacingOccurrences(of: ".", with: ",")
        }
        var parts = ["время \(clockShort(e.elapsed()))"]
        if kind.hasDistance {
            parts.append("дистанция \(distanceValue) \(distanceUnit)")
            parts.append(kind.isCycle ? "скорость \(e.speedText) км/ч" : "темп \(e.paceText) /км")
        }
        parts.append("\(e.activeKcal) ккал")
        if let hr = e.avgHeart { parts.append("пульс \(hr)") }
        if e.laps.count > 1 { parts.append("отрезков: \(e.laps.count)") }
        let note = parts.joined(separator: " · ").prefix(1).uppercased() + parts.joined(separator: " · ").dropFirst()
        do {
            let _: Workout = try await API.call("/workouts", method: "POST", body: [
                "date": RU.dayFormatter.string(from: start), "title": title, "groups": ["cardio"],
                "time": f.string(from: start), "calories": e.activeKcal, "note": String(note)])
            saved = true
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "checkmark.circle.fill", title: "Сохранено в дневник", message: String(note))
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func clockShort(_ s: TimeInterval) -> String {
        let i = Int(s)
        return i >= 3600 ? String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60) : String(format: "%02d:%02d", i / 60, i % 60)
    }
    private func clockCenti(_ s: TimeInterval) -> String {
        let i = Int(s), cs = Int((s - Double(i)) * 100)
        return i >= 3600 ? String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60)
                         : String(format: "%02d:%02d,%02d", i / 60, i % 60, cs)
    }
}
