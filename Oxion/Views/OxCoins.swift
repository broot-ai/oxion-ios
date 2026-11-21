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
            let s = d * CGFloat.random(in: 0.88...1.08)
            node.size = CGSize(width: s, height: s)
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard Date().timeIntervalSince(lastTap) > 0.25 else { return }
        lastTap = Date()
        burst(at: touches.first?.location(in: self))
    }

    // Гравитация следует за наклоном телефона
    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive, PowerSaver.allowsNow(.liveBackgrounds) else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let dx = CGFloat(g.x) * 9.8
            let dy = min(-3, CGFloat(g.y) * 9.8)   // всегда немного вниз, чтобы горка не «взлетала»
            self.physicsWorld.gravity = CGVector(dx: dx, dy: dy)
        }
    }

    // Лёгкая вибрация при сильных ударах (не чаще 12 раз в секунду)
    private var lastHaptic = Date.distantPast
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

/// Карточка с жетонами и стеклянной плашкой поверх (как счётчик бонусов)
struct OxCoinsCard<Label: View>: View {
    var height: CGFloat = 250
    @ViewBuilder var label: () -> Label
    @State private var scene: CoinScene = {
        let s = CoinScene(size: CGSize(width: 360, height: 250))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color.lime.opacity(0.18), Color.oxCard], center: .bottom, startRadius: 10, endRadius: 320)
            SpriteView(scene: scene, options: [.allowsTransparency])
            label()
                .padding(.top, 34)
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
