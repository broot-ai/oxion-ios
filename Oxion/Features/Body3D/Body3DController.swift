import SwiftUI
import RealityKit
import ARKit
import Combine
import CoreMotion
import AVFoundation
import Observation

// Body3DController — одна сцена RealityKit для двух режимов:
//  • Studio — модель в приложении (виртуальная камера);
//  • AR — та же модель на полу через камеру (ARKit + RealityKit).
// Выбор мышц, подсветка, жесты и анимации общие.

@MainActor
@Observable
final class MuscleSelectionManager {
    var selected: Set<MusclePartID> = []
    var focused: MusclePartID?
    /// Выбирать сразу левую и правую сторону
    var bothSides = true

    /// Выбирать целую группу: пресс — весь пресс, спина — вся спина, ноги — все ноги
    var wholeGroups: Bool = UserDefaults.standard.object(forKey: "body3d.groups") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wholeGroups, forKey: "body3d.groups") }
    }

    func toggle(_ p: MusclePartID) {
        var set: Set<MusclePartID> = bothSides ? [p, p.mirror] : [p]
        if wholeGroups, let region = MuscleDataManager.byId[p.muscle]?.region {
            // все мышцы этого раздела, обе стороны
            for m in MuscleDataManager.all where m.region == region {
                set.insert(MusclePartID(muscle: m.id, side: .l))
                set.insert(MusclePartID(muscle: m.id, side: .r))
            }
        }
        if selected.contains(p) {
            selected.subtract(set)
            if let f = focused, set.contains(f) { focused = selected.sorted().first }
        } else {
            selected.formUnion(set)
            focused = p
        }
    }

    func select(muscle: String) {
        let set: Set<MusclePartID> = [MusclePartID(muscle: muscle, side: .l), MusclePartID(muscle: muscle, side: .r)]
        selected.formUnion(set)
        focused = MusclePartID(muscle: muscle, side: .l)
    }

    func clear() { selected = []; focused = nil }

    /// Уникальные мышцы без учёта стороны
    var muscles: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in selected.sorted() where !seen.contains(p.muscle) { seen.insert(p.muscle); out.append(p.muscle) }
        return MuscleDataManager.all.map(\.id).filter { out.contains($0) }
    }
}

enum Body3DMode: String, CaseIterable, Identifiable {
    case studio, ar
    var id: String { rawValue }
    var title: String { self == .studio ? "Студия" : "AR" }
}

enum Body3DColorMode: String { case anatomy, load }

@MainActor
@Observable
final class Body3DController: NSObject, UIGestureRecognizerDelegate, ARSessionDelegate {
    // состояние для интерфейса
    private(set) var loading = true
    private(set) var errorText: String?
    private(set) var source: Body3DSource = .builtIn
    private(set) var mode: Body3DMode = .studio
    private(set) var placed = false
    private(set) var arHint = ""
    private(set) var arError: String?
    var colorMode: Body3DColorMode = .anatomy { didSet { refreshTargets() } }
    let selection = MuscleSelectionManager()
    let intel = MuscleIntelligenceManager.shared
    var onTap: ((MusclePartID) -> Void)?

    // сцена
    @ObservationIgnored private(set) weak var view: ARView?
    @ObservationIgnored private var loaded: Body3DLoaded?
    @ObservationIgnored private let studioAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private let pivot = Entity()          // вращение, масштаб, сдвиг
    @ObservationIgnored private var floor: ModelEntity?
    @ObservationIgnored private var arAnchor: AnchorEntity?
    @ObservationIgnored private var reticle: ModelEntity?
    @ObservationIgnored private var coaching: ARCoachingOverlayView?
    @ObservationIgnored private var updateSub: Cancellable?

    // анимация цвета
    private struct PartLook { var color: SIMD4<Float>; var glow: Float }
    @ObservationIgnored private var current: [MusclePartID: PartLook] = [:]
    @ObservationIgnored private var target: [MusclePartID: PartLook] = [:]
    @ObservationIgnored private var skinCurrent: Float = 1
    @ObservationIgnored private var skinTarget: Float = 1

