import SwiftUI
import LocalAuthentication
import Observation

// MARK: - OXION Progress: приватное хранилище фото и замеров на iPhone

struct ProgressPhoto: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var pose: String          // front / side / back
    var file: String
    var note: String?

    static let poses: [(key: String, title: String)] = [("front", "Спереди"), ("side", "Сбоку"), ("back", "Сзади")]
    var poseTitle: String { Self.poses.first { $0.key == pose }?.title ?? pose }
}

struct BodyMeasurement: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var values: [String: Double]   // ключ MeasureKey → см
}

enum MeasureKey: String, CaseIterable, Identifiable {
    case waist, chest, hips, arm, thigh, calf, neck
    var id: String { rawValue }
    var title: String {
        switch self {
        case .waist: return "Талия"
        case .chest: return "Грудь"
        case .hips: return "Бёдра"
        case .arm: return "Бицепс"
        case .thigh: return "Бедро"
        case .calf: return "Икра"
        case .neck: return "Шея"
        }
    }
}

@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private(set) var photos: [ProgressPhoto] = []
    private(set) var measurements: [BodyMeasurement] = []
    var unlocked = false

    var backupAllowed: Bool {
        didSet { UserDefaults.standard.set(backupAllowed, forKey: "progress_backup"); applyBackupFlag() }
    }
    var faceLock: Bool {
        didSet { UserDefaults.standard.set(faceLock, forKey: "progress_lock") }
    }

    private let fm = FileManager.default
    private let cache = NSCache<NSString, UIImage>()

    let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("OxionProgress", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return d
    }()

    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    private struct Index: Codable { var photos: [ProgressPhoto]; var measurements: [BodyMeasurement] }

    private init() {
        backupAllowed = UserDefaults.standard.bool(forKey: "progress_backup")
        faceLock = UserDefaults.standard.bool(forKey: "progress_lock")
        load()
        applyBackupFlag()
    }

    private func load() {
        guard let d = try? Data(contentsOf: indexURL),
              let i = try? JSONDecoder().decode(Index.self, from: d) else { return }
        photos = i.photos.sorted { $0.date < $1.date }
        measurements = i.measurements.sorted { $0.date < $1.date }
    }

    private func save() {
        let i = Index(photos: photos, measurements: measurements)
        if let d = try? JSONEncoder().encode(i) {
            try? d.write(to: indexURL, options: [.atomic, .completeFileProtection])
        }
    }

    /// По умолчанию фото НЕ попадают в резервную копию iCloud — только по согласию
    private func applyBackupFlag() {
        var u = dir
        var v = URLResourceValues()
        v.isExcludedFromBackup = !backupAllowed
        try? u.setResourceValues(v)
    }

    // MARK: Фото

    func addPhoto(_ image: UIImage, date: Date, pose: String, note: String? = nil) {
        guard let data = API.jpeg(image, maxSide: 1800) else { return }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            photos.append(ProgressPhoto(date: date, pose: pose, file: name, note: note))
            photos.sort { $0.date < $1.date }
            save()
        } catch {
            OxAlert.error("Не удалось сохранить фото: \(error.localizedDescription)")
        }
    }

    func delete(_ p: ProgressPhoto) {
        try? fm.removeItem(at: dir.appendingPathComponent(p.file))
        cache.removeObject(forKey: p.file as NSString)
        photos.removeAll { $0.id == p.id }
        save()
    }

    func deleteAllPhotos() {
        for p in photos { try? fm.removeItem(at: dir.appendingPathComponent(p.file)) }
        cache.removeAllObjects()
        photos = []
        save()
    }

    func image(_ p: ProgressPhoto) -> UIImage? {
        if let i = cache.object(forKey: p.file as NSString) { return i }
        guard let i = UIImage(contentsOfFile: dir.appendingPathComponent(p.file).path) else { return nil }
        cache.setObject(i, forKey: p.file as NSString)
        return i
    }

    func photos(from: Date, to: Date) -> [ProgressPhoto] {
        photos.filter { $0.date >= from && $0.date <= to }
    }

    // MARK: Замеры

    func addMeasurement(_ m: BodyMeasurement) {
        measurements.append(m)
        measurements.sort { $0.date < $1.date }
        save()
    }

    func delete(_ m: BodyMeasurement) {
        measurements.removeAll { $0.id == m.id }
        save()
    }

    /// Последнее значение и изменение к предыдущему замеру
    func latest(_ k: MeasureKey) -> (value: Double, delta: Double?)? {
        let list = measurements.compactMap { m in m.values[k.rawValue].map { (m.date, $0) } }
        guard let last = list.last else { return nil }
        let prev = list.dropLast().last
        return (last.1, prev.map { last.1 - $0.1 })
    }

    func series(_ k: MeasureKey) -> [(date: Date, value: Double)] {
        measurements.compactMap { m in m.values[k.rawValue].map { (m.date, $0) } }
    }

    // MARK: Face ID

    func unlock() async -> Bool {
        if !faceLock { unlocked = true; return true }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { unlocked = true; return true }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Открыть фото прогресса")
            unlocked = ok
            return ok
        } catch {
            return false
        }
    }
}
