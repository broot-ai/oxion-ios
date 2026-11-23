import SwiftUI

// OXION — Interface Reassembly
// Потянул экран вниз → карточки приподнимаются над своими местами (3D, глубина, тень).
// Отпустил → разлетаются на небольшие расстояния: у каждой своя траектория, поворот и масштаб.
// Пока данные грузятся — карточки парят, на их местах остаются стеклянные «гнёзда» (matchedGeometryEffect).
// Данные пришли → карточки по очереди возвращаются на места, мягкая голубая вспышка.
// Reduce Motion: без полёта — только лёгкое затухание и вспышка. Нажатия не блокируются.

@MainActor @Observable
final class Reassembly {
    enum Phase: Equatable { case idle, pulling, scattered, returning }
    var phase: Phase = .idle
    /// 0…1 — насколько потянули
    var pull: CGFloat = 0
    /// счётчик вспышек: меняется — вспышка
    var flash = 0
    var reduceMotion = false
    private var crossed = false

    static let threshold: CGFloat = 110

    func pulled(_ d: CGFloat) {
        guard phase == .idle || phase == .pulling else { return }
        let p = max(0, min(1.3, d / Self.threshold))
        if p <= 0.02 {
            if phase == .pulling { withAnimation(.spring(duration: 0.35)) { phase = .idle; pull = 0 } }
            crossed = false
            return
        }
        if phase == .idle { phase = .pulling }
        pull = p
        if p >= 1 && !crossed { crossed = true; Haptic.tap(.medium) }
        else if p < 0.9 { crossed = false }
    }

    /// палец отпущен: если дотянули — разлёт, загрузка, сборка
    func released(_ work: @escaping () async -> Void) {
        guard phase == .pulling else { return }
        guard pull >= 1 else {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { phase = .idle; pull = 0 }
            return
        }
        Task { await run(work) }
    }

    func run(_ work: @escaping () async -> Void) async {
        withAnimation(.spring(duration: 0.7, bounce: 0.28)) { phase = .scattered; pull = 0 }
        let started = Date()
        await work()
        // анимация не короче 0.9 с — чтобы разлёт успел «прочитаться»
        let spent = Date().timeIntervalSince(started)
        if spent < 0.9 { try? await Task.sleep(for: .seconds(0.9 - spent)) }
        withAnimation(.spring(duration: 0.75, bounce: 0.22)) { phase = .returning }
        try? await Task.sleep(for: .milliseconds(520))
        withAnimation(.easeOut(duration: 0.6)) { flash += 1 }
        Haptic.success()
        try? await Task.sleep(for: .milliseconds(450))
        phase = .idle
        crossed = false
    }
}

// MARK: - Траектория карточки

/// индивидуальная, но постоянная для карточки траектория (по её номеру)
struct ScatterPath {
    let dx: CGFloat, dy: CGFloat, angle: Double, scale: CGFloat, tiltX: Double, tiltY: Double, lift: CGFloat
    init(index i: Int, amplitude a: CGFloat = 1) {
        func r(_ k: Int) -> CGFloat {  // детерминированный «случай» −1…1
            let x = sin(Double(i * 92821 + k * 68917) * 0.0137) * 43758.5453
            return CGFloat((x - floor(x)) * 2 - 1)
        }
        dx = r(1) * 46 * a
        dy = (r(2) * 34 - 6) * a
        angle = Double(r(3) * a) * 9
        scale = 1 - (0.1 - (r(4) + 1) * 0.07) * a
        tiltX = Double(r(5) * a) * 16
        tiltY = Double(r(6) * a) * 18
        lift = 6 + (r(7) + 1) * 5
    }
}

