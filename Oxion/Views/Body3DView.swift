import SwiftUI
import SceneKit
import Charts

// MARK: - OXION 3D Body: интерактивная модель тела на SceneKit

/// Ключи мышечных групп совпадают с ключами упражнений на сервере (chest, back, …)
enum BodyMuscles {
    static let keys = ["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs"]
    /// На какой стороне группа видна лучше (для автоповорота)
    static let backSide: Set<String> = ["back", "triceps", "glutes"]

    /// Общие ориентиры (не медицинская рекомендация)
    static func tips(_ key: String) -> [String] {
        switch key {
        case "chest": return ["10–20 рабочих подходов в неделю, 2 тренировки", "6–12 повторений в жимах, 10–15 в разводках", "Отдых 1,5–3 мин в базовых упражнениях", "Лопатки сведены, плечи не поднимаются к ушам"]
        case "back": return ["10–20 подходов в неделю: вертикальные и горизонтальные тяги", "8–12 повторений, полная амплитуда", "Тяните локтями, а не кистями", "Спина ровная в наклонных тягах"]
        case "shoulders": return ["8–16 подходов в неделю, жимы + махи", "Махи: 12–20 повторений с лёгким весом", "Не забывайте заднюю дельту", "Без рывков корпусом"]
        case "biceps": return ["6–12 подходов в неделю — спина тоже их нагружает", "8–15 повторений, медленное опускание", "Локти прижаты к корпусу"]
        case "triceps": return ["6–12 подходов в неделю — жимы тоже их нагружают", "10–15 повторений", "Локти не разводите в стороны"]
        case "abs": return ["2–3 раза в неделю, 6–10 подходов", "Важен контроль, а не скорость", "Планка и подъёмы ног — основа"]
        case "glutes": return ["10–16 подходов в неделю", "Ягодичный мост, выпады, тяга на прямых ногах", "Пауза 1 сек в верхней точке"]
        case "legs": return ["12–20 подходов в неделю: квадрицепсы, бицепс бедра, икры", "Приседания и жимы — 6–12 повторений", "Колени смотрят туда же, куда носки", "Икры: 12–20 повторений с паузой"]
        default: return []
        }
    }

    /// Слова в направлениях тренеров, подходящие группе
    static func trainerWords(_ key: String) -> [String] {
        switch key {
        case "abs": return ["функц", "пилат", "йог", "кор", "похуд"]
        case "glutes", "legs": return ["силов", "функц", "кроссфит", "бодибилд", "фитнес", "похуд"]
        default: return ["силов", "бодибилд", "пауэр", "кроссфит", "набор", "масс"]
        }
    }
}

// MARK: Сцена

@MainActor
final class BodyScene {
    let scene = SCNScene()
    let root = SCNNode()
    let camera = SCNNode()
    private(set) var muscles: [String: [SCNNode]] = [:]

