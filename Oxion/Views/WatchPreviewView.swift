import SwiftUI
import WatchConnectivity

// MARK: - Связь с Apple Watch (WatchConnectivity)

/// Передаёт состояние тренировки на часы. Когда приложение OXION для Apple Watch будет установлено,
/// часы получат тренировку и смогут управлять ею; при обрыве связи часы продолжают по меткам времени.
@MainActor
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    private(set) var paired = false
    private(set) var appInstalled = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ s: WorkoutState?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var ctx: [String: Any] = ["active": s != nil && s?.phase != .finished, "sent": Date().timeIntervalSince1970]
        if let s, let d = try? JSONEncoder().encode(s) { ctx["state"] = d }
        // простые поля для приложения на часах
        if let s {
            let it = s.currentItem
            ctx["title"] = s.title
            ctx["exercise"] = it?.name ?? ""
            ctx["setNo"] = min((it?.doneSets ?? 0) + 1, it?.sets ?? 0)
            ctx["sets"] = it?.sets ?? 0
            ctx["reps"] = it?.reps ?? 0
            ctx["weight"] = it?.weight ?? 0
            ctx["unit"] = it?.unit ?? ""
            ctx["type"] = it?.type ?? ""
            ctx["phase"] = String(describing: s.phase)
            ctx["restEndsAt"] = s.restEndsAt?.timeIntervalSince1970 ?? 0
            ctx["startedAt"] = s.startedAt.timeIntervalSince1970
            ctx["pausedTotal"] = s.pausedTotal
            ctx["setsDone"] = s.setsDoneAll
            ctx["setsTotal"] = s.setsTotalAll
            ctx["next"] = s.nextItem?.name ?? ""
        }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let p = session.isPaired, i = session.isWatchAppInstalled
        Task { @MainActor in
            self.paired = p
            self.appInstalled = i
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// команды с часов: next, pause, resume, complete, finish
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    /// Пульс с часов (bpm) — показывается на экране тренировки
    private(set) var heartRate: Int = 0
    private(set) var heartRateAt: Date?

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let hr = message["hr"] as? Int {
            Task { @MainActor in
                self.heartRate = hr
                self.heartRateAt = Date()
            }
            return
        }
        guard let cmd = message["cmd"] as? String else { return }
        Task { @MainActor in
            let e = WorkoutEngine.shared
            switch cmd {
            case "complete": e.completeSet()
            case "next": e.nextSet()
            case "pause": e.pause()
            case "resume": e.resume()
            case "finish": e.finish()
            default: break
            }
        }
    }
}

// MARK: - Превью интерфейса Apple Watch (работает с настоящей тренировкой на iPhone)

struct WatchPreviewView: View {
    @State private var engine = WorkoutEngine.shared
    @State private var page = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("Так OXION будет выглядеть на Apple Watch. Кнопки на часах ниже работают — они управляют вашей текущей тренировкой.")
                    .font(.subheadline)
                    .foregroundStyle(Color.oxHint)
                    .multilineTextAlignment(.center)

                WatchFrame {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        if let s = engine.state, s.phase != .finished {
                            TabView(selection: $page) {
                                mainScreen(s, now: ctx.date).tag(0)
                                metrics(s, now: ctx.date).tag(1)
                                controls(s).tag(2)
                            }
                            .tabViewStyle(.page(indexDisplayMode: .always))
                        } else {
                            idle
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Активная тренировка, подход, отдых, повторения, прогресс", systemImage: "applewatch")
                    Label("Пульс, калории, шаги и дистанция с датчиков часов (HealthKit)", systemImage: "heart.fill")
                    Label("Синхронизация с iPhone через WatchConnectivity; без связи часы считают сами", systemImage: "arrow.triangle.2.circlepath")
                    Label("Нужно: аккаунт разработчика Apple и сборка приложения часов в Xcode", systemImage: "info.circle")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
                .labelStyle(TintedIconLabel(tint: Color.lime))
                .padding(16)
                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Apple Watch")
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image("ox-logo").resizable().scaledToFit().frame(height: 44)
            Text("OXION").font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Начните тренировку на iPhone").font(.system(size: 11)).foregroundStyle(.gray).multilineTextAlignment(.center)
        }
    }

    private func mainScreen(_ s: WorkoutState, now: Date) -> some View {
        let it = s.currentItem
        let resting = s.phase == .resting
        return VStack(spacing: 4) {
            Text(s.phase == .paused ? "ПАУЗА" : resting ? "ОТДЫХ" : "ПОДХОД \(min((it?.doneSets ?? 0) + 1, it?.sets ?? 1))/\(it?.sets ?? 0)")
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.lime)
            Text(clock(resting ? s.restLeft(now) : s.elapsed(now)))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            Text(it?.name ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text("\(it?.reps ?? 0) повт." + ((it?.weight ?? 0) > 0 ? " · \(Int(it?.weight ?? 0)) кг" : ""))
                .font(.system(size: 11)).foregroundStyle(.gray)
            ProgressView(value: Double(s.setsDoneAll), total: Double(max(1, s.setsTotalAll))).tint(Color.lime)
                .padding(.horizontal, 10)
        }
    }

    private func metrics(_ s: WorkoutState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("heart.fill", "— уд/мин", .red)
            row("flame.fill", "— ккал", .orange)
            row("clock.fill", clock(s.elapsed(now)), Color.lime)
            row("square.stack.3d.up.fill", "\(s.setsDoneAll)/\(s.setsTotalAll) подх.", .cyan)
            Text("датчики — в приложении часов").font(.system(size: 8)).foregroundStyle(.gray)
        }
    }

    private func controls(_ s: WorkoutState) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                wbtn("checkmark", Color.lime) { engine.completeSet(); OxHaptics.play(.setDone) }
                wbtn("forward.fill", .white.opacity(0.2)) { engine.nextSet() }
            }
            HStack(spacing: 6) {
                if s.phase == .paused {
                    wbtn("play.fill", .white.opacity(0.2)) { engine.resume() }
                } else {
                    wbtn("pause.fill", .white.opacity(0.2)) { engine.pause() }
                }
                wbtn("xmark", .red.opacity(0.8)) { engine.finish(); OxHaptics.play(.workoutDone) }
            }
        }
    }

    private func row(_ icon: String, _ text: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(c).frame(width: 16)
            Text(text).font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func wbtn(_ icon: String, _ c: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(c == Color.lime ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(c, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%ld:%02ld", s / 60, s % 60)
    }
}

/// Корпус часов
struct WatchFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 64, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 236, height: 282)
                .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .fill(Color.black)
                .frame(width: 212, height: 258)
            content
                .foregroundStyle(.white)
                .frame(width: 186, height: 226)
            Capsule().fill(Color(white: 0.35)).frame(width: 10, height: 44).offset(x: 122, y: -40)
        }
        .frame(height: 300)
    }
}