/// Смещение, поворот, масштаб и 3D‑наклон одной проекцией — анимируется плавно, без мерцания
struct ReassembleEffect: GeometryEffect {
    var t: CGFloat          // 0 — на месте, 1 — разлетелась
    var lift: CGFloat       // 0…1 — приподнята при потягивании
    let path: ScatterPath

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(t, lift) }
        set { t = newValue.first; lift = newValue.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let w = size.width, h = size.height
        let angle = CGFloat(path.angle * Double(t)) * .pi / 180
        let s = 1 + (path.scale - 1) * t + 0.015 * lift
        let tx = path.dx * t
        let ty = path.dy * t - path.lift * lift

        // 3D-наклон с перспективой вокруг центра карточки
        var p = CATransform3DIdentity
        p.m34 = -1 / 900
        p = CATransform3DTranslate(p, w / 2 + tx, h / 2 + ty, 0)
        p = CATransform3DRotate(p, CGFloat(path.tiltX * Double(t)) * .pi / 180 + 0.08 * lift, 1, 0, 0)
        p = CATransform3DRotate(p, CGFloat(path.tiltY * Double(t)) * .pi / 180, 0, 1, 0)
        p = CATransform3DRotate(p, angle, 0, 0, 1)
        p = CATransform3DScale(p, s, s, 1)
        p = CATransform3DTranslate(p, -w / 2, -h / 2, 0)
        return ProjectionTransform(p)
    }
}

// MARK: - Модификаторы

private struct ReassemblyInsideKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// true внутри карточки, которая уже летает — вложенные карточки не разлетаются отдельно
    var reassemblyInside: Bool {
        get { self[ReassemblyInsideKey.self] }
        set { self[ReassemblyInsideKey.self] = newValue }
    }
}

private struct ReassembleCard: ViewModifier {
    let index: Int?
    let radius: CGFloat
    let amplitude: CGFloat
    let ghost: Bool
    @State private var seed = Int.random(in: 1...9999)
    @Namespace private var ns
    @Environment(Reassembly.self) private var ra: Reassembly?
    @Environment(\.reassemblyInside) private var inside

    @ViewBuilder
    func body(content: Content) -> some View {
        if let ra, !inside {
            flying(content.environment(\.reassemblyInside, true), ra)
        } else {
            content
        }
    }

    private func flying(_ content: some View, _ ra: Reassembly) -> some View {
        let path = ScatterPath(index: index ?? seed, amplitude: amplitude)
        let scattered = ra.phase == .scattered
        let lift = ra.phase == .pulling ? min(1, ra.pull) : 0
        // небольшая задержка у каждой карточки — разлёт и сборка «волной»
        let delay = Double((index ?? seed) % 9) * 0.035
        let shape = RoundedRectangle(cornerRadius: max(radius, 1), style: .continuous)
        return content
            .matchedGeometryEffect(id: "slot", in: ns, properties: .frame, isSource: true)
            .modifier(ReassembleEffect(t: ra.reduceMotion ? 0 : (scattered ? 1 : 0), lift: ra.reduceMotion ? 0 : lift, path: path))
            .animation(.spring(duration: scattered ? 0.7 : 0.75, bounce: scattered ? 0.28 : 0.22).delay(delay), value: scattered)
            .shadow(color: Color(hex: 0x5AC8FA).opacity(scattered ? 0.25 : 0.1 * lift), radius: scattered ? 20 : 10 * lift, y: scattered ? 8 : 5 * lift)
            .opacity(ra.reduceMotion && scattered ? 0.55 : 1)
            .background {
                // стеклянное «гнездо» на исходном месте карточки
                if ghost && !ra.reduceMotion {
                    shape
                        .fill(Color(hex: 0x5AC8FA).opacity(0.05))
                        .overlay(shape.strokeBorder(Color(hex: 0x5AC8FA).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6])))
                        .matchedGeometryEffect(id: "slot", in: ns, properties: .frame, isSource: false)
                        .opacity(scattered ? 1 : 0)
                        .animation(.easeInOut(duration: 0.35), value: scattered)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                FlashRim(trigger: ra.flash, delay: delay, radius: radius)
                    .allowsHitTesting(false)
            }
    }
}