    static let base = UIColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1)
    static let muscle = UIColor(red: 0.30, green: 0.32, blue: 0.35, alpha: 1)
    static let lime = UIColor(red: 0.698, green: 0.933, blue: 0.216, alpha: 1)

    init() {
        scene.background.contents = UIColor.clear
        root.position = SCNVector3(0, -0.92, 0)
        scene.rootNode.addChildNode(root)
        buildBody()
        buildMuscles()
        buildStage()

        let cam = SCNCamera()
        cam.fieldOfView = 32
        cam.zNear = 0.05
        cam.wantsHDR = true
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 0.75
        camera.camera = cam
        camera.position = SCNVector3(0, 0, 4.4)
        scene.rootNode.addChildNode(camera)

        func light(_ type: SCNLight.LightType, _ color: UIColor, _ intensity: CGFloat, _ pos: SCNVector3? = nil, look: Bool = true) {
            let l = SCNLight()
            l.type = type
            l.color = color
            l.intensity = intensity
            let n = SCNNode()
            n.light = l
            if let pos { n.position = pos }
            if look { n.look(at: SCNVector3(0, 0, 0)) }
            scene.rootNode.addChildNode(n)
        }
        light(.ambient, UIColor(white: 1, alpha: 1), 220, look: false)
        light(.directional, UIColor(white: 1, alpha: 1), 900, SCNVector3(1.5, 2.5, 3))
        light(.directional, UIColor(red: 0.7, green: 1, blue: 0.4, alpha: 1), 700, SCNVector3(-2, 1.2, -3))
        light(.directional, UIColor(white: 0.8, alpha: 1), 300, SCNVector3(-2.5, 0.5, 2))
    }

    private func mat(_ c: UIColor, rough: CGFloat = 0.55) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = 0.08
        return m
    }

    @discardableResult
    private func add(_ g: SCNGeometry, _ x: Float, _ y: Float, _ z: Float,
                     scale: SCNVector3 = SCNVector3(1, 1, 1), color: UIColor = BodyScene.base, key: String? = nil) -> SCNNode {
        g.firstMaterial = mat(color, rough: key == nil ? 0.7 : 0.45)
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        n.scale = scale
        if let key {
            n.name = "m:\(key)"
            muscles[key, default: []].append(n)
        }
        root.addChildNode(n)
        return n
    }

    private func sphere(_ r: CGFloat) -> SCNSphere { let s = SCNSphere(radius: r); s.segmentCount = 48; return s }
    private func capsule(_ r: CGFloat, _ h: CGFloat) -> SCNCapsule {
        let c = SCNCapsule(capRadius: r, height: h)
        c.radialSegmentCount = 40
        c.capSegmentCount = 24
        return c
    }

    /// Основа тела (метры, ноги на y = 0)
    private func buildBody() {
        add(sphere(0.105), 0, 1.65, 0, scale: SCNVector3(0.88, 1.08, 0.98))
        add(SCNCylinder(radius: 0.052, height: 0.12), 0, 1.51, 0)
        add(capsule(0.16, 0.6), 0, 1.24, 0, scale: SCNVector3(1.32, 1, 0.74))
        add(capsule(0.15, 0.34), 0, 0.93, 0, scale: SCNVector3(1.18, 1, 0.8))
        for s: Float in [-1, 1] {
            add(capsule(0.056, 0.34), 0.272 * s, 1.27, 0)
            add(capsule(0.046, 0.31), 0.29 * s, 0.98, 0)
            add(sphere(0.05), 0.3 * s, 0.79, 0.005, scale: SCNVector3(0.75, 1.2, 0.55))
            add(capsule(0.092, 0.5), 0.1 * s, 0.62, 0)
            add(capsule(0.062, 0.44), 0.1 * s, 0.22, 0)
            let foot = SCNBox(width: 0.09, height: 0.05, length: 0.21, chamferRadius: 0.02)
            add(foot, 0.1 * s, 0.025, 0.045)
        }
    }

    /// Мышечные группы поверх основы — их можно выбрать нажатием
    private func buildMuscles() {
        let c = BodyScene.muscle
        for s: Float in [-1, 1] {
            add(sphere(0.11), 0.088 * s, 1.36, 0.072, scale: SCNVector3(1.05, 0.7, 0.55), color: c, key: "chest")
            add(sphere(0.077), 0.226 * s, 1.44, 0, scale: SCNVector3(1, 0.95, 0.98), color: c, key: "shoulders")
            add(capsule(0.044, 0.2), 0.272 * s, 1.27, 0.03, color: c, key: "biceps")
            add(capsule(0.044, 0.23), 0.272 * s, 1.29, -0.03, color: c, key: "triceps")
            add(sphere(0.12), 0.09 * s, 1.27, -0.07, scale: SCNVector3(1, 1.5, 0.5), color: c, key: "back")
            add(sphere(0.1), 0.077 * s, 0.9, -0.085, scale: SCNVector3(1, 1, 0.6), color: c, key: "glutes")
            add(capsule(0.074, 0.38), 0.1 * s, 0.64, 0.032, color: c, key: "legs")
            add(capsule(0.07, 0.36), 0.1 * s, 0.64, -0.03, color: c, key: "legs")
            add(capsule(0.053, 0.22), 0.1 * s, 0.28, -0.024, color: c, key: "legs")
            for (i, y) in [Float(1.17), 1.1, 1.03].enumerated() {
                let b = SCNBox(width: 0.066, height: 0.06, length: 0.032, chamferRadius: 0.013)
                add(b, 0.037 * s, y, i == 2 ? 0.112 : 0.118, color: c, key: "abs")
            }
        }
        add(sphere(0.09), 0, 1.45, -0.05, scale: SCNVector3(1.7, 0.7, 0.6), color: c, key: "back")
    }

    private func buildStage() {
        let disk = SCNCylinder(radius: 0.5, height: 0.004)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.black
        m.emission.contents = BodyScene.lime.withAlphaComponent(0.25)
        m.transparency = 0.6
        disk.firstMaterial = m
        let n = SCNNode(geometry: disk)
        n.position = SCNVector3(0, -0.004, 0)
        root.addChildNode(n)
        let ring = SCNTorus(ringRadius: 0.5, pipeRadius: 0.004)
        let rm = SCNMaterial()
        rm.diffuse.contents = BodyScene.lime
        rm.emission.contents = BodyScene.lime
        ring.firstMaterial = rm
        let rn = SCNNode(geometry: ring)
        rn.position = SCNVector3(0, 0, 0)
        root.addChildNode(rn)
    }

    /// Раскраска: выбранная группа — лайм, остальные — по нагрузке (0…1) или нейтрально
    func paint(selected: String?, heat: [String: Double]?, animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.3 : 0
        for (key, nodes) in muscles {
            let color: UIColor
            var glow = UIColor.black
            if key == selected {
                color = BodyScene.lime
                glow = BodyScene.lime.withAlphaComponent(0.45)
            } else if let heat {
                let h = CGFloat(min(1, max(0, heat[key] ?? 0)))
                color = BodyScene.blend(BodyScene.muscle, UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1), h)
                glow = UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1).withAlphaComponent(h * 0.3)
            } else {
                color = selected == nil ? BodyScene.muscle : BodyScene.muscle.withAlphaComponent(1)
            }
            for n in nodes {
                n.geometry?.firstMaterial?.diffuse.contents = color
                n.geometry?.firstMaterial?.emission.contents = glow
            }
        }
        SCNTransaction.commit()
    }

    static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    func showBack(_ back: Bool) {
        let a = SCNAction.rotateTo(x: 0, y: back ? .pi : 0, z: 0, duration: 0.6, usesShortestUnitArc: true)
        a.timingMode = .easeInEaseOut
        root.runAction(a)
    }

    /// Центр группы в мировых координатах (для приближения камеры)
    func center(_ key: String) -> SCNVector3? {
        guard let nodes = muscles[key], !nodes.isEmpty else { return nil }
        var x: Float = 0, y: Float = 0, z: Float = 0
        for n in nodes { let p = n.worldPosition; x += p.x; y += p.y; z += p.z }
        let k = Float(nodes.count)
        return SCNVector3(x / k, y / k, z / k)
    }

    static func key(of node: SCNNode?) -> String? {
        var n = node
        while let cur = n {
            if let name = cur.name, name.hasPrefix("m:") { return String(name.dropFirst(2)) }
            n = cur.parent
        }
        return nil
    }
}

