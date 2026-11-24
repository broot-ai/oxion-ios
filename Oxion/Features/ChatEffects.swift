import SwiftUI

// Эффект «распада» удалённого сообщения

struct DissolveModifier: ViewModifier {
    let start: Date?
    /// стикеры, видео, кружки рисуются через UIKit — шейдер их не видит, для них частицы рисуем сверху
    var overlayParticles = false
    var tint: Color = Color.lime
    static let duration: TimeInterval = 1.1

    func body(content: Content) -> some View {
        if let start, overlayParticles {
            TimelineView(.animation) { tl in
                let t = min(1, tl.date.timeIntervalSince(start) / Self.duration)
                content
                    .opacity(max(0, 1 - t * 1.6))
                    .scaleEffect(1 - 0.15 * t)
                    .blur(radius: t * 8)
                    .overlay { DustBurst(t: t, tint: tint).padding(-60).allowsHitTesting(false) }
            }
        } else if let start {
            TimelineView(.animation) { tl in
                let t = min(1, tl.date.timeIntervalSince(start) / Self.duration)
                // запас вокруг пузыря, чтобы частицы могли разлететься за его края
                content
                    .padding(60)
                    .visualEffect { c, proxy in
                        c.layerEffect(ShaderLibrary.oxDissolve(.float(t), .float2(proxy.size)),
                                      maxSampleOffset: CGSize(width: 100, height: 100))
                    }
                    .padding(-60)
            }
        } else {
            content
        }
    }
}


/// Облако частиц поверх исчезающего стикера
private struct DustBurst: View {
    let t: Double
    var tint: Color
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<260 {
                let fi = Double(i)
                func r(_ k: Double) -> Double { let x = sin(fi * 12.9898 + k * 78.233) * 43758.5453; return x - floor(x) }
                // частица стартует внутри стикера и улетает вверх-вправо
                let sx = c.x + (r(1) - 0.5) * (size.width - 120)
                let sy = c.y + (r(2) - 0.5) * (size.height - 120)
                let delay = (1 - (sx / size.width)) * 0.4 + r(3) * 0.2
                let k = max(0, min(1, (t - delay) / 0.5))
                guard k > 0, k < 1 else { continue }
                let ang = -1.2 + r(4) * 1.9
                let d = (16 + r(5) * 60) * k * k
                let p = CGPoint(x: sx + cos(ang) * d, y: sy + sin(ang) * d)
                let s = 1.5 + r(6) * 2
                var g = ctx
                g.opacity = 1 - k
                let col: Color = r(7) < 0.5 ? tint : (r(7) < 0.8 ? .white : tint.opacity(0.6))
                g.fill(Path(CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(col))
            }
        }
    }
}



