import SwiftUI
import Network
import ImageIO
import Charts

// MARK: - Энергосбережение (как в Telegram)

@MainActor
@Observable
final class PowerSaver {
    static let shared = PowerSaver()

    enum Feature: String, CaseIterable, Identifiable {
        case interface, liveBackgrounds, haptics, preload, background
        var id: String { rawValue }
        var title: String {
            switch self {
            case .interface: "Анимации интерфейса"
            case .liveBackgrounds: "Живые фоны"
            case .haptics: "Вибрация"
            case .preload: "Предзагрузка данных"
            case .background: "Обновление в фоне"
            }
        }
        var sub: String {
            switch self {
            case .interface: "Плавные переходы и эффекты, которые делают OXION живее."
            case .liveBackgrounds: "Жетоны PRO с физикой, эмодзи на визитке, которые плывут при наклоне."
            case .haptics: "Тактильный отклик на нажатия и события тренировки."
            case .preload: "Каталог упражнений и тренеров для поиска iPhone загружается заранее."
            case .background: "Чаты обновляются чаще, приложение обновляет данные в фоне."
            }
        }
        var icon: String {
            switch self {
            case .interface: "sparkles"
            case .liveBackgrounds: "circle.hexagongrid.fill"
            case .haptics: "iphone.radiowaves.left.and.right"
            case .preload: "arrow.down.circle.fill"
            case .background: "clock.arrow.circlepath"
            }
        }
        var color: Color {
            switch self {
            case .interface: Color(hex: 0x3FB8F5)
            case .liveBackgrounds: Color(hex: 0x58C770)
            case .haptics: Color(hex: 0xF0A030)
            case .preload: Color(hex: 0x3478F6)
            case .background: Color(hex: 0x9B59D9)
            }
        }
    }

    /// Порог заряда: 0 — выключено, 100 — всегда, иначе «при заряде менее N%»
    var threshold: Int { didSet { UserDefaults.standard.set(threshold, forKey: "power_threshold") } }
    var battery: Float = 1
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private init() {
        threshold = UserDefaults.standard.object(forKey: "power_threshold") as? Int ?? 15
        UIDevice.current.isBatteryMonitoringEnabled = true
        battery = UIDevice.current.batteryLevel
        PowerSaver.batteryCache = battery
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                PowerSaver.shared.battery = UIDevice.current.batteryLevel
                PowerSaver.batteryCache = UIDevice.current.batteryLevel
            }
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerSaver.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    /// Режим экономии сейчас включён
    var saving: Bool {
        if threshold >= 100 { return true }
        if threshold <= 0 { return false }
        return lowPower || (battery >= 0 && battery * 100 < Float(threshold))
    }

    func isOn(_ f: Feature) -> Bool { UserDefaults.standard.object(forKey: "power_" + f.rawValue) as? Bool ?? true }
    func set(_ f: Feature, _ v: Bool) { UserDefaults.standard.set(v, forKey: "power_" + f.rawValue); tick += 1 }
    private var tick = 0

    /// Можно ли сейчас использовать функцию
    func allows(_ f: Feature) -> Bool {
        _ = tick
        return isOn(f) && !saving
    }

    nonisolated(unsafe) static var batteryCache: Float = 1

    /// Проверка из любого потока (без обращения к объекту)
    nonisolated static func allowsNow(_ f: Feature) -> Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: "power_" + f.rawValue) as? Bool ?? true else { return false }
        let th = d.object(forKey: "power_threshold") as? Int ?? 15
        if th >= 100 { return false }
        if th <= 0 { return true }
        let b = batteryCache
        return !(ProcessInfo.processInfo.isLowPowerModeEnabled || (b >= 0 && b * 100 < Float(th)))
    }
}

