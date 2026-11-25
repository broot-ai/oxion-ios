import SwiftUI
import RealityKit
import ARKit
import AVFoundation
import Observation

// AR MOTION (экспериментально) — отслеживание тела ARKit Body Tracking.
// Скелет поверх человека, углы суставов, распознавание простых движений и сравнение приседа с эталоном.
// Это оценка по камере, не измерение медицинского уровня.

@MainActor
@Observable
final class BodyTrackingManager: NSObject, ARSessionDelegate {
    struct Angles: Equatable {
        var kneeL: Double = 180, kneeR: Double = 180
        var hipL: Double = 180, hipR: Double = 180
        var elbowL: Double = 180, elbowR: Double = 180
        var torso: Double = 0          // наклон корпуса от вертикали
    }

    private(set) var tracking = false
    private(set) var angles = Angles()
    private(set) var pose = "Встаньте в кадр целиком"
    private(set) var reps = 0
    private(set) var depthBest: Double = 180
    private(set) var errorText: String?
    private(set) var lastRepScore: Int?

    enum CamState: Equatable { case starting, running, denied, failed(String) }
    /// Состояние камеры: пока нет первого кадра — показываем «Запускаю камеру…», а не чёрный экран
    private(set) var camState: CamState = .starting
    @ObservationIgnored nonisolated(unsafe) private var frameSeen = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    static var supported: Bool { ARBodyTrackingConfiguration.isSupported }

    @ObservationIgnored private weak var view: ARView?
    @ObservationIgnored private let root = AnchorEntity(world: .zero)
    @ObservationIgnored private var jointEntities: [String: ModelEntity] = [:]
    @ObservationIgnored private var boneEntities: [Int: ModelEntity] = [:]
    @ObservationIgnored private var down = false
    @ObservationIgnored private var repMin: Double = 180
    @ObservationIgnored private var repMaxLean: Double = 0
    @ObservationIgnored private var repMaxAsym: Double = 0

    static let joints = ["hips_joint", "spine_7_joint", "neck_1_joint", "head_joint",
                         "left_shoulder_1_joint", "left_arm_joint", "left_forearm_joint", "left_hand_joint",
                         "right_shoulder_1_joint", "right_arm_joint", "right_forearm_joint", "right_hand_joint",
                         "left_upLeg_joint", "left_leg_joint", "left_foot_joint",
                         "right_upLeg_joint", "right_leg_joint", "right_foot_joint"]
    static let bones: [(String, String)] = [
        ("hips_joint", "spine_7_joint"), ("spine_7_joint", "neck_1_joint"), ("neck_1_joint", "head_joint"),
        ("spine_7_joint", "left_shoulder_1_joint"), ("left_shoulder_1_joint", "left_arm_joint"),
        ("left_arm_joint", "left_forearm_joint"), ("left_forearm_joint", "left_hand_joint"),
        ("spine_7_joint", "right_shoulder_1_joint"), ("right_shoulder_1_joint", "right_arm_joint"),
        ("right_arm_joint", "right_forearm_joint"), ("right_forearm_joint", "right_hand_joint"),
        ("hips_joint", "left_upLeg_joint"), ("left_upLeg_joint", "left_leg_joint"), ("left_leg_joint", "left_foot_joint"),
        ("hips_joint", "right_upLeg_joint"), ("right_upLeg_joint", "right_leg_joint"), ("right_leg_joint", "right_foot_joint"),
    ]

