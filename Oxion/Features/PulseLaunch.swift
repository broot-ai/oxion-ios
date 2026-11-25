import SwiftUI
import UIKit
import CoreHaptics
import QuartzCore

// MARK: - OXION Pulse Loading — анимация запуска
// Огонёк (Metal-шейдер oxFire) в капле жидкого стекла, вокруг вращаются стеклянные кольца,
// внутри копится энергия (искры — CAEmitterLayer, тактильный нарастающий гул — Core Haptics).
// Когда данные реально загрузились — вспышка, световая волна, огонёк превращается в логотип OXION,
// логотип растворяется и открывает интерфейс.
// • Играет один раз за запуск процесса, перерисовки состояния его не перезапускают.
// • Ничего не ждёт искусственно: финал стартует сразу, как только AppModel вышел из .loading.
// • Долгая загрузка → спокойное «дыхание» без вибрации.
// • Reduce Motion — без вращения, масштабов и частиц, простое затухание.
// • Вибрацию выключает общий переключатель «Вибрация» и режим энергосбережения.

@MainActor
@Observable
final class PulseLaunch {
    static let shared = PulseLaunch()
    /// показывать ли слой (один раз за запуск)
    var visible = true
    private(set) var started = false
    func markStarted() -> Bool {
        if started { return false }
        started = true
        return true
    }
}

struct PulseLaunchView: View {
    /// данные загружены (AppModel вышел из .loading)
    let ready: Bool
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Stage { case hidden, appearing, charging, calm, flash, logo, out }
    @State private var stage: Stage = .hidden
    @State private var energy: CGFloat = 0          // 0…1 — накопленная энергия
    @State private var appear: CGFloat = 0          // 0…1 — появление огонька
    @State private var spin = false
    @State private var flash: CGFloat = 0
    @State private var wave: CGFloat = 0
    @State private var breathe = false
    @State private var haptics = PulseHaptics()
    @State private var finaleStarted = false
    @State private var appearedAt = Date()