private struct FlashRim: View {
    let trigger: Int
    let delay: Double
    let radius: CGFloat
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: max(radius, 1), style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color(hex: 0x8FE3FF), Color(hex: 0x5AC8FA).opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            .shadow(color: Color(hex: 0x5AC8FA).opacity(0.8), radius: 12)
            .opacity(on ? 1 : 0)
            .onChange(of: trigger) {
                withAnimation(.easeOut(duration: 0.25).delay(delay)) { on = true }
                withAnimation(.easeIn(duration: 0.7).delay(delay + 0.3)) { on = false }
            }
    }
}

/// Мягкая световая вспышка всего экрана и индикатор потягивания
private struct ReassemblyHost: ViewModifier {
    let action: () async -> Void
    @State private var ra = Reassembly()
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(ra)
            .onScrollGeometryChange(for: CGFloat.self) { g in
                -(g.contentOffset.y + g.contentInsets.top)
            } action: { _, v in
                ra.pulled(v)
            }
            .onScrollPhaseChange { old, new in
                if old == .interacting && new != .interacting { ra.released(action) }
            }
            .overlay(alignment: .top) {
                // подсказка сверху: голубое кольцо заполняется, пока тянешь; во время загрузки — крутится
                PullOrb(phase: ra.phase, pull: ra.pull)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
            .overlay {
                RadialGradient(colors: [Color(hex: 0x5AC8FA).opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 520)
                    .ignoresSafeArea()
                    .opacity(glow ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: ra.flash) {
                withAnimation(.easeOut(duration: 0.3)) { glow = true }
                withAnimation(.easeIn(duration: 0.9).delay(0.3)) { glow = false }
            }
            .onAppear { ra.reduceMotion = reduceMotion }
            .onChange(of: reduceMotion) { ra.reduceMotion = reduceMotion }
    }
}

private struct PullOrb: View {
    let phase: Reassembly.Phase
    let pull: CGFloat
    @State private var spin = false

    var body: some View {
        let visible = phase == .pulling || phase == .scattered
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().stroke(Color(hex: 0x5AC8FA).opacity(0.2), lineWidth: 2.5).padding(7)
            Circle().trim(from: 0, to: phase == .scattered ? 0.7 : min(1, pull))
                .stroke(Color(hex: 0x5AC8FA), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(phase == .scattered ? (spin ? 270 : -90) : -90))
                .animation(phase == .scattered ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spin)
                .padding(7)
                .shadow(color: Color(hex: 0x5AC8FA).opacity(0.7), radius: 6)
        }
        .frame(width: 40, height: 40)
        .glassEffect(.regular, in: .circle)
        .scaleEffect(visible ? (phase == .pulling ? 0.6 + 0.4 * min(1, pull) : 1) : 0.4)
        .opacity(visible ? 1 : 0)
        .animation(.spring(duration: 0.35), value: visible)
        .onChange(of: phase) { spin = phase == .scattered }
    }
}

extension View {
    /// Обновление «Interface Reassembly»: вместо стандартного pull‑to‑refresh
    func reassemblyRefreshable(_ action: @escaping () async -> Void) -> some View {
        modifier(ReassemblyHost(action: action))
    }

    /// Карточка, которая участвует в разлёте и сборке (на экранах с обновлением)
    func reassembles(_ index: Int, in ns: Namespace.ID? = nil, radius: CGFloat = 22) -> some View {
        modifier(ReassembleCard(index: index, radius: radius, amplitude: 1, ghost: true))
    }

    /// Любой блок: своя случайная, но постоянная траектория
    func reassembles(radius: CGFloat = 22, amplitude: CGFloat = 1, ghost: Bool = true) -> some View {
        modifier(ReassembleCard(index: nil, radius: radius, amplitude: amplitude, ghost: ghost))
    }

    /// Строка списка или поста: разлёт поменьше, без «гнезда»
    func reassemblesRow() -> some View {
        modifier(ReassembleCard(index: nil, radius: 0, amplitude: 0.45, ghost: false))
    }

    /// Фон карточки Oxion + участие в разлёте
    func oxCardBG(_ r: CGFloat) -> some View {
        background(Color.oxCard, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .reassembles(radius: r)
    }
}