// MARK: SwiftUI-обёртка

struct BodySceneView: UIViewRepresentable {
    var selected: String?
    var heat: [String: Double]?
    var back: Bool
    var zoom: Bool = true
    var interactive: Bool = true
    var onSelect: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.body.scene
        v.pointOfView = context.coordinator.body.camera
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = interactive
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.maximumVerticalAngle = 35
        v.defaultCameraController.minimumVerticalAngle = -20
        v.defaultCameraController.target = SCNVector3(0, 0, 0)
        if interactive {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
            v.addGestureRecognizer(tap)
        }
        context.coordinator.view = v
        context.coordinator.onSelect = onSelect
        context.coordinator.body.paint(selected: selected, heat: heat, animated: false)
        if back { context.coordinator.body.showBack(true) }
        context.coordinator.lastBack = back
        context.coordinator.lastSelected = selected
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.body.paint(selected: selected, heat: heat)
        if c.lastBack != back {
            c.lastBack = back
            c.body.showBack(back)
        }
        if c.lastSelected != selected {
            c.lastSelected = selected
            if zoom { c.focus(selected) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        let body = BodyScene()
        weak var view: SCNView?
        var onSelect: (String?) -> Void = { _ in }
        var lastBack = false
        var lastSelected: String?

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = view else { return }
            let hits = v.hitTest(g.location(in: v), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            // берём мышцу, только если она у самой поверхности (не «сквозь» тело)
            var key: String?
            if let cam = v.pointOfView?.worldPosition, let first = hits.first {
                func dist(_ h: SCNHitTestResult) -> Float {
                    let p = h.worldCoordinates
                    return sqrt(pow(p.x - cam.x, 2) + pow(p.y - cam.y, 2) + pow(p.z - cam.z, 2))
                }
                let d0 = dist(first)
                key = hits.first(where: { BodyScene.key(of: $0.node) != nil && dist($0) - d0 < 0.04 })
                    .flatMap { BodyScene.key(of: $0.node) }
            }
            OxHaptics.play(.select)
            onSelect(key)
        }

        /// Плавно приблизить камеру к выбранной группе или вернуть общий план
        func focus(_ key: String?) {
            guard let v = view, let pov = v.pointOfView else { return }
            let target: SCNVector3
            var dist: Float = 4.4
            if let key, let c = body.center(key) {
                target = SCNVector3(0, c.y, 0)
                dist = 2.6
            } else {
                target = SCNVector3(0, 0, 0)
            }
            // направление взгляда сохраняем, меняем только дистанцию и цель
            let p = pov.position
            let ct = v.defaultCameraController.target
            var dir = SCNVector3(p.x - ct.x, p.y - ct.y, p.z - ct.z)
            let len = max(0.001, sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z))
            dir = SCNVector3(dir.x / len, dir.y / len, dir.z / len)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pov.position = SCNVector3(target.x + dir.x * dist, target.y + dir.y * dist, target.z + dir.z * dist)
            pov.look(at: target)
            SCNTransaction.commit()
            v.defaultCameraController.target = target
        }
    }
}