struct EnergySettingsView: View {
    @State private var p = PowerSaver.shared
    private let steps: [Int] = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]

    private var label: String {
        p.threshold <= 0 ? "Выключено" : p.threshold >= 100 ? "Всегда включено" : "При заряде менее \(p.threshold)%"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    HStack {
                        Text("Выкл.").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(label).font(.headline).contentTransition(.numericText())
                            BatteryGlyph(level: p.threshold)
                        }
                        Spacer()
                        Text("Вкл.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(steps.firstIndex(of: p.threshold) ?? 3) },
                                          set: { v in
                                              let n = steps[Int(v.rounded())]
                                              if n != p.threshold { Haptic.tap(.soft); withAnimation(.snappy) { p.threshold = n } }
                                          }),
                           in: 0...Double(steps.count - 1), step: 1)
                        .tint(Color.lime)
                }
                .padding(.vertical, 6)
            } header: {
                Text(p.saving ? "Режим энергосбережения (вкл.)" : "Режим энергосбережения (выкл.)")
            } footer: {
                Text(p.threshold <= 0 ? "Экономия не включается автоматически." :
                        p.threshold >= 100 ? "Все ресурсоёмкие процессы отключены." :
                        "Автоматически отключать все ресурсоёмкие процессы при заряде менее \(p.threshold)% или в режиме энергосбережения iPhone.")
            }

            Section("Ресурсоёмкие процессы") {
                ForEach(PowerSaver.Feature.allCases) { f in
                    Toggle(isOn: Binding(get: { p.isOn(f) }, set: { p.set(f, $0) })) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: f.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(f.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).font(.body.weight(.semibold))
                                Text(f.sub).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(Color.lime)
                    .disabled(p.saving)
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Энергосбережение")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BatteryGlyph: View {
    let level: Int
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 1.5).frame(width: 28, height: 14)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(level <= 20 ? Color.red : level >= 100 ? Color.lime : Color.orange)
                    .frame(width: max(3, 24 * CGFloat(min(100, max(level, 4))) / 100), height: 10)
                    .padding(.leading, 2)
            }
            RoundedRectangle(cornerRadius: 1).fill(.secondary).frame(width: 2, height: 5)
        }
        .animation(.snappy, value: level)
    }
}

// MARK: - Сеть и трафик

final class NetKind: @unchecked Sendable {
    static let shared = NetKind()
    private let monitor = NWPathMonitor()
    private(set) var cellular = false
    private init() {
        monitor.pathUpdateHandler = { [weak self] p in self?.cellular = p.usesInterfaceType(.cellular) || p.isExpensive }
        monitor.start(queue: DispatchQueue(label: "oxion.net"))
    }
}

enum Traffic {
    enum Kind: String { case api, media }
    private static let lock = NSLock()

    static func add(_ bytes: Int, _ kind: Kind) {
        guard bytes > 0 else { return }
        let key = "traffic_\(NetKind.shared.cellular ? "cell" : "wifi")_\(kind.rawValue)"
        lock.lock(); defer { lock.unlock() }
        let d = UserDefaults.standard
        d.set(d.integer(forKey: key) + bytes, forKey: key)
        if d.object(forKey: "traffic_since") == nil { d.set(Date().timeIntervalSince1970, forKey: "traffic_since") }
    }

    static func value(cell: Bool, _ kind: Kind) -> Int {
        UserDefaults.standard.integer(forKey: "traffic_\(cell ? "cell" : "wifi")_\(kind.rawValue)")
    }

    static var since: Date? {
        let t = UserDefaults.standard.double(forKey: "traffic_since")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func reset() {
        for n in ["cell", "wifi"] { for k in ["api", "media"] { UserDefaults.standard.removeObject(forKey: "traffic_\(n)_\(k)") } }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "traffic_since")
    }
}

// MARK: - Загрузка фото с кешем, учётом трафика и автозагрузкой

