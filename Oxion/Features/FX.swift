import SwiftUI
import UIKit

// MARK: - Частицы и световые эффекты
// Короткие (0,6–1,8 с), рисуются в отдельном прозрачном окне поверх всего и НЕ перехватывают нажатия.

enum FXKind {
    case confetti          // завершение тренировки
    case sparks            // достижение
    case lightWaves        // цель выполнена
    case energyPulse       // старт тренировки / импульс
    case dust              // мелкие частицы при переходах
}

struct FXParticle {
    var p: CGPoint
    var v: CGVector
    var size: CGFloat
    var color: Color
    var spin: Double
    var angle: Double
    var shape: Int          // 0 круг, 1 прямоугольник-конфетти, 2 искра-линия, 3 звёздочка
    var life: Double
}

struct FXBurst: Identifiable {
    let id = UUID()
    let kind: FXKind
    let origin: CGPoint
    let start = Date()
    var duration: Double
    var particles: [FXParticle]
}

@MainActor
@Observable
final class FX {
    static let shared = FX()
    var bursts: [FXBurst] = []
    private var window: UIWindow?

    /// Проиграть эффект. `at` — точка на экране (по умолчанию центр).
    static func play(_ kind: FXKind, at point: CGPoint? = nil) {
        guard PowerSaver.allowsNow(.interface) else { return }
        shared.attach()
        let size = shared.window?.bounds.size ?? UIScreen.main.bounds.size
        let origin = point ?? CGPoint(x: size.width / 2, y: size.height * 0.42)
        let b = shared.make(kind, origin: origin, size: size)
        shared.bursts.append(b)
        shared.window?.isHidden = false
        switch kind {
        case .confetti: OxHaptics.play(.workoutDone)
        case .sparks, .lightWaves: Haptic.success()
        case .energyPulse: Haptic.tap(.medium)
        case .dust: break
        }
        let d = b.duration
        Task {
            try? await Task.sleep(for: .seconds(d + 0.05))
            shared.bursts.removeAll { $0.id == b.id }
            if shared.bursts.isEmpty { shared.window?.isHidden = true }
        }
    }

    private func attach() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PassthroughWindow(windowScene: scene)
        w.windowLevel = .alert + 2
        w.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: FXOverlay())
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        w.rootViewController = host
        w.backgroundColor = .clear
        w.isHidden = true
        window = w
    }

    private static let palette: [Color] = [Color.lime, Color(hex: 0x58F670), Color(hex: 0x3FD6C9), Color(hex: 0xFFD25E), .white, Color(hex: 0xFF7BC0)]

    private func make(_ kind: FXKind, origin o: CGPoint, size: CGSize) -> FXBurst {
        var ps: [FXParticle] = []
        func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
        switch kind {
        case .confetti:
            // два залпа из нижних углов + немного сверху
            for side in [0.0, 1.0] {
                for _ in 0..<55 {
                    let ang = side == 0 ? rnd(-1.35, -0.75) : rnd(-2.4, -1.8)
                    let sp = rnd(700, 1250)
                    ps.append(.init(p: CGPoint(x: side * size.width, y: size.height * 0.92), v: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp),
                                    size: rnd(6, 11), color: Self.palette.randomElement()!, spin: rnd(-9, 9), angle: rnd(0, 6),
                                    shape: Bool.random() ? 1 : 0, life: rnd(1.3, 1.8)))
                }
            }
            return FXBurst(kind: kind, origin: o, duration: 1.8, particles: ps)
        case .sparks:
            for _ in 0..<46 {
                let ang = rnd(0, .pi * 2), sp = rnd(220, 620)
                ps.append(.init(p: o, v: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp), size: rnd(2, 4.5),
                                color: [Color(hex: 0xFFD25E), .white, Color.lime].randomElement()!, spin: 0, angle: ang,
                                shape: Bool.random() ? 2 : 3, life: rnd(0.5, 0.95)))
            }
            return FXBurst(kind: kind, origin: o, duration: 1.0, particles: ps)
        case .lightWaves:
            for _ in 0..<18 {
                let ang = rnd(0, .pi * 2), sp = rnd(60, 160)
                ps.append(.init(p: o, v: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp), size: rnd(3, 6),
                                color: Color.lime, spin: 0, angle: 0, shape: 0, life: rnd(0.8, 1.3)))
            }
            return FXBurst(kind: kind, origin: o, duration: 1.4, particles: ps)
        case .energyPulse:
            for _ in 0..<26 {
                let ang = rnd(0, .pi * 2), sp = rnd(320, 520)
                ps.append(.init(p: o, v: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp), size: rnd(2, 3.5),
                                color: Color(hex: 0x58F670), spin: 0, angle: ang, shape: 2, life: rnd(0.35, 0.6)))
            }
            return FXBurst(kind: kind, origin: o, duration: 0.7, particles: ps)
        case .dust:
            for _ in 0..<14 {
                let ang = rnd(-.pi, 0), sp = rnd(40, 120)
                ps.append(.init(p: CGPoint(x: o.x + rnd(-30, 30), y: o.y + rnd(-6, 6)), v: CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp),
                                size: rnd(1.5, 3), color: Color.lime.opacity(0.9), spin: 0, angle: 0, shape: 0, life: rnd(0.4, 0.65)))
            }
            return FXBurst(kind: kind, origin: o, duration: 0.65, particles: ps)
        }
    }
}

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

