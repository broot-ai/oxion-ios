import SwiftUI
import PhotosUI

// «Написать сообщение» как в Telegram: поиск людей, создание группы, контакта по номеру и канала.

private struct IdResp: Decodable { let id: Int }

@MainActor
enum NewChatAPI {
    static func openUser(_ id: Int) async -> Int? {
        do {
            let r: IdResp = try await API.call("/chats/open", method: "POST", body: ["user_id": id])
            return r.id
        } catch { OxAlert.error(error.localizedDescription); return nil }
    }

    static func create(kind: String, title: String, about: String, members: [Int], photo: UIImage?) async -> GroupInfo? {
        do {
            var g: GroupInfo = try await API.call("/chats/group", method: "POST",
                                                  body: ["kind": kind, "title": title, "about": about, "members": members])
            if let photo, let jpg = API.jpeg(photo) {
                if let g2: GroupInfo = try? await API.upload("/chats/\(g.id)/photo", data: jpg) { g = g2 }
            }
            Haptic.success()
            return g
        } catch { OxAlert.error(error.localizedDescription); return nil }
    }
}

// MARK: - Главный экран

struct NewMessageSheet: View {
    var onOpen: (ChatRef) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    @State private var contacts: [Contact] = []
    @State private var found: [Contact] = []
    @State private var foundChats: [ContactChat] = []
    @State private var q = ""
    @State private var loaded = false
    @AppStorage("ox.newchat.sort") private var sort = "seen"

    enum Route: Hashable { case group, contact, channel }

