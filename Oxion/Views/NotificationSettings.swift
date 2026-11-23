import SwiftUI
import UserNotifications

// Настройки уведомлений прямо в приложении, как в Telegram. В «Настройки» iPhone ведём только если
// уведомления для Oxion запрещены в самой системе — включить их обратно приложение не может.

enum NotifPrefs {
    enum Kind: String, CaseIterable, Identifiable {
        case dm, groups, channels
        var id: String { rawValue }
        var title: String { self == .dm ? "Личные чаты" : self == .groups ? "Группы" : "Каналы" }
        var icon: String { self == .dm ? "person.fill" : self == .groups ? "person.3.fill" : "megaphone.fill" }
        var color: Color { self == .dm ? Color(hex: 0x2E8BFF) : self == .groups ? Color(hex: 0x34C759) : Color(hex: 0xF5A623) }
        static func of(_ c: ChatItem) -> Kind { c.peer.group == "channel" ? .channels : c.peer.group == "group" ? .groups : .dm }
    }

    private static func flag(_ k: String, _ def: Bool = true) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }

    static var all: Bool { flag("np.all") }
    static func isOn(_ k: Kind) -> Bool { flag("np." + k.rawValue) }
    static var preview: Bool { flag("np.preview") }
    static var names: Bool { flag("np.names") }
    static var badgeChannels: Bool { flag("np.badgeChannels") }
    static var badgeMessages: Bool { flag("np.badgeMessages") }

    /// число на иконке с учётом настроек «Каналы» и «Число сообщений»
    static func badge(_ items: [ChatItem]) -> Int {
        items.filter { $0.muted != true && $0.archived != true && (badgeChannels || $0.peer.group != "channel") }
            .reduce(0) { acc, c in
                let n = max(c.unread ?? 0, c.marked == true ? 1 : 0)
                return acc + (badgeMessages ? n : (n > 0 ? 1 : 0))
            }
    }

    /// отправить на сервер — он учитывает их для пушей и сообщений бота
    static func sync() async {
        let body: [String: Any] = ["notif_prefs": ["dm": isOn(.dm), "groups": isOn(.groups), "channels": isOn(.channels),
                                                   "preview": preview, "names": names]]
        let _: OK? = try? await API.call("/me", method: "PATCH", body: body)
    }

    static func reset() {
        for k in ["np.all", "np.dm", "np.groups", "np.channels", "np.preview", "np.names", "np.badgeChannels", "np.badgeMessages"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}

extension AppBadge {
    @MainActor static func update(_ items: [ChatItem]) { set(NotifPrefs.badge(items)) }
}

struct NotificationSettingsView: View {
    @Environment(ChatsStore.self) private var chats
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage("np.all") private var all = true
    @AppStorage("np.preview") private var preview = true
    @AppStorage("np.names") private var names = true
    @AppStorage("np.badgeChannels") private var badgeChannels = true
    @AppStorage("np.badgeMessages") private var badgeMessages = true
    @AppStorage("np.dm") private var dm = true
    @AppStorage("np.groups") private var groups = true
    @AppStorage("np.channels") private var channels = true
    @AppStorage("sounds") private var sounds = true
    @AppStorage("haptics") private var haptics = true
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                OxSettingsHeader(icon: "bell.badge.fill", tint: Color(hex: 0xFF5A4E), title: "Уведомления",
                                 text: "Выберите, о чём сообщать: личные сообщения, группы, каналы и тренировки. Без перехода в настройки iPhone.")
                    .oxHeaderRow()
            }
            if status != .authorized && status != .provisional && status != .ephemeral {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "bell.slash.fill").font(.title3).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Color(hex: 0xFF5A4E), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status == .denied ? "Уведомления запрещены в iOS" : "Уведомления ещё не разрешены").font(.headline)
                            Text(status == .denied ? "Без этого Oxion не сможет показывать уведомления" : "Разрешите, чтобы не пропускать сообщения")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(status == .denied ? "Открыть настройки iPhone" : "Разрешить уведомления") {
                        Task { await ask() }
                    }
                    .bold()
                }
            }

            Section {
                Toggle("Показывать уведомления", isOn: $all)
                    .onChange(of: all) { Task { let _: OK? = try? await API.call("/me", method: "PATCH", body: ["notify": all]) } }
            } footer: {
                Text("Выключите, чтобы Oxion совсем не присылал уведомления о сообщениях.")
            }

            Section("Уведомления о сообщениях") {
                ForEach(NotifPrefs.Kind.allCases) { k in
                    NavigationLink {
                        NotifKindView(kind: k, on: binding(k))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: k.icon).font(.subheadline).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(k.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(k.title)
                                let n = exceptions(k)
                                if n > 0 { Text(GroupText.exceptions(n)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(binding(k).wrappedValue ? "Вкл." : "Выкл.").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!all)
                }
                NavigationLink {
                    WorkoutNotifView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "dumbbell.fill").font(.subheadline).foregroundStyle(.black)
                            .frame(width: 32, height: 32).background(Color.lime, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Тренировки")
                            Text("Напоминания, отдых, рекорды").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Уведомления в приложении") {
                Toggle("Звук", isOn: $sounds)
                Toggle("Вибрация", isOn: $haptics)
                Toggle("Показывать текст", isOn: $preview)
            }

            Section {
                Toggle("Имена в уведомлениях", isOn: $names)
            } footer: {
                Text("Если выключить, на заблокированном экране вместо имени будет «Oxion», а вместо текста — «Новое сообщение».")
            }

            Section {
                Toggle("Каналы", isOn: $badgeChannels)
                Toggle("Число сообщений", isOn: $badgeMessages)
            } header: {
                Text("Счётчик на иконке")
            } footer: {
                Text("Когда выключено, счётчик показывает число непрочитанных чатов, а не число сообщений.")
            }

            Section {
                Button("Сбросить настройки уведомлений", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Вернуть всё как было и включить звук во всех чатах, где он выключен.")
            }
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: preview) { Task { await NotifPrefs.sync() } }
        .onChange(of: names) { Task { await NotifPrefs.sync() } }
        .onChange(of: dm) { Task { await NotifPrefs.sync() } }
        .onChange(of: groups) { Task { await NotifPrefs.sync() } }
        .onChange(of: channels) { Task { await NotifPrefs.sync() } }
        .onChange(of: badgeChannels) { AppBadge.update(chats.items) }
        .onChange(of: badgeMessages) { AppBadge.update(chats.items) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
        .confirmationDialog("Сбросить все настройки уведомлений?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { Task { await reset() } }
        }
    }

    private func binding(_ k: NotifPrefs.Kind) -> Binding<Bool> {
        switch k { case .dm: $dm; case .groups: $groups; case .channels: $channels }
    }

    private func exceptions(_ k: NotifPrefs.Kind) -> Int {
        chats.items.filter { NotifPrefs.Kind.of($0) == k && $0.muted == true }.count
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func ask() async {
        if status == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refresh()
        } else if let u = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(u)
        }
    }

    private func reset() async {
        NotifPrefs.reset()
        all = true; preview = true; names = true; badgeChannels = true; badgeMessages = true; dm = true; groups = true; channels = true
        for c in chats.items where c.muted == true { await chats.setMuted(c, false) }
        await NotifPrefs.sync()
        let _: OK? = try? await API.call("/me", method: "PATCH", body: ["notify": true])
        AppBadge.update(chats.items)
        Haptic.success()
    }
}

extension GroupText {
    static func exceptions(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        let w = m10 == 1 && m100 != 11 ? "исключение" : (2...4).contains(m10) && !(12...14).contains(m100) ? "исключения" : "исключений"
        return "\(n) \(w)"
    }
}

/// Личные / Группы / Каналы: общий переключатель и чаты-исключения (без звука)
struct NotifKindView: View {
    let kind: NotifPrefs.Kind
    @Binding var on: Bool
    @Environment(ChatsStore.self) private var chats
    @State private var adding = false

    private var muted: [ChatItem] { chats.items.filter { NotifPrefs.Kind.of($0) == kind && $0.muted == true } }
    private var others: [ChatItem] { chats.items.filter { NotifPrefs.Kind.of($0) == kind && $0.muted != true } }

    var body: some View {
        List {
            Section {
                Toggle("Показывать уведомления", isOn: $on)
            } footer: {
                Text(kind == .dm ? "Уведомления о новых сообщениях в личных чатах." : kind == .groups ? "Уведомления о новых сообщениях в группах." : "Уведомления о новых публикациях в каналах.")
            }
            Section {
                Button { adding = true } label: { Label("Добавить исключение", systemImage: "plus.circle.fill") }
                    .disabled(others.isEmpty)
                ForEach(muted) { c in
                    HStack(spacing: 12) {
                        if c.peer.group != nil {
                            GroupAvatar(photo: c.peer.photo, title: c.peer.name ?? "?", kind: c.peer.group, size: 36)
                        } else {
                            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 36)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.peer.name ?? "Чат")
                            Text("Без звука").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Включить") { Task { await chats.setMuted(c, false) } }.tint(Color(hex: 0x34C759))
                    }
                }
            } header: {
                Text("Исключения")
            } footer: {
                Text("В этих чатах уведомления выключены. Смахните влево, чтобы включить.")
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                List(others) { c in
                    Button {
                        Task { await chats.setMuted(c, true) }
                        adding = false
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 36)
                            Text(c.peer.name ?? "Чат").foregroundStyle(.primary)
                        }
                    }
                }
                .navigationTitle("Выключить звук")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { adding = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Уведомления о тренировках (локальные, считаются на телефоне)
struct WorkoutNotifView: View {
    @State private var states: [String: Bool] = [:]

    var body: some View {
        List {
            Section {
                ForEach(SmartNotify.Category.allCases) { c in
                    Toggle(isOn: Binding(get: { states[c.rawValue] ?? SmartNotify.isOn(c) },
                                         set: { v in states[c.rawValue] = v; SmartNotify.set(c, v) })) {
                        Label(c.title, systemImage: c.icon)
                    }
                }
            } footer: {
                Text("Эти уведомления Oxion составляет сам по вашему дневнику: напомнит о тренировке, конце отдыха и новых рекордах.")
            }
        }
        .navigationTitle("Тренировки")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await SmartNotify.reschedule() } }
    }
}
