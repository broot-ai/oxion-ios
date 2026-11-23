import SwiftUI
import CoreNFC
import GroupActivities

// MARK: - NFC check-in

struct CheckinResult: Decodable { let ok: Bool?; let `repeat`: Bool?; let place: String?; let city: String?; let total: Int?; let month: Int? }
struct CheckinItem: Decodable, Identifiable { let at: Double; let place: String?; let city: String?; var id: Double { at } }
struct CheckinList: Decodable { let items: [CheckinItem] }

/// Читает NDEF-метку клуба «oxion:<id>»; сама метка ничего не доказывает — посещение проверяет сервер
@MainActor
final class NFCReader: NSObject, NFCNDEFReaderSessionDelegate {
    var onTag: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private var session: NFCNDEFReaderSession?

    var available: Bool { NFCNDEFReaderSession.readingAvailable }

    func scan() {
        guard available else {
            onError?("NFC недоступен на этом устройстве или в тестовой версии приложения")
            return
        }
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = "Поднесите верх iPhone к метке OXION на входе в клуб"
        session?.begin()
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let e = error as NSError
        // 200 — пользователь сам закрыл окно, 204 — метка прочитана
        if e.code == 200 || e.code == 204 { return }
        let text = error.localizedDescription
        Task { @MainActor in self.onError?(text) }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for m in messages {
            for r in m.records {
                // метка-ссылка …/clip/tag/<id>: её же открывает App Clip у тех, у кого OXION не установлен
                if let u = r.wellKnownTypeURIPayload(), u.path.contains("/clip/tag/") {
                    let id = u.lastPathComponent
                    Task { @MainActor in self.onTag?("oxion:" + id) }
                    return
                }
                let (text, _) = r.wellKnownTypeTextPayload()
                if let t = text, t.lowercased().hasPrefix("oxion:") {
                    Task { @MainActor in self.onTag?(t) }
                    return
                }
            }
        }
        Task { @MainActor in self.onError?("Это не метка OXION") }
    }
}

