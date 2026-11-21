import SwiftUI
import CoreBluetooth
import AVKit
import MediaPlayer
import CoreMotion

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
        }
        peripheral.discoverServices([CBUUID(string: "180D"), CBUUID(string: "180F")])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            connected[id] = nil
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
            }
        } else if c.uuid == CBUUID(string: "2A19") {
            let lvl = Int(d[0])
            MainActor.assumeIsolated { battery[id] = lvl }
        }
    }
}

// MARK: - Плитки панели

enum PanelTile: String, CaseIterable, Identifiable, Codable {
    case heartRate, audio, music, restTimer, devices, watch, startWorkout, torch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .heartRate: "Пульс"
        case .audio: "Звук и колонки"
        case .music: "Музыка"
        case .restTimer: "Таймер отдыха"
        case .devices: "Устройства"
        case .watch: "Apple Watch"
        case .startWorkout: "Тренировка"
        case .torch: "Фонарик"
        }
    }
    var icon: String {
        switch self {
        case .heartRate: "heart.fill"
        case .audio: "hifispeaker.2.fill"
        case .music: "music.note"
        case .restTimer: "timer"
        case .devices: "dot.radiowaves.left.and.right"
        case .watch: "applewatch"
        case .startWorkout: "play.fill"
        case .torch: "flashlight.on.fill"
        }
    }
    /// широкая плитка (на всю строку)
    var wide: Bool { self == .heartRate || self == .music }
}

@MainActor
@Observable
final class PanelLayout {
    static let shared = PanelLayout()
    var tiles: [PanelTile] {
        didSet { UserDefaults.standard.set(tiles.map(\.rawValue), forKey: "panel_tiles") }
    }
    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: "panel_tiles")
        tiles = raw?.compactMap(PanelTile.init) ?? [.heartRate, .audio, .restTimer, .music, .devices, .startWorkout]
    }
}

// MARK: - Панель управления

struct DevicePanelView: View {
    @Environment(AppModel.self) private var model
    @State private var hub = BLEHub.shared
    @State private var layout = PanelLayout.shared
    @State private var editing = false
    @State private var devices = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(layout.tiles) { t in
                    tile(t)
                        .gridCellColumns(t.wide ? 2 : 1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(16)
            .animation(.spring(duration: 0.4, bounce: 0.25), value: layout.tiles)

            Text("Пульс — с нагрудных датчиков и часов, которые умеют «транслировать пульс» по Bluetooth. Колонки, в том числе с Алисой, подключите в настройках Bluetooth iPhone как обычную колонку — они появятся в плитке «Звук».")
                .font(.footnote)
                .foregroundStyle(Color.oxHint)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
        .background(Color.oxBg)
        .navigationTitle("Умные устройства")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Настроить") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { PanelEditor() }
        .sheet(isPresented: $devices) { NavigationStack { DeviceScanView() } }
        .onAppear { hub.start() }
    }

    @ViewBuilder
    private func tile(_ t: PanelTile) -> some View {
        switch t {
        case .heartRate: HeartTile { devices = true }
        case .audio: AudioTile()
        case .music: MusicTile()
        case .restTimer: RestTile()
        case .devices: SmallTile(t: t, value: hub.connected.isEmpty ? "не подключены" : "\(hub.connected.count) подключено") { devices = true }
        case .watch: WatchTile()
        case .startWorkout: SmallTile(t: t, value: WorkoutEngine.shared.isActive ? "идёт" : "начать", accent: true) { model.handle(route: "workout") }
        case .torch: TorchTile()
        }
    }
}

private struct TileBox<C: View>: View {
    var accent = false
    @ViewBuilder var content: () -> C
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(accent ? Color.lime : Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .foregroundStyle(accent ? Color.onLime : Color.primary)
    }
}

private struct SmallTile: View {
    let t: PanelTile
    let value: String
    var accent = false
    var action: () -> Void
    var body: some View {
        Button { Haptic.tap(); action() } label: {
            TileBox(accent: accent) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: t.icon).font(.title2)
                    Spacer(minLength: 0)
                    Text(t.title).font(.subheadline.bold())
                    Text(value).font(.caption).opacity(0.7)
                }
            }
        }
        .buttonStyle(TileStyle())
    }
}

struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private struct HeartTile: View {
    var connect: () -> Void
    @State private var hub = BLEHub.shared
    @State private var beat = false

    private var zone: (String, Color) {
        let b = hub.heartRate
        switch b {
        case ..<100: return ("разминка", Color(hex: 0x3FD6C9))
        case 100..<130: return ("жиросжигание", Color(hex: 0x58F670))
        case 130..<155: return ("аэробная", Color(hex: 0xFFD25E))
        case 155..<175: return ("анаэробная", Color(hex: 0xF0A030))
        default: return ("максимум", Color(hex: 0xFF5A4E))
        }
    }

    var body: some View {
        TileBox {
            HStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(hub.hrFresh ? zone.1 : Color.oxHint)
                    .scaleEffect(beat ? 1.15 : 1)
                    .animation(.easeOut(duration: 0.15), value: beat)
                VStack(alignment: .leading, spacing: 2) {
                    if hub.hrFresh {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(hub.heartRate)").font(.system(size: 40, weight: .bold, design: .rounded)).contentTransition(.numericText())
                            Text("уд/мин").font(.subheadline).foregroundStyle(Color.oxHint)
                        }
                        Text("зона: \(zone.0)").font(.caption.bold()).foregroundStyle(zone.1)
                    } else {
                        Text("Пульс").font(.headline)
                        Text("Подключите датчик или часы").font(.caption).foregroundStyle(Color.oxHint)
                    }
                }
                Spacer()
                if !hub.hrFresh {
                    Button("Подключить", action: connect).buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                }
            }
        }
        .animation(.snappy, value: hub.heartRate)
        .onChange(of: hub.heartAt) {
            beat = true
            Task { try? await Task.sleep(for: .milliseconds(160)); beat = false }
        }
    }
}

/// Системная кнопка выбора, куда выводить звук (AirPods, колонки, Яндекс Станция по Bluetooth, AirPlay)
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = UIColor(Color.lime)
        v.tintColor = .label
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

private struct AudioTile: View {
    @State private var output = AudioTile.current()

    static func current() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "iPhone"
    }

    var body: some View {
        TileBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "hifispeaker.2.fill").font(.title2)
                    Spacer()
                    RoutePicker().frame(width: 34, height: 34)
                }
                Spacer(minLength: 0)
                Text("Звук").font(.subheadline.bold())
                Text(output).font(.caption).opacity(0.7).lineLimit(1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            output = Self.current()
        }
    }
}

private struct MusicTile: View {
    @State private var title = "Ничего не играет"
    @State private var playing = false
    private let player = MPMusicPlayerController.systemMusicPlayer

