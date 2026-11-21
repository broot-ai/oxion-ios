import SwiftUI
import SpriteKit
import CoreMotion
import UIKit

// MARK: - Жетоны OXION с настоящей физикой (SpriteKit)
// Высыпаются сверху, отскакивают и ложатся горкой. Нажатие подбрасывает их,
// наклон телефона пересыпает в сторону, при ударах — лёгкая вибрация.

final class CoinScene: SKScene, SKPhysicsContactDelegate {
    private var coins: [SKSpriteNode] = []
    private let motion = CMMotionManager()
    private var lastTap = Date.distantPast
    private var spawned = false
    var count = 30

    private static let coinCat: UInt32 = 1
    private static let wallCat: UInt32 = 2

    /// Текстуры жетона под разными углами наклона (1 — плашмя к нам, 0.3 — почти ребром)
    private static let textures: [SKTexture] = ([1.0, 0.86, 0.7, 0.52, 0.36] as [CGFloat]).map { SKTexture(image: coinImage(tilt: $0)) }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        rebuildWalls()
        if !spawned { spawned = true; drop() }
        startMotion()
    }

    override func willMove(from view: SKView) {
        motion.stopDeviceMotionUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildWalls()
    }

    /// Пол и стенки; сверху открыто — подброшенные жетоны улетают за край и падают обратно
    private func rebuildWalls() {
        guard size.width > 0 else { return }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: size.height * 4))
        p.addLine(to: .zero)
        p.addLine(to: CGPoint(x: size.width, y: 0))
        p.addLine(to: CGPoint(x: size.width, y: size.height * 4))
        let b = SKPhysicsBody(edgeChainFrom: p)
        b.categoryBitMask = Self.wallCat
        b.friction = 0.7
        physicsBody = b
    }

    /// Жетоны высыпаются сверху по одному
    func drop() {
        coins.forEach { $0.removeFromParent() }
        coins = []
        let w = max(size.width, 300)
        let d = w / 6.2
        for i in 0..<count {
            let tex = Self.textures.randomElement()!
            let node = SKSpriteNode(texture: tex)
            // глубина: дальние жетоны меньше и темнее, лежат «за» ближними
            let z = CGFloat.random(in: 0.7...1.0)
            let s = d * CGFloat.random(in: 0.9...1.06) * z
            node.size = CGSize(width: s, height: s)
            node.zPosition = z * 10
            node.color = .black
            node.colorBlendFactor = (1 - z) * 0.9
            node.position = CGPoint(x: CGFloat.random(in: s...(w - s)), y: size.height + s + CGFloat(i) * 16)
            node.zRotation = CGFloat.random(in: -0.6...0.6)
            let body = SKPhysicsBody(texture: tex, alphaThreshold: 0.5, size: node.size)
            body.restitution = 0.28
            body.friction = 0.55
            body.linearDamping = 0.15
            body.angularDamping = 0.6
            body.density = 1.2
            body.categoryBitMask = Self.coinCat
            body.collisionBitMask = Self.coinCat | Self.wallCat
            body.contactTestBitMask = Self.wallCat | Self.coinCat
            node.physicsBody = body
            addChild(node)
            coins.append(node)
        }
    }

    /// Подбросить все жетоны вверх
    func burst(at point: CGPoint? = nil) {
        for c in coins {
            guard let b = c.physicsBody else { continue }
            var dx = CGFloat.random(in: -260...260)
            if let p = point { dx += (c.position.x - p.x) * 2.2 }
            b.velocity = CGVector(dx: dx, dy: CGFloat.random(in: 650...1100))
            b.angularVelocity = CGFloat.random(in: -14...14)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // Касание: короткое — подбросить; смахивание — швырнуть жетоны по направлению пальца
    private var touchStart: (CGPoint, Date)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchStart = (t.location(in: self), Date())
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let (p0, t0) = touchStart else { return }
        touchStart = nil
        let p1 = t.location(in: self)
        let dt = max(0.016, Date().timeIntervalSince(t0))
        let v = CGVector(dx: (p1.x - p0.x) / dt, dy: (p1.y - p0.y) / dt)
        let speed = hypot(v.dx, v.dy)
        if speed > 260 {
            fling(from: p0, to: p1, velocity: v)
        } else {
            guard Date().timeIntervalSince(lastTap) > 0.25 else { return }
            lastTap = Date()
            burst(at: p1)
        }
    }

    /// Швырок пальцем: жетоны рядом с линией жеста получают скорость по направлению жеста
    func fling(from a: CGPoint, to b: CGPoint, velocity v: CGVector) {
        let k = min(1.6, 900 / max(hypot(v.dx, v.dy), 1)) * 1.1
        for c in coins {
            guard let body = c.physicsBody else { continue }
            let d = distance(c.position, toSegment: a, b)
            guard d < 130 else { continue }
            let w = 1 - d / 130
            body.velocity = CGVector(dx: body.velocity.dx + v.dx * k * w, dy: body.velocity.dy + max(v.dy * k * w, 250 * w))
            body.angularVelocity += CGFloat.random(in: -10...10) * w
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
    }

    /// Подкидывание телефоном: сила зависит от рывка
    func toss(strength: CGFloat, side: CGFloat) {
        for c in coins {
            guard let b = c.physicsBody else { continue }
            let up = (420 + 900 * strength) * CGFloat.random(in: 0.75...1.15)
            b.velocity = CGVector(dx: b.velocity.dx + side * 260 + CGFloat.random(in: -120...120), dy: up)
            b.angularVelocity = CGFloat.random(in: -12...12)
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: min(1, 0.5 + strength))
    }

    private func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let len2 = ab.dx * ab.dx + ab.dy * ab.dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / len2))
        return hypot(p.x - (a.x + ab.dx * t), p.y - (a.y + ab.dy * t))
    }

    // Гравитация следует за наклоном телефона
    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive, PowerSaver.allowsNow(.liveBackgrounds) else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let g = m.gravity, ua = m.userAcceleration
            let dx = CGFloat(g.x) * 9.8
            let dy = min(-3, CGFloat(g.y) * 9.8)   // всегда немного вниз, чтобы горка не «взлетала»
            self.physicsWorld.gravity = CGVector(dx: dx, dy: dy)
            // рывок телефона вверх (против силы тяжести) — жетоны подпрыгивают
            let up = -(ua.x * g.x + ua.y * g.y + ua.z * g.z)
            if up > 0.75, Date().timeIntervalSince(self.lastToss) > 0.4 {
                self.lastToss = Date()
                self.toss(strength: CGFloat(min(1, (up - 0.75) / 1.2)), side: CGFloat(max(-1, min(1, ua.x * 2))))
            }
        }
    }

    // Лёгкая вибрация при сильных ударах (не чаще 12 раз в секунду)
    private var lastHaptic = Date.distantPast
    private var lastToss = Date.distantPast
    private let tick = UIImpactFeedbackGenerator(style: .light)

    func didBegin(_ contact: SKPhysicsContact) {
        guard contact.collisionImpulse > 2.2, Date().timeIntervalSince(lastHaptic) > 0.08 else { return }
        lastHaptic = Date()
        tick.impactOccurred(intensity: min(1, contact.collisionImpulse / 9))
    }

    // MARK: Рисунок жетона: обод, лицевая сторона с градиентом, выдавленный логотип

    static func coinImage(tilt k: CGFloat) -> UIImage {
        let side: CGFloat = 160
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return r.image { ctx in
            let g = ctx.cgContext
            let faceW = side * 0.92
            let faceH = faceW * k
            let thick = side * 0.09 * (1 - k * 0.55)
            let x = (side - faceW) / 2
            let y = (side - faceH - thick) / 2
            let face = CGRect(x: x, y: y, width: faceW, height: faceH)
            let rim = face.offsetBy(dx: 0, dy: thick)

            // обод (толщина жетона)
            let rimPath = UIBezierPath(ovalIn: rim)
            rimPath.append(UIBezierPath(rect: CGRect(x: face.minX, y: face.midY, width: faceW, height: thick)))
            UIColor(red: 0.20, green: 0.52, blue: 0.10, alpha: 1).setFill()
            rimPath.fill()

            // лицевая сторона
            g.saveGState()
            UIBezierPath(ovalIn: face).addClip()
            let colors = [UIColor(red: 0.90, green: 1.00, blue: 0.55, alpha: 1).cgColor,
                          UIColor(red: 0.70, green: 0.93, blue: 0.22, alpha: 1).cgColor,
                          UIColor(red: 0.35, green: 0.75, blue: 0.20, alpha: 1).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
            g.drawRadialGradient(grad, startCenter: CGPoint(x: face.midX - faceW * 0.18, y: face.midY - faceH * 0.22), startRadius: 2,
                                 endCenter: CGPoint(x: face.midX, y: face.midY), endRadius: faceW * 0.62, options: [.drawsAfterEndLocation])
            g.restoreGState()

            // внутреннее кольцо
            let inner = face.insetBy(dx: faceW * 0.09, dy: faceH * 0.09)
            let ring = UIBezierPath(ovalIn: inner)
            ring.lineWidth = side * 0.022
            UIColor(red: 0.30, green: 0.62, blue: 0.12, alpha: 0.55).setStroke()
            ring.stroke()

            // логотип, «выдавленный» в металле
            if let logo = UIImage(named: "ox-logo") {
                let lw = faceW * 0.34
                let lh = lw * (logo.size.height / max(1, logo.size.width)) * k
                let lr = CGRect(x: face.midX - lw / 2, y: face.midY - lh / 2, width: lw, height: lh)
                logo.withTintColor(UIColor(white: 1, alpha: 0.45), renderingMode: .alwaysOriginal).draw(in: lr.offsetBy(dx: 0, dy: -1.5))
                logo.withTintColor(UIColor(red: 0.22, green: 0.50, blue: 0.08, alpha: 0.9), renderingMode: .alwaysOriginal).draw(in: lr)
            }

            // блик
            g.saveGState()
            UIBezierPath(ovalIn: face).addClip()
            let hl = CGRect(x: face.minX + faceW * 0.12, y: face.minY + faceH * 0.06, width: faceW * 0.5, height: faceH * 0.32)
            UIColor(white: 1, alpha: 0.28).setFill()
            UIBezierPath(ovalIn: hl).fill()
            g.restoreGState()
        }
    }
}

