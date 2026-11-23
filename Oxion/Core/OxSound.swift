import AudioToolbox
import Foundation

/// Свои короткие звуки OXION (файлы Oxion/Sounds/*.wav): мягкие «колокольчики» под каждое действие.
/// Играем как системные звуки: они не прерывают музыку и молчат в беззвучном режиме.
/// Выключаются в Настройки iPhone → Oxion → «Звуки».
enum OxSound {
    enum Kind: String, CaseIterable {
        case tap = "ox_tap"                  // лёгкий щелчок
        case sent = "ox_sent"                // сообщение улетело
        case received = "ox_received"        // пришло сообщение
        case setDone = "ox_set_done"         // подход сделан — «дзинь»
        case restOver = "ox_rest_over"       // отдых закончился — три ноты вверх
        case workoutDone = "ox_workout_done" // тренировка завершена — короткие фанфары
        case success = "ox_success"
        case error = "ox_error"
    }

    private static var ids: [Kind: SystemSoundID] = [:]
    private static let lock = NSLock()

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "sounds") && PowerSaver.allowsNow(.interface) }

    private static func id(_ k: Kind) -> SystemSoundID? {
        lock.lock(); defer { lock.unlock() }
        if let i = ids[k] { return i }
        guard let url = Bundle.main.url(forResource: k.rawValue, withExtension: "wav") else { return nil }
        var sid: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sid) == noErr else { return nil }
        ids[k] = sid
        return sid
    }

    static func play(_ k: Kind) {
        guard enabled else { return }
        // сообщения звучат как в iMessage: системные «вжух» при отправке и «дзынь» при получении
        switch k {
        case .sent: AudioServicesPlaySystemSound(1004); return       // SentMessage.caf
        case .received: AudioServicesPlaySystemSound(1003); return   // ReceivedMessage.caf
        default: break
        }
        guard let sid = id(k) else { return }
        AudioServicesPlaySystemSound(sid)
    }

    /// Подготовить звуки заранее, чтобы первый не опаздывал
    static func preload() {
        DispatchQueue.global(qos: .utility).async { for k in Kind.allCases { _ = id(k) } }
    }
}
