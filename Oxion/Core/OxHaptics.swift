import Foundation
import CoreHaptics
import UIKit

/// Свои тактильные сигналы OXION на Core Haptics.
/// Сила настраивается в «Настройки» → Oxion → «Сила вибрации» (выкл / мягко / обычно / сильно).
@MainActor
enum OxHaptics {
    enum Kind { case select, setDone, restOver, workoutDone, record }

    private static var engine: CHHapticEngine?

    /// 0 — выключено
    static var level: Float {
        guard AppSettings.haptics, PowerSaver.allowsNow(.haptics) else { return 0 }
        switch UserDefaults.standard.string(forKey: "haptic_level") ?? "normal" {
        case "off": return 0
        case "soft": return 0.55
        case "strong": return 1.0
        default: return 0.8
        }
    }

    static func play(_ kind: Kind) {
        let k = level
        guard k > 0 else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: CGFloat(k))
            return
        }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
                engine?.resetHandler = { Task { @MainActor in try? OxHaptics.engine?.start() } }
            }
            try engine?.start()
            let pattern = try CHHapticPattern(events: events(kind, k), parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: CGFloat(k))
        }
    }

    private static func tap(_ t: TimeInterval, _ i: Float, _ s: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: s)],
                      relativeTime: t)
    }

    private static func buzz(_ t: TimeInterval, _ d: TimeInterval, _ i: Float, _ s: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: s)],
                      relativeTime: t, duration: d)
    }

    private static func events(_ kind: Kind, _ k: Float) -> [CHHapticEvent] {
        switch kind {
        case .select:
            return [tap(0, 0.45 * k, 0.8)]
        case .setDone:
            // короткий двойной «чик»
            return [tap(0, 0.9 * k, 0.6), tap(0.09, 0.6 * k, 0.9)]
        case .restOver:
            // три нарастающих удара — «пора!»
            return [tap(0, 0.5 * k, 0.4), tap(0.18, 0.75 * k, 0.5), tap(0.36, 1.0 * k, 0.7)]
        case .workoutDone:
            // выраженный: гул + серия
            return [buzz(0, 0.35, 0.7 * k, 0.3), tap(0.4, 1.0 * k, 0.8), tap(0.55, 0.8 * k, 0.8), tap(0.7, 1.0 * k, 1.0)]
        case .record:
            // «фанфары»: быстрая лесенка
            return (0..<5).map { tap(Double($0) * 0.07, Float(0.5 + Double($0) * 0.1) * k, 0.9) } + [buzz(0.4, 0.25, 0.9 * k, 0.6)]
        }
    }
}
