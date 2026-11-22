import SwiftUI
import MapKit
import CoreLocation
import CoreMotion

// MARK: - Пробежка и прогулка с картой (GPS), шаги за день и определение активности (Core Motion)

@MainActor
@Observable
final class RunTracker: NSObject, CLLocationManagerDelegate {
    enum Kind: String, CaseIterable { case run, walk
        var title: String { self == .run ? "Бег" : "Ходьба" }
        var icon: String { self == .run ? "figure.run" : "figure.walk" }
    }

    var kind: Kind = .run
    var running = false
    var paused = false
    var coords: [CLLocationCoordinate2D] = []
    var distance: Double = 0          // метры
    var startedAt: Date?
    var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    private var last: CLLocation?
    var denied = false

    // шаги и активность
    var stepsToday: Int = 0
    var activityText = ""
    var suggestWalk = false

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private let activity = CMMotionActivityManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        // кнопка паузы в Dynamic Island
        NotificationCenter.default.addObserver(forName: .oxRunTogglePause, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.togglePause()
            }
        }
    }

    /// Обновить Live Activity: время, дистанция, темп, пульс, маршрут
    func pushIsland(force: Bool = false) {
        guard running, let s = startedAt else { return }
        let hub = BLEHub.shared
        let hr: Int? = (hub.heartAt.map { Date().timeIntervalSince($0) < 15 } ?? false) && hub.heartRate > 0 ? hub.heartRate : nil
        RunIsland.update(kind: kind.rawValue, paused: paused, timerStart: s.addingTimeInterval(pausedTotal),
                         elapsed: Int(elapsed(Date())), distance: distance, heartRate: hr, calories: calories,
                         coords: coords, force: force)
    }

    func elapsed(_ now: Date) -> TimeInterval {
        guard let s = startedAt else { return 0 }
        let end = paused ? (pausedAt ?? now) : now
        return max(0, end.timeIntervalSince(s) - pausedTotal)
    }

    /// мин/км
    func pace(_ now: Date) -> String {
        guard distance > 50 else { return "—" }
        let secPerKm = elapsed(now) / (distance / 1000)
        return String(format: "%d:%02d", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    var calories: Int {
        let kg = 70.0
        return Int((distance / 1000) * kg * (kind == .run ? 1.0 : 0.55))
    }

    /// iPhone отдаёт «примерную» геопозицию (большой круг на карте) — просим точную на время тренировки
    var approximate = false

    func askPrecise() {
        let st = manager.authorizationStatus
        if st == .notDetermined { manager.requestWhenInUseAuthorization(); return }
        approximate = manager.accuracyAuthorization == .reducedAccuracy
        if approximate {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "run") { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.approximate = self.manager.accuracyAuthorization == .reducedAccuracy
                }
            }
        }
    }

    func start() {
        askPrecise()
        let st = manager.authorizationStatus
        if st == .notDetermined { manager.requestWhenInUseAuthorization() }
        if st == .denied || st == .restricted { denied = true; return }
        coords = []
        distance = 0
        last = nil
        pausedTotal = 0
        startedAt = Date()
        running = true
        paused = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        OxHaptics.play(.setDone)
        RunIsland.start(kind: kind.rawValue, title: kind.title)
    }

    func togglePause() {
        paused.toggle()
        if paused {
            pausedAt = Date()
            manager.stopUpdatingLocation()
        } else {
            pausedTotal += Date().timeIntervalSince(pausedAt ?? Date())
            pausedAt = nil
            last = nil
            manager.startUpdatingLocation()
        }
        OxHaptics.play(.select)
        pushIsland(force: true)
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        pushIsland(force: true)
        running = false
        if paused { pausedTotal += Date().timeIntervalSince(pausedAt ?? Date()); paused = false }
        RunIsland.end()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 35 {
                if let p = self.last {
                    let d = l.distance(from: p)
                    if d < 80 { self.distance += d }    // отсекаем скачки GPS
                }
                self.last = l
                self.coords.append(l.coordinate)
            }
            self.pushIsland()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in
            self.denied = st == .denied || st == .restricted
            if st == .authorizedWhenInUse || st == .authorizedAlways { self.askPrecise() }
        }
    }

    // MARK: шаги и «вы, похоже, идёте»

    func startMotion() {
        if CMPedometer.isStepCountingAvailable() {
            let start = Calendar.current.startOfDay(for: Date())
            pedometer.startUpdates(from: start) { data, _ in
                let n = data?.numberOfSteps.intValue ?? 0
                Task { @MainActor in self.stepsToday = n }
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { a in
                guard let a else { return }
                let text: String
                if a.running { text = "Похоже, вы бежите" }
                else if a.walking { text = "Похоже, вы идёте" }
                else if a.cycling { text = "Похоже, вы на велосипеде" }
                else if a.automotive { text = "Вы в транспорте" }
                else { text = "" }
                let walking = (a.walking || a.running) && a.confidence != .low
                Task { @MainActor in
                    self.activityText = text
                    self.suggestWalk = walking && !self.running
                    if a.running, !self.running { self.kind = .run }
                    if a.walking, !self.running { self.kind = .walk }
                }
            }
        }
    }

    func stopMotion() {
        pedometer.stopUpdates()
        activity.stopActivityUpdates()
    }
}