/// Карточка с жетонами: «коробка» с эффектом глубины — задняя стенка, пол, тени,
/// стекло спереди с бликом; слои смещаются при наклоне телефона (параллакс).
struct OxCoinsCard<Label: View>: View {
    var height: CGFloat = 250
    @ViewBuilder var label: () -> Label
    @State private var scene: CoinScene = {
        let s = CoinScene(size: CGSize(width: 360, height: 250))
        s.scaleMode = .resizeFill
        return s
    }()
    private let live = PowerSaver.allowsNow(.liveBackgrounds)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !live)) { _ in
            let t = TiltMotion.shared
            let px = CGFloat(t.x), py = CGFloat(t.y)
            ZStack(alignment: .top) {
                // глубина: задняя стенка и пол, сходящиеся к центру
                DepthBox(parallax: CGSize(width: px * 14, height: -py * 10))
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .offset(x: px * 4, y: -py * 3)
                // внутренняя тень по краям — будто жетоны внутри
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.black.opacity(0.55), lineWidth: 18)
                    .blur(radius: 14)
                    .allowsHitTesting(false)
                // стекло спереди: блик ездит за наклоном
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.0), .white.opacity(0.05)],
                               startPoint: UnitPoint(x: 0.1 + px * 0.6, y: 0), endPoint: UnitPoint(x: 0.7 + px * 0.6, y: 1))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(Double(-py) * 4), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(Double(px) * 4), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        // «жидкое стекло» поверх — вне 3D-поворота, чтобы стекло преломляло живые жетоны
        .overlay(alignment: .top) {
            label()
                .padding(.top, 34)
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: Color.lime.opacity(0.18), radius: 24, y: 10)
        .onAppear { if live { TiltMotion.shared.start() } }
        .onDisappear { if live { TiltMotion.shared.stop() } }
    }
}