    func makeView() -> ARView {
        let v = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        v.renderOptions.insert(.disableMotionBlur)
        v.renderOptions.insert(.disableDepthOfField)
        v.session.delegate = self
        v.scene.addAnchor(root)
        view = v
        let lime = UIColor(red: 0xB2 / 255, green: 0xEE / 255, blue: 0x37 / 255, alpha: 1)
        for j in Self.joints {
            let e = ModelEntity(mesh: .generateSphere(radius: j == "head_joint" ? 0.06 : 0.028), materials: [UnlitMaterial(color: lime)])
            e.isEnabled = false
            root.addChild(e)
            jointEntities[j] = e
        }
        for (i, _) in Self.bones.enumerated() {
            let e = ModelEntity(mesh: .generateBox(size: [0.018, 1, 0.018], cornerRadius: 0.009),
                                materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.85))])
            e.isEnabled = false
            root.addChild(e)
            boneEntities[i] = e
        }
        // сессию запускаем, когда экран уже на месте (begin), — иначе камера иногда не стартует и экран чёрный
        return v
    }

    /// Запуск: доступ к камере → сессия → сторож: нет кадров 3 с — перезапуск, ещё 4 с — понятная ошибка
    func begin() async {
        guard Self.supported else { errorText = "Отслеживание тела не поддерживается на этом устройстве"; return }
        camState = .starting
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { camState = .denied; return }
        // даём SwiftUI вставить ARView в окно
        for _ in 0..<20 where view?.window == nil { try? await Task.sleep(for: .milliseconds(50)) }
        start()
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, !self.frameSeen else { return }
            self.start()
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !self.frameSeen else { return }
            self.camState = .failed("Камера не запустилась. Закройте другие приложения с камерой и нажмите «Повторить».")
        }
    }

    func start() {
        guard Self.supported else { errorText = "Отслеживание тела не поддерживается на этом устройстве"; return }
        frameSeen = false
        let c = ARBodyTrackingConfiguration()
        c.automaticSkeletonScaleEstimationEnabled = true
        view?.session.run(c, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        watchdog?.cancel()
        view?.session.pause()
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !frameSeen else { return }
        frameSeen = true
        Task { @MainActor in self.camState = .running }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.camState = .failed("Камера занята — например, звонком или другим приложением.") }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in self.camState = .starting; self.start() }
    }

    func resetReps() { reps = 0; depthBest = 180; lastRepScore = nil }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let body = anchors.compactMap({ $0 as? ARBodyAnchor }).first else { return }
        let base = body.transform
        let sk = body.skeleton
        let def = sk.definition
        var pos: [String: SIMD3<Float>] = [:]
        for name in Self.joints {
            let i = def.index(for: ARSkeleton.JointName(rawValue: name))
            guard i != NSNotFound, i < sk.jointModelTransforms.count else { continue }
            let m = base * sk.jointModelTransforms[i]
            pos[name] = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }
        let tracked = body.isTracked
        Task { @MainActor in self.apply(pos, tracked: tracked) }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let t = error.localizedDescription
        Task { @MainActor in self.errorText = t; self.camState = .failed(t) }
    }

    private func apply(_ p: [String: SIMD3<Float>], tracked: Bool) {
        tracking = tracked && p.count >= 12
        for (n, e) in jointEntities {
            if let v = p[n], tracking { e.isEnabled = true; e.position = v } else { e.isEnabled = false }
        }
        for (i, b) in Self.bones.enumerated() {
            guard let e = boneEntities[i] else { continue }
            guard tracking, let a = p[b.0], let c = p[b.1] else { e.isEnabled = false; continue }
            let d = c - a
            let len = simd_length(d)
            guard len > 0.001 else { e.isEnabled = false; continue }
            e.isEnabled = true
            e.position = (a + c) / 2
            e.scale = [1, len, 1]
            e.orientation = simd_quatf(from: [0, 1, 0], to: d / len)
        }
        guard tracking else { pose = "Встаньте в кадр целиком"; return }

        func ang(_ a: String, _ b: String, _ c: String) -> Double? {
            guard let pa = p[a], let pb = p[b], let pc = p[c] else { return nil }
            let u = simd_normalize(pa - pb), w = simd_normalize(pc - pb)
            return Double(acos(max(-1, min(1, simd_dot(u, w))))) * 180 / .pi
        }
        var a = Angles()
        a.kneeL = ang("left_upLeg_joint", "left_leg_joint", "left_foot_joint") ?? 180
        a.kneeR = ang("right_upLeg_joint", "right_leg_joint", "right_foot_joint") ?? 180
        a.hipL = ang("spine_7_joint", "left_upLeg_joint", "left_leg_joint") ?? 180
        a.hipR = ang("spine_7_joint", "right_upLeg_joint", "right_leg_joint") ?? 180
        a.elbowL = ang("left_arm_joint", "left_forearm_joint", "left_hand_joint") ?? 180
        a.elbowR = ang("right_arm_joint", "right_forearm_joint", "right_hand_joint") ?? 180
        if let h = p["hips_joint"], let s = p["spine_7_joint"] {
            let d = simd_normalize(s - h)
            a.torso = Double(acos(max(-1, min(1, d.y)))) * 180 / .pi
        }
        angles = a

        // распознавание простых движений
        let knee = (a.kneeL + a.kneeR) / 2
        let handsUp: Bool = {
            guard let hl = p["left_hand_joint"], let hr = p["right_hand_joint"], let head = p["head_joint"] else { return false }
            return hl.y > head.y && hr.y > head.y
        }()
        if handsUp { pose = "Руки вверх" }
        else if abs(a.kneeL - a.kneeR) > 35 && min(a.kneeL, a.kneeR) < 120 { pose = "Выпад" }
        else if knee < 120 { pose = "Присед" }
        else if a.torso > 35 && knee > 150 { pose = "Наклон корпуса" }
        else { pose = "Стоя" }

        // счёт приседаний с гистерезисом и оценкой повтора
        if !down, knee < 115 { down = true; repMin = knee; repMaxLean = a.torso; repMaxAsym = abs(a.kneeL - a.kneeR) }
        if down {
            repMin = min(repMin, knee)
            repMaxLean = max(repMaxLean, a.torso)
            repMaxAsym = max(repMaxAsym, abs(a.kneeL - a.kneeR))
            if knee > 160 {
                down = false
                reps += 1
                depthBest = min(depthBest, repMin)
                lastRepScore = SquatReference.score(minKnee: repMin, maxLean: repMaxLean, asym: repMaxAsym)
                OxHaptics.play(.setDone)
            }
        }
    }
}