final class MediaLoader: @unchecked Sendable {
    static let shared = MediaLoader()
    let cache = URLCache(memoryCapacity: 40 << 20, diskCapacity: 400 << 20, directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "oxion-media"))
    private let mem = NSCache<NSURL, UIImage>()
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = cache
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()

    init() { mem.totalCostLimit = 120 << 20 }

    enum Auto { static let cellKey = "auto_photos_cell", wifiKey = "auto_photos_wifi" }

    static var autoPhotos: Bool {
        let d = UserDefaults.standard
        return NetKind.shared.cellular ? (d.object(forKey: Auto.cellKey) as? Bool ?? true) : (d.object(forKey: Auto.wifiKey) as? Bool ?? true)
    }

    private func key(_ url: URL, _ maxPixel: CGFloat?) -> NSURL {
        // разные размеры одной картинки (аватар 40 pt и фото на весь экран) кешируем отдельно
        let m = maxPixel.map { "#\(Int($0))" } ?? "#full"
        return (URL(string: url.absoluteString + m) ?? url) as NSURL
    }

    /// только из памяти — мгновенно, без диска и без раскодирования
    func cached(_ url: URL, maxPixel: CGFloat? = 1600) -> UIImage? {
        mem.object(forKey: key(url, maxPixel))
    }

    /// Загрузка: диск/сеть и раскодирование — в фоне, сразу в нужном размере.
    /// Раньше большие фото раскодировались в полном размере прямо во время прокрутки — отсюда рывки.
    func load(_ url: URL, maxPixel: CGFloat? = 1600, cacheOnly: Bool = false) async -> UIImage? {
        let k = key(url, maxPixel)
        if let i = mem.object(forKey: k) { return i }
        let cache = self.cache
        var data = await Task.detached(priority: .userInitiated) { cache.cachedResponse(for: URLRequest(url: url))?.data }.value
        if data == nil {
            if cacheOnly { return nil }
            guard let (d, _) = try? await session.data(from: url) else { return nil }
            Traffic.add(d.count, .media)
            data = d
        }
        guard let data else { return nil }
        let img = await Task.detached(priority: .userInitiated) { MediaLoader.decode(data, maxPixel: maxPixel) }.value
        guard let img else { return nil }
        let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
        mem.setObject(img, forKey: k, cost: cost)
        return img
    }

    /// Раскодировать сразу (не при первой отрисовке) и уменьшить до нужного размера
    nonisolated static func decode(_ data: Data, maxPixel: CGFloat?) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        if let maxPixel {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceShouldCacheImmediately: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: maxPixel]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { return UIImage(cgImage: cg) }
        }
        return UIImage(data: data)?.preparingForDisplay()
    }

    func clear() {
        cache.removeAllCachedResponses()
        mem.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
    }
}

/// Картинка из сети: кеш, учёт трафика; для фото — уважает «Автозагрузку медиа»
struct OxRemoteImage<Placeholder: View>: View {
    let url: URL?
    var gated = false
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var img: UIImage?
    @State private var waiting = false
    @State private var sensitive = false
    @State private var revealed = false

