import Foundation

/// Состояние умных устройств — для виджета на экране блокировки и Пункта управления
struct DeviceSnapshot: Codable, Hashable {
    struct Dev: Codable, Hashable { var name: String; var battery: Int?; var heart: Bool }
    var devices: [Dev] = []
    var heartRate: Int?
    var heartAt: Date?
    var updated = Date()

    static let key = "device_snapshot_v1"
    static let widgetKind = "ru.oxion.app.devices"
    static let heartControlKind = "ru.oxion.app.control.heart"

    static func load() -> DeviceSnapshot {
        guard let d = WidgetShared.defaults?.data(forKey: key),
              let s = try? JSONDecoder().decode(DeviceSnapshot.self, from: d) else { return DeviceSnapshot() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { WidgetShared.defaults?.set(d, forKey: Self.key) }
    }

    /// пульс считается «живым» 2 минуты
    var freshHeart: Int? {
        guard let h = heartRate, let at = heartAt, Date().timeIntervalSince(at) < 120 else { return nil }
        return h
    }
}
