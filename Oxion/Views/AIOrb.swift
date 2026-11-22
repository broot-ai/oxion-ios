import SwiftUI

/// Мягкая «капля»: край волнуется, как желе
struct BlobShape: Shape {
    var t: Double
    var amp: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = Double(min(rect.width, rect.height)) / 2 / (1 + amp * 1.6)
        let n = 64
        var pts: [CGPoint] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * .pi * 2
            var r = 1.0
            r += amp * sin(3 * a + t * 1.3)
            r += amp * 0.6 * sin(5 * a - t * 1.9 + 1.1)
            r += amp * 0.4 * cos(2 * a + t * 0.8)
            pts.append(CGPoint(x: c.x + CGFloat(cos(a) * base * r), y: c.y + CGFloat(sin(a) * base * r)))
        }
        // гладкий замкнутый контур через середины отрезков
        var p = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n {
            p.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i])
        }
        p.closeSubpath()
        return p
    }
}

/// Значок ИИ-тренера: живая капля из жидкого стекла с зелёным свечением внутри.
/// Всё время слегка «дышит» и меняет форму; когда ИИ думает (`active`) — сжимается, тянется и кривляется сильнее.
/// Силуэт пламени: капля с качающимся кончиком. t — время, amp — сила колыхания.
struct GlassFlameShape: Shape {
    var t: Double
    var amp: Double

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + CGFloat(x) * w, y: r.minY + CGFloat(y) * h) }
        let sway = sin(t * 1.7) * amp * 1.6 + sin(t * 3.1) * amp * 0.6     // кончик гуляет
        let breathe = sin(t * 2.3) * amp * 0.5                              // бока «дышат»
        let tipY = 0.02 + abs(sin(t * 2.9)) * amp * 0.8
        var path = Path()
        path.move(to: p(0.5 + sway, tipY))
        path.addCurve(to: p(0.86 + breathe, 0.58),
                      control1: p(0.6 + sway * 0.5, 0.2), control2: p(0.92 + breathe, 0.38))
        path.addCurve(to: p(0.5, 1.0),
                      control1: p(0.88 + breathe, 0.84), control2: p(0.72, 1.0))
        path.addCurve(to: p(0.14 - breathe, 0.6),
                      control1: p(0.28, 1.0), control2: p(0.1 - breathe, 0.82))
        path.addCurve(to: p(0.5 + sway, tipY),
                      control1: p(0.16 - breathe, 0.4), control2: p(0.4 + sway * 0.5, 0.22))
        path.closeSubpath()
        return path
    }
}

struct AIOrb: View {
    var size: CGFloat = 46
    var active = false
    /// реагирует на касания: тык — сплющивается и отпружинивает, тянешь — тянется за пальцем
    var interactive = false
    @State private var poke = false
    @State private var pull: CGSize = .zero
    @State private var squish: CGFloat = 0
    @State private var jiggle: Double = 0

    var body: some View {
        let live = PowerSaver.allowsNow(.liveBackgrounds)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * (active ? 2.4 : 0.9)
            let amp = (active ? 0.07 : 0.025) + jiggle * 0.08
            let shape = GlassFlameShape(t: t, amp: amp)
            // лёгкое «дыхание» пламени: вытягивается вверх и оседает
            let stretch = (active ? 0.06 : 0.025) * sin(t * (active ? 2.2 : 1.1))
            ZStack {
                // спокойное состояние: мягкое зелёное свечение у основания, к краю — чистое стекло
                shape
                    .fill(RadialGradient(colors: [Color(hex: 0x9BEA3C).opacity(0.8), Color.lime.opacity(0.28), Color.lime.opacity(0.0)],
                                         center: UnitPoint(x: 0.5 + 0.04 * cos(t * 0.8), y: 0.74),
                                         startRadius: 0, endRadius: size * 0.6))
                    .blur(radius: size * 0.04)
                    .opacity(active ? 0.45 : 1)
                // думает: внутри стекла горит настоящий огонь OXION
                if active && live {
                    AnimatedFire(size: size * 1.45, loop: 1.8)
                        .frame(width: size, height: size)
                        .offset(y: size * 0.06)
                        .blendMode(.screen)
                        .mask(shape)
                        .transition(.opacity)
                }
                // стеклянный край и блик
                shape
                    .stroke(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.08), Color.lime.opacity(0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(1, size * 0.024))
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.16, height: size * 0.3)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -size * 0.12, y: -size * 0.02)
                    .blur(radius: size * 0.012)
            }
            .compositingGroup()
            .frame(width: size * 0.82, height: size)
            .glassEffect(.clear.tint(Color.lime.opacity(active ? 0.06 : 0.12)), in: shape)
            .scaleEffect(x: 1 - stretch * 0.6 - squish * 0.3, y: 1 + stretch + squish * 0.3, anchor: .bottom)
        }
        .frame(width: size, height: size)
        .offset(pull)
        .scaleEffect(poke ? 0.82 : 1)
        .shadow(color: Color.lime.opacity(active ? 0.6 : 0.25), radius: size * (active ? 0.4 : 0.16))
        .animation(.easeInOut(duration: 0.4), value: active)
        .onChange(of: active) {
            // «подпрыгивает», когда начинает думать
            withAnimation(.spring(duration: 0.18)) { poke = true }
            withAnimation(.spring(duration: 0.6, bounce: 0.6).delay(0.18)) { poke = false }
        }
        .contentShape(Circle())
        .gesture(interactive ? drag : nil)
        .simultaneousGesture(interactive ? TapGesture().onEnded { bounce() } : nil)
        .accessibilityLabel("ИИ-тренер")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                pull = CGSize(width: v.translation.width * 0.35, height: v.translation.height * 0.35)
                squish = -min(1, hypot(v.translation.width, v.translation.height) / 160) * 0.8
            }
            .onEnded { _ in
                Haptic.tap(.soft)
                withAnimation(.spring(duration: 0.6, bounce: 0.6)) { pull = .zero; squish = 0 }
                wobble()
            }
    }

    private func bounce() {
        Haptic.tap(.rigid)
        withAnimation(.spring(duration: 0.12)) { squish = 0.9 }
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(duration: 0.7, bounce: 0.7)) { squish = 0 }
        }
        wobble()
    }

    private func wobble() {
        withAnimation(.easeOut(duration: 0.1)) { jiggle = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 1.2)) { jiggle = 0 }
        }
    }
}