    private let cyan = Color(red: 0.25, green: 0.86, blue: 1.0)
    private let blue = Color(red: 0.16, green: 0.45, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // фоновое сияние, растёт с энергией
            RadialGradient(colors: [cyan.opacity(0.10 + 0.25 * energy), blue.opacity(0.06), .clear],
                           center: .center, startRadius: 4, endRadius: 260 + 140 * energy)
                .ignoresSafeArea()
                .opacity(stage == .out ? 0 : 1)

            if !reduceMotion && stage != .out && stage != .logo {
                SparkEmitter(rate: Float(stage == .calm ? 4 : 6 + 40 * energy), color: UIColor(cyan))
                    .frame(width: 260, height: 260)
                    .allowsHitTesting(false)
                    .opacity(appear)
            }

            rings
                .opacity(stage == .logo || stage == .out ? 0 : appear)

            flame
            logo

            // световая волна
            Circle()
                .stroke(LinearGradient(colors: [.white, cyan, blue], startPoint: .top, endPoint: .bottom), lineWidth: 6 * (1 - wave) + 1)
                .frame(width: 160, height: 160)
                .scaleEffect(0.6 + wave * 5)
                .opacity(wave > 0 && wave < 1 ? Double(1 - wave) : 0)
                .blur(radius: 2 + 6 * wave)
                .blendMode(.plusLighter)

            // вспышка
            RadialGradient(colors: [.white, cyan.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .opacity(Double(flash))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .opacity(stage == .out ? 0 : 1)
        // интерфейс под слоем уже работает; во время финала касания проходят насквозь
        .allowsHitTesting(stage != .flash && stage != .logo && stage != .out)
        .accessibilityElement()
        .accessibilityLabel(Text("Загрузка OXION"))
        .onAppear(perform: begin)
        .onChange(of: ready) { if ready { finaleIfPossible() } }
    }

    // MARK: огонёк в капле жидкого стекла

    private var flame: some View {
        let s = 1 + 0.12 * energy + (breathe ? 0.03 : 0)
        return ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 150, height: 150)
                .glassEffect(.clear.tint(cyan.opacity(0.10 + 0.15 * energy)), in: Circle())
                .overlay(
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), cyan.opacity(0.15), .clear],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                )
                .shadow(color: cyan.opacity(0.25 + 0.5 * energy), radius: 18 + 30 * energy)
            // Metal-шейдер огня, перекрашенный из фирменного лайма в циан
            AnimatedFire(size: 170)
                .frame(width: 120, height: 120)
                .hueRotation(.degrees(75))
                .saturation(1.15)
                .brightness(0.05 + 0.25 * energy)
                .mask(Circle().frame(width: 140, height: 140))
        }
        .scaleEffect(reduceMotion ? 1 : (0.55 + 0.45 * appear) * s * (stage == .logo || stage == .out ? 0.4 : 1))
        .blur(radius: reduceMotion ? 0 : (1 - appear) * 18 + (stage == .logo ? 12 : 0))
        .opacity(stage == .logo || stage == .out ? 0 : appear)
    }

    // MARK: стеклянные кольца

    private var rings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let d = CGFloat(200 + i * 46)
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [.white.opacity(0.5), cyan.opacity(0.35), .clear, blue.opacity(0.3), .white.opacity(0.5)],
                                        center: .center),
                        lineWidth: 1.5 + CGFloat(i) * 0.5)
                    .frame(width: d, height: d)
                    .rotation3DEffect(.degrees(Double(62 + i * 7)), axis: (x: 1, y: CGFloat(i) * 0.35 - 0.3, z: 0))
                    .rotationEffect(.degrees(spin && !reduceMotion ? (i.isMultiple(of: 2) ? 360 : -360) : 0))
                    .animation(reduceMotion ? nil : .linear(duration: Double(stage == .calm ? 14 + i * 4 : 6 + i * 2) / (1 + Double(energy)))
                        .repeatForever(autoreverses: false), value: spin)
                    .shadow(color: cyan.opacity(0.3 * Double(energy)), radius: 8)
            }
        }
        .scaleEffect(reduceMotion ? 1 : 0.8 + 0.2 * appear)
    }

    // MARK: логотип

    private var logo: some View {
        let on = stage == .logo
        return VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, cyan, blue], startPoint: .top, endPoint: .bottom))
                .shadow(color: cyan.opacity(0.8), radius: 16)
            Text(verbatim: "OXION")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(on ? 10 : 2)
                .foregroundStyle(LinearGradient(colors: [.white, cyan], startPoint: .leading, endPoint: .trailing))
        }
        .scaleEffect(reduceMotion ? 1 : (on ? 1 : 1.25))
        .blur(radius: reduceMotion ? 0 : (on ? 0 : 10))
        .opacity(on ? 1 : 0)
    }

    // MARK: сценарий

    private func begin() {
        guard PulseLaunch.shared.markStarted() else { return }   // повторное появление — не перезапускаем
        appearedAt = Date()
        haptics.start()
        stage = .appearing
        haptics.soft()
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.8, bounce: 0.25)) { appear = 1 }
        spin = true
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 380))
            guard !finaleStarted else { return }
            stage = .charging
            haptics.charge(duration: 2.4)
            withAnimation(.easeOut(duration: 2.4)) { energy = 0.85 }
            if ready { finaleIfPossible(); return }
            // загрузка затянулась — спокойное циклическое состояние
            try? await Task.sleep(for: .seconds(2.6))
            guard !finaleStarted else { return }
            haptics.stopCharge()
            stage = .calm
            withAnimation(.easeInOut(duration: 1.2)) { energy = 0.55 }
            withAnimation(.easeInOut(duration: 1.6).repeatForever()) { breathe = true }
        }
        if ready { finaleIfPossible() }
    }

    private func finaleIfPossible() {
        guard ready, !finaleStarted, stage != .hidden else { return }
        finaleStarted = true
        Task {
            // огонёк должен хотя бы появиться (не больше ~0,45 с с момента старта), иначе вспышка будет «из ниоткуда»
            let since = Date().timeIntervalSince(appearedAt)
            if since < 0.45 { try? await Task.sleep(for: .seconds(0.45 - since)) }
            haptics.stopCharge()
            if reduceMotion {
                stage = .logo
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.3)) { stage = .out }
                haptics.finish()
                try? await Task.sleep(for: .milliseconds(320))
                onFinish()
                return
            }
            // добираем энергию до предела
            withAnimation(.easeIn(duration: 0.22)) { energy = 1 }
            try? await Task.sleep(for: .milliseconds(220))
            // вспышка и волна
            stage = .flash
            haptics.flash()
            withAnimation(.easeOut(duration: 0.12)) { flash = 1 }
            withAnimation(.easeOut(duration: 0.9)) { wave = 1 }
            try? await Task.sleep(for: .milliseconds(120))
            // огонёк превращается в логотип
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { stage = .logo }
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            try? await Task.sleep(for: .milliseconds(620))
            // логотип растворяется, открывая интерфейс
            haptics.finish()
            withAnimation(.easeInOut(duration: 0.45)) { stage = .out }
            try? await Task.sleep(for: .milliseconds(470))
            haptics.stop()
            onFinish()
        }
    }
}