    // вращение и камера
    @ObservationIgnored private var yaw: Float = 0
    @ObservationIgnored private var yawVelocity: Float = 0
    @ObservationIgnored private var yawTarget: Float?
    @ObservationIgnored private var zoom: Float = 5.1
    @ObservationIgnored private var pan = SIMD2<Float>(0, 0)
    @ObservationIgnored private var arScale: Float = 1
    @ObservationIgnored private var appear: Float = 0
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private let motion = CMMotionManager()

    static let studioCamY: Float = -0.1
    static let defaultZoom: Float = 5.1

    // MARK: - Создание вида

    func makeView() -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(UIColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1))
        v.renderOptions.insert(.disableMotionBlur)
        v.renderOptions.insert(.disableDepthOfField)
        v.renderOptions.insert(.disableHDR)
        v.session.delegate = self
        view = v

        // свет
        let key = DirectionalLight()
        key.light.intensity = 2600
        key.look(at: .zero, from: [0.9, 1.6, 2.2], relativeTo: nil)
        let rim = DirectionalLight()
        rim.light.intensity = 900
        rim.look(at: .zero, from: [-1.2, 0.8, -2.0], relativeTo: nil)
        studioAnchor.addChild(key)
        studioAnchor.addChild(rim)

        camera.camera.fieldOfViewInDegrees = 30
        studioAnchor.addChild(camera)
        studioAnchor.addChild(pivot)

        let f = Body3DPalette.floorEntity(size: 1.4)
        f.position = [0, -0.905, 0]
        studioAnchor.addChild(f)
        floor = f
        v.scene.addAnchor(studioAnchor)
        applyCamera()

        // жесты
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapGesture(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let one = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        one.maximumNumberOfTouches = 1
        let two = UIPanGestureRecognizer(target: self, action: #selector(onTwoPan(_:)))
        two.minimumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        for g in [tap, dbl, one, two, pinch] as [UIGestureRecognizer] { g.delegate = self; v.addGestureRecognizer(g) }

        updateSub = v.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
            MainActor.assumeIsolated { self?.tick(Float(e.deltaTime)) }
        }
        Task { await load() }
        return v
    }

    func teardown() {
        motion.stopDeviceMotionUpdates()
        view?.session.pause()
        coaching?.removeFromSuperview()
        updateSub?.cancel()
        updateSub = nil
    }

    func load() async {
        loading = true
        errorText = nil
        do {
            let l = try await Body3DAsset.load()
            pivot.children.removeAll()
            pivot.addChild(l.body)
            loaded = l
            source = l.source
            current = [:]
            for id in l.parts.keys { current[id] = PartLook(color: Body3DPalette.skin, glow: 0) }
            refreshTargets()
            appear = 0
            yaw = -0.5
            yawTarget = 0
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
        if !intel.loaded { await intel.refresh(); refreshTargets() }
    }

    // MARK: - Цвета

    func refreshTargets() {
        guard let l = loaded else { return }
        let sel = selection.selected
        let dim: Float = sel.isEmpty ? 1 : 0.62
        for id in l.parts.keys {
            if sel.contains(id) {
                target[id] = PartLook(color: Body3DPalette.selected, glow: 0.08)
            } else {
                var c = Body3DPalette.skin
                if colorMode == .load, let g = MuscleDataManager.info(id.muscle)?.group {
                    c = Body3DPalette.simd(intel.status(for: g).ui)
                }
                target[id] = PartLook(color: SIMD4(c.x * dim, c.y * dim, c.z * dim, 1), glow: 0)
            }
        }
        skinTarget = dim
    }

    private func tick(_ dt: Float) {
        guard let l = loaded else { return }
        let k = 1 - exp(-dt * 9)
        for (id, e) in l.parts {
            guard let t = target[id], var c = current[id] else { continue }
            let dc = t.color - c.color
            let dg = t.glow - c.glow
            if simd_length(dc) < 0.002 && abs(dg) < 0.002 { continue }
            c.color += dc * k
            c.glow += dg * k
            if simd_length(t.color - c.color) < 0.003 { c = t }
            current[id] = c
            setMaterial(e, Body3DPalette.material(c.color, glow: c.glow))
        }
        if abs(skinTarget - skinCurrent) > 0.002 {
            skinCurrent += (skinTarget - skinCurrent) * k
            if abs(skinTarget - skinCurrent) < 0.003 { skinCurrent = skinTarget }
            let s = Body3DPalette.skin * skinCurrent
            for e in l.skin { setMaterial(e, Body3DPalette.material(SIMD4(s.x, s.y, s.z, 1))) }
        }

        // вращение: инерция или плавный доворот
        if let tgt = yawTarget {
            yaw += (tgt - yaw) * (1 - exp(-dt * 6))
            if abs(tgt - yaw) < 0.002 { yaw = tgt; yawTarget = nil }
        } else if !dragging, abs(yawVelocity) > 0.001 {
            yaw += yawVelocity * dt
            yawVelocity *= exp(-dt * 3.2)
        }
        pivot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        // появление
        if appear < 1 {
            appear = min(1, appear + dt * 1.6)
            let e = 1 - pow(1 - appear, 3)
            l.body.components.set(OpacityComponent(opacity: e))
            let s = 0.92 + 0.08 * e
            l.body.scale = SIMD3(repeating: s)
        }

        if mode == .ar { arTick() }
    }

    private func setMaterial(_ e: Entity, _ m: PhysicallyBasedMaterial) {
        if var mc = e.components[ModelComponent.self] {
            mc.materials = Array(repeating: m, count: max(1, mc.materials.count))
            e.components.set(mc)
        }
        for c in e.children where loaded?.source == .custom { setMaterial(c, m) }
    }

    // MARK: - Вид

    private func applyCamera() {
        let y = Self.studioCamY
        camera.look(at: [0, y, 0], from: [0, y, zoom], relativeTo: nil)
        pivot.position = [pan.x, pan.y, 0]
    }

    func face(back: Bool) {
        let base: Float = back ? .pi : 0
        let k = ((yaw - base) / (2 * .pi)).rounded()
        yawVelocity = 0
        yawTarget = base + k * 2 * .pi
    }

    var showsBack: Bool {
        var y = yaw.truncatingRemainder(dividingBy: 2 * .pi)
        if y < 0 { y += 2 * .pi }
        return y > .pi / 2 && y < 3 * .pi / 2
    }

    func flip() { face(back: !showsBack) }

    func resetView() {
        face(back: false)
        zoom = Self.defaultZoom
        pan = .zero
        if mode == .studio { applyCamera() } else { arScale = 1; pivot.scale = SIMD3(repeating: arScale) }
    }

    /// Повернуть модель к выбранной мышце
    func focus(_ muscle: String) {
        if let i = MuscleDataManager.info(muscle) { face(back: i.backSide) }
    }

    // MARK: - Наклон телефона (только Студия)

    private func startTilt() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        var last: TimeInterval = 0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            MainActor.assumeIsolated {
                guard let self, let m else { return }
                let dt = last == 0 ? 0 : min(0.05, m.timestamp - last)
                last = m.timestamp
                guard self.mode == .studio, !self.dragging, self.yawTarget == nil, abs(self.yawVelocity) < 0.05 else { return }
                let gx = m.gravity.x, dead = 0.07
                guard abs(gx) > dead else { return }
                self.yaw += Float((gx - (gx > 0 ? dead : -dead)) * 4.5 * dt)
            }
        }
    }

    // MARK: - Жесты

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
        (g is UIPinchGestureRecognizer && o is UIPanGestureRecognizer) || (o is UIPinchGestureRecognizer && g is UIPanGestureRecognizer)
    }

    @objc private func onTapGesture(_ g: UITapGestureRecognizer) {
        guard let v = view else { return }
        let pt = g.location(in: v)
        if mode == .ar && !placed { placeFromReticle(); return }
        guard let id = hitPart(at: pt) else { Haptic.tap(); return }
        selection.toggle(id)
        refreshTargets()
        OxHaptics.play(.select)
        onTap?(id)
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        if mode == .ar && !placed { return }
        flip()
        Haptic.tap()
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            dragging = true; yawTarget = nil; yawVelocity = 0
        case .changed:
            yaw += Float(g.translation(in: v).x) * 0.011
            g.setTranslation(.zero, in: v)
        case .ended, .cancelled:
            dragging = false
            yawVelocity = Float(g.velocity(in: v).x) * 0.011
        default: break
        }
    }

    @objc private func onTwoPan(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        if mode == .studio {
            let t = g.translation(in: v)
            let k = zoom / Float(max(1, v.bounds.height)) * 0.55
            pan.x = max(-0.8, min(0.8, pan.x + Float(t.x) * k))
            pan.y = max(-0.9, min(0.9, pan.y - Float(t.y) * k))
            g.setTranslation(.zero, in: v)
            applyCamera()
        } else if placed, g.state == .changed || g.state == .ended {
            let pt = g.location(in: v)
            if let r = v.raycast(from: pt, allowing: .estimatedPlane, alignment: .horizontal).first {
                arAnchor?.setTransformMatrix(r.worldTransform, relativeTo: nil)
            }
        }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if mode == .studio {
            zoom = max(1.8, min(7.5, zoom / Float(g.scale)))
            applyCamera()
        } else if placed {
            arScale = max(0.12, min(1.6, arScale * Float(g.scale)))
            pivot.scale = SIMD3(repeating: arScale)
        }
        g.scale = 1
    }

    private func hitPart(at pt: CGPoint) -> MusclePartID? {
        guard let v = view, let l = loaded else { return nil }
        if l.source == .custom {
            var e = v.entity(at: pt)
            while let cur = e {
                if let id = MusclePartID(cur.name.lowercased()) { return id }
                e = cur.parent
            }
            return nil
        }
        // луч из камеры через точку касания: в Студии считаем сами по параметрам виртуальной камеры
        var rayO: SIMD3<Float>, rayD: SIMD3<Float>
        if mode == .studio {
            let w = Float(max(1, v.bounds.width)), h = Float(max(1, v.bounds.height))
            let t = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
            let nx = (2 * Float(pt.x) / w - 1) * t * (w / h)
            let ny = (1 - 2 * Float(pt.y) / h) * t
            rayO = [0, Self.studioCamY, zoom]
            rayD = simd_normalize([nx, ny, -1])
        } else {
            guard let ray = v.ray(through: pt) else { return nil }
            rayO = ray.origin; rayD = ray.direction
        }
        let inv = l.body.transformMatrix(relativeTo: nil).inverse
        let o4 = inv * SIMD4(rayO, 1)
        let d4 = inv * SIMD4(rayD, 0)
        let o = SIMD3(o4.x, o4.y, o4.z), d = simd_normalize(SIMD3(d4.x, d4.y, d4.z))
        guard let id = Body3DAsset.hit(l.meshes, origin: o, dir: d) else { return nil }
        // проверяем, не закрыта ли мышца кожей (кисть, голова)
        if let m = l.meshes[id] {
            let tMuscle = Body3DAsset.hit([id: m], origin: o, dir: d) != nil ? distance(m, o, d) : .greatestFiniteMagnitude
            if Body3DAsset.skinDistance(l.skinMeshes, origin: o, dir: d) + 0.002 < tMuscle { return nil }
        }
        return id
    }

    private func distance(_ p: BodyMeshPart, _ o: SIMD3<Float>, _ d: SIMD3<Float>) -> Float {
        Body3DAsset.skinDistance([p], origin: o, dir: d)
    }

    // MARK: - AR

    var arSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func setMode(_ m: Body3DMode) async {
        guard m != mode else { return }
        if m == .ar {
            guard arSupported else { arError = "Это устройство не поддерживает AR. Студия доступна полностью."; return }
            let st = AVCaptureDevice.authorizationStatus(for: .video)
            if st == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                arError = "Нет доступа к камере. Разрешите его в Настройки → Oxion → Камера."
                return
            }
            enterAR()
        } else {
            exitAR()
        }
    }

    private func enterAR() {
        guard let v = view else { return }
        arError = nil
        mode = .ar
        placed = false
        arScale = 1
        pan = .zero
        v.scene.removeAnchor(studioAnchor)
        studioAnchor.removeChild(pivot)
        v.cameraMode = .ar
        v.environment.background = .cameraFeed()
        v.renderOptions.remove(.disableHDR)
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = [.horizontal]
        c.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth),
           ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue {
            c.frameSemantics.insert(.personSegmentationWithDepth)   // человек в кадре закрывает модель
        }
        v.session.run(c, options: [.resetTracking, .removeExistingAnchors])

        let r = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.22),
                            materials: [UnlitMaterial(color: Body3DPalette.ui(Body3DPalette.selected).withAlphaComponent(0.55))])
        let ra = AnchorEntity(world: .zero)
        ra.addChild(r)
        v.scene.addAnchor(ra)
        r.isEnabled = false
        reticle = r

        let co = ARCoachingOverlayView()
        co.session = v.session
        co.goal = .horizontalPlane
        co.activatesAutomatically = true
        co.frame = v.bounds
        co.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(co)
        coaching = co
        arHint = "Наведите камеру на пол"
    }

    private func exitAR() {
        guard let v = view else { return }
        v.session.pause()
        coaching?.removeFromSuperview()
        coaching = nil
        if let a = arAnchor { a.removeChild(pivot); v.scene.removeAnchor(a) }
        arAnchor = nil
        if let r = reticle?.parent as? AnchorEntity { v.scene.removeAnchor(r) }
        reticle = nil
        v.cameraMode = .nonAR
        v.environment.background = .color(UIColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1))
        v.renderOptions.insert(.disableHDR)
        loaded?.body.position = .zero
        pivot.scale = .one
        studioAnchor.addChild(pivot)
        v.scene.addAnchor(studioAnchor)
        mode = .studio
        placed = false
        zoom = Self.defaultZoom
        pan = .zero
        applyCamera()
        appear = 0
    }

    private func arTick() {
        guard let v = view, !placed, let r = reticle else { return }
        let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        if let hit = v.raycast(from: c, allowing: .estimatedPlane, alignment: .horizontal).first {
            r.isEnabled = true
            r.setTransformMatrix(hit.worldTransform, relativeTo: nil)
            let t = Float(Date().timeIntervalSinceReferenceDate)
            r.scale = SIMD3(repeating: 1 + 0.06 * sin(t * 3))
            if arHint != "Нажмите, чтобы поставить модель" { arHint = "Нажмите, чтобы поставить модель" }
        } else {
            r.isEnabled = false
            if arHint != "Наведите камеру на пол" { arHint = "Наведите камеру на пол" }
        }
    }

    func placeFromReticle() {
        guard let v = view, let r = reticle, r.isEnabled else { Haptic.tap(); return }
        let a = AnchorEntity(world: r.transformMatrix(relativeTo: nil))
        a.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        // разворачиваем модель лицом к камере
        let camPos = v.cameraTransform.translation
        let p = r.position(relativeTo: nil)
        let toCam = SIMD2(camPos.x - p.x, camPos.z - p.z)
        yaw = atan2(toCam.x, toCam.y)
        yawTarget = nil
        loaded?.body.position = [0, 0.9, 0]       // стопы на полу
        pivot.scale = SIMD3(repeating: arScale)
        a.addChild(pivot)
        // мягкое кольцо-вспышка при появлении
        let burst = Body3DPalette.floorEntity(size: 1.6)
        burst.position = [0, 0.002, 0]
        a.addChild(burst)
        burst.scale = SIMD3(repeating: 0.2)
        var tr = burst.transform
        tr.scale = SIMD3(repeating: 1.4)
        burst.move(to: tr, relativeTo: a, duration: 0.9, timingFunction: .easeOut)
        v.scene.addAnchor(a)
        arAnchor = a
        r.isEnabled = false
        placed = true
        appear = 0
        arHint = ""
        OxHaptics.play(.setDone)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            burst.removeFromParent()
            let f = Body3DPalette.floorEntity(size: 1.2)
            f.position = [0, 0.002, 0]
            a.addChild(f)
        }
    }

    func replace() {
        guard mode == .ar, let a = arAnchor, let v = view else { return }
        a.removeChild(pivot)
        v.scene.removeAnchor(a)
        arAnchor = nil
        placed = false
        arHint = "Наведите камеру на пол"
    }

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in self.arError = "AR-сессия остановилась: \(text)" }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.arHint = "Камера недоступна — вернитесь в приложение" }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in self.arHint = self.placed ? "" : "Наведите камеру на пол" }
    }
}