    private var searching: Bool { !q.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                List {
                    if !searching {
                        Section {
                            action("Создать группу", "person.2") { path.append(.group) }
                            action("Создать контакт", "person.badge.plus") { path.append(.contact) }
                            action("Создать канал", "megaphone") { path.append(.channel) }
                        }
                        if sort == "name" {
                            ForEach(sections, id: \.0) { sec in
                                Section {
                                    ForEach(Array(sec.1.enumerated()), id: \.element.id) { i, c in
                                        contactRow(c).id(i == 0 ? "sec-\(sec.0)" : "c\(c.id)")
                                    }
                                } header: { Text(sec.0).font(.subheadline.bold()) }
                            }
                        } else {
                            Section {
                                ForEach(sortedBySeen) { c in contactRow(c) }
                            } header: {
                                if !contacts.isEmpty { Text("Недавно в сети") }
                            }
                        }
                        if loaded && contacts.isEmpty {
                            Text("Здесь появятся люди, с которыми вы переписывались или на которых подписаны. Найдите кого-нибудь через поиск.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        if !foundChats.isEmpty {
                            Section("Группы и каналы") {
                                ForEach(foundChats) { c in chatRow(c) }
                            }
                        }
                        Section(found.isEmpty ? "" : "Люди") {
                            ForEach(found) { c in contactRow(c) }
                            if found.isEmpty && foundChats.isEmpty {
                                Text("Никого не нашлось").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay(alignment: .trailing) {
                    if sort == "name" && !searching && sections.count > 3 {
                        AlphabetIndex(letters: sections.map(\.0)) { l in
                            proxy.scrollTo("sec-\(l)", anchor: .top)
                        }
                        .padding(.trailing, 2)
                    }
                }
            }
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
            .navigationTitle("Написать сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Сортировка", selection: $sort.animation(.smooth(duration: 0.25))) {
                            Text("по времени захода").tag("seen")
                            Text("по имени").tag("name")
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .task { await loadContacts() }
            .task(id: q) {
                guard searching else { found = []; foundChats = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                await search()
            }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .group:
                    GroupPickView(kind: "group", contacts: contacts) { g in finish(g) }
                case .contact:
                    CreateContactView { c in Task { await openUser(c.id, c.name) } }
                case .channel:
                    ChannelIntroView(contacts: contacts) { g in finish(g) }
                }
            }
        }
    }

    // MARK: данные

    private var sortedBySeen: [Contact] { contacts.sorted { ($0.lastSeen ?? 0) > ($1.lastSeen ?? 0) } }

    private var sections: [(String, [Contact])] {
        let sorted = contacts.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        var out: [(String, [Contact])] = []
        for c in sorted {
            let f = (c.name ?? "#").trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "#"
            let key = f.rangeOfCharacter(from: .letters) != nil ? f : "#"
            if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1.append(c) } else { out.append((key, [c])) }
        }
        return out
    }

    private func loadContacts() async {
        if let r: ContactsResponse = try? await API.call("/contacts") {
            withAnimation(.smooth(duration: 0.25)) { contacts = r.items }
        }
        loaded = true
    }

    private func search() async {
        guard let r: ContactsResponse = try? await API.call("/contacts", query: ["q": q]) else { return }
        withAnimation(.smooth(duration: 0.2)) {
            found = r.items
            foundChats = r.chats ?? []
        }
    }

    private func openUser(_ id: Int, _ name: String?) async {
        if let cid = await NewChatAPI.openUser(id) {
            Haptic.tap(.soft)
            dismiss()
            onOpen(ChatRef(id: cid, name: name ?? "Чат"))
        }
    }

    private func finish(_ g: GroupInfo) {
        dismiss()
        onOpen(ChatRef(id: g.id, name: g.title ?? "Группа"))
    }

    // MARK: строки

    private func action(_ title: String, _ icon: String, go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Label {
                Text(title).foregroundStyle(Color.limeInk)
            } icon: {
                Image(systemName: icon).foregroundStyle(Color.limeInk)
            }
        }
    }

    private func contactRow(_ c: Contact) -> some View {
        Button { Task { await openUser(c.id, c.name) } } label: {
            HStack(spacing: 12) {
                Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.name ?? "Пользователь").font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(PeerStatus.text(c.lastSeen))
                        .font(.caption)
                        .foregroundStyle(PeerStatus.online(c.lastSeen) ? Color.limeInk : Color.secondary)
                }
            }
        }
    }

    private func chatRow(_ c: ContactChat) -> some View {
        Button {
            Task {
                if c.joined != true {
                    do { let _: GroupInfo = try await API.call("/chats/\(c.id)/join", method: "POST") }
                    catch { OxAlert.error(error.localizedDescription); return }
                }
                dismiss()
                onOpen(ChatRef(id: c.id, name: c.title ?? "Канал"))
            }
        } label: {
            HStack(spacing: 12) {
                GroupAvatar(photo: c.photo, title: c.title ?? "?", kind: c.kind, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title ?? "").font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(GroupText.count(c.members ?? 0, channel: c.kind == "channel")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if c.joined != true {
                    Text(c.kind == "channel" ? "Подписаться" : "Вступить").font(.caption.bold()).foregroundStyle(Color.limeInk)
                }
            }
        }
    }
}

// MARK: - Алфавит справа

struct AlphabetIndex: View {
    let letters: [String]
    var onPick: (String) -> Void
    @State private var last: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { l in
                    Text(l)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.limeInk)
                        .frame(width: 18, height: min(16, geo.size.height / CGFloat(max(1, letters.count))))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let rowH = min(16, geo.size.height / CGFloat(max(1, letters.count)))
                let top = (geo.size.height - rowH * CGFloat(letters.count)) / 2
                let i = Int(floor((v.location.y - top) / rowH))
                guard letters.indices.contains(i), letters[i] != last else { return }
                last = letters[i]
                Haptic.tap(.soft)
                onPick(letters[i])
            }.onEnded { _ in last = nil })
        }
        .frame(width: 20)
        .padding(.vertical, 60)
    }
}

// MARK: - Аватарка группы/канала

