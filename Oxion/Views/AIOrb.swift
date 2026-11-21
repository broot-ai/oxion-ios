import SwiftUI

/// Мягкая «желейная» форма: радиус гуляет по нескольким гармоникам
struct BlobShape: Shape {
    var t: Double
    var amp: Double            // сила деформации, 0…0.2

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = Double(min(rect.width, rect.height)) / 2
        var p = Path()
        let n = 72
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let r = R * (1 - amp * 0.6
                         + amp * 0.55 * sin(2 * a + t * 1.3)
                         + amp * 0.35 * sin(3 * a - t * 1.7 + 1.1)
                         + amp * 0.22 * sin(5 * a + t * 2.3 + 2.4))
            let pt = CGPoint(x: c.x + CGFloat(cos(a) * r), y: c.y + CGFloat(sin(a) * r))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Значок ИИ-тренера: живой разноцветный блоб под жидким стеклом.
/// Сам по себе дышит, переливается и иногда «подпрыгивает»; когда ИИ думает — кривляется сильнее.
/// `interactive` — реагирует на касания: тык — сплющивается и отпружинивает, тянешь — тянется за пальцем.
struct AIOrb: View {
    var size: CGFloat = 46
    var active = false
    var interactive = false

    @State private var squish: CGFloat = 0          // -1…1: сплющен / вытянут
    @State private var pull: CGSize = .zero
    @State private var poke = 0.0                    // всплеск деформации после тыка

    private let colors: [Color] = [
        Color.lime, Color(hex: 0x3FD6C9), Color(hex: 0x8E7CFF), Color(hex: 0xFF7BC0), Color(hex: 0x58F670), Color(hex: 0x4CC3F0),
    ]

    var body: some View {
        let live = PowerSaver.allowsNow(.liveBackgrounds)
        TimelineView(.animation(minimumInterval: 1 / 40, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * (active ? 2.4 : 1.0)
            // иногда «икает»: короткий подскок раз в несколько секунд
            let hop = pow(max(0, sin(t * 0.55)), 24)
            let amp = (active ? 0.13 : 0.06) + hop * 0.08 + poke * 0.12
            let shape = BlobShape(t: t, amp: amp)
            ZStack {
                AngularGradient(colors: colors + [colors[0]], center: .center, angle: .radians(t * 0.6))
                    .blur(radius: size * 0.12)
                ForEach(0..<4, id: \.self) { i in blob(i, t: t) }
                    .blur(radius: size * 0.14)
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { Color.clear.glassEffect(.clear, in: shape) }
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.5, height: size * 0.26)
                    .offset(x: CGFloat(sin(t * 0.8)) * size * 0.04, y: size * 0.1)
                    .blur(radius: size * 0.02)
            }
            // дыхание + подскок + сплющивание от касаний
            .scaleEffect(x: 1 + 0.04 * CGFloat(sin(t * 1.9)) + squish * 0.22 - CGFloat(hop) * 0.06,
                         y: 1 + 0.04 * CGFloat(cos(t * 1.6)) - squish * 0.22 + CGFloat(hop) * 0.1,
                         anchor: .bottom)
            .offset(y: -CGFloat(hop) * size * 0.08)
            .rotationEffect(.degrees(active ? sin(t * 1.3) * 8 : sin(t * 0.7) * 3))
        }
        .frame(width: size, height: size)
        .offset(pull)
        .shadow(color: Color.lime.opacity(active ? 0.55 : 0.3), radius: size * (active ? 0.4 : 0.22))
        .animation(.easeInOut(duration: 0.4), value: active)
        .contentShape(Circle())
        .gesture(interactive ? drag : nil)
        .simultaneousGesture(interactive ? TapGesture().onEnded { bounce() } : nil)
        .accessibilityLabel("ИИ-тренер")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                // тянется за пальцем с сопротивлением
                let k: CGFloat = 0.35
                pull = CGSize(width: v.translation.width * k, height: v.translation.height * k)
                let d = min(1, hypot(v.translation.width, v.translation.height) / 160)
                squish = -d * 0.8
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
        withAnimation(.easeOut(duration: 0.1)) { poke = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 1.2)) { poke = 0 }
        }
    }

    private func blob(_ i: Int, t: Double) -> some View {
        let k = Double(i)
        let r = Double(size) * 0.26
        let dx = cos(t * (0.9 + k * 0.23) + k * 1.7) * r
        let dy = sin(t * (1.1 + k * 0.19) + k * 2.3) * r
        let d = size * 0.62
        return Circle()
            .fill(colors[(i * 2 + 1) % colors.count])
            .frame(width: d, height: d)
            .offset(x: CGFloat(dx), y: CGFloat(dy))
            .blendMode(.plusLighter)
            .opacity(0.75)
    }
}