struct NFCCheckInView: View {
    @Environment(AppModel.self) private var model
    @State private var reader = NFCReader()
    @State private var history: [CheckinItem] = []
    @State private var last: CheckinResult?
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(Color.lime.opacity(0.35), lineWidth: 2)
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulse ? 1.6 + Double(i) * 0.25 : 1)
                            .opacity(pulse ? 0 : 0.8)
                            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.4), value: pulse)
                    }
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.limeInk)
                }
                .frame(height: 220)
                Text("Отметка в клубе").font(.title.bold())
                Text("Приложите iPhone к метке OXION на входе. Посещение засчитается в статистику, а мы предложим начать тренировку.")
                    .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                Button {
                    reader.scan()
                } label: {
                    Label("Приложить iPhone", systemImage: "wave.3.right").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)

                if let r = last {
                    VStack(spacing: 6) {
                        Image(systemName: r.repeat == true ? "checkmark.circle" : "checkmark.seal.fill").font(.largeTitle).foregroundStyle(Color.limeInk)
                        Text(r.repeat == true ? "Вы уже отмечены" : "Посещение засчитано").font(.headline)
                        Text(r.place ?? "").foregroundStyle(Color.oxHint)
                        Text("В этом месяце: \(r.month ?? 0) · всего: \(r.total ?? 0)").font(.caption).foregroundStyle(Color.oxHint)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .oxCardBG(22)
                }

                if !history.isEmpty {
                    SectionCard(title: "История посещений") {
                        ForEach(history) { h in
                            HStack {
                                IconBubble(icon: "building.2.fill", size: 34)
                                VStack(alignment: .leading) {
                                    Text(h.place ?? "Клуб").font(.subheadline.bold())
                                    Text(Date(timeIntervalSince1970: h.at / 1000).formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(Color.oxHint)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("NFC check-in")
        .onAppear {
            pulse = true
            reader.onTag = { t in Task { await checkin(t) } }
            reader.onError = { e in
                OxAlert.show(icon: "wave.3.right.circle", tint: Color(hex: 0xF0A030), title: "Метка не прочитана",
                             message: e + "\n\nВ тестовой установке чтение NFC закрыто Apple — оно включится в версии с аккаунтом разработчика ($99).")
            }
        }
        .task { await loadHistory() }
    }

    private func checkin(_ tag: String) async {
        do {
            let r: CheckinResult = try await API.call("/checkin", method: "POST", body: ["tag": tag])
            last = r
            OxHaptics.play(r.repeat == true ? .select : .record)
            await loadHistory()
            if r.repeat != true {
                OxAlert.show(icon: "figure.strengthtraining.traditional", title: "Вы в клубе \(r.place ?? "")!", message: "Начать тренировку?",
                             buttons: [OxAlertButton(title: "Начать", role: .primary) { model.handle(route: "diary") },
                                       OxAlertButton(title: "Позже", role: .cancel)])
            }
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func loadHistory() async {
        if let r: CheckinList = try? await API.call("/checkin") { history = r.items }
    }
}

/// Для владельцев: создать метку клуба и записать её через любое приложение для NFC (например, NFC Tools)
struct NFCTagsAdminView: View {
    struct Tag: Decodable, Identifiable { let id: String; let name: String?; let city: String?; let visits: Int?; let payload: String }
    struct Tags: Decodable { let items: [Tag] }
    @State private var items: [Tag] = []
    @State private var name = ""

    var body: some View {
        List {
            Section {
                TextField("Название клуба", text: $name)
                Button("Создать метку") { Task { await create() } }.disabled(name.count < 2)
            } footer: {
                Text("Скопируйте текст «oxion:…» и запишите его на NFC-метку как текстовую запись (приложение NFC Tools). Метка хранит только случайный номер — посещение проверяет сервер, повтор в течение 4 часов не засчитывается.")
            }
            Section("Метки") {
                ForEach(items) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name ?? "").font(.headline)
                        Text(t.payload).font(.caption.monospaced()).foregroundStyle(Color.limeInk).textSelection(.enabled)
                        Text("Посещений: \(t.visits ?? 0)").font(.caption).foregroundStyle(Color.oxHint)
                    }
                    .contextMenu { Button("Скопировать") { UIPasteboard.general.string = t.payload } }
                }
            }
        }
        .navigationTitle("NFC-метки клубов")
        .task { await load() }
    }

    private func load() async { if let r: Tags = try? await API.call("/checkin/tags") { items = r.items } }
    private func create() async {
        do {
            let _: Tag = try await API.call("/checkin/tags", method: "POST", body: ["name": name])
            name = ""
            await load()
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - SharePlay: совместная тренировка

struct OxionWorkoutActivity: GroupActivity {
    var title: String
    var workoutId: Int

    static let activityIdentifier = "ru.oxion.app.workout-together"

    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = "Тренировка в OXION: \(title)"
        m.subtitle = "Тренируемся вместе"
        m.type = .workoutTogether
        return m
    }
}

struct SharePlayView: View {
    @State private var engine = WorkoutEngine.shared
    @State private var starting = false

    private var title: String { engine.state?.title ?? "Совместная тренировка" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.lime.opacity(0.12)).frame(width: 150, height: 150)
                    Image(systemName: "shareplay").font(.system(size: 60)).foregroundStyle(Color.limeInk)
                }
                Text("Тренируйтесь вместе").font(.title.bold())
                Text("Создайте комнату в FaceTime: друзья увидят ваши подходы, а вы — их. Соревнуйтесь по количеству подходов и смотрите общие итоги.")
                    .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    participant("Вы", progress: engine.state.map { Double($0.setsDoneAll) / Double(max(1, $0.setsTotalAll)) } ?? 0,
                                detail: engine.state.map { "\($0.setsDoneAll)/\($0.setsTotalAll) подходов" } ?? "тренировка не начата")
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.title2).foregroundStyle(Color.oxHint)
                        Text("Друзья появятся здесь, когда подключатся").font(.subheadline).foregroundStyle(Color.oxHint)
                        Spacer()
                    }
                    .padding(14)
                    .oxCardBG(18)
                }

                Button {
                    Task { await start() }
                } label: {
                    HStack {
                        if starting { ProgressView() }
                        Label("Создать комнату SharePlay", systemImage: "shareplay")
                    }
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)

                ShareLink(item: AppSettings.serverURL.absoluteString + "/#challenges",
                          message: Text("Давай тренироваться вместе в OXION 💪")) {
                    Label("Пригласить без FaceTime", systemImage: "link").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)

                Text("Если связь у кого-то пропала, его прогресс догонит при переподключении: подходы хранятся на телефоне и на сервере OXION.")
                    .font(.caption).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("SharePlay")
    }

    private func participant(_ name: String, progress: Double, detail: String) -> some View {
        HStack(spacing: 12) {
            Initials(name: name, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(name).font(.headline); Spacer(); Text(detail).font(.caption).foregroundStyle(Color.oxHint) }
                ProgressView(value: progress).tint(Color.lime)
            }
        }
        .padding(14)
        .oxCardBG(18)
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let act = OxionWorkoutActivity(title: title, workoutId: engine.state?.workoutId ?? 0)
        switch await act.prepareForActivation() {
        case .activationPreferred:
            do { _ = try await act.activate() } catch { failed(error.localizedDescription) }
        case .activationDisabled:
            failed("SharePlay выключен в настройках FaceTime")
        case .cancelled:
            break
        @unknown default:
            failed("SharePlay недоступен")
        }
    }

    private func failed(_ text: String) {
        OxAlert.show(icon: "shareplay.slash", tint: Color(hex: 0xF0A030), title: "SharePlay пока недоступен",
                     message: text + "\n\nСовместные тренировки через FaceTime включатся в версии с аккаунтом разработчика Apple ($99). Пока можно пригласить друга ссылкой.")
    }
}

/// Буква-аватар (для превью без фото)
struct Initials: View {
    let name: String
    var size: CGFloat = 36
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Color.limeInk)
            .frame(width: size, height: size)
            .background(Color.lime.opacity(0.18), in: Circle())
    }
}
