import SwiftUI

/// Живой зелёный «блоб»: несколько капель сливаются друг с другом (эффект метаболов),
/// медленно перетекают и тянутся за пальцем. Рисуется на GPU через Canvas.
struct OxBlob: View {
    var height: CGFloat = 240
    var interactive = true
    @State private var touch: CGPoint?
    @State private var start = Date()

    private struct Drop { let rx, ry, sx, sy, phase, r: Double }
    private let drops: [Drop] = [
        Drop(rx: 0.20, ry: 0.16, sx: 0.31, sy: 0.43, phase: 0.0, r: 0.30),
        Drop(rx: 0.24, ry: 0.20, sx: 0.47, sy: 0.29, phase: 1.7, r: 0.24),
        Drop(rx: 0.16, ry: 0.22, sx: 0.23, sy: 0.37, phase: 3.1, r: 0.22),
        Drop(rx: 0.26, ry: 0.14, sx: 0.39, sy: 0.51, phase: 4.4, r: 0.19),
        Drop(rx: 0.12, ry: 0.18, sx: 0.55, sy: 0.33, phase: 5.6, r: 0.17),
        Drop(rx: 0.22, ry: 0.10, sx: 0.29, sy: 0.61, phase: 2.5, r: 0.14)
    ]

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            ZStack {
                // мягкое свечение
                fill.mask(shape(t)).blur(radius: 34).opacity(0.55)
                // сам блоб
                fill.mask(shape(t))
                // блик
                RadialGradient(colors: [.white.opacity(0.45), .clear], center: UnitPoint(x: 0.38, y: 0.3), startRadius: 2, endRadius: 120)
                    .mask(shape(t))
                    .blendMode(.plusLighter)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(interactive ? DragGesture(minimumDistance: 0)
            .onChanged { touch = $0.location }
            .onEnded { _ in withAnimation(.spring) { touch = nil } } : nil)
        .accessibilityHidden(true)
    }

    private var fill: some View {
        LinearGradient(colors: [Color(hex: 0xD8FF6A), Color.lime, Color(hex: 0x58F670), Color(hex: 0x1E8F3A)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func shape(_ t: Double) -> some View {
        Canvas { ctx, size in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .white))
            ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.07))
            ctx.drawLayer { l in
                let m = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for d in drops {
                    let x = c.x + CGFloat(sin(t * d.sx + d.phase) * d.rx) * m
                    let y = c.y + CGFloat(cos(t * d.sy + d.phase * 1.3) * d.ry) * m
                    let pulse = 1 + 0.08 * sin(t * 1.3 + d.phase)
                    let r = CGFloat(d.r * pulse) * m * 0.5
                    l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
                }
                if let p = touch {
                    let r = m * 0.11
                    l.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white))
                }
            }
        }
    }
}

extension View {
    /// Контент не уезжает под шапку и Dynamic Island: прокрутка обрезается у нижнего края панели навигации
    func oxNoUnderlap() -> some View {
        self.padding(.top, 0.5).clipped()
    }
}