struct FXOverlay: View {
    @State private var fx = FX.shared

    var body: some View {
        TimelineView(.animation(paused: fx.bursts.isEmpty)) { tl in
            Canvas { ctx, size in
                let now = tl.date
                for b in fx.bursts {
                    let t = now.timeIntervalSince(b.start)
                    draw(b, t: t, ctx: &ctx, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func draw(_ b: FXBurst, t: Double, ctx: inout GraphicsContext, size: CGSize) {
        switch b.kind {
        case .lightWaves:
            // три расходящихся светящихся кольца
            for i in 0..<3 {
                let lt = t - Double(i) * 0.18
                guard lt > 0 else { continue }
                let k = min(1, lt / 1.0)
                let r = 30 + k * max(size.width, size.height) * 0.55
                var c = ctx
                c.opacity = (1 - k) * 0.8
                c.addFilter(.blur(radius: 3 + k * 6))
                let rect = CGRect(x: b.origin.x - r, y: b.origin.y - r, width: r * 2, height: r * 2)
                c.stroke(Circle().path(in: rect), with: .color(Color.lime), lineWidth: 10 * (1 - k) + 2)
            }
        case .energyPulse:
            let k = min(1, t / 0.55)
            let r = 20 + k * 170
            var c = ctx
            c.opacity = (1 - k)
            c.addFilter(.blur(radius: 4))
            c.fill(Circle().path(in: CGRect(x: b.origin.x - r, y: b.origin.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0x58F670).opacity(0.0), Color(hex: 0x58F670).opacity(0.55), .clear]),
                                         center: b.origin, startRadius: r * 0.5, endRadius: r))
        default:
            break
        }
        let gravity: Double = b.kind == .confetti ? 1500 : (b.kind == .sparks ? 500 : 0)
        let drag: Double = b.kind == .confetti ? 1.4 : 2.2
        for p in b.particles {
            guard t < p.life else { continue }
            let damp = (1 - exp(-drag * t)) / drag
            let x = p.p.x + p.v.dx * damp
            let y = p.p.y + p.v.dy * damp + 0.5 * gravity * t * t * (b.kind == .confetti ? 0.55 : 1)
            let fade = 1 - pow(t / p.life, 2)
            var c = ctx
            c.opacity = max(0, fade)
            switch p.shape {
            case 1:
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(p.angle + p.spin * t))
                let flip = abs(cos(p.spin * t * 1.3))
                c.fill(Path(CGRect(x: -p.size / 2, y: -p.size * 0.3 * flip, width: p.size, height: p.size * 0.6 * flip + 0.5)), with: .color(p.color))
            case 2:
                let len = p.size * 5 * fade
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - cos(p.angle) * len, y: y - sin(p.angle) * len))
                c.addFilter(.blur(radius: 0.6))
                c.stroke(path, with: .color(p.color), style: StrokeStyle(lineWidth: p.size * 0.7, lineCap: .round))
            case 3:
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * 4))
                let s = p.size * 1.8
                var star = Path()
                star.move(to: CGPoint(x: 0, y: -s)); star.addLine(to: CGPoint(x: 0, y: s))
                star.move(to: CGPoint(x: -s, y: 0)); star.addLine(to: CGPoint(x: s, y: 0))
                c.stroke(star, with: .color(p.color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            default:
                if b.kind == .lightWaves || b.kind == .dust { c.addFilter(.blur(radius: 1.2)) }
                c.fill(Circle().path(in: CGRect(x: x - p.size / 2, y: y - p.size / 2, width: p.size, height: p.size)), with: .color(p.color))
            }
        }
    }
}

// MARK: - Наклон устройства: 3D-наклон и инерция (Core Motion)
// Движение телефона используется ТОЛЬКО для визуала, а не как доказательство выполнения упражнения.

struct MotionTilt: ViewModifier {
    var amount: Double = 7
    var shine = true

    func body(content: Content) -> some View {
        if PowerSaver.allowsNow(.liveBackgrounds) {
            TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                let t = TiltMotion.shared
                content
                    .rotation3DEffect(.degrees(-t.y * amount), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(t.x * amount), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .overlay {
                        if shine {
                            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.10), .white.opacity(0)],
                                           startPoint: UnitPoint(x: 0.2 + t.x * 0.8, y: 0), endPoint: UnitPoint(x: 0.8 + t.x * 0.8, y: 1))
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .onAppear { TiltMotion.shared.start() }
            .onDisappear { TiltMotion.shared.stop() }
        } else {
            content
        }
    }
}

extension View {
    /// Лёгкий 3D-наклон за телефоном с инерцией и бликом
    func motionTilt(_ amount: Double = 7, shine: Bool = true) -> some View { modifier(MotionTilt(amount: amount, shine: shine)) }
}
