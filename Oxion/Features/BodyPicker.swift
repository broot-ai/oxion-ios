import SwiftUI
import SceneKit
import CoreMotion

// «Что качаем сегодня?» — 3D-фигура на весь экран.
// Пользователь нажимает на мышцы прямо на фигуре: выбранные загораются неоново-зелёным,
// остальное тело — телесного цвета. Из выбора сразу создаётся тренировка или план от ИИ.
//
// Модель: Assets → body.dataset/body.oxb (сжатый DEFLATE).
// Внутри 9 частей: chest, back, shoulders, biceps, triceps, abs, glutes, legs и skin (неактивная кожа).

// MARK: - Данные модели

struct BodyPart: @unchecked Sendable {
    let name: String
    let vertexCount: Int
    let indexCount: Int
    let positions: Data   // Float32 x3
    let normals: Data     // Float32 x3
    let indices: Data     // UInt32
}

enum BodyMeshLoader {
    @MainActor static var cache: [BodyPart]?

    @MainActor
    static func load() async -> [BodyPart]? {
        if let cache { return cache }
        guard let asset = NSDataAsset(name: "body") else { return nil }
        let raw = asset.data
        let parts = await Task.detached(priority: .userInitiated) { parse(raw) }.value
        cache = parts
        return parts
    }

    static func parse(_ compressed: Data) -> [BodyPart]? {
        guard let data = try? (compressed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> [BodyPart]? in
            guard buf.count > 32, buf[0] == 0x4F, buf[1] == 0x58, buf[2] == 0x42, buf[3] == 0x31 else { return nil }
            var o = 4
            func f32() -> Float { let v = buf.loadUnaligned(fromByteOffset: o, as: Float.self); o += 4; return v }
            func u32() -> Int { let v = buf.loadUnaligned(fromByteOffset: o, as: UInt32.self); o += 4; return Int(v) }
            let mn = SIMD3<Float>(f32(), f32(), f32())
            let mx = SIMD3<Float>(f32(), f32(), f32())
            let sc = (mx - mn) / 65535
            let n = u32()
            var out: [BodyPart] = []
            for _ in 0..<n {
                guard o < buf.count else { return nil }
                let l = Int(buf[o]); o += 1
                let name = String(decoding: UnsafeRawBufferPointer(rebasing: buf[o..<(o + l)]), as: UTF8.self); o += l
                let vc = u32(), ic = u32()
                guard o + vc * 9 + ic * 4 <= buf.count else { return nil }
                var pos = [Float](repeating: 0, count: vc * 3)
                for i in 0..<vc {
                    let b = o + i * 6
                    for k in 0..<3 {
                        let q = Float(buf.loadUnaligned(fromByteOffset: b + k * 2, as: UInt16.self))
                        pos[i * 3 + k] = mn[k] + q * sc[k]
                    }
                }
                o += vc * 6
                var nrm = [Float](repeating: 0, count: vc * 3)
                for i in 0..<(vc * 3) {
                    nrm[i] = Float(buf.loadUnaligned(fromByteOffset: o + i, as: Int8.self)) / 127
                }
                o += vc * 3
                let idx = Data(bytes: buf.baseAddress! + o, count: ic * 4)
                o += ic * 4
                out.append(BodyPart(name: name, vertexCount: vc, indexCount: ic,
                                    positions: pos.withUnsafeBufferPointer { Data(buffer: $0) },
                                    normals: nrm.withUnsafeBufferPointer { Data(buffer: $0) },
                                    indices: idx))
            }
            return out
        }
    }

    static func geometry(_ p: BodyPart) -> SCNGeometry {
        let v = SCNGeometrySource(data: p.positions, semantic: .vertex, vectorCount: p.vertexCount,
                                  usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                  dataOffset: 0, dataStride: 12)
        let n = SCNGeometrySource(data: p.normals, semantic: .normal, vectorCount: p.vertexCount,
                                  usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                  dataOffset: 0, dataStride: 12)
        let e = SCNGeometryElement(data: p.indices, primitiveType: .triangles,
                                   primitiveCount: p.indexCount / 3, bytesPerIndex: 4)
        return SCNGeometry(sources: [v, n], elements: [e])
    }
}