// MARK: Экран «3D-тело»

struct BodyExplorerView: View {
    @Environment(AppModel.self) private var model
    var initial: String? = nil

    @State private var selected: String?
    @State private var back = false
    @State private var showHeat = false
    @State private var exercises: [Exercise] = []
    @State private var trainers: [Trainer] = []
    @State private var workouts: [Workout] = []
    @State private var loaded = false

    private var heat: [String: Double] {
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        var c: [String: Int] = [:]
        for w in workouts where (RU.dayFormatter.date(from: w.date) ?? .distantPast) >= since {
            for g in Set(normGroups(w.groups)) { c[g, default: 0] += 1 }
        }
        let mx = Double(max(1, c.values.max() ?? 1))
        return c.mapValues { Double($0) / mx }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    RadialGradient(colors: [Color.lime.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 260)
                    BodySceneView(selected: selected, heat: showHeat ? heat : nil, back: back) { key in
                        withAnimation(.snappy) { select(key) }
                    }
                    .frame(height: 460)
                    HStack {
                        Picker("", selection: $back.animation()) {
                            Text("Спереди").tag(false)
                            Text("Сзади").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                        Spacer()
                        Button {
                            withAnimation { showHeat.toggle() }
                            OxHaptics.play(.select)
                        } label: {
                            Label("Нагрузка", systemImage: showHeat ? "flame.fill" : "flame")
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .glassEffect(.regular.tint(showHeat ? Color.orange.opacity(0.4) : .clear).interactive(), in: .capsule)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .overlay(alignment: .bottom) {
                    Text(selected.map { model.muscleName($0) } ?? "Нажмите на мышцу · вращайте пальцем · сведите пальцы для зума")
                        .font(selected == nil ? .caption : .title3.bold())
                        .foregroundStyle(selected == nil ? Color.oxHint : Color.lime)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 8)
                        .contentTransition(.opacity)
                }

                if showHeat {
                    HStack(spacing: 8) {
                        Text("Мало").font(.caption2)
                        LinearGradient(colors: [Color(uiColor: BodyScene.muscle), Color(red: 0.95, green: 0.55, blue: 0.15)], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 6).clipShape(Capsule())
                        Text("Часто").font(.caption2)
                    }
                    .foregroundStyle(Color.oxHint)
                    .padding(.horizontal, 20)
                    Text("Сколько тренировок за 4 недели задействовали группу (по вашему дневнику).")
                        .font(.caption).foregroundStyle(Color.oxHint).padding(.horizontal, 20)
                }

                chips

                if let key = selected {
                    detail(key)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 30)
        }
        .background(Color.oxBg)
        .navigationTitle("3D-тело")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            if let k = initial { select(k) }
            await load()
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BodyMuscles.keys, id: \.self) { k in
                    Button {
                        withAnimation(.snappy) { select(selected == k ? nil : k) }
                        OxHaptics.play(.select)
                    } label: {
                        Text(model.muscleName(k))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(selected == k ? Color.black : Color.white)
                            .background(selected == k ? Color.lime : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func select(_ key: String?) {
        selected = key
        if let key {
            let wantBack = BodyMuscles.backSide.contains(key)
            if wantBack != back { back = wantBack }
        }
    }

    @ViewBuilder
    private func detail(_ key: String) -> some View {
        let list = exercises.filter { $0.muscle == key }
        VStack(alignment: .leading, spacing: 18) {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Нагрузка по неделям", systemImage: "chart.bar.fill").font(.headline)
                    let weeks = weekly(key)
                    Chart(weeks, id: \.label) { w in
                        BarMark(x: .value("Неделя", w.label), y: .value("Тренировок", w.count))
                            .foregroundStyle(Color.lime.gradient)
                            .cornerRadius(5)
                    }
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 120)
                    let total = weeks.reduce(0) { $0 + $1.count }
                    Text(total == 0 ? "За 8 недель тренировок на эту группу не было." : "За 8 недель: \(total) \(RU.plural(total, "тренировка", "тренировки", "тренировок")).")
                        .font(.caption).foregroundStyle(Color.oxHint)
                }
            }

            section("Упражнения", count: list.count) {
                if list.isEmpty {
                    Text(loaded ? "Упражнений для этой группы пока нет." : "Загрузка…")
                        .foregroundStyle(Color.oxHint).padding(.horizontal, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(list.prefix(8)) { e in
                            NavigationLink { ExerciseDetailView(e: e) } label: {
                                HStack(spacing: 12) {
                                    if e.image != nil {
                                        RemoteImage(url: API.media(e.image), icon: "dumbbell")
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else {
                                        MuscleThumb(key: e.muscle, size: 44)
                                    }
                                    Text(e.name).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.oxHint)
                                }
                                .padding(.vertical, 8).padding(.horizontal, 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }

            section("Рекомендации", count: nil) {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(BodyMuscles.tips(key), id: \.self) { t in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.lime).font(.caption)
                                Text(t).font(.subheadline)
                            }
                        }
                        Text("Общие ориентиры для здоровых взрослых, не медицинский совет. Точную программу лучше составить с тренером.")
                            .font(.caption2).foregroundStyle(Color.oxHint).padding(.top, 4)
                    }
                }
            }

            let tr = matchedTrainers(key)
            if !tr.isEmpty {
                section("Тренеры OXION", count: nil) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(tr) { t in
                                NavigationLink { TrainerDetailView(id: t.userId) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        RemoteImage(url: API.media(t.cover), icon: "person.fill")
                                            .frame(width: 150, height: 170)
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        Text(t.name ?? "Тренер").font(.subheadline.bold()).lineLimit(1)
                                        Text((t.directions ?? []).prefix(2).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                                    }
                                    .frame(width: 150)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
    }

    private func section<C: View>(_ title: String, count: Int?, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.bold())
                if let count, count > 0 { Text("\(count)").foregroundStyle(Color.oxHint) }
            }
            .padding(.horizontal, 16)
            c()
        }
    }

    // MARK: данные

    private func normGroups(_ g: [String]?) -> [String] {
        (g ?? []).compactMap { s in
            if BodyMuscles.keys.contains(s) || s == "cardio" { return s }
            return Muscles.fallback.first(where: { $0.value.lowercased() == s.lowercased() })?.key
                ?? model.meta?.muscles?.first(where: { $0.name.lowercased() == s.lowercased() })?.key
        }
    }

    private struct WeekBar { let label: String; let count: Int }

    private func weekly(_ key: String) -> [WeekBar] {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d.MM"
        return (0..<8).reversed().map { i in
            let ws = cal.date(byAdding: .weekOfYear, value: -i, to: start) ?? start
            let we = cal.date(byAdding: .day, value: 7, to: ws) ?? ws
            let n = workouts.filter { w in
                guard let d = RU.dayFormatter.date(from: w.date) else { return false }
                return d >= ws && d < we && normGroups(w.groups).contains(key)
            }.count
            return WeekBar(label: f.string(from: ws), count: n)
        }
    }

    private func matchedTrainers(_ key: String) -> [Trainer] {
        let words = BodyMuscles.trainerWords(key)
        let hit = trainers.filter { t in
            let d = (t.directions ?? []).joined(separator: " ").lowercased()
            return words.contains { d.contains($0) }
        }
        return Array((hit.isEmpty ? trainers : hit).prefix(6))
    }

    private func load() async {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -60, to: to) ?? to
        async let ex: ExercisesResponse? = try? API.call("/exercises")
        async let tr: TrainersResponse? = try? API.call("/trainers", query: ["sort": "match", "offset": "0"])
        async let wk: WorkoutsResponse? = try? API.call("/workouts", query: ["from": RU.dayFormatter.string(from: from), "to": RU.dayFormatter.string(from: to)])
        let (e, t, w) = await (ex, tr, wk)
        exercises = e?.items ?? []
        trainers = t?.items ?? []
        workouts = w?.items ?? []
    }
}
