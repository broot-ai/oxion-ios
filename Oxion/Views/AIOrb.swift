import SwiftUI

/// Значок ИИ-тренера: живой разноцветный блоб под жидким стеклом.
/// `active` — когда ИИ думает: блоб двигается быстрее и «дышит».
struct AIOrb: View {
    var size: CGFloat = 46
    var active = false

    private let colors: [Color] = [
        Color.lime, Color(hex: 0x3FD6C9), Color(hex: 0x8E7CFF), Color(hex: 0xFF7BC0), Color(hex: 0x58F670), Color(hex: 0x4CC3F0),
    ]

    var body: some View {
        let live = PowerSaver.allowsNow(.liveBackgrounds)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate * (active ? 2.2 : 0.8)
            ZStack {
                // основа: мягкий градиент по кругу, медленно вращается
                AngularGradient(colors: colors + [colors[0]], center: .center, angle: .radians(t * 0.6))
                    .blur(radius: size * 0.12)
                // плавающие пятна цвета — «блоб»
                ForEach(0..<4, id: \.self) { i in
                    let k = Double(i)
                    Circle()
                        .fill(colors[(i * 2 + 1) % colors.count])
                        .frame(width: size * 0.62, height: size * 0.62)
                        .offset(x: cos(t * (0.9 + k * 0.23) + k * 1.7) * size * 0.26,
                                y: sin(t * (1.1 + k * 0.19) + k * 2.3) * size * 0.26)
                        .blendMode(.plusLighter)
                        .opacity(0.75)
                }
                .blur(radius: size * 0.14)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            // «дыхание» и деформация, когда ИИ думает
            .scaleEffect(active ? 1 + 0.05 * sin(t * 3) : 1)
            .scaleEffect(x: 1 + 0.03 * sin(t * 1.7), y: 1 + 0.03 * cos(t * 1.3))
        }
        // жидкое стекло поверх: блик и преломление по краю
        .overlay {
            Circle()
                .fill(.clear)
                .glassEffect(.clear, in: .circle)
        }
        .overlay {
            // верхний блик
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.3)
                .offset(y: -size * 0.24)
                .blur(radius: size * 0.02)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.lime.opacity(active ? 0.55 : 0.3), radius: size * (active ? 0.4 : 0.22))
        .animation(.easeInOut(duration: 0.4), value: active)
        .accessibilityLabel("ИИ-тренер")
    }
}