/// Внутренность «коробки»: задняя стенка меньше рамки, рёбра к углам, светлый пол
private struct DepthBox: View {
    var parallax: CGSize

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0E1410)))
            let inset = CGSize(width: w * 0.16, height: h * 0.2)
            let back = CGRect(x: inset.width + parallax.width, y: inset.height * 0.6 + parallax.height,
                              width: w - inset.width * 2, height: h - inset.height * 1.6)
            // задняя стенка
            ctx.fill(RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: back),
                     with: .radialGradient(Gradient(colors: [Color.lime.opacity(0.22), Color(hex: 0x111A0C)]),
                                           center: CGPoint(x: back.midX, y: back.maxY), startRadius: 4, endRadius: back.width * 0.8))
            // пол (трапеция от низа задней стенки к низу карточки)
            var floor = Path()
            floor.move(to: CGPoint(x: back.minX, y: back.maxY))
            floor.addLine(to: CGPoint(x: back.maxX, y: back.maxY))
            floor.addLine(to: CGPoint(x: w, y: h))
            floor.addLine(to: CGPoint(x: 0, y: h))
            floor.closeSubpath()
            ctx.fill(floor, with: .linearGradient(Gradient(colors: [Color(hex: 0x1E2E12), Color(hex: 0x34501C)]),
                                                  startPoint: CGPoint(x: 0, y: back.maxY), endPoint: CGPoint(x: 0, y: h)))
            // рёбра коробки
            var edges = Path()
            for (a, b) in [(CGPoint(x: back.minX, y: back.minY), CGPoint.zero), (CGPoint(x: back.maxX, y: back.minY), CGPoint(x: w, y: 0)),
                           (CGPoint(x: back.minX, y: back.maxY), CGPoint(x: 0, y: h)), (CGPoint(x: back.maxX, y: back.maxY), CGPoint(x: w, y: h))] {
                edges.move(to: a); edges.addLine(to: b)
            }
            ctx.stroke(edges, with: .color(.white.opacity(0.06)), lineWidth: 1)
            ctx.stroke(RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: back), with: .color(.white.opacity(0.07)), lineWidth: 1)
            // сетка на полу для перспективы
            var grid = Path()
            for i in 1..<6 {
                let k = CGFloat(i) / 6
                let y = back.maxY + (h - back.maxY) * k * k
                let x0 = back.minX * (1 - k * k), x1 = back.maxX + (w - back.maxX) * k * k
                grid.move(to: CGPoint(x: x0, y: y)); grid.addLine(to: CGPoint(x: x1, y: y))
            }
            ctx.stroke(grid, with: .color(Color.lime.opacity(0.07)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Контент не уезжает под шапку и Dynamic Island, но внизу, как обычно, проходит под меню.
    /// Маска совпадает с рамкой экрана (верх = низ шапки) и продлена вниз до края экрана.
    func oxNoUnderlap() -> some View {
        self
            .mask { Rectangle().ignoresSafeArea(edges: .bottom) }
            .background(Color.oxBg)
    }
}