struct RunTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var t = RunTracker()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var saving = false
    @Namespace private var mapScope

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if t.coords.count > 1 {
                    MapPolyline(coordinates: t.coords)
                        .stroke(Color.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { }
            .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .bottom) {
                // панель снизу: значок «Карты» и кнопки карты поднимаются над ней, а не прячутся
                panel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .overlay(alignment: .topTrailing) {
                // кнопки карты — под шапкой, а не в строке состояния
                VStack(spacing: 10) {
                    MapUserLocationButton(scope: mapScope)
                    MapCompass(scope: mapScope)
                }
                .buttonBorderShape(.circle)
                .padding(.trailing, 12)
                .padding(.top, 8)
            }
            .overlay(alignment: .top) {
                if t.approximate {
                    Button { t.askPrecise() } label: {
                        Label("Геопозиция примерная — включить точную", systemImage: "location.circle")
                            .font(.footnote.bold())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 8)
                }
            }
        .mapScope(mapScope)     // кнопки «моё место» и компас работают только внутри общей области карты
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(t.kind == .run ? "Пробежка" : "Прогулка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") {
                    if t.running {
                        OxAlert.confirm(title: "Остановить без сохранения?", message: "Маршрут не сохранится в дневник.", action: "Остановить", destructive: true) {
                            t.stop(); dismiss()
                        }
                    } else { dismiss() }
                }
            }
        }
        .onAppear { t.startMotion(); t.askPrecise() }
        .onDisappear { t.stopMotion() }
        .onChange(of: t.denied) {
            if t.denied { PermPrompt.show(.location, denied: true) }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            if !t.running {
                if t.suggestWalk {
                    Label("\(t.activityText) — записать тренировку?", systemImage: "sparkles")
                        .font(.subheadline.bold()).foregroundStyle(Color.limeInk)
                }
                Picker("", selection: $t.kind) {
                    ForEach(RunTracker.Kind.allCases, id: \.self) { k in Label(k.title, systemImage: k.icon).tag(k) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Label("\(t.stepsToday) шагов сегодня", systemImage: "shoeprints.fill")
                    Spacer()
                    if !t.activityText.isEmpty { Text(t.activityText).foregroundStyle(Color.oxHint) }
                }
                .font(.caption)
            }

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack {
                    stat(String(format: "%.2f", t.distance / 1000), "км")
                    stat(clock(t.elapsed(ctx.date)), "время")
                    stat(t.pace(ctx.date), "темп /км")
                    stat("\(t.calories)", "ккал")
                }
            }

            if t.running {
                HStack(spacing: 10) {
                    Button { t.togglePause() } label: {
                        Label(t.paused ? "Дальше" : "Пауза", systemImage: t.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { Task { await finish() } } label: {
                        Label("Завершить", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
                    .disabled(saving)
                }
                .lineLimit(1)
            } else {
                Button { t.start() } label: {
                    Label("Старт", systemImage: t.kind.icon).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(t).font(.caption2).foregroundStyle(Color.oxHint)
        }
        .frame(maxWidth: .infinity)
    }

    private func clock(_ s: TimeInterval) -> String {
        let i = Int(s)
        return i >= 3600 ? String(format: "%d:%02d:%02d", i / 3600, i / 60 % 60, i % 60) : String(format: "%d:%02d", i / 60, i % 60)
    }

    private func finish() async {
        let now = Date()
        let elapsed = t.elapsed(now)
        let km = t.distance / 1000
        let start = t.startedAt ?? now
        t.stop()
        guard km >= 0.05 else {
            OxAlert.show(icon: "figure.run", title: "Слишком коротко", message: "Маршрут меньше 50 метров — в дневник не сохраняем.")
            return
        }
        saving = true
        defer { saving = false }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let title = (t.kind == .run ? "Пробежка " : "Прогулка ") + String(format: "%.1f км", km).replacingOccurrences(of: ".", with: ",")
        let note = "Дистанция \(String(format: "%.2f", km)) км · время \(clock(elapsed)) · темп \(t.pace(now)) /км"
        do {
            let _: Workout = try await API.call("/workouts", method: "POST", body: [
                "date": RU.dayFormatter.string(from: start), "title": title, "groups": ["cardio"],
                "time": f.string(from: start), "calories": t.calories, "note": note])
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "checkmark.circle.fill", title: "Сохранено в дневник", message: note)
            dismiss()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}