// MARK: - Группы

enum BodyZone {
    /// Группы, которые лучше видно со спины — при выборе фигура разворачивается
    static let backSide: Set<String> = ["back", "triceps", "glutes"]
    static let all = ["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs", "cardio"]
    static func icon(_ k: String) -> String {
        switch k {
        case "chest": "figure.strengthtraining.traditional"
        case "back": "figure.rower"
        case "shoulders": "figure.arms.open"
        case "biceps": "dumbbell.fill"
        case "triceps": "figure.strengthtraining.functional"
        case "abs": "figure.core.training"
        case "glutes": "figure.step.training"
        case "legs": "figure.walk"
        case "cardio": "heart.fill"
        default: "circle"
        }
    }
}

// MARK: - Сцена

@MainActor
final class BodyStage {
    weak var view: SCNView?
    let root = SCNNode()
    let body = SCNNode()
    let camera = SCNNode()
    var materials: [String: SCNMaterial] = [:]
    var selected: Set<String> = []
    var onTap: ((String) -> Void)?
    var onSkinTap: (() -> Void)?
    var dragging = false
    private let motion = CMMotionManager()
    private var lastTick: TimeInterval = 0

    /// Наклон телефона вправо — фигура крутится вправо, влево — влево
    func startTilt() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        lastTick = 0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let now = m.timestamp
            let dt = self.lastTick == 0 ? 0 : min(0.05, now - self.lastTick)
            self.lastTick = now
            guard !self.dragging, self.body.action(forKey: "spin") == nil else { return }
            let gx = m.gravity.x
            let dead = 0.07
            guard abs(gx) > dead else { return }
            let speed = (gx - (gx > 0 ? dead : -dead)) * 4.5   // рад/с
            self.body.eulerAngles.y += Float(speed * dt)
        }
    }

    func stopTilt() { motion.stopDeviceMotionUpdates() }

    /// Фиксированный кадр: фигура целиком между верхними кнопками и нижней панелью
    static let camPos = SCNVector3(0, -0.1, 5.1)
    static let skin = UIColor(red: 0.91, green: 0.72, blue: 0.60, alpha: 1)
    static let neon = UIColor(red: 0xB2 / 255, green: 0xEE / 255, blue: 0x37 / 255, alpha: 1)

    func build(parts: [BodyPart]) -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.addChildNode(root)
        root.addChildNode(body)
        for p in parts {
            let g = BodyMeshLoader.geometry(p)
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = Self.skin
            m.roughness.contents = 0.62
            m.metalness.contents = 0.0
            m.emission.contents = UIColor.black
            g.materials = [m]
            let node = SCNNode(geometry: g)
            node.name = p.name
            body.addChildNode(node)
            materials[p.name] = m
        }

        // свечение-подиум под ногами
        let plate = SCNPlane(width: 1.3, height: 1.3)
        let pm = SCNMaterial()
        pm.lightingModel = .constant
        pm.diffuse.contents = Self.glowImage()
        pm.blendMode = .add
        pm.writesToDepthBuffer = false
        plate.materials = [pm]
        let plateNode = SCNNode(geometry: plate)
        plateNode.eulerAngles.x = -.pi / 2
        plateNode.position = SCNVector3(0, -0.905, 0)
        root.addChildNode(plateNode)

        // камера
        let cam = SCNCamera()
        cam.fieldOfView = 30
        cam.zNear = 0.1
        cam.zFar = 50
        cam.wantsHDR = false
        camera.camera = cam
        camera.position = Self.camPos
        scene.rootNode.addChildNode(camera)

        // свет: мягкий общий + основной сверху-спереди + контровой
        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ color: UIColor, _ euler: SCNVector3) {
            let l = SCNLight()
            l.type = type
            l.intensity = intensity
            l.color = color
            let n = SCNNode()
            n.light = l
            n.eulerAngles = euler
            scene.rootNode.addChildNode(n)
        }
        light(.ambient, 260, .white, SCNVector3Zero)
        light(.directional, 750, .white, SCNVector3(-0.55, -0.45, 0))
        light(.directional, 260, .white, SCNVector3(-0.2, 0.9, 0))
        light(.directional, 320, .white, SCNVector3(-0.3, .pi, 0))

        // появление
        body.opacity = 0
        body.eulerAngles.y = -0.6
        body.runAction(.group([.fadeIn(duration: 0.5),
                               { let a = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 1.1); a.timingMode = .easeOut; return a }()]))
        return scene
    }

    static func glowImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [neon.withAlphaComponent(0.55).cgColor, neon.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                             endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
    }

    func apply(_ sel: Set<String>, animated: Bool) {
        selected = sel
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.3 : 0
        for (key, m) in materials where key != "skin" {
            let on = sel.contains(key)
            m.diffuse.contents = on ? Self.neon : Self.skin
            m.emission.contents = UIColor.black
            m.roughness.contents = 0.62
        }
        SCNTransaction.commit()
    }

    /// Повернуть фигуру лицом (false) или спиной (true)
    func face(back: Bool) {
        let cur = Double(body.eulerAngles.y)
        let base = back ? Double.pi : 0
        let k = ((cur - base) / (2 * .pi)).rounded()
        let target = base + k * 2 * .pi
        body.removeAction(forKey: "spin")
        let a = SCNAction.rotateTo(x: 0, y: CGFloat(target), z: 0, duration: 0.7)
        a.timingMode = .easeInEaseOut
        body.runAction(a, forKey: "spin")
    }

    var showsBack: Bool {
        let y = Double(body.eulerAngles.y).truncatingRemainder(dividingBy: 2 * .pi)
        let v = y < 0 ? y + 2 * .pi : y
        return v > .pi / 2 && v < 3 * .pi / 2
    }

    func flip() { face(back: !showsBack) }

    func reset() {
        face(back: false)
        if let cam = camera.camera {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.4
            cam.fieldOfView = 30
            camera.position = Self.camPos
            SCNTransaction.commit()
        }
    }

    // MARK: жесты

    @objc func tap(_ g: UITapGestureRecognizer) {
        guard let view else { return }
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue,
                                                                .ignoreHiddenNodes: true])
        guard let name = hits.first?.node.name else { return }
        if name == "skin" { onSkinTap?() } else { onTap?(name) }
    }

    @objc func doubleTap(_ g: UITapGestureRecognizer) { flip() }

    @objc func pan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        switch g.state {
        case .began:
            dragging = true
            body.removeAction(forKey: "spin")
        case .changed:
            let t = g.translation(in: view)
            body.eulerAngles.y += Float(t.x) * 0.011
            g.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            dragging = false
            let vx = g.velocity(in: view).x
            let a = SCNAction.rotateBy(x: 0, y: CGFloat(vx) * 0.0028, z: 0, duration: 0.9)
            a.timingMode = .easeOut
            body.runAction(a, forKey: "spin")
        default: break
        }
    }

}

