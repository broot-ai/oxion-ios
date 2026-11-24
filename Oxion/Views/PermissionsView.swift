import SwiftUI
import AVFoundation
import Photos
import Contacts
import CoreLocation
import LocalAuthentication
import UserNotifications
import Network
import CoreTelephony
import ActivityKit

// MARK: - Доступы OXION: каждое разрешение привязано к настоящей функции.
// iOS показывает строку в «Настройки → Oxion» только после того, как приложение один раз запросило доступ.

enum PermState: Equatable {
    case notAsked, granted, limited, denied, info(String)
    var title: String {
        switch self {
        case .notAsked: return "Не запрошено"
        case .granted: return "Разрешено"
        case .limited: return "Частично"
        case .denied: return "Запрещено"
        case .info(let t): return t
        }
    }
    var color: Color {
        switch self {
        case .granted: return .lime
        case .limited: return Color(hex: 0x3FD6C9)
        case .denied: return Color(hex: 0xFF5A4E)
        case .notAsked: return Color(hex: 0xF0A030)
        case .info: return Color.oxHint
        }
    }
}

enum PermKind: String, CaseIterable, Identifiable {
    case notifications, liveActivities, location, contacts, photos, camera, microphone, faceID, localNetwork, backgroundRefresh, cellular
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "Уведомления"
        case .liveActivities: return "Live Activities"
        case .location: return "Геопозиция"
        case .contacts: return "Контакты"
        case .photos: return "Фото"
        case .camera: return "Камера"
        case .microphone: return "Микрофон"
        case .faceID: return "Face ID"
        case .localNetwork: return "Локальная сеть"
        case .backgroundRefresh: return "Обновление контента"
        case .cellular: return "Сотовые данные"
        }
    }
    var icon: String {
        switch self {
        case .notifications: return "bell.badge.fill"
        case .liveActivities: return "platter.filled.top.iphone"
        case .location: return "location.fill"
        case .contacts: return "person.crop.circle.fill"
        case .photos: return "photo.fill.on.rectangle.fill"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .faceID: return "faceid"
        case .localNetwork: return "network"
        case .backgroundRefresh: return "arrow.clockwise.circle.fill"
        case .cellular: return "antenna.radiowaves.left.and.right"
        }
    }
    var tint: Color {
        switch self {
        case .notifications: return Color(hex: 0xFF5A4E)
        case .liveActivities: return Color(hex: 0x1C1C1E)
        case .location: return Color(hex: 0x0A84FF)
        case .contacts: return Color(hex: 0x8E8E93)
        case .photos: return Color(hex: 0xF0A030)
        case .camera, .microphone: return Color(hex: 0x636366)
        case .faceID: return Color(hex: 0x58F670)
        case .localNetwork: return Color(hex: 0x0A84FF)
        case .backgroundRefresh: return Color(hex: 0x8E7CFF)
        case .cellular: return Color(hex: 0x58F670)
        }
    }
    var purpose: String {
        switch self {
        case .liveActivities: return "Тренировка и синхронизация в Dynamic Island и на экране блокировки"
        case .notifications: return "Баннеры, звуки и наклейка с числом непрочитанных: сообщения, отдых окончен, план тренировок"
        case .location: return "Определить ваш город для каталога тренеров и ленты «Мой город»"
        case .contacts: return "Пригласить друзей из контактов в OXION. Контакты не загружаются на сервер"
        case .photos: return "Сохранять карточки прогресса и итогов тренировки в «Фото»"
        case .camera: return "Подсчёт повторов (Vision), фото прогресса, видеозвонки"
        case .microphone: return "Голосовые сообщения, кружки и звонки"
        case .faceID: return "Закрыть фото прогресса тела"
        case .localNetwork: return "Найти экраны и устройства в вашей Wi‑Fi сети для тренировки (Apple TV, тренажёры)"
        case .backgroundRefresh: return "Обновлять виджеты и счётчик сообщений, пока OXION закрыт"
        case .cellular: return "Работа OXION без Wi‑Fi. Отключается в настройках iPhone"
        }
    }
}

