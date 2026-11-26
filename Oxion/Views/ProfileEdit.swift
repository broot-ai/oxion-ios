import SwiftUI

// MARK: - «Мой профиль» как «Изменить профиль» в Telegram: без иконок, имя и «О себе» прямо в карточках

struct MyChannel: Decodable, Hashable, Identifiable {
    let id: Int
    let title: String
    let photo: String?
    var members: Int? = nil
    var `public`: Bool? = nil
}

struct EditMyProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var last = ""
    @State private var bio = ""
    @State private var loadedFrom: Int?
    @State private var saving = false
    @State private var editingCity = false
    @State private var avatarStudio = false
    @State private var showCard = false
    @FocusState private var focus: Field?

    enum Field { case first, last, bio }

    private var me: Me? { model.me }
    private var originalName: String { me?.displayName ?? "" }
    private var newName: String { [first, last].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ") }
    private var dirty: Bool { loadedFrom != nil && (newName != originalName || bio.trimmingCharacters(in: .whitespacesAndNewlines) != (me?.bio ?? "")) }

    var body: some View {
        List {
            if let me {
                Section {
                    VStack(spacing: 12) {
                        Button { avatarStudio = true } label: {
                            Avatar(url: API.media(me.photoUrl), name: me.displayName, size: 110)
                        }
                        .buttonStyle(.plain)
                        Button("Изменить фотографию") { avatarStudio = true }
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.limeInk)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }

                Section {
                    TextField("Имя", text: $first)
                        .focused($focus, equals: .first)
                        .textContentType(.givenName)
                        .submitLabel(.next)
                        .onSubmit { focus = .last }
                    TextField("Фамилия", text: $last)
                        .focused($focus, equals: .last)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                } footer: {
                    Text("Укажите имя и, если хотите, добавьте фотографию для вашего профиля.")
                }

                Section {
                    HStack(alignment: .top) {
                        TextField("О себе", text: $bio, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focus, equals: .bio)
                            .onChange(of: bio) { _, v in if v.count > 140 { bio = String(v.prefix(140)) } }
                        if focus == .bio || !bio.isEmpty {
                            Text("\(140 - bio.count)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                } footer: {
                    Text("Раздел «О себе» виден всем в вашем профиле.")
                }

                Section {
                    NavigationLink { PhoneSettingsView() } label: {
                        row("Номер", me.phone.map(Self.prettyPhone) ?? String(localized: "Указать"))
                    }
                    NavigationLink { UsernameSettingsView() } label: {
                        row("Имя пользователя", me.username.map { "@" + $0 } ?? String(localized: "Указать"))
                    }
                    NavigationLink { MyChannelPickerView() } label: {
                        HStack {
                            Text("Канал")
                            Spacer(minLength: 12)
                            if let c = me.channel {
                                HStack(spacing: 8) {
                                    Avatar(url: API.media(c.photo), name: c.title, size: 26)
                                    Text(c.title).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } else {
                                Text("Добавить").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { editingCity = true } label: {
                        HStack {
                            row("Город и цель", "\(me.city ?? String(localized: "Не указан")) · \(me.weekGoal ?? 3) " + String(localized: "в неделю"))
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Канал показывается в вашем профиле — так подписчики найдут ваши новости.")
                }

                Section("Как меня видят") {
                    NavigationLink { UserProfileView(userId: me.id) } label: { Text("Мой профиль в ленте") }
                    Button { showCard = true } label: {
                        HStack {
                            Text("Моя визитка и QR").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    if me.mode == "trainer" || me.hasTrainer == true {
                        NavigationLink { TrainerEditView() } label: { Text("Моя анкета тренера") }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Мой профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dirty {
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(saving || newName.count < 2)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { fill(force: true); focus = nil } label: { Image(systemName: "xmark") }
                }
            }
        }
        .onAppear { fill(force: false) }
        .onChange(of: model.me?.id) { fill(force: false) }
        .sheet(isPresented: $editingCity) { EditProfileSheet() }
        .fullScreenCover(isPresented: $avatarStudio) { AvatarStudio() }
        .fullScreenCover(isPresented: $showCard) { MyCardSheet() }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func fill(force: Bool) {
        guard let me, force || loadedFrom != me.id else { return }
        let parts = me.displayName.split(separator: " ", maxSplits: 1).map(String.init)
        first = parts.first ?? ""
        last = parts.count > 1 ? parts[1] : ""
        bio = me.bio ?? ""
        loadedFrom = me.id
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = [:]
        if newName != originalName { body["name"] = newName }
        let b = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if b != (me?.bio ?? "") { body["bio"] = b }
        do {
            let _: OK = try await API.call("/me", method: "PATCH", body: body)
            focus = nil
            Haptic.success()
            await model.loadMe()
            fill(force: true)
        } catch {
            Haptic.error()
            OxAlert.error(error.localizedDescription)
        }
    }

    static func prettyPhone(_ p: String) -> String {
        let d = p.filter(\.isNumber)
        guard d.count == 11, d.first == "7" || d.first == "8" else { return p }
        let a = Array(d)
        return "+7 \(String(a[1...3])) \(String(a[4...6])) \(String(a[7...8])) \(String(a[9...10]))"
    }
}

/// Выбор своего канала для профиля
struct MyChannelPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MyChannel] = []
    @State private var current: Int?
    @State private var loaded = false

    private struct R: Decodable { let current: Int?; let items: [MyChannel] }

    var body: some View {
        List {
            if !items.isEmpty {
                Section {
                    ForEach(items) { c in
                        Button { Task { await pick(c.id) } } label: {
                            HStack(spacing: 12) {
                                Avatar(url: API.media(c.photo), name: c.title, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).foregroundStyle(.primary)
                                    Text(c.public == false ? String(localized: "закрытый — нельзя показать в профиле")
                                         : "\(c.members ?? 0) " + RU.plural(c.members ?? 0, "подписчик", "подписчика", "подписчиков"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if current == c.id { Image(systemName: "checkmark").foregroundStyle(Color.limeInk).fontWeight(.bold) }
                            }
                        }
                        .disabled(c.public == false)
                    }
                } footer: {
                    Text("Канал появится в вашем профиле с аватаркой и названием. Показать можно только публичный канал, где вы владелец или администратор.")
                }
                if current != nil {
                    Section {
                        Button("Не показывать канал", role: .destructive) { Task { await pick(nil) } }
                    }
                }
            }
        }
        .overlay {
            if !loaded { ProgressView() }
            else if items.isEmpty {
                ContentUnavailableView("Нет своих каналов", systemImage: "megaphone",
                                       description: Text("Создайте канал: «Чаты» → ✎ → «Новый канал». Потом выберите его здесь."))
            }
        }
        .navigationTitle("Канал")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let r: R = try? await API.call("/me/channels") { items = r.items; current = r.current }
            loaded = true
        }
    }

    private func pick(_ id: Int?) async {
        do {
            let _: OK = try await API.call("/me", method: "PATCH", body: ["channel_id": id ?? 0])
            Haptic.success()
            current = id
            await model.loadMe()
            dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Канал в чужом/своём профиле: аватарка, название, переход в канал
struct ProfileChannelRow: View {
    let channel: MyChannel
    @State private var open: ChatRef?
    @State private var busy = false

    var body: some View {
        Button {
            Task {
                busy = true
                defer { busy = false }
                // вступаем, если ещё не подписаны (канал публичный)
                let _: GroupInfo? = try? await API.call("/chats/\(channel.id)/join", method: "POST")
                open = ChatRef(id: channel.id, name: channel.title)
            }
        } label: {
            HStack(spacing: 12) {
                Avatar(url: API.media(channel.photo), name: channel.title, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Канал").font(.caption).foregroundStyle(.secondary)
                    Text(channel.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                }
                Spacer()
                if busy { ProgressView() } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .navigationDestination(item: $open) { ChatView(chatId: $0.id, title: $0.name) }
    }
}
