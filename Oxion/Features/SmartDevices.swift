import SwiftUI
import CoreBluetooth
import AVKit
import MediaPlayer
import CoreMotion
import WidgetKit

// MARK: - Умные устройства по Bluetooth
// Работает по стандартным профилям Bluetooth LE:
// • пульс (Heart Rate, 0x180D) — нагрудные датчики и часы с «трансляцией пульса» (Amazfit, Xiaomi, Huawei, Garmin, Polar…);
// • заряд (Battery, 0x180F).
// Колонки (в т. ч. с Алисой) подключаются как обычные Bluetooth-колонки и выбираются в плитке «Звук».

@MainActor
@Observable
final class BLEHub: NSObject {
    static let shared = BLEHub()

    struct Found: Identifiable, Hashable {
        let id: UUID
        var name: String
        var rssi: Int
        var hr: Bool
    }

    var state: CBManagerState = .unknown
    var scanning = false
    var found: [Found] = []
    var connected: [UUID: String] = [:]
    var heartRate = 0
    var heartAt: Date?
    var battery: [UUID: Int] = [:]
    var hrDevice: UUID?
    /// последние значения пульса — для графика
    var hrHistory: [Int] = []
    private var lastPublish = Date.distantPast
    private var lastWidgetReload = Date.distantPast

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private let savedKey = "ble_saved"

    private static let hrService = CBUUID(string: "180D")
    private static let hrMeasure = CBUUID(string: "2A37")
    private static let batService = CBUUID(string: "180F")
    private static let batLevel = CBUUID(string: "2A19")

    var saved: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: savedKey) ?? []).compactMap(UUID.init) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: savedKey) }
    }

    /// Включить Bluetooth (спросит разрешение) и переподключить сохранённые устройства
    func start() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
    }

    func scan() {
        start()
        guard let c = central, c.state == .poweredOn else { return }
        found.removeAll { !connected.keys.contains($0.id) }
        scanning = true
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task {
            try? await Task.sleep(for: .seconds(15))
            stopScan()
        }
    }

    func stopScan() {
        central?.stopScan()
        scanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        central?.connect(p)
        if !saved.contains(id) { saved.append(id) }
    }

    func disconnect(_ id: UUID) {
        if let p = peripherals[id] { central?.cancelPeripheralConnection(p) }
        saved.removeAll { $0 == id }
        connected[id] = nil
    }

    /// Сохранить состояние для виджета на экране блокировки и Пункта управления
    func publish(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastPublish) > 3 else { return }
        lastPublish = Date()
        var snap = DeviceSnapshot()
        snap.devices = connected.map { .init(name: $0.value, battery: battery[$0.key], heart: $0.key == hrDevice) }.sorted { $0.name < $1.name }
        snap.heartRate = hrFresh ? heartRate : nil
        snap.heartAt = heartAt
        snap.save()
        ControlCenter.shared.reloadControls(ofKind: DeviceSnapshot.heartControlKind)
        if force || Date().timeIntervalSince(lastWidgetReload) > 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: DeviceSnapshot.widgetKind)
        }
    }

    var hrFresh: Bool { (heartAt.map { Date().timeIntervalSince($0) < 8 } ?? false) && heartRate > 0 }

    fileprivate func reconnectSaved() {
        guard let c = central else { return }
        for p in c.retrievePeripherals(withIdentifiers: saved) {
            peripherals[p.identifier] = p
            p.delegate = self
            c.connect(p)
        }
    }
}