/// Эталон приседа: угол колена по фазе повтора и правила оценки
enum SquatReference {
    static let targetKnee: Double = 90
    /// Угол колена эталона в фазе 0…1 (стоя → низ → стоя)
    static func knee(at phase: Double) -> Double {
        let x = (1 - cos(phase * 2 * .pi)) / 2   // 0 → 1 → 0
        return 175 - (175 - targetKnee) * x
    }
    static func hip(at phase: Double) -> Double {
        let x = (1 - cos(phase * 2 * .pi)) / 2
        return 175 - 95 * x
    }
    /// 0…100: глубина, наклон корпуса и симметрия (простая расчётная оценка)
    static func score(minKnee: Double, maxLean: Double, asym: Double) -> Int {
        let depth = max(0, min(1, (175 - minKnee) / (175 - targetKnee)))
        let lean = maxLean < 45 ? 1 : max(0, 1 - (maxLean - 45) / 30)
        let sym = max(0, 1 - asym / 30)
        return Int((depth * 0.55 + lean * 0.25 + sym * 0.2) * 100)
    }
}

struct BodyTrackingARView: UIViewRepresentable {
    let manager: BodyTrackingManager
    func makeUIView(context: Context) -> ARView { manager.makeView() }
    func updateUIView(_ v: ARView, context: Context) {}
    static func dismantleUIView(_ v: ARView, coordinator: ()) { v.session.pause() }
}

