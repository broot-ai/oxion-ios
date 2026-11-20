import SwiftUI
import AVFoundation
import Vision

// MARK: - OXION Vision: подсчёт повторений по камере (всё считается на телефоне, видео никуда не отправляется)

/// Правило упражнения: угол в суставе (A–B–C), нижняя и верхняя точки движения
struct MoveRule: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let joints: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)]
    /// угол в нижней точке (меньше — «опустился»)
    let down: Double
    /// угол в верхней точке (больше — «вернулся»)
    let up: Double
    let tipLow: String
    let setup: String

    static func == (a: MoveRule, b: MoveRule) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [MoveRule] = [
        MoveRule(id: "squat", name: "Приседания", icon: "figure.cross.training",
                 joints: [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)],
                 down: 105, up: 160, tipLow: "Опуститесь ниже — бедро до параллели",
                 setup: "Поставьте телефон боком на уровне пояса, отойдите на 2–3 метра, чтобы были видны ноги целиком"),
        MoveRule(id: "pushup", name: "Отжимания", icon: "figure.strengthtraining.functional",
                 joints: [(.leftShoulder, .leftElbow, .leftWrist), (.rightShoulder, .rightElbow, .rightWrist)],
                 down: 95, up: 150, tipLow: "Опускайтесь ниже — локти до 90°",
                 setup: "Положите телефон на пол сбоку, примерно в 1,5 метрах, камерой к вам"),
        MoveRule(id: "curl", name: "Сгибания на бицепс", icon: "dumbbell.fill",
                 joints: [(.leftWrist, .leftElbow, .leftShoulder), (.rightWrist, .rightElbow, .rightShoulder)],
                 down: 60, up: 145, tipLow: "Сгибайте руку полностью",
                 setup: "Встаньте боком или лицом к камере, чтобы были видны плечо, локоть и кисть"),
        MoveRule(id: "lunge", name: "Выпады", icon: "figure.step.training",
                 joints: [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)],
                 down: 110, up: 160, tipLow: "Колено ниже — до угла 90°",
                 setup: "Телефон боком на уровне пояса, в 2–3 метрах")
    ]
}

@MainActor
final class PoseCounter: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var reps = 0
    @Published var angle: Double?
    @Published var hint = "Встаньте так, чтобы тело было видно целиком"
    @Published var visible = false
    @Published var calibrated = false
    @Published var running = false
    @Published var denied = false

    var rule: MoveRule = MoveRule.all[0]
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "oxion.vision")
    private var atBottom = false
    private var minAngle = 180.0
    private var visibleSince: Date?
    nonisolated(unsafe) private var busy = false
    private var useFront = true

    func start(front: Bool = true) {
        useFront = front
        Task {
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            guard ok else { denied = true; return }
            configure()
            let s = session
            queue.async { s.startRunning() }
            running = true
        }
    }

    func stop() {
        let s = session
        queue.async { s.stopRunning() }
        running = false
    }

    func reset() {
        reps = 0
        atBottom = false
        minAngle = 180
    }

    private func configure() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .high
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: useFront ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else {
            session.commitConfiguration()
            hint = "Камера недоступна"
            return
        }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(out) { session.addOutput(out) }
        if let c = out.connection(with: .video) {
            c.videoRotationAngle = 90
            if useFront { c.isVideoMirrored = true }
        }
        session.commitConfiguration()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if busy { return }
        busy = true
        defer { busy = false }
        let req = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        try? handler.perform([req])
        let obs = req.results?.first
        var pts: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        if let all = try? obs?.recognizedPoints(.all) {
            for (k, p) in all where p.confidence > 0.3 {
                pts[k] = CGPoint(x: p.location.x, y: 1 - p.location.y)
            }
        }
        Task { @MainActor in self.process(pts) }
    }

    private func process(_ pts: [VNHumanBodyPoseObservation.JointName: CGPoint]) {
        points = pts
        // угол по той стороне тела, которую видно лучше
        var angles: [Double] = []
        for (a, b, c) in rule.joints {
            if let pa = pts[a], let pb = pts[b], let pc = pts[c] { angles.append(Self.angle(pa, pb, pc)) }
        }
        guard let ang = angles.min() else {
            visible = false
            visibleSince = nil
            hint = "Не видно нужных суставов. \(rule.setup)"
            angle = nil
            return
        }
        angle = ang
        visible = true
        // калибровка: тело должно быть видно хотя бы секунду в исходном положении
        if !calibrated {
            if visibleSince == nil { visibleSince = Date() }
            if Date().timeIntervalSince(visibleSince!) > 1.0 && ang > rule.up - 10 {
                calibrated = true
                hint = "Готово! Начинайте"
                OxHaptics.play(.select)
            } else {
                hint = "Калибровка… встаньте в исходное положение"
            }
            return
        }
        minAngle = min(minAngle, ang)
        if !atBottom && ang < rule.down {
            atBottom = true
            hint = "Нижняя точка ✓ — возвращайтесь"
        } else if atBottom && ang > rule.up {
            atBottom = false
            reps += 1
            hint = "Повтор \(reps) засчитан"
            OxHaptics.play(.select)
            minAngle = 180
        } else if !atBottom && ang < rule.up - 15 && ang > rule.down + 5 {
            hint = rule.tipLow
        }
    }

    static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let m = sqrt(v1.dx * v1.dx + v1.dy * v1.dy) * sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard m > 0 else { return 180 }
        let cosv = Double(max(-1, min(1, dot / m)))
        return Foundation.acos(cosv) * 180 / Double.pi
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.layer2.session = session
        v.layer2.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer2: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Скелет поверх камеры