extension BLEHub: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let st = central.state
        MainActor.assumeIsolated {
            state = st
            if st == .poweredOn { reconnectSaved() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let hr = services.contains(CBUUID(string: "180D"))
        let id = peripheral.identifier, r = RSSI.intValue
        MainActor.assumeIsolated {
            peripherals[id] = peripheral
            peripheral.delegate = self
            if let i = found.firstIndex(where: { $0.id == id }) {
                found[i].rssi = r
            } else {
                found.append(Found(id: id, name: name, rssi: r, hr: hr))
            }
            found.sort { ($0.hr ? 1 : 0, $0.rssi) > ($1.hr ? 1 : 0, $1.rssi) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier, name = peripheral.name ?? "Устройство"
        MainActor.assumeIsolated {
            connected[id] = name
            Haptic.success()
            publish(force: true)
        }
        peripheral.discoverServices([CBUUID(string: "180D"), CBUUID(string: "180F")])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            connected[id] = nil
            if hrDevice == id { hrDevice = nil; WorkoutEngine.shared.setHeartRate(nil) }
            publish(force: true)
            // если устройство сохранено — пробуем вернуться, когда оно снова будет рядом
            if saved.contains(id) { central.connect(peripheral) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([CBUUID(string: "2A37"), CBUUID(string: "2A19")], for: s)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == CBUUID(string: "2A37") { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == CBUUID(string: "2A19") { peripheral.readValue(for: c); peripheral.setNotifyValue(true, for: c) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let d = c.value, !d.isEmpty else { return }
        let id = peripheral.identifier
        if c.uuid == CBUUID(string: "2A37") {
            // флаг 0-го бита: пульс в 8 или 16 битах
            let bpm = (d[0] & 0x01) == 0 ? Int(d[1]) : (d.count > 2 ? Int(d[1]) | (Int(d[2]) << 8) : 0)
            MainActor.assumeIsolated {
                heartRate = bpm
                heartAt = Date()
                hrDevice = id
                hrHistory.append(bpm)
                if hrHistory.count > 60 { hrHistory.removeFirst(hrHistory.count - 60) }
                WorkoutEngine.shared.setHeartRate(bpm)
                publish()
            }
        } else if c.uuid == CBUUID(string: "2A19") {
            let lvl = Int(d[0])
            MainActor.assumeIsolated { battery[id] = lvl; publish() }
        }
    }
}

// MARK: - Панель как «Пункт управления»: стеклянные модули, долгое нажатие раскрывает модуль

enum PanelTile: String, CaseIterable, Identifiable, Codable {
    case devices, heartRate, music, audio, restTimer, watch, startWorkout, torch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .devices: "Bluetooth"
        case .heartRate: "Пульс"
        case .music: "Сейчас играет"
        case .audio: "Звук"
        case .restTimer: "Отдых"
        case .watch: "Apple Watch"
        case .startWorkout: "Тренировка"
        case .torch: "Фонарик"
        }
    }
    var icon: String {
        switch self {
        case .devices: "antenna.radiowaves.left.and.right"
        case .heartRate: "heart.fill"
        case .music: "music.note"
        case .audio: "hifispeaker.2.fill"
        case .restTimer: "timer"
        case .watch: "applewatch"
        case .startWorkout: "play.fill"
        case .torch: "flashlight.on.fill"
        }
    }
    /// размер по умолчанию: пульс и музыка — широкие
    var defaultSize: TileSize { (self == .heartRate || self == .music) ? .wide : .small }
    /// раскрывается долгим нажатием
    var expandable: Bool { self == .devices || self == .heartRate || self == .restTimer }
}

/// Размер модуля, как в Пункте управления: удерживайте и тяните уголок
enum TileSize: String, Codable, CaseIterable {
    case small, wide, large
    var bigger: TileSize? { switch self { case .small: .wide; case .wide: .large; case .large: nil } }
    var smaller: TileSize? { switch self { case .small: nil; case .wide: .small; case .large: .wide } }
    var title: String { switch self { case .small: "маленький"; case .wide: "широкий"; case .large: "большой" } }
}

@MainActor
@Observable
final class PanelLayout {
    static let shared = PanelLayout()
    var tiles: [PanelTile] {
        didSet { UserDefaults.standard.set(tiles.map(\.rawValue), forKey: "panel_tiles_v2") }
    }
    var sizes: [String: TileSize] {
        didSet { if let d = try? JSONEncoder().encode(sizes) { UserDefaults.standard.set(d, forKey: "panel_sizes_v1") } }
    }
    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: "panel_tiles_v2")
        tiles = raw?.compactMap(PanelTile.init) ?? [.devices, .audio, .heartRate, .restTimer, .startWorkout, .music, .torch, .watch]
        if let d = UserDefaults.standard.data(forKey: "panel_sizes_v1"), let m = try? JSONDecoder().decode([String: TileSize].self, from: d) {
            sizes = m
        } else { sizes = [:] }
    }

    func size(_ t: PanelTile) -> TileSize { sizes[t.rawValue] ?? t.defaultSize }
    func setSize(_ t: PanelTile, _ v: TileSize) { sizes[t.rawValue] = v }

    /// Ряды: широкий и большой модуль — один в ряду, маленькие — по два
    var rows: [[PanelTile]] {
        var out: [[PanelTile]] = []
        var pending: PanelTile?
        for t in tiles {
            if size(t) != .small {
                out.append([t])
            } else if let p = pending {
                out.append([p, t]); pending = nil
            } else {
                pending = t
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }
}

private let heartRed = Color(hex: 0xFF3B5C)

struct DevicePanelView: View {
    /// true — открыта шторкой от Dynamic Island (без навигации, свой заголовок)
    var overlay: Bool = false
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var hub = BLEHub.shared
    @State private var layout = PanelLayout.shared
    @State private var editing = false
    @State private var arranging = false
    @State private var expanded: PanelTile?
    @State private var wiggle = false
    @Namespace private var ns

    private let gap: CGFloat = 12
    private let side: CGFloat = 158

    var body: some View {
        ZStack {
            if !overlay { backdrop }
            else {
                // пустое место шторки: нажатие закрывает (в режиме правки — выходит из него)
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { if arranging { endArranging() } else { onClose?() } }
            }
            ScrollView {
                VStack(spacing: gap) {
                    if overlay || arranging { panelHeader }
                    statusHeader
                    ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: gap) {
                            ForEach(row) { t in
                                module(t)
                                    .frame(height: layout.size(t) == .large ? side * 2 + gap : side)
                                    .frame(maxWidth: .infinity)
                            }
                            if row.count == 1 && layout.size(row[0]) == .small { Color.clear.frame(maxWidth: .infinity, maxHeight: side) }
                        }
                    }
                    if !overlay {
                        Text("Удерживайте Bluetooth, Пульс или Отдых, чтобы раскрыть модуль. Удерживайте любой другой модуль — включится правка: уголок меняет размер, «−» убирает. Шторка открывается свайпом вниз от Dynamic Island.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
                .animation(.spring(duration: 0.45, bounce: 0.25), value: layout.tiles)
                .animation(.spring(duration: 0.45, bounce: 0.25), value: layout.sizes)
            }
            .scrollBounceBehavior(.basedOnSize)
            .blur(radius: expanded == nil ? 0 : 14)
            .allowsHitTesting(expanded == nil)

            if let e = expanded {
                expandedModule(e)
                    .zIndex(2)
            }
        }
        .navigationTitle("Устройства")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !overlay {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { arranging ? endArranging() : startArranging() } label: {
                        Image(systemName: arranging ? "checkmark" : "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { PanelEditor() }
        .onAppear { hub.start() }
    }

    // заголовок шторки и режима правки
    private var panelHeader: some View {
        HStack(spacing: 10) {
            if arranging {
                let rest = PanelTile.allCases.filter { !layout.tiles.contains($0) }
                Menu {
                    ForEach(rest) { t in
                        Button { Haptic.tap(); withAnimation { layout.tiles.append(t) } } label: { Label(t.title, systemImage: t.icon) }
                    }
                    Divider()
                    Button { editing = true } label: { Label("Порядок модулей", systemImage: "arrow.up.arrow.down") }
                    Button(role: .destructive) {
                        withAnimation { layout.sizes = [:] }
                    } label: { Label("Сбросить размеры", systemImage: "arrow.counterclockwise") }
                } label: {
                    Label("Добавить", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .tint(.primary)
                Spacer()
                Button { endArranging() } label: {
                    Text("Готово").font(.subheadline.weight(.bold)).foregroundStyle(Color.onLime)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.lime, in: Capsule())
                }
            } else {
                Text("Устройства").font(.title2.bold())
                Spacer()
                Button { startArranging() } label: {
                    Image(systemName: "square.resize").font(.headline)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .tint(.primary)
                if overlay {
                    Button { onClose?() } label: {
                        Image(systemName: "chevron.up").font(.headline)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .tint(.primary)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func startArranging() {
        guard !arranging else { return }
        OxHaptics.play(.select)
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { arranging = true }
        withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { wiggle = true }
    }

    private func endArranging() {
        Haptic.tap()
        withAnimation(.spring(duration: 0.35)) { arranging = false; wiggle = false }
    }

    /// уголок изменения размера: тянуть наружу — больше, внутрь — меньше, нажатие — по кругу
    private func resizeHandle(_ t: PanelTile) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Color.onLime)
            .frame(width: 30, height: 30)
            .background(Color.lime, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            .padding(6)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture {
                let cur = layout.size(t)
                let next = cur.bigger ?? .small
                resize(t, next)
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { v in
                        let d = max(v.translation.width, v.translation.height)
                        let cur = layout.size(t)
                        if d > 30, let b = cur.bigger { resize(t, b) }
                        else if d < -30, let s = cur.smaller { resize(t, s) }
                    }
            )
    }

    private func resize(_ t: PanelTile, _ v: TileSize) {
        Haptic.tap(.medium)
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { layout.setSize(t, v) }
    }

    // фон: мягкие цветные пятна, чтобы стекло «играло»
    private var backdrop: some View {
        ZStack {
            Color.oxBg
            Circle().fill(Color.lime.opacity(scheme == .dark ? 0.22 : 0.35)).frame(width: 320).blur(radius: 90).offset(x: -120, y: -220)
            Circle().fill(Color(hex: 0x3FD6C9).opacity(scheme == .dark ? 0.18 : 0.3)).frame(width: 300).blur(radius: 100).offset(x: 140, y: 80)
            Circle().fill(heartRed.opacity(hub.hrFresh ? 0.2 : 0.06)).frame(width: 260).blur(radius: 90).offset(x: -60, y: 320)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: hub.hrFresh)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: hub.connected.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(hub.connected.isEmpty ? Color.secondary : Color.limeInk)
                .symbolEffect(.variableColor.iterative, isActive: hub.scanning)
            VStack(alignment: .leading, spacing: 1) {
                Text(hub.connected.isEmpty ? "Нет подключений" : hub.connected.values.sorted().joined(separator: ", "))
                    .font(.subheadline.bold()).lineLimit(1)
                Text(hub.hrFresh ? "пульс \(hub.heartRate) уд/мин" : (hub.state == .poweredOff ? "Bluetooth выключен" : "удерживайте Bluetooth, чтобы подключить"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    // MARK: модули

    @ViewBuilder
    private func module(_ t: PanelTile) -> some View {
        let content = Group {
            switch t {
            case .devices: BluetoothModule(onOpen: { open(t) })
            case .heartRate: HeartModule(onConnect: { open(.devices) })
            case .music: NowPlayingModule()
            case .audio: AudioModule()
            case .restTimer: RestModule()
            case .watch: WatchModule()
            case .startWorkout: WorkoutModule { onClose?(); model.handle(route: "workout") }
            case .torch: TorchModule()
            }
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!arranging)
            .glassEffect(t == .startWorkout ? .regular.tint(Color.lime).interactive() : .regular.interactive(), in: .rect(cornerRadius: 32))
            .overlay(alignment: .topLeading) {
                if arranging {
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(duration: 0.4)) { layout.tiles.removeAll { $0 == t } }
                    } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .heavy)).foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if arranging { resizeHandle(t).transition(.scale.combined(with: .opacity)) }
            }
            .overlay(alignment: .bottom) {
                if arranging {
                    Text(layout.size(t).title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }
            }
            .rotationEffect(.degrees(arranging ? (wiggle ? 0.8 : -0.8) * (t.rawValue.count.isMultiple(of: 2) ? 1 : -1) : 0))
            .scaleEffect(arranging ? 0.96 : 1)
            .matchedGeometryEffect(id: t.id, in: ns, isSource: expanded != t)
            .opacity(expanded == t ? 0 : 1)
            .onLongPressGesture(minimumDuration: 0.4) {
                if arranging { return }
                if t.expandable { open(t) } else { startArranging() }
            }
    }

    private func open(_ t: PanelTile) {
        OxHaptics.play(.select)
        if t == .devices { hub.scan() }
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { expanded = t }
    }

    private func close() {
        hub.stopScan()
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { expanded = nil }
    }

    // MARK: раскрытый модуль

    private func expandedModule(_ t: PanelTile) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: t.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(t == .heartRate ? .white : Color.onLime)
                        .frame(width: 48, height: 48)
                        .background(t == .heartRate ? heartRed : Color.lime, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.title3.bold())
                        Text(t == .restTimer ? "системный таймер" : (hub.connected.isEmpty ? "не подключено" : "подключено: \(hub.connected.count)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                switch t {
                case .restTimer: RestChooser { close() }
                case .heartRate: DeviceList(onlyHeart: true)
                default: DeviceList(onlyHeart: false)
                }
                if t != .restTimer {
                    Divider()
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        Text("Настройки Bluetooth…").font(.subheadline.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 36))
            .matchedGeometryEffect(id: t.id, in: ns, isSource: true)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: Модуль Bluetooth

private struct BluetoothModule: View {
    var onOpen: () -> Void
    @State private var hub = BLEHub.shared

    var body: some View {
        let on = !hub.connected.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptic.tap()
                if hub.saved.isEmpty || on { onOpen() } else { hub.start(); hub.scan() }
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? Color.onLime : .primary)
                    .frame(width: 56, height: 56)
                    .background(on ? Color.lime : Color.primary.opacity(0.1), in: Circle())
                    .symbolEffect(.variableColor.iterative, isActive: hub.scanning)
            }
            .buttonStyle(TileStyle())
            Spacer(minLength: 0)
            Text("Bluetooth").font(.subheadline.bold())
            Text(on ? hub.connected.values.sorted().joined(separator: ", ") : "удерживайте")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Модуль пульса

private struct HeartModule: View {
    var onConnect: () -> Void
    @State private var hub = BLEHub.shared
    @State private var beat = false

    static let zones: [(String, Color, ClosedRange<Int>)] = [
        ("разминка", Color(hex: 0x3FD6C9), 0...99), ("жиросжигание", Color(hex: 0x58F670), 100...129),
        ("аэробная", Color(hex: 0xFFD25E), 130...154), ("анаэробная", Color(hex: 0xF0A030), 155...174), ("максимум", heartRed, 175...260),
    ]
    private var zone: Int { Self.zones.firstIndex { $0.2.contains(hub.heartRate) } ?? 0 }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(hub.hrFresh ? heartRed : Color.secondary)
                        .scaleEffect(beat ? 1.22 : 1)
                    Text("Пульс").font(.subheadline.bold())
                }
                if hub.hrFresh {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(hub.heartRate)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(hub.heartRate)))
                        Text("уд/мин").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(Self.zones[zone].0).font(.caption.bold()).foregroundStyle(Self.zones[zone].1)
                } else {
                    Text("Датчик не подключён").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Подключить", action: onConnect)
                        .font(.subheadline.bold())
                        .buttonStyle(.glassProminent)
                        .tint(Color.lime)
                        .foregroundStyle(Color.onLime)
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                Sparkline(values: hub.hrHistory.count > 1 ? hub.hrHistory.map(Double.init) : [70, 72, 71, 74, 73], color: hub.hrFresh ? heartRed : Color.secondary.opacity(0.4))
                    .frame(width: 120, height: 50)
                // шкала зон
                HStack(spacing: 3) {
                    ForEach(Array(Self.zones.enumerated()), id: \.offset) { i, z in
                        Capsule().fill(z.1.opacity(hub.hrFresh && i == zone ? 1 : 0.28))
                            .frame(width: 20, height: hub.hrFresh && i == zone ? 8 : 5)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.35), value: hub.heartRate)
        .onChange(of: hub.heartAt) {
            withAnimation(.easeOut(duration: 0.12)) { beat = true }
            Task { try? await Task.sleep(for: .milliseconds(150)); withAnimation(.easeIn(duration: 0.2)) { beat = false } }
        }
    }
}

// MARK: Звук

/// Системная кнопка выбора, куда выводить звук (AirPods, колонки, в т. ч. с Алисой по Bluetooth, AirPlay)
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor = .label
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = UIColor(Color.lime)
        v.tintColor = tint
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

private struct AudioModule: View {
    @State private var output = AudioModule.current()

    static func current() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "iPhone"
    }

    var body: some View {
        let external = output != "iPhone" && output != "Динамик" && output != "Speaker"
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: external ? "hifispeaker.2.fill" : "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(external ? Color.onLime : .primary)
                .frame(width: 56, height: 56)
                .background(external ? Color.lime : Color.primary.opacity(0.1), in: Circle())
            Spacer(minLength: 0)
            Text("Звук").font(.subheadline.bold())
            Text(output).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // вся плитка — системная кнопка выбора вывода звука
        .overlay { RoutePicker(tint: .clear).opacity(0.02) }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            Task { @MainActor in output = Self.current() }
        }
    }
}

private struct NowPlayingModule: View {
    @State private var title = "Ничего не играет"
    @State private var artist = "Приложение «Музыка»"
    @State private var art: UIImage?
    @State private var playing = false
    private let player = MPMusicPlayerController.systemMusicPlayer

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let art { Image(uiImage: art).resizable().scaledToFill() }
                else { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
            }
            .frame(width: 72, height: 72)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 26) {
                    Button { player.skipToPreviousItem(); Haptic.tap() } label: { Image(systemName: "backward.fill") }
                    Button {
                        if playing { player.pause() } else { player.play() }
                        Haptic.tap()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).contentTransition(.symbolEffect(.replace))
                    }
                    Button { player.skipToNextItem(); Haptic.tap() } label: { Image(systemName: "forward.fill") }
                }
                .font(.title3)
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .overlay(alignment: .topTrailing) { RoutePicker().frame(width: 30, height: 30).padding(12) }
        .onAppear { player.beginGeneratingPlaybackNotifications(); refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in refresh() }
    }

    private func refresh() {
        playing = player.playbackState == .playing
        if let i = player.nowPlayingItem {
            title = i.title ?? "Без названия"
            artist = i.artist ?? ""
            art = i.artwork?.image(at: CGSize(width: 144, height: 144))
        }
    }
}

// MARK: Отдых

@MainActor
@Observable
final class RestClock {
    static let shared = RestClock()
    var end: Date?
    var total: Double = 90
    func start(_ s: Int) {
        total = Double(s)
        end = Date().addingTimeInterval(Double(s))
        Task { await OxAlarms.scheduleRest(seconds: s, next: "") }
        FX.play(.energyPulse)
    }
}

private struct RestModule: View {
    @State private var clock = RestClock.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = max(0, clock.end?.timeIntervalSince(tl.date) ?? 0)
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: left > 0 ? left / clock.total : 0)
                        .stroke(Color.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    if left > 0 {
                        Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                            .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    } else {
                        Image(systemName: "timer").font(.system(size: 20, weight: .semibold))
                    }
                }
                .frame(width: 56, height: 56)
                Spacer(minLength: 0)
                Text("Отдых").font(.subheadline.bold())
                Text(left > 0 ? "идёт" : "нажмите — 90 с").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture { Haptic.tap(); clock.start(90) }
    }
}

private struct RestChooser: View {
    var done: () -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach([30, 45, 60, 90, 120, 180], id: \.self) { s in
                Button {
                    RestClock.shared.start(s)
                    done()
                } label: {
                    Text(s < 60 ? "\(s) с" : (s % 60 == 0 ? "\(s / 60) мин" : "\(s / 60):\(String(format: "%02d", s % 60))"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.glass)
            }
        }
    }
}

// MARK: Прочие модули

private struct WatchModule: View {
    var body: some View {
        let w = WatchLink.shared
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(w.appInstalled ? Color.onLime : .primary)
                .frame(width: 56, height: 56)
                .background(w.appInstalled ? Color.lime : Color.primary.opacity(0.1), in: Circle())
            Spacer(minLength: 0)
            Text("Apple Watch").font(.subheadline.bold())
            Text(w.appInstalled ? "OXION на часах" : (w.paired ? "подключены" : "нет часов")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { w.activate() }
    }
}

private struct WorkoutModule: View {
    var action: () -> Void
    var body: some View {
        Button { Haptic.tap(); action() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: WorkoutEngine.shared.isActive ? "figure.strengthtraining.traditional" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 56, height: 56)
                    .background(Color.onLime.opacity(0.12), in: Circle())
                Spacer(minLength: 0)
                Text("Тренировка").font(.subheadline.bold())
                Text(WorkoutEngine.shared.isActive ? "идёт — открыть" : "начать").font(.caption).opacity(0.7)
            }
            .foregroundStyle(Color.onLime)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
    }
}

private struct TorchModule: View {
    @State private var on = false
    var body: some View {
        Button {
            guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
            try? d.lockForConfiguration()
            on.toggle()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
            Haptic.tap()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? Color.onLime : .primary)
                    .frame(width: 56, height: 56)
                    .background(on ? Color.white : Color.primary.opacity(0.1), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 0)
                Text("Фонарик").font(.subheadline.bold())
                Text(on ? "включён" : "выключен").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle())
    }
}

struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

// MARK: Список устройств в раскрытом модуле (как в Пункте управления)

private struct DeviceList: View {
    var onlyHeart: Bool
    @State private var hub = BLEHub.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hub.state == .unauthorized {
                Text("Разрешите Bluetooth: Настройки → Oxion → Bluetooth").font(.footnote).foregroundStyle(.orange)
            } else if hub.state == .poweredOff {
                Text("Bluetooth выключен — включите в Пункте управления").font(.footnote).foregroundStyle(.orange)
            }
            ForEach(hub.connected.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                row(icon: id == hub.hrDevice ? "heart.fill" : "checkmark", name: name,
                    sub: hub.battery[id].map { "заряд \($0)%" } ?? "подключено", on: true) {
                    hub.disconnect(id)
                }
            }
            let others = hub.found.filter { hub.connected[$0.id] == nil && (!onlyHeart || $0.hr) }
            if !others.isEmpty {
                Text(onlyHeart ? "Датчики пульса рядом" : "Устройства рядом")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(others) { d in
                        row(icon: d.hr ? "heart" : "dot.radiowaves.left.and.right", name: d.name,
                            sub: d.hr ? "датчик пульса" : signal(d.rssi), on: false) {
                            hub.connect(d.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            if hub.scanning {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Поиск…").font(.caption).foregroundStyle(.secondary) }
                    .padding(.top, 4)
            } else if others.isEmpty && hub.connected.isEmpty {
                Text(onlyHeart ? "Включите на часах «Трансляцию пульса» или наденьте нагрудный датчик." : "Ничего не найдено рядом.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Искать снова") { hub.scan() }.font(.subheadline.bold()).tint(Color.limeInk)
            }
        }
    }

    private func signal(_ rssi: Int) -> String { rssi > -60 ? "рядом" : rssi > -75 ? "недалеко" : "далеко" }

    private func row(icon: String, name: String, sub: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); action() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Color.onLime : .primary)
                    .frame(width: 36, height: 36)
                    .background(on ? Color.lime : Color.primary.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if on { Text("Отключить").font(.caption.bold()).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Настройка панели

private struct PanelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layout = PanelLayout.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.tiles) { t in
                        Label(t.title, systemImage: t.icon)
                    }
                    .onMove { layout.tiles.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { layout.tiles.remove(atOffsets: $0) }
                } header: {
                    Text("На панели")
                } footer: {
                    Text("Перетащите, чтобы поменять порядок. Смахните влево, чтобы убрать. «Пульс» и «Сейчас играет» — широкие модули.")
                }
                let rest = PanelTile.allCases.filter { !layout.tiles.contains($0) }
                if !rest.isEmpty {
                    Section("Добавить") {
                        ForEach(rest) { t in
                            Button {
                                Haptic.tap()
                                withAnimation { layout.tiles.append(t) }
                            } label: {
                                Label(t.title, systemImage: t.icon)
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Модули")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .tint(Color.limeInk)
    }
}

// MARK: - Режим «Табло»: телефон лежит экраном вверх — крупные цифры, видно издалека
// Положение телефона только переключает вид экрана и никак не засчитывает упражнения.

@MainActor
@Observable
final class FlatDetector {
    var flat = false
    private let mm = CMMotionManager()
    private var since: Date?

    func start() {
        guard mm.isDeviceMotionAvailable, !mm.isDeviceMotionActive else { return }
        mm.deviceMotionUpdateInterval = 1 / 10
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let isFlat = g.z < -0.93
            if isFlat {
                if self.since == nil { self.since = Date() }
                if !self.flat, Date().timeIntervalSince(self.since!) > 1.2 {
                    withAnimation(.spring(duration: 0.5, bounce: 0.2)) { self.flat = true }
                }
            } else {
                self.since = nil
                if self.flat, g.z > -0.8 { withAnimation(.spring(duration: 0.4)) { self.flat = false } }
            }
        }
    }

    func stop() { mm.stopDeviceMotionUpdates(); flat = false }
}

struct ScoreboardView: View {
    let s: WorkoutState
    let now: Date
    @State private var hub = BLEHub.shared

    var body: some View {
        VStack(spacing: 18) {
            Text(s.phase == .resting ? "ОТДЫХ" : (s.currentItem?.name.uppercased() ?? "ТРЕНИРОВКА"))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(s.phase == .resting ? Color(hex: 0x3FD6C9) : Color.lime)
                .lineLimit(1).minimumScaleFactor(0.5)
            Group {
                if s.phase == .resting, let end = s.restEndsAt {
                    Text(timerInterval: now...max(now, end), countsDown: true)
                } else {
                    let e = Int(s.elapsed(now))
                    Text(String(format: "%d:%02d", e / 60, e % 60))
                }
            }
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            if let it = s.currentItem {
                Text("подход \(min(it.doneSets + 1, it.sets)) из \(it.sets)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if hub.hrFresh {
                Label("\(hub.heartRate)", systemImage: "heart.fill")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFF3B5C))
            }
            Text("Поднимите телефон, чтобы вернуться").font(.footnote).foregroundStyle(.white.opacity(0.4)).padding(.top, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