struct GroupAvatar: View {
    let photo: String?
    let title: String
    let kind: String?
    var size: CGFloat = 44
    var body: some View {
        if let u = API.media(photo) {
            RemoteImage(url: u)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(LinearGradient(colors: kind == "channel" ? [Color(hex: 0x5AC8FA), Color(hex: 0x007AFF)] : [Color(hex: 0xC6F94A), Color(hex: 0x22B8A6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(title.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

enum GroupText {
    static func count(_ n: Int, channel: Bool) -> String {
        let m10 = n % 10, m100 = n % 100
        let one = m10 == 1 && m100 != 11
        let few = (2...4).contains(m10) && !(12...14).contains(m100)
        if channel { return "\(n) " + (one ? "подписчик" : few ? "подписчика" : "подписчиков") }
        return "\(n) " + (one ? "участник" : few ? "участника" : "участников")
    }
}

// MARK: - Создать контакт (поиск по номеру)

struct CreateContactView: View {
    var onFound: (Contact) -> Void
    @State private var first = ""
    @State private var last = ""
    @State private var phone = ""
    @State private var busy = false
    @FocusState private var focus: Int?

    var body: some View {
        Form {
            Section {
                TextField("Имя", text: $first).focused($focus, equals: 0)
                TextField("Фамилия", text: $last).focused($focus, equals: 1)
            }
            Section {
                HStack {
                    Text("🇷🇺 Россия")
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text("+7").foregroundStyle(.secondary)
                    TextField("000 000 0000", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focus, equals: 2)
                        .onChange(of: phone) { phone = Self.format(phone) }
                }
            } footer: {
                Text("Если человек уже в Oxion, сразу откроется переписка с ним.")
            }
            Section {
                Button { PendingRoute.go("qr") } label: {
                    Label("Добавить по QR-коду", systemImage: "qrcode")
                }
            }
        }
        .navigationTitle("Новый контакт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await find() } } label: {
                    if busy { ProgressView() } else { Image(systemName: "checkmark") }
                }
                .buttonStyle(.glassProminent)
                .disabled(digits.count < 10 || busy)
            }
        }
        .onAppear { focus = 2 }
    }

    private var digits: String { phone.filter(\.isNumber) }

    static func format(_ s: String) -> String {
        let d = String(s.filter(\.isNumber).prefix(10))
        var out = ""
        for (i, ch) in d.enumerated() {
            if i == 3 || i == 6 { out += " " }
            out.append(ch)
        }
        return out
    }

    private func find() async {
        busy = true
        defer { busy = false }
        do {
            let c: Contact = try await API.call("/contacts/phone", method: "POST", body: ["phone": "7" + digits])
            Haptic.success()
            onFound(c)
        } catch {
            OxAlert.show(icon: "person.crop.circle.badge.questionmark", title: "Не найден", message: error.localizedDescription)
        }
    }
}

// MARK: - Выбор участников

struct GroupPickView: View {
    let kind: String
    let contacts: [Contact]
    var title = ""
    var about = ""
    var photo: UIImage? = nil
    var onDone: (GroupInfo) -> Void
    @State private var picked: [Contact] = []
    @State private var q = ""
    @State private var found: [Contact] = []
    @State private var creating = false
    @State private var goNext = false

    private var isChannel: Bool { kind == "channel" }
    private var list: [Contact] {
        let s = q.trimmingCharacters(in: .whitespaces)
        let base = s.isEmpty ? contacts : (found.isEmpty ? contacts.filter { ($0.name ?? "").localizedCaseInsensitiveContains(s) } : found)
        return base.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            // выбранные — капсулами сверху, как в Telegram
            if !picked.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(picked) { c in
                            Button { toggle(c) } label: {
                                HStack(spacing: 5) {
                                    Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 22)
                                    Text(c.name ?? "").font(.caption.weight(.semibold)).lineLimit(1)
                                    Image(systemName: "xmark").font(.caption2.bold())
                                }
                                .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
                                .background(Color.lime.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            List(list) { c in
                Button { toggle(c) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: picked.contains(c) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(picked.contains(c) ? Color.limeInk : Color.secondary.opacity(0.5))
                            .contentTransition(.symbolEffect(.replace))
                        Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name ?? "Пользователь").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(PeerStatus.text(c.lastSeen)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Кого вы хотите пригласить?")
        .task(id: q) {
            let s = q.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { found = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            if let r: ContactsResponse = try? await API.call("/contacts", query: ["q": s]) { found = r.items }
        }
        .navigationTitle(isChannel ? "Подписчики" : "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(isChannel ? "Подписчики" : "Группа").font(.headline)
                    Text("\(picked.count)/200").font(.caption2).foregroundStyle(.secondary).contentTransition(.numericText())
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isChannel ? (picked.isEmpty ? "Пропустить" : "Создать") : "Далее") {
                    if isChannel { Task { await createChannel() } } else { goNext = true }
                }
                .bold()
                .disabled((!isChannel && picked.isEmpty) || creating)
            }
        }
        .navigationDestination(isPresented: $goNext) {
            GroupFormView(kind: "group", members: picked, onDone: onDone)
        }
        .animation(.smooth(duration: 0.25), value: picked)
    }

    private func toggle(_ c: Contact) {
        Haptic.tap(.soft)
        if let i = picked.firstIndex(of: c) { picked.remove(at: i) } else if picked.count < 199 { picked.append(c) }
    }

    private func createChannel() async {
        creating = true
        defer { creating = false }
        if let g = await NewChatAPI.create(kind: "channel", title: title, about: about, members: picked.map(\.id), photo: photo) { onDone(g) }
    }
}

// MARK: - Название, фото, описание

struct GroupFormView: View {
    let kind: String
    var members: [Contact] = []
    var onDone: (GroupInfo) -> Void
    @State private var title = ""
    @State private var about = ""
    @State private var photo: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var creating = false
    @State private var next = false
    @FocusState private var focused: Bool

    private var isChannel: Bool { kind == "channel" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $pick, matching: .images) {
                        ZStack {
                            if let photo {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                Color.lime.opacity(0.18)
                                Image(systemName: "camera.fill").font(.title3).foregroundStyle(Color.limeInk)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    }
                    TextField(isChannel ? "Название канала" : "Название группы", text: $title)
                        .font(.title3)
                        .focused($focused)
                        .onChange(of: title) { if title.count > 64 { title = String(title.prefix(64)) } }
                }
            }
            if isChannel {
                Section {
                    TextField("Описание", text: $about, axis: .vertical).lineLimit(2...5)
                } footer: {
                    Text("Можете указать дополнительное описание канала.")
                }
            } else if !members.isEmpty {
                Section(GroupText.count(members.count + 1, channel: false)) {
                    ForEach(members) { c in
                        HStack(spacing: 12) {
                            Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 34)
                            Text(c.name ?? "")
                        }
                    }
                }
            }
        }
        .navigationTitle(isChannel ? "Создать канал" : "Новая группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isChannel ? "Далее" : "Создать") {
                    if isChannel { next = true } else { Task { await create() } }
                }
                .bold()
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
        }
        .navigationDestination(isPresented: $next) {
            GroupPickView(kind: "channel", contacts: ChannelContacts.shared.list,
                          title: title.trimmingCharacters(in: .whitespaces), about: about, photo: photo, onDone: onDone)
        }
        .onChange(of: pick) {
            Task {
                if let d = try? await pick?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    withAnimation { photo = img }
                }
            }
        }
        .onAppear { focused = true }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        if let g = await NewChatAPI.create(kind: kind, title: title.trimmingCharacters(in: .whitespaces), about: about,
                                           members: members.map(\.id), photo: photo) { onDone(g) }
    }
}

/// список контактов для шага «подписчики» канала (передаём с первого экрана)
@MainActor final class ChannelContacts {
    static let shared = ChannelContacts()
    var list: [Contact] = []
}

// MARK: - «Что такое канал?»

struct ChannelIntroView: View {
    let contacts: [Contact]
    var onDone: (GroupInfo) -> Void
    @State private var go = false
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 150, height: 230)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 2))
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0x007AFF)], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: bounce)
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0x007AFF)).frame(width: 22, height: 22)
                        .overlay(Image(systemName: "dumbbell.fill").font(.system(size: 10)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Канал").font(.caption2.bold())
                        Text("2 480 подписчиков").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .offset(x: -50, y: -96)
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 72, y: -20)
            }
            Text("Что такое канал?").font(.title2.bold())
            Text("Каналы — инструмент, который позволяет транслировать сообщения на большую аудиторию: тренировки, советы, новости зала.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button { go = true } label: {
                Text("Создать канал").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $go) { GroupFormView(kind: "channel", onDone: onDone) }
        .onAppear {
            ChannelContacts.shared.list = contacts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { bounce.toggle() }
        }
    }
}