struct BodySceneView: UIViewRepresentable {
    let stage: BodyStage
    let parts: [BodyPart]
    let selected: Set<String>

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 120
        v.rendersContinuously = false
        v.isJitteringEnabled = false
        v.scene = stage.build(parts: parts)
        v.pointOfView = stage.camera
        v.isPlaying = true
        stage.view = v

        let tap = UITapGestureRecognizer(target: stage, action: #selector(BodyStage.tap(_:)))
        let dbl = UITapGestureRecognizer(target: stage, action: #selector(BodyStage.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(dbl)
        v.addGestureRecognizer(UIPanGestureRecognizer(target: stage, action: #selector(BodyStage.pan(_:))))
        stage.apply(selected, animated: false)
        stage.startTilt()
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        if stage.selected != selected { stage.apply(selected, animated: true) }
    }
}

// MARK: - Экран

struct MusclePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    @State private var stage = BodyStage()
    @State private var parts: [BodyPart]?
    @State private var failed = false
    @State private var selected: Set<String> = []
    @State private var aiPrompt: PromptBox?

    struct PromptBox: Identifiable { let id = UUID(); let text: String }

    private var ordered: [String] { BodyZone.all.filter { selected.contains($0) } }
    private var title: String {
        let names = ordered.map { model.muscleName($0) }
        return names.isEmpty ? "Тренировка" : names.prefix(3).joined(separator: " + ")
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            if let parts {
                BodySceneView(stage: stage, parts: parts, selected: selected)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else if failed {
                ContentUnavailableView("Не удалось загрузить фигуру", systemImage: "figure.stand",
                                       description: Text("Выберите группы мышц кнопками ниже"))
            } else {
                ProgressView().controlSize(.large).tint(Color.limeInk)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selected)
        .animation(.easeInOut(duration: 0.3), value: parts == nil)
        .task {
            stage.onTap = { key in toggle(key, fromModel: true) }
            stage.onSkinTap = { Haptic.tap() }
            if let p = await BodyMeshLoader.load() { parts = p } else { failed = true }
        }
        .onDisappear { stage.stopTilt() }
        .sheet(item: $aiPrompt) { p in
            NavigationStack {
                AICoachView(initial: p.text)
                    .navigationTitle("ИИ-тренер")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") { aiPrompt = nil }
                        }
                    }
            }
        }
    }

    private var background: some View {
        ZStack {
            (scheme == .dark ? Color(hex: 0x0B0C0E) : Color(hex: 0xF2F3F5))
            RadialGradient(colors: [Color.lime.opacity(scheme == .dark ? 0.16 : 0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.78), startRadius: 10, endRadius: 360)
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.06 : 0.6), .clear],
                           center: UnitPoint(x: 0.5, y: 0.25), startRadius: 10, endRadius: 320)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Menu {
                Button { stage.face(back: false) } label: { Label("Спереди", systemImage: "person.fill") }
                Button { stage.face(back: true) } label: { Label("Сзади", systemImage: "person.fill.turn.down") }
                Button { stage.reset() } label: { Label("Сбросить вид", systemImage: "arrow.counterclockwise") }
                if !selected.isEmpty {
                    Button(role: .destructive) { selected = []; Haptic.tap() } label: { Label("Снять выбор", systemImage: "xmark.circle") }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.headline).frame(width: 44, height: 44)
            } primaryAction: {
                stage.flip(); Haptic.tap()
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var panel: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BodyZone.all, id: \.self) { key in
                        let on = selected.contains(key)
                        Button { toggle(key, fromModel: false) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: on ? "checkmark" : BodyZone.icon(key))
                                    .font(.caption.weight(.bold))
                                    .contentTransition(.symbolEffect(.replace))
                                Text(model.muscleName(key)).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(on ? Color.onLime : Color.primary)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(on ? Color.lime : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(on ? .regular.tint(Color.lime) : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            HStack(spacing: 10) {
                Button {
                    let names = ordered.map { model.muscleName($0).lowercased() }.joined(separator: ", ")
                    aiPrompt = PromptBox(text: "Составь тренировку на сегодня на: \(names). Учитывай мой уровень и цель.")
                } label: {
                    Label("План от ИИ", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glass)

                Button { start() } label: {
                    Label("Начать", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.lime)
                .foregroundStyle(Color.onLime)
            }
            .disabled(selected.isEmpty)
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func toggle(_ key: String, fromModel: Bool) {
        if selected.contains(key) {
            selected.remove(key)
            Haptic.tap()
        } else {
            selected.insert(key)
            OxHaptics.play(.select)
            if !fromModel && key != "cardio" { stage.face(back: BodyZone.backSide.contains(key)) }
        }
    }

    private func start() {
        let groups = ordered
        let t = title
        Haptic.success()
        dismiss()
        let model = model
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            await model.quickWorkout(title: t, groups: groups)
        }
    }
}

/// Карточка на главном экране
struct HomeMuscleCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.showMuscles = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.lime.opacity(0.18))
                    Image(systemName: "figure.stand")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.limeInk)
                        .symbolEffect(.pulse, options: .repeating.speed(0.4))
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Что качаем сегодня?").font(.headline)
                    Text("Выбери мышцы на 3D-фигуре — соберём тренировку")
                        .font(.subheadline)
                        .foregroundStyle(Color.oxHint)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
            }
            .padding(16)
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
