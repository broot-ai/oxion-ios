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
struct AIOrb: View {
    var size: CGFloat = 46
    var active = false
    @State private var poke = false

    var body: some View {
        let live = PowerSaver.allowsNow(.liveBackgrounds)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * (active ? 2.6 : 1.0)
            let amp = active ? 0.075 : 0.035
            let shape = BlobShape(t: t, amp: amp)
            // сжатие-растяжение (как желе): по ширине больше — по высоте меньше
            let squash = (active ? 0.09 : 0.035) * sin(t * (active ? 2.4 : 1.2))
            ZStack {
                // зелёное свечение внутри, к краю переходит в чистое стекло
                shape
                    .fill(RadialGradient(colors: [Color(hex: 0x9BEA3C).opacity(0.85), Color.lime.opacity(0.35), Color.lime.opacity(0.0)],
                                         center: UnitPoint(x: 0.42 + 0.08 * cos(t * 0.7), y: 0.62 + 0.06 * sin(t * 0.9)),
                                         startRadius: 0, endRadius: size * 0.62))
                    .blur(radius: size * 0.05)
                // второе пятно — бирюзовый отлив
                Circle()
                    .fill(Color(hex: 0x3FD6C9).opacity(0.35))
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: CGFloat(cos(t * 1.1)) * size * 0.16, y: CGFloat(sin(t * 0.8)) * size * 0.14 - size * 0.08)
                    .blur(radius: size * 0.12)
                    .mask(shape)
                // стеклянный край и блик
                shape
                    .stroke(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05), Color.lime.opacity(0.5)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(1, size * 0.025))
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.42, height: size * 0.2)
                    .offset(x: -size * 0.08, y: -size * 0.24)
                    .blur(radius: size * 0.015)
            }
            .frame(width: size, height: size)
            .glassEffect(.clear.tint(Color.lime.opacity(0.12)), in: shape)
            .scaleEffect(x: 1 + squash, y: 1 - squash)
            .rotationEffect(.degrees(active ? 6 * sin(t * 0.9) : 0))
        }
        .frame(width: size, height: size)
        .scaleEffect(poke ? 0.82 : 1)
        .shadow(color: Color.lime.opacity(active ? 0.5 : 0.25), radius: size * (active ? 0.35 : 0.18))
        .animation(.easeInOut(duration: 0.4), value: active)
        .onChange(of: active) {
            // «подпрыгивает», когда начинает думать
            withAnimation(.spring(duration: 0.18)) { poke = true }
            withAnimation(.spring(duration: 0.6, bounce: 0.6).delay(0.18)) { poke = false }
        }
        .accessibilityLabel("ИИ-тренер")
    }
}