// MARK: - Информация о группе/канале

struct GroupInfoView: View {
    let chatId: Int
    var onLeft: () -> Void = {}
    @State private var info: GroupInfo?
    @State private var adding = false
    @State private var editing = false
    @State private var pick: PhotosPickerItem?
    @State private var contacts: [Contact] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let g = info {
                Section {
                    VStack(spacing: 10) {
                        GroupAvatar(photo: g.photo, title: g.title ?? "?", kind: g.kind, size: 96)
                            .overlay(alignment: .bottomTrailing) {
                                if g.canEdit == true {
                                    PhotosPicker(selection: $pick, matching: .images) {
                                        Image(systemName: "camera.fill").font(.caption).padding(7)
                                            .background(.regularMaterial, in: Circle())
                                    }
                                }
                            }
                        Text(g.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(GroupText.count(g.membersCount ?? 0, channel: g.isChannel)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                if let a = g.about, !a.isEmpty {
                    Section("Описание") { Text(a) }
                }
                if g.canEdit == true || !g.isChannel {
                    Section {
                        Button { adding = true } label: {
                            Label(g.isChannel ? "Добавить подписчиков" : "Добавить участников", systemImage: "person.badge.plus")
                        }
                        if g.canEdit == true {
                            Button { editing = true } label: { Label("Изменить", systemImage: "pencil") }
                        }
                    }
                }
                if let ms = g.members, !ms.isEmpty {
                    Section(g.isChannel ? "Подписчики" : "Участники") {
                        ForEach(ms) { u in
                            HStack(spacing: 12) {
                                Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.name ?? "").font(.body.weight(.semibold))
                                    Text(PeerStatus.text(u.lastSeen)).font(.caption)
                                        .foregroundStyle(PeerStatus.online(u.lastSeen) ? Color.limeInk : Color.secondary)
                                }
                                Spacer()
                                if u.role == "owner" { Text("владелец").font(.caption).foregroundStyle(.secondary) }
                                else if u.role == "admin" { Text("админ").font(.caption).foregroundStyle(.secondary) }
                            }
                            .swipeActions {
                                if g.canEdit == true && u.role != "owner" {
                                    Button(role: .destructive) { Task { await remove(u) } } label: { Label("Удалить", systemImage: "person.badge.minus") }
                                    if g.role == "owner" {
                                        Button { Task { await setAdmin(u, u.role != "admin") } } label: {
                                            Label(u.role == "admin" ? "Снять админа" : "Сделать админом", systemImage: "star")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        OxAlert.confirm(icon: "rectangle.portrait.and.arrow.right", title: g.isChannel ? "Покинуть канал?" : "Покинуть группу?",
                                        message: "Переписка исчезнет из списка чатов", action: "Покинуть", destructive: true) {
                            Task { await leave() }
                        }
                    } label: { Label(g.isChannel ? "Покинуть канал" : "Покинуть группу", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .navigationTitle(info?.isChannel == true ? "Канал" : "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                GroupAddMembersView(chatId: chatId, existing: Set(info?.members?.map(\.id) ?? [])) { g in info = g }
            }
        }
        .sheet(isPresented: $editing) {
            if let g = info { GroupEditSheet(info: g) { info = $0 } }
        }
        .onChange(of: pick) {
            Task {
                guard let d = try? await pick?.loadTransferable(type: Data.self), let img = UIImage(data: d), let jpg = API.jpeg(img) else { return }
                do { info = try await API.upload("/chats/\(chatId)/photo", data: jpg); Haptic.success() }
                catch { OxAlert.error(error.localizedDescription) }
            }
        }
    }

    private func load() async {
        do { info = try await API.call("/chats/\(chatId)/info") } catch { OxAlert.error(error.localizedDescription) }
    }
    private func remove(_ u: GMember) async {
        do { info = try await API.call("/chats/\(chatId)/members/\(u.id)", method: "DELETE") } catch { OxAlert.error(error.localizedDescription) }
    }
    private func setAdmin(_ u: GMember, _ v: Bool) async {
        do { info = try await API.call("/chats/\(chatId)/members/\(u.id)", method: "PATCH", body: ["admin": v]); Haptic.success() }
        catch { OxAlert.error(error.localizedDescription) }
    }
    private func leave() async {
        do {
            let _: OK = try await API.call("/chats/\(chatId)/leave", method: "POST")
            Haptic.success()
            onLeft()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

struct GroupAddMembersView: View {
    let chatId: Int
    let existing: Set<Int>
    var onDone: (GroupInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [Contact] = []
    @State private var picked = Set<Int>()
    @State private var q = ""
    @State private var found: [Contact] = []

    private var list: [Contact] {
        (q.isEmpty ? contacts : found).filter { !existing.contains($0.id) }
    }

    var body: some View {
        List(list) { c in
            Button {
                if picked.contains(c.id) { picked.remove(c.id) } else { picked.insert(c.id) }
                Haptic.tap(.soft)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(picked.contains(c.id) ? Color.limeInk : Color.secondary.opacity(0.5))
                    Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 38)
                    Text(c.name ?? "").foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
        .task { if let r: ContactsResponse = try? await API.call("/contacts") { contacts = r.items } }
        .task(id: q) {
            guard !q.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            if let r: ContactsResponse = try? await API.call("/contacts", query: ["q": q]) { found = r.items }
        }
        .navigationTitle("Добавить")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") {
                    Task {
                        do {
                            let g: GroupInfo = try await API.call("/chats/\(chatId)/members", method: "POST", body: ["ids": Array(picked)])
                            Haptic.success()
                            onDone(g)
                            dismiss()
                        } catch { OxAlert.error(error.localizedDescription) }
                    }
                }
                .bold()
                .disabled(picked.isEmpty)
            }
        }
    }
}

struct GroupEditSheet: View {
    let info: GroupInfo
    var onSaved: (GroupInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var isPublic = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Название", text: $title) }
                Section("Описание") { TextField("Описание", text: $about, axis: .vertical).lineLimit(2...5) }
                Section {
                    Toggle(info.isChannel ? "Публичный канал" : "Публичная группа", isOn: $isPublic)
                } footer: {
                    Text("Публичные находятся в поиске «Написать сообщение», вступить может любой.")
                }
            }
            .navigationTitle("Изменить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task {
                            do {
                                let g: GroupInfo = try await API.call("/chats/\(info.id)/info", method: "PATCH",
                                                                      body: ["title": title, "about": about, "public": isPublic])
                                Haptic.success()
                                onSaved(g)
                                dismiss()
                            } catch { OxAlert.error(error.localizedDescription) }
                        }
                    }
                    .bold()
                }
            }
            .onAppear { title = info.title ?? ""; about = info.about ?? ""; isPublic = info.public == true }
        }
    }
}
