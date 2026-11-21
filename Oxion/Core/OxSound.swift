import AudioToolbox
import Foundation

/// Системные звуки iOS для событий OXION.
/// Звучат только если включён переключатель «Звуки» (Настройки → Oxion) и iPhone не в беззвучном режиме —
/// системные звуки сами подчиняются переключателю «Звонок / Бесшумно».
enum OxSound {
    enum Kind {
        case tap, sent, received, setDone, restOver, workoutDone, success, error
        var id: SystemSoundID {
            switch self {
            case .tap: 1104          // Tock — короткий щелчок
            case .sent: 1004         // отправка сообщения
            case .received: 1003     // входящее сообщение
            case .setDone: 1057      // Tink — подход сделан
            case .restOver: 1021     // Bloom — отдых закончился
            case .workoutDone: 1025  // Fanfare — тренировка завершена
            case .success: 1394      // короткий «успех»
            case .error: 1073        // ошибка
            }
        }
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "sounds") && PowerSaver.allowsNow(.interface) }

    static func play(_ k: Kind) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(k.id)
    }
}