@MainActor
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()
    var states: [PermKind: PermState] = [:]
    var city: String?
    var networkDevices: [String] = []

    private let location = LocationAsker()
    private var browsers: [NWBrowser] = []

    func refresh() async {
        let n = await UNUserNotificationCenter.current().notificationSettings()
        states[.notifications] = { () -> PermState in switch n.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .provisional, .ephemeral: return .limited
        default: return .granted
        } }()
        states[.location] = { () -> PermState in switch location.manager.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .granted
        } }()
        states[.contacts] = { () -> PermState in switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        case .limited: return .limited
        default: return .granted
        } }()
        states[.photos] = { () -> PermState in switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        case .limited: return .limited
        default: return .granted
        } }()
        states[.camera] = Self.av(AVCaptureDevice.authorizationStatus(for: .video))
        states[.microphone] = { () -> PermState in switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notAsked
        case .denied: return .denied
        default: return .granted
        } }()
        let ctx = LAContext()
        var err: NSError?
        let can = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        if ctx.biometryType == .none && !can {
            states[.faceID] = .info("Нет на устройстве")
        } else if let e = err as? LAError, e.code == .biometryNotAvailable {
            states[.faceID] = .denied
        } else {
            states[.faceID] = ProgressStore.shared.faceLock ? PermState.granted : PermState.notAsked
        }
        if states[.localNetwork] == nil { states[.localNetwork] = .notAsked }
        states[.liveActivities] = ActivityAuthorizationInfo().areActivitiesEnabled ? .granted : .denied
        states[.backgroundRefresh] = { () -> PermState in switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .granted
        case .denied: return .denied
        default: return .info("Ограничено")
        } }()
        states[.cellular] = { () -> PermState in switch CTCellularData().restrictedState {
        case .notRestricted: return .granted
        case .restricted: return .denied
        default: return .info("Как в настройках")
        } }()
    }

    private static func av(_ s: AVAuthorizationStatus) -> PermState {
        switch s {
        case .notDetermined: return .notAsked
        case .authorized: return .granted
        default: return .denied
        }
    }

    /// Нажатие на доступ: сначала окно с картинкой-подсказкой, потом системный запрос или настройки
    func request(_ k: PermKind) async {
        let st = states[k] ?? .notAsked
        switch k {
        case .faceID, .localNetwork:
            await systemRequest(k)
        default:
            if st == .denied || ((k == .backgroundRefresh || k == .cellular || k == .liveActivities) && st != .granted) {
                PermPrompt.show(k, denied: true)
            } else if st == .notAsked {
                PermPrompt.show(k, denied: false) { Task { await self.systemRequest(k) } }
            } else {
                openSettings(k)
            }
        }
    }

    /// Системный запрос доступа
    func systemRequest(_ k: PermKind) async {
        switch k {
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        case .location:
            if states[.location] == .denied { PermPrompt.show(.location, denied: true); return }
            if await location.ask() { city = await location.city() }
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .photos:
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .faceID:
            if ProgressStore.shared.faceLock {
                ProgressStore.shared.faceLock = false
            } else {
                let ctx = LAContext()
                if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Включить защиту фото прогресса")) == true {
                    ProgressStore.shared.faceLock = true
                    OxAlert.show(icon: "faceid", title: "Face ID включён", message: "Фото прогресса теперь открываются только после Face ID.")
                }
            }
        case .localNetwork:
            scanNetwork()
        case .backgroundRefresh, .cellular, .liveActivities:
            openSettings(k)
        }
        await refresh()
    }

    func openSettings(_ k: PermKind? = nil) {
        let s = k == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString
        if let u = URL(string: s) { UIApplication.shared.open(u) }
    }

    /// Все ещё не запрошенные — по очереди
    func requestAll() async {
        for k in [PermKind.notifications, .location, .camera, .microphone, .photos, .contacts, .localNetwork] where states[k] == .notAsked {
            await systemRequest(k)
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: Локальная сеть — поиск AirPlay-экранов и устройств OXION (Bonjour)

    func scanNetwork() {
        browsers.forEach { $0.cancel() }
        browsers = []
        networkDevices = []
        states[.localNetwork] = .info("Поиск…")
        for type in ["_airplay._tcp", "_oxion._tcp"] {
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            b.stateUpdateHandler = { st in
                Task { @MainActor in
                    if case .waiting(let e) = st, case .dns(let code) = e, code == -65570 {
                        PermissionCenter.shared.states[.localNetwork] = .denied
                    }
                }
            }
            b.browseResultsChangedHandler = { results, _ in
                let names = results.compactMap { r -> String? in
                    if case .service(let name, _, _, _) = r.endpoint { return name }
                    return nil
                }
                Task { @MainActor in
                    let all = Set(PermissionCenter.shared.networkDevices + names)
                    PermissionCenter.shared.networkDevices = all.sorted()
                    PermissionCenter.shared.states[.localNetwork] = .granted
                }
            }
            b.start(queue: .main)
            browsers.append(b)
        }
        Task {
            try? await Task.sleep(for: .seconds(6))
            browsers.forEach { $0.cancel() }
            if case .info = states[.localNetwork] ?? .notAsked {
                states[.localNetwork] = networkDevices.isEmpty ? PermState.info("Устройств не найдено") : PermState.granted
            }
        }
    }
}

/// Запрос геопозиции «при использовании» + определение города
final class LocationAsker: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    private var authCont: CheckedContinuation<Bool, Never>?
    private var locCont: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    @MainActor func ask() async -> Bool {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways { return true }
        guard s == .notDetermined else { return false }
        return await withCheckedContinuation { c in
            authCont = c
            manager.requestWhenInUseAuthorization()
        }
    }

    @MainActor func city() async -> String? {
        let loc: CLLocation? = await withCheckedContinuation { c in
            locCont = c
            manager.requestLocation()
        }
        guard let loc else { return nil }
        let pm = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: L10n.locale)
        return pm?.first?.locality
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        guard s != .notDetermined else { return }
        authCont?.resume(returning: s == .authorizedWhenInUse || s == .authorizedAlways)
        authCont = nil
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locCont?.resume(returning: locations.last)
        locCont = nil
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        locCont?.resume(returning: nil)
        locCont = nil
    }
}