    var body: some View {
        TileBox {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .background(Color(hex: 0xFF3B5C).opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Музыка").font(.subheadline.bold())
                    Text(title).font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                }
                Spacer()
                HStack(spacing: 18) {
                    Button { player.skipToPreviousItem(); refresh() } label: { Image(systemName: "backward.fill") }
                    Button {
                        if playing { player.pause() } else { player.play() }
                        Haptic.tap()
                        Task { try? await Task.sleep(for: .milliseconds(300)); refresh() }
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).contentTransition(.symbolEffect(.replace))
                    }
                    Button { player.skipToNextItem(); refresh() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            player.beginGeneratingPlaybackNotifications()
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in refresh() }
    }

    private func refresh() {
        playing = player.playbackState == .playing
        if let i = player.nowPlayingItem {
            title = [i.title, i.artist].compactMap { $0 }.joined(separator: " — ")
        } else {
            title = "Приложение «Музыка»"
        }
    }
}

private struct RestTile: View {
    @State private var started: Int?
    var body: some View {
        TileBox {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "timer").font(.title2)
                Spacer(minLength: 0)
                Text(started.map { "Отдых \($0) с" } ?? "Таймер отдыха").font(.subheadline.bold())
                HStack(spacing: 6) {
                    ForEach([60, 90, 120], id: \.self) { s in
                        Button("\(s)") {
                            Haptic.tap()
                            started = s
                            Task { await OxAlarms.scheduleRest(seconds: s, next: "") }
                        }
                        .font(.caption.bold())
                        .buttonStyle(.glass)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }
}

private struct WatchTile: View {
    var body: some View {
        let w = WatchLink.shared
        TileBox {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "applewatch").font(.title2)
                Spacer(minLength: 0)
                Text("Apple Watch").font(.subheadline.bold())
                Text(w.appInstalled ? "OXION на часах" : (w.paired ? "часы подключены" : "не подключены"))
                    .font(.caption).opacity(0.7)
            }
        }
        .onAppear { w.activate() }
    }
}

private struct TorchTile: View {
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
            TileBox(accent: on) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill").font(.title2).contentTransition(.symbolEffect(.replace))
                    Spacer(minLength: 0)
                    Text("Фонарик").font(.subheadline.bold())
                    Text(on ? "включён" : "выключен").font(.caption).opacity(0.7)
                }
            }
        }
        .buttonStyle(TileStyle())
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
                    Text("Перетащите, чтобы поменять порядок. Смахните влево, чтобы убрать.")
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
            .navigationTitle("Панель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .tint(Color.limeInk)
    }
}

// MARK: - Поиск устройств

struct DeviceScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hub = BLEHub.shared

    var body: some View {
        List {
            if hub.state == .unauthorized {
                Section { Text("Разрешите доступ к Bluetooth: Настройки → Oxion → Bluetooth.").foregroundStyle(.orange) }
            } else if hub.state == .poweredOff {
                Section { Text("Bluetooth выключен — включите его в Пункте управления.").foregroundStyle(.orange) }
            }
            if !hub.connected.isEmpty {
                Section("Подключены") {
                    ForEach(hub.connected.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.limeInk)
                            Text(name)
                            Spacer()
                            if let b = hub.battery[id] { Label("\(b)%", systemImage: "battery.75percent").font(.caption).foregroundStyle(Color.oxHint) }
                        }
                        .swipeActions { Button("Забыть", role: .destructive) { hub.disconnect(id) } }
                    }
                }
            }
            Section {
                ForEach(hub.found.filter { hub.connected[$0.id] == nil }) { d in
                    Button {
                        Haptic.tap()
                        hub.connect(d.id)
                    } label: {
                        HStack {
                            Image(systemName: d.hr ? "heart.fill" : "dot.radiowaves.left.and.right")
                                .foregroundStyle(d.hr ? Color(hex: 0xFF3B5C) : Color.oxHint)
                                .frame(width: 26)
                            VStack(alignment: .leading) {
                                Text(d.name)
                                if d.hr { Text("датчик пульса").font(.caption).foregroundStyle(Color.limeInk) }
                            }
                            Spacer()
                            SignalBars(rssi: d.rssi)
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                HStack {
                    Text("Рядом")
                    if hub.scanning { ProgressView().controlSize(.mini) }
                }
            } footer: {
                Text("На часах включите «Трансляцию пульса» (Heart Rate Broadcast) — тогда они появятся здесь как датчик пульса. Apple Watch работает через приложение OXION на часах.")
            }
        }
        .navigationTitle("Устройства")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(hub.scanning ? "Стоп" : "Искать") { hub.scanning ? hub.stopScan() : hub.scan() }
            }
            ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
        }
        .onAppear { hub.start(); Task { try? await Task.sleep(for: .milliseconds(400)); hub.scan() } }
        .onDisappear { hub.stopScan() }
    }
}

private struct SignalBars: View {
    let rssi: Int
    var body: some View {
        let lvl = rssi > -60 ? 3 : rssi > -75 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i <= lvl ? Color.primary : Color.primary.opacity(0.2)).frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
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