// MARK: - Core Haptics

@MainActor
final class PulseHaptics {
    private var engine: CHHapticEngine?
    private var charging: CHHapticAdvancedPatternPlayer?

    private var allowed: Bool {
        AppSettings.haptics
            && (UserDefaults.standard.object(forKey: "launch.haptics") as? Bool ?? true)
            && PowerSaver.allowsNow(.haptics)
            && CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func start() {
        guard allowed, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.playsHapticsOnly = true
        try? engine?.start()
    }

    private func play(_ events: [CHHapticEvent], curves: [CHHapticParameterCurve] = []) {
        guard allowed, let engine else { return }
        if let p = try? CHHapticPattern(events: events, parameterCurves: curves),
           let pl = try? engine.makePlayer(with: p) {
            try? pl.start(atTime: CHHapticTimeImmediate)
        }
    }

    private func transient(_ i: Float, _ s: Float, at t: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: s)
        ], relativeTime: t)
    }

    /// лёгкий мягкий отклик при появлении
    func soft() { play([transient(0.35, 0.1)]) }

    /// нарастающий гул: энергия копится
    func charge(duration: TimeInterval) {
        guard allowed, let engine else { return }
        let ev = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
        ], relativeTime: 0, duration: duration)
        let intensity = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.05),
            .init(relativeTime: duration * 0.5, value: 0.25),
            .init(relativeTime: duration, value: 0.55)
        ], relativeTime: 0)
        let sharp = CHHapticParameterCurve(parameterID: .hapticSharpnessControl, controlPoints: [
            .init(relativeTime: 0, value: -0.2),
            .init(relativeTime: duration, value: 0.25)
        ], relativeTime: 0)
        if let p = try? CHHapticPattern(events: [ev], parameterCurves: [intensity, sharp]),
           let pl = try? engine.makeAdvancedPlayer(with: p) {
            charging = pl
            try? pl.start(atTime: CHHapticTimeImmediate)
        }
    }

    func stopCharge() {
        try? charging?.stop(atTime: CHHapticTimeImmediate)
        charging = nil
    }

    /// выразительный короткий импульс во вспышке
    func flash() {
        play([transient(1, 0.9), transient(0.6, 0.5, at: 0.07)])
    }

    /// мягкий финальный отклик
    func finish() { play([transient(0.3, 0.05)]) }

    func stop() {
        stopCharge()
        engine?.stop()
        engine = nil
    }
}

// MARK: - Искры энергии (Core Animation, CAEmitterLayer)

struct SparkEmitter: UIViewRepresentable {
    var rate: Float
    var color: UIColor

    func makeUIView(context: Context) -> EmitterView { EmitterView(color: color) }
    func updateUIView(_ v: EmitterView, context: Context) { v.emitter.birthRate = rate / 10 }

    final class EmitterView: UIView {
        let emitter = CAEmitterLayer()

        init(color: UIColor) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            emitter.emitterShape = .circle
            emitter.emitterMode = .outline
            emitter.renderMode = .additive
            let cell = CAEmitterCell()
            cell.contents = Self.dot.cgImage
            cell.birthRate = 10
            cell.lifetime = 1.6
            cell.lifetimeRange = 0.6
            cell.velocity = -38            // к центру — энергия втягивается в огонёк
            cell.velocityRange = 14
            cell.scale = 0.22
            cell.scaleRange = 0.12
            cell.scaleSpeed = -0.1
            cell.alphaSpeed = -0.55
            cell.color = color.withAlphaComponent(0.9).cgColor
            emitter.emitterCells = [cell]
            emitter.birthRate = 0.4
            layer.addSublayer(emitter)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitter.emitterSize = CGSize(width: bounds.width * 0.9, height: bounds.height * 0.9)
        }

        static let dot: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 12, y: 12), startRadius: 0,
                                                 endCenter: CGPoint(x: 12, y: 12), endRadius: 12, options: [])
            }
        }
    }
}