// MARK: - Экран

struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    @State private var pc = PermissionCenter.shared
    @State private var invite = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Доступы OXION").font(.title2.bold())
                    Text("Каждый доступ нужен для конкретной функции. После первого запроса он появляется в «Настройки → Oxion» на iPhone, и там его можно выключить в любой момент.")
                        .font(.subheadline).foregroundStyle(Color.oxHint)
                    HStack {
                        Button { Task { await pc.requestAll() } } label: {
                            Label("Разрешить нужное", systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
                        Button { pc.openSettings() } label: {
                            Label("Настройки", systemImage: "gearshape.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                    .padding(.top, 4)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(PermKind.allCases) { k in row(k) }
            }

            if let c = pc.city {
                Section("Геопозиция") {
                    HStack {
                        Label("Вы в городе \(c)", systemImage: "mappin.and.ellipse")
                        Spacer()
                        if model.me?.city != c {
                            Button("Сделать моим") { Task { await setCity(c) } }.buttonStyle(.glass)
                        } else {
                            Image(systemName: "checkmark").foregroundStyle(Color.limeInk)
                        }
                    }
                }
            }

            if !pc.networkDevices.isEmpty {
                Section("Найдено в вашей сети") {
                    ForEach(pc.networkDevices, id: \.self) { Label($0, systemImage: "appletv.fill") }
                }
            }

            Section {
                Button { invite = true } label: { Label("Пригласить друзей из контактов", systemImage: "person.2.badge.plus") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Доступы")
        .navigationBarTitleDisplayMode(.inline)
        .task { await pc.refresh() }
        .onChange(of: phase) { if phase == .active { Task { await pc.refresh() } } }
        .sheet(isPresented: $invite) { ContactsInviteView() }
    }

    private func row(_ k: PermKind) -> some View {
        let st = pc.states[k] ?? .notAsked
        return Button {
            Task { await pc.request(k) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: k.icon)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(k.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.title).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(k.purpose).font(.caption).foregroundStyle(Color.oxHint).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Text(st.title).font(.system(size: 11, weight: .bold)).foregroundStyle(st.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(st.color.opacity(0.14), in: Capsule())
            }
        }
    }

    private func setCity(_ c: String) async {
        do {
            let _: OK = try await API.call("/me", method: "PATCH", body: ["city": c])
            await model.loadMe()
            OxHaptics.play(.setDone)
        } catch {
            OxAlert.error("Город «\(c)» пока не поддерживается каталогом. Выберите ближайший в профиле.")
        }
    }
}

// MARK: - Пригласить из контактов (контакты читаются только на телефоне)

struct ContactsInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var people: [Contact] = []
    struct Contact: Hashable { let name: String; let phone: String }
    @State private var query = ""
    @State private var denied = false

    private var link: String { "https://t.me/\(model.meta?.botUsername ?? "OxionBot")" }

    var body: some View {
        NavigationStack {
            List {
                if denied {
                    ContentUnavailableView {
                        Label("Нет доступа к контактам", systemImage: "person.crop.circle.badge.xmark")
                    } description: {
                        Text("Разрешите: Настройки → Oxion → Контакты. Или просто поделитесь ссылкой.")
                    } actions: {
                        Button("Как включить") { PermPrompt.show(.contacts, denied: true) }
                    }
                }
                Section {
                    ShareLink(item: URL(string: link)!, message: Text("Тренируюсь в OXION — присоединяйся!")) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                    }
                }
                Section {
                    ForEach(people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, id: \.phone) { p in
                        HStack {
                            Initials(name: p.name, size: 38)
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(p.phone).font(.caption).foregroundStyle(Color.oxHint)
                            }
                            Spacer()
                            Button("Пригласить") { sms(p.phone) }.buttonStyle(.glass)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Поиск по контактам")
            .navigationTitle("Пригласить друзей")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        let store = CNContactStore()
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        let st = CNContactStore.authorizationStatus(for: .contacts)
        guard st == .authorized || st == .limited else { denied = true; PermPrompt.show(.contacts, denied: true); return }
        let list: [(String, String)] = await Task.detached {
            var out: [(String, String)] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let req = CNContactFetchRequest(keysToFetch: keys)
            req.sortOrder = .givenName
            try? CNContactStore().enumerateContacts(with: req) { c, _ in
                if let ph = c.phoneNumbers.first?.value.stringValue {
                    let n = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
                    out.append((n.isEmpty ? ph : n, ph))
                }
            }
            return out
        }.value
        var seen = Set<String>()
        people = list.filter { seen.insert($0.1).inserted }.map { Contact(name: $0.0, phone: $0.1) }
    }

    private func sms(_ phone: String) {
        let body = "Привет! Тренируюсь в OXION — присоединяйся: \(link)"
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        var c = URLComponents()
        c.scheme = "sms"
        c.path = digits
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        if let u = c.url { UIApplication.shared.open(u) }
    }
}