    var body: some View {
        // из памяти — сразу, без мигания заглушки (фото — только если уже проверено на откровенность)
        let shown = img ?? url.flatMap { u in
            (!gated || SensitiveGuard.shared.cached(u) == false) ? MediaLoader.shared.cached(u, maxPixel: maxPixel) : nil
        }
        // Color.clear занимает ровно отведённое место, фото заполняет его и обрезается по краям —
        // иначе «заполняющая» картинка раздвигает карточку и всю страницу вбок
        Color.clear.overlay {
        ZStack {
            if let img = shown {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: sensitive && !revealed ? 40 : 0, opaque: true)
                    .transition(.opacity)
                if sensitive && !revealed {
                    GeometryReader { g in
                        SensitiveCover(compact: g.size.width < 180 || g.size.height < 160) { revealed = true }
                    }
                    .transition(.opacity)
                }
            } else {
                placeholder()
                if waiting {
                    Button {
                        waiting = false
                        Task { await fetch(force: true) }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        }
        .clipped()
        .task(id: url) { await fetch(force: false) }
    }

    /// фото в ленте и чатах — до 1600 точек, аватары и иконки — до 480
    private var maxPixel: CGFloat { gated ? 1600 : 480 }

    private func fetch(force: Bool) async {
        guard let url else { return }
        if let c = MediaLoader.shared.cached(url, maxPixel: maxPixel) {
            if gated { sensitive = await SensitiveGuard.shared.check(c, url: url) }
            if img !== c { img = c }
            return
        }
        if gated && !force && !MediaLoader.autoPhotos {
            // уже скачанное раньше показываем и без автозагрузки
            if let i = await MediaLoader.shared.load(url, maxPixel: maxPixel, cacheOnly: true) {
                if gated { sensitive = await SensitiveGuard.shared.check(i, url: url) }
                img = i
            } else {
                waiting = true
            }
            return
        }
        if let i = await MediaLoader.shared.load(url, maxPixel: maxPixel) {
            // откровенные фото размываем ещё до показа
            if gated { sensitive = await SensitiveGuard.shared.check(i, url: url) }
            withAnimation(.easeOut(duration: 0.25)) { img = i }
        }
    }
}

// MARK: - Данные и память

struct DataStorageView: View {
    @AppStorage(MediaLoader.Auto.cellKey) private var autoCell = true
    @AppStorage(MediaLoader.Auto.wifiKey) private var autoWifi = true
    @AppStorage("save_photos_personal") private var savePersonal = false
    @AppStorage("save_photos_trainer") private var saveTrainer = false
    @State private var usage: [(String, Int64, Color)] = []
    @State private var clearing = false
    @State private var trafficTick = 0

    private var total: Int64 { usage.reduce(0) { $0 + $1.1 } }

    var body: some View {
        List {
            Section {
                OxSettingsHeader(icon: "internaldrive.fill", tint: Color(hex: 0x3478F6), title: "Данные и память",
                                 text: "Сколько места занимает Oxion, сколько трафика тратит и когда загружать фото.")
                    .oxHeaderRow()
            }
            Section {
                NavigationLink {
                    storage
                } label: {
                    settingRow("chart.pie.fill", Color(hex: 0xF0A030), "Использование памяти", value: bytes(total))
                }
                NavigationLink {
                    traffic
                } label: {
                    settingRow("chart.bar.fill", Color(hex: 0x9B59D9), "Использование трафика",
                               value: bytes(Int64(Traffic.value(cell: true, .api) + Traffic.value(cell: true, .media) + Traffic.value(cell: false, .api) + Traffic.value(cell: false, .media))))
                }
            }
            Section {
                Toggle(isOn: $autoCell) { settingRow("antenna.radiowaves.left.and.right", Color(hex: 0x58C770), "Через мобильную сеть", sub: autoCell ? "Фото загружаются сразу" : "Фото — по нажатию") }
                Toggle(isOn: $autoWifi) { settingRow("wifi", Color(hex: 0x3478F6), "Через Wi-Fi", sub: autoWifi ? "Фото загружаются сразу" : "Фото — по нажатию") }
                Button {
                    withAnimation { autoCell = true; autoWifi = true }
                } label: {
                    Label("Сбросить настройки", systemImage: "arrow.counterclockwise")
                }
                .disabled(autoCell && autoWifi)
            } header: {
                Text("Автозагрузка медиа")
            } footer: {
                Text("Если выключить, фото в ленте и чатах загрузятся только после нажатия. Аватарки загружаются всегда.")
            }
            .tint(Color.lime)
            Section {
                Toggle(isOn: $savePersonal) { settingRow("person.fill", Color(hex: 0x3478F6), "Личные чаты") }
                Toggle(isOn: $saveTrainer) { settingRow("person.badge.shield.checkmark.fill", Color(hex: 0x58C770), "Чаты с тренером") }
            } header: {
                Text("Сохранение в галерею")
            } footer: {
                Text("Автоматическое сохранение новых входящих фотографий из этих чатов в приложение «Фото».")
            }
            .tint(Color.lime)
        }
        .navigationTitle("Данные и память")
        .navigationBarTitleDisplayMode(.inline)
        .task { usage = await Self.measure() }
    }

    // память

    private var storage: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ZStack {
                        Chart(usage, id: \.0) { u in
                            SectorMark(angle: .value("Размер", max(u.1, 1)), innerRadius: .ratio(0.62), angularInset: 2)
                                .cornerRadius(6)
                                .foregroundStyle(u.2)
                        }
                        .frame(height: 190)
                        VStack(spacing: 2) {
                            Text(bytes(total)).font(.title2.bold()).contentTransition(.numericText())
                            Text("занято").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .animation(.spring(duration: 0.6), value: total)
                    Text("OXION занимает \(bytes(total)) на iPhone. Всё это можно удалить: данные снова загрузятся с сервера.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            }
            Section {
                ForEach(usage, id: \.0) { u in
                    HStack {
                        Circle().fill(u.2).frame(width: 12, height: 12)
                        Text(u.0)
                        Spacer()
                        Text(bytes(u.1)).foregroundStyle(.secondary).contentTransition(.numericText())
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    HStack {
                        Spacer()
                        if clearing { ProgressView() } else { Text("Очистить кеш · \(bytes(total))").bold() }
                        Spacer()
                    }
                }
                .disabled(total == 0 || clearing)
            }
        }
        .navigationTitle("Использование памяти")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func clear() async {
        clearing = true
        MediaLoader.shared.clear()
        let fm = FileManager.default
        for dir in [fm.urls(for: .cachesDirectory, in: .userDomainMask)[0], fm.temporaryDirectory] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent != "oxion-media" {
                try? fm.removeItem(at: f)
            }
        }
        UserDefaults.standard.removeObject(forKey: "catalog_at")
        let u = await Self.measure()
        withAnimation(.spring(duration: 0.6)) { usage = u }
        clearing = false
        Haptic.success()
        OxAlert.show(icon: "checkmark.circle.fill", title: "Кеш очищен")
    }

    nonisolated static func measure() async -> [(String, Int64, Color)] {
        let fm = FileManager.default
        func size(_ url: URL, skip: String? = nil) -> Int64 {
            var t: Int64 = 0
            if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
                for case let f as URL in e {
                    if let skip, f.path.contains("/\(skip)") { continue }
                    t += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                }
            }
            return t
        }
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let media = Int64(MediaLoader.shared.cache.currentDiskUsage) + Int64(URLCache.shared.currentDiskUsage)
        let other = size(caches, skip: "oxion-media")
        let tmp = size(fm.temporaryDirectory)
        return [("Фото и медиа", media, Color(hex: 0x3478F6)),
                ("Данные приложения", other, Color(hex: 0x58C770)),
                ("Временные файлы", tmp, Color(hex: 0xF0A030))]
    }

    // трафик

    private var traffic: some View {
        List {
            ForEach([true, false], id: \.self) { cell in
                Section(cell ? "Мобильная сеть" : "Wi-Fi") {
                    LabeledContent("Фото и медиа", value: bytes(Int64(Traffic.value(cell: cell, .media))))
                    LabeledContent("Сообщения и данные", value: bytes(Int64(Traffic.value(cell: cell, .api))))
                }
            }
            Section {
                Button("Сбросить статистику", role: .destructive) {
                    Traffic.reset()
                    trafficTick += 1
                    Haptic.success()
                }
            } footer: {
                if let s = Traffic.since { Text("Считается с \(s.formatted(date: .long, time: .shortened)).") }
            }
        }
        .id(trafficTick)
        .navigationTitle("Использование трафика")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingRow(_ icon: String, _ color: Color, _ title: String, sub: String? = nil, value: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let sub { Text(sub).font(.footnote).foregroundStyle(.secondary) }
            }
            if let value {
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }

    private func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}

/// Сохранение входящих фото из чатов в «Фото», если включено
enum ChatAutoSave {
    static func handle(_ messages: [Message], trainerChat: Bool) {
        let on = UserDefaults.standard.bool(forKey: trainerChat ? "save_photos_trainer" : "save_photos_personal")
        guard on else { return }
        for m in messages where !m.mine {
            guard let p = m.photo, let url = API.media(p) else { continue }
            Task {
                if let img = await MediaLoader.shared.load(url, maxPixel: nil) { PhotoSaver.save(img) { _ in } }
            }
        }
    }
}