struct BodyTrackingScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var m = BodyTrackingManager()
    @State private var start = Date()

    var body: some View {
        ZStack {
            if BodyTrackingManager.supported {
                BodyTrackingARView(manager: m).ignoresSafeArea()
            } else {
                Color(hex: 0x0B0C0E).ignoresSafeArea()
                ContentUnavailableView("Нет отслеживания тела", systemImage: "figure.walk.motion",
                                       description: Text("Этому iPhone недоступен ARKit Body Tracking. Студия и AR работают как обычно."))
                    .foregroundStyle(.white)
            }
            if BodyTrackingManager.supported && m.camState != .running {
                camOverlay
            }
            VStack(spacing: 10) {
                HStack {
                    Button { m.stop(); dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Label("AR MOTION · бета", systemImage: "figure.walk.motion")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                    Spacer()
                    Button { m.resetReps(); Haptic.tap() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.headline).frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 16)
                if let e = m.errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold))
                        .padding(12).glassEffect(.regular.tint(.orange.opacity(0.3)), in: .rect(cornerRadius: 16))
                        .padding(.horizontal, 16)
                }
                Spacer()
                if BodyTrackingManager.supported { panel }
            }
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .task { await m.begin() }
        .onDisappear { m.stop() }
    }

    /// Вместо чёрного экрана — понятное состояние камеры
    @ViewBuilder private var camOverlay: some View {
        ZStack {
            Color(hex: 0x0B0C0E).ignoresSafeArea()
            VStack(spacing: 14) {
                switch m.camState {
                case .starting:
                    ProgressView().controlSize(.large).tint(Color.lime)
                    Text("Запускаю камеру…").font(.headline)
                    Text("Нужна задняя камера. Встаньте в 2–3 м от человека.").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                case .denied:
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text("Нет доступа к камере").font(.headline)
                    Text("Разрешите камеру для Oxion в Настройках.").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    Button("Открыть настройки") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime)
                case .failed(let t):
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text(t).font(.subheadline).multilineTextAlignment(.center)
                    Button("Повторить") { Task { await m.begin() } }
                        .buttonStyle(.glassProminent).tint(Color.lime)
                case .running:
                    EmptyView()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
        }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.pose).font(.title2.bold()).contentTransition(.opacity)
                    Text(m.tracking ? "Отслеживаю · держите телефон неподвижно, 2–3 м до человека" : "Наведите камеру на человека в полный рост")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(m.reps)").font(.system(size: 36, weight: .bold).monospacedDigit()).contentTransition(.numericText())
                    Text("приседаний").font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 12) {
                TimelineView(.animation) { t in
                    let phase = (t.date.timeIntervalSince(start) / 3).truncatingRemainder(dividingBy: 1)
                    StickFigure(knee: SquatReference.knee(at: phase), hip: SquatReference.hip(at: phase), color: .white.opacity(0.45), label: "Эталон")
                }
                StickFigure(knee: (m.angles.kneeL + m.angles.kneeR) / 2, hip: (m.angles.hipL + m.angles.hipR) / 2, color: Color.lime, label: "Вы")
                VStack(alignment: .leading, spacing: 6) {
                    angleRow("Колени", m.angles.kneeL, m.angles.kneeR)
                    angleRow("Таз", m.angles.hipL, m.angles.hipR)
                    angleRow("Локти", m.angles.elbowL, m.angles.elbowR)
                    Text("Корпус: \(Int(m.angles.torso))°").font(.caption.monospacedDigit())
                    if let s = m.lastRepScore {
                        Text("Повтор: \(s)/100").font(.caption.bold()).foregroundStyle(Color.lime)
                    }
                    if m.depthBest < 180 {
                        Text("Глубина: \(Int(m.depthBest))° (цель ≤ \(Int(SquatReference.targetKnee))°)").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Экспериментальная функция: углы — оценка по камере, не медицинское измерение.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func angleRow(_ t: String, _ l: Double, _ r: Double) -> some View {
        HStack(spacing: 6) {
            Text(t).font(.caption).frame(width: 52, alignment: .leading)
            Text("Л \(Int(l))° · П \(Int(r))°").font(.caption.monospacedDigit())
        }
    }
}

/// Схематичная фигура сбоку по углам колена и таза — для сравнения с эталоном
struct StickFigure: View {
    let knee: Double
    let hip: Double
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 3.4
                let foot = CGPoint(x: size.width * 0.5, y: size.height - 4)
                // голень наклоняется вперёд, бедро назад — по углу колена
                let kneeBend = (180 - knee) * .pi / 180
                let shin = Angle(radians: kneeBend * 0.45)
                let kneeP = CGPoint(x: foot.x + sin(shin.radians) * s, y: foot.y - cos(shin.radians) * s)
                let thighA = shin.radians - kneeBend
                let hipP = CGPoint(x: kneeP.x + sin(thighA) * s, y: kneeP.y - cos(thighA) * s)
                let hipBend = (180 - hip) * .pi / 180
                let torsoA = thighA + hipBend
                let neck = CGPoint(x: hipP.x + sin(torsoA) * s * 1.1, y: hipP.y - cos(torsoA) * s * 1.1)
                var path = Path()
                path.move(to: foot); path.addLine(to: kneeP); path.addLine(to: hipP); path.addLine(to: neck)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: neck.x - 7, y: neck.y - 16, width: 14, height: 14)), with: .color(color))
                for p in [kneeP, hipP] { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(color)) }
            }
            .frame(width: 62, height: 96)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
        }
    }
}