struct SkeletonOverlay: View {
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    private let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose)
    ]

    var body: some View {
        Canvas { ctx, size in
            func p(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                points[j].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            }
            for (a, b) in bones {
                if let pa = p(a), let pb = p(b) {
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    ctx.stroke(path, with: .color(Color.lime), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            for (_, pt) in points {
                let c = CGPoint(x: pt.x * size.width, y: pt.y * size.height)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}

struct VisionCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pc = PoseCounter()
    @State private var rule = MoveRule.all[0]
    @State private var front = true
    @State private var engine = WorkoutEngine.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if pc.running {
                CameraPreview(session: pc.session).ignoresSafeArea()
                SkeletonOverlay(points: pc.points).ignoresSafeArea()
            }
            VStack(spacing: 12) {
                HStack {
                    Button { pc.stop(); dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Menu {
                        ForEach(MoveRule.all) { r in
                            Button { rule = r; pc.rule = r; pc.reset(); pc.calibrated = false } label: { Label(r.name, systemImage: r.icon) }
                        }
                    } label: {
                        Label(rule.name, systemImage: rule.icon).font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    Spacer()
                    Button {
                        front.toggle()
                        pc.stop()
                        pc.calibrated = false
                        pc.start(front: front)
                    } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").font(.headline).frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                Spacer()
                VStack(spacing: 6) {
                    Text("\(pc.reps)")
                        .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.lime)
                        .contentTransition(.numericText())
                        .animation(.spring, value: pc.reps)
                    Text(RU.plural(pc.reps, "повторение", "повторения", "повторений")).foregroundStyle(.white.opacity(0.8))
                    if let a = pc.angle { Text("угол \(Int(a))°").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6)) }
                }
                Text(pc.hint)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular.tint((pc.visible ? Color.lime : Color.orange).opacity(0.25)), in: .capsule)
                HStack(spacing: 10) {
                    Button { pc.reset() } label: { Label("Сброс", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity).padding(.vertical, 4) }
                        .buttonStyle(.glass)
                    Button {
                        if engine.isActive, engine.state?.phase == .exercising {
                            engine.completeSet(reps: pc.reps)
                            OxHaptics.play(.setDone)
                            pc.reset()
                            OxAlert.show(icon: "checkmark.circle.fill", title: "Подход записан", message: "Повторений: \(engine.state?.items[safe: max(0, (engine.state?.current ?? 0))]?.reps ?? 0). Начался отдых.")
                        } else {
                            OxAlert.show(icon: "info.circle.fill", title: "\(pc.reps) \(RU.plural(pc.reps, "повторение", "повторения", "повторений"))",
                                         message: "Начните тренировку в дневнике — тогда подход запишется сюда одной кнопкой.")
                        }
                    } label: {
                        Label("Записать подход", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(pc.reps == 0)
                }
                .controlSize(.large)
                Text("Подсчёт приблизительный и не заменяет тренера. Обработка — только на вашем iPhone.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            .padding(16)
            if pc.denied {
                ContentUnavailableView {
                    Label("Нет доступа к камере", systemImage: "camera.fill")
                } description: {
                    Text("Камера нужна, чтобы считать повторы")
                } actions: {
                    Button("Как включить") { PermPrompt.show(.camera, denied: true) }.buttonStyle(.glassProminent)
                }
                .background(Color.black)
                .onAppear { PermPrompt.show(.camera, denied: true) }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { pc.rule = rule; pc.start(front: front) }
        .onDisappear { pc.stop() }
        .statusBarHidden()
    }
}
