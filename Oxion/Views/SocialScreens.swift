import SwiftUI
import PhotosUI

// MARK: - Профиль человека в ленте

struct UserProfileView: View {
    let userId: Int
    @Environment(AppModel.self) private var model
    @State private var u: FUser?
    @State private var tab = "posts"
    @State private var posts: [FeedItem] = []
    @State private var errorText: String?
    @State private var route: FeedRoute?
    @Environment(\.feedPush) private var feedPush
    /// внутри вкладки «Лента» — пушим в общий стек, иначе — в свой
    private func go(_ r: FeedRoute) { if let feedPush { feedPush(r) } else { route = r } }
    @State private var chat: ChatRef?
    @State private var compose: ComposeRequest?
    @State private var showCard = false
    @State private var showNote = false
    @State private var showBio = false
    @State private var photoPick: PhotosPickerItem?
    @State private var showPhotoPick = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let u {
                    header(u)
                    UnderlineTabs(tabs: [("posts", "Ветки"), ("replies", "Ответы"), ("media", "Медиа"), ("reposts", "Репосты")], selection: $tab)
                        .padding(.top, 4)
                    if u.me == true, tab == "posts", let todo = u.todo {
                        ProfileTodoCards(todo: todo) { key in
                            switch key {
                            case "post": compose = ComposeRequest()
                            case "photo": showPhotoPick = true
                            case "bio": showBio = true
                            default: go(.search)
                            }
                        }
                    }
                    if let pin = u.pinned, tab == "posts" {
                        Label("Закреплено", systemImage: "pin.fill").font(.caption).foregroundStyle(Color.oxHint).padding(.horizontal, 16)
                        ThreadPost(post: pin, onOpen: { go(.post(pin.id)) }, onUser: { if $0 != userId { go(.user($0)) } }, onCompose: { compose = $0 })
                        Divider().overlay(Color.primary.opacity(0.06))
                    }
                    if posts.isEmpty {
                        Text("Пока ничего нет").foregroundStyle(Color.oxHint).frame(maxWidth: .infinity).padding(40)
                    }
                    ForEach(posts) { item in
                        ThreadPost(post: item.post,
                                   onOpen: { go(.post(item.post.chainOf ?? item.post.id)) },
                                   onUser: { if $0 != userId { go(.user($0)) } },
                                   onChange: { change in
                                       for i in posts.indices where posts[i].post.id == item.post.id { change(&posts[i].post) }
                                   },
                                   onRemove: { posts.removeAll { $0.post.id == item.post.id } },
                                   onCompose: { compose = $0 })
                            .reassemblesRow()
                        Divider().overlay(Color.primary.opacity(0.06))
                    }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
        }
        .background(Color.oxBg)
        .navigationTitle(u?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
        .sheet(item: $compose) { ComposerView(request: $0) { _ in Task { await loadPosts() } } }
        .onReceive(NotificationCenter.default.publisher(for: .oxPostDeleted)) { n in
            guard let id = n.object as? Int else { return }
            withAnimation(.smooth(duration: 0.3)) { posts.removeAll { $0.post.id == id || $0.post.chainOf == id } }
        }
        .fullScreenCover(isPresented: $showCard) { MyCardSheet() }
        .sheet(isPresented: $showNote) { NoteComposerSheet(current: u?.note) { nu in withAnimation(.smooth(duration: 0.3)) { u = nu } } }
        .sheet(isPresented: $showBio) { BioEditSheet(current: u?.bio ?? "") { nu in withAnimation(.smooth(duration: 0.3)) { u = nu } } }
        .photosPicker(isPresented: $showPhotoPick, selection: $photoPick, matching: .images)
        .onChange(of: photoPick) { Task { await uploadPhoto() } }
        .toolbar {
            if let u, model.me?.admin == true {
                ToolbarItem(placement: .topBarTrailing) {
                    OfficialAdminMenu(userId: u.id, current: u.official) { o in
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { self.u?.official = o }
                    }
                }
            }
            if let u, u.me != true {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await toggle("notify", true) } } label: { Label("Уведомлять о новых ветках", systemImage: "bell") }
                        Button { Task { await toggle("mute", !(u.muted ?? false)) } } label: {
                            Label(u.muted == true ? "Показывать в ленте" : "Скрыть из ленты", systemImage: "speaker.slash")
                        }
                        Button(role: .destructive) {
                            OxAlert.confirm(icon: "hand.raised.fill", title: u.blocked == true ? "Разблокировать?" : "Заблокировать \(u.name ?? "")?",
                                            action: u.blocked == true ? "Разблокировать" : "Заблокировать", destructive: u.blocked != true) {
                                Task { await toggle("block", !(u.blocked ?? false)) }
                            }
                        } label: { Label(u.blocked == true ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised") }
                        ShareLink(item: (u.username.map { ProfileLink.string($0) } ?? AppSettings.serverURL.absoluteString + "/#u/\(u.id)")) { Label("Поделиться профилем", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onChange(of: tab) { Task { await loadPosts() } }
        .oxRefreshable { await load() }
        .task { await load() }
    }

    private func uploadPhoto() async {
        guard let item = photoPick else { return }
        photoPick = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = API.jpeg(img) else { return }
        do {
            let nu: FUser = try await API.upload("/feed/me/photo", data: jpg)
            Haptic.success()
            withAnimation(.smooth(duration: 0.3)) { u = nu }
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func header(_ u: FUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // огонёк OXION слева от имени, как галочка Telegram
                        if let o = u.official {
                            OxionSealButton(official: o, userId: u.id, name: u.name ?? "", photo: u.photo, username: u.username, size: 26)
                        }
                        Text(u.name ?? "").font(.title.bold())
                        if u.trainer == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.limeInk) }
                    }
                    if let un = u.username {
                        Menu {
                            Button {
                                UIPasteboard.general.string = ProfileLink.string(un)
                                Haptic.success()
                            } label: { Label("Скопировать ссылку", systemImage: "link") }
                            Button {
                                UIPasteboard.general.string = "@" + un
                                Haptic.success()
                            } label: { Label("Скопировать имя", systemImage: "at") }
                            ShareLink(item: ProfileLink.url(un)) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        } label: {
                            Text("@" + un).font(.subheadline.weight(.medium)).foregroundStyle(Color.limeInk)
                        }
                        let more = (u.usernames ?? []).dropFirst()
                        if !more.isEmpty {
                            Text(String(localized: "также") + " " + more.map { "@" + $0 }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(Color.oxHint).lineLimit(2)
                        }
                    }
                    if let c = u.city { Label(c, systemImage: "mappin").font(.subheadline).foregroundStyle(Color.oxHint) }
                }
                Spacer()
                Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 76)
                    .overlay(alignment: .topLeading) {
                        // заметка над аватаркой (видна 24 часа), как в Threads
                        if u.me == true || (u.note?.isEmpty == false) {
                            Button { if u.me == true { showNote = true } } label: {
                                NoteBubble(text: u.note, mine: u.me == true)
                            }
                            .buttonStyle(.plain)
                            .offset(x: -44, y: -12)
                            .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                        }
                    }
            }
            if let b = u.bio, !b.isEmpty { Text(b) }
            if let c = u.channel { ProfileChannelRow(channel: c) }
            if let o = u.official { OfficialFootnote(official: o) }
            HStack(spacing: 16) {
                Text("\(u.followers ?? 0)").bold() + Text(" подписчиков").foregroundColor(Color.oxHint)
                Text("\(u.following ?? 0)").bold() + Text(" подписок").foregroundColor(Color.oxHint)
                if let s = u.streak, s > 0 { Text("🔥 \(s) нед.").foregroundStyle(Color.limeInk) }
            }
            .font(.subheadline)
            if u.me == true {
                HStack(spacing: 10) {
                    Button { showCard = true } label: {
                        Label("Моя визитка", systemImage: "qrcode").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    ShareLink(item: (u.username.map { ProfileLink.string($0) } ?? AppSettings.serverURL.absoluteString + "/#u/\(u.id)")) {
                        Label("Поделиться", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        Task { await toggle("follow", !(u.isFollowing ?? false)) }
                    } label: {
                        Text(u.isFollowing == true ? "Вы подписаны" : (u.followsMe == true ? "Подписаться в ответ" : "Подписаться"))
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(u.isFollowing == true ? Color.primary.opacity(0.15) : Color.lime)
                    Button {
                        Task { await openChat(u) }
                    } label: {
                        Text("Написать").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .padding(16)
    }

    private func load() async {
        do {
            u = try await API.call("/feed/users/\(userId)") as FUser
            await loadPosts()
        } catch { errorText = error.localizedDescription }
    }

    private func loadPosts() async {
        if let r: FeedResponse = try? await API.call("/feed/users/\(userId)/posts", query: ["tab": tab]) { posts = r.items }
    }

    private func toggle(_ what: String, _ on: Bool) async {
        do {
            let _: OK = try await API.call("/feed/users/\(userId)/\(what)", method: on ? "POST" : "DELETE")
            Haptic.success()
            u = try? await API.call("/feed/users/\(userId)") as FUser
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func openChat(_ u: FUser) async {
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": u.id])
            chat = ChatRef(id: r.id, name: u.name ?? "Чат")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Активность (лайки, ответы, подписки)

struct ActivityView: View {
    @State private var items: [ActivityItem] = []
    @State private var loaded = false
    @State private var route: FeedRoute?
    @Environment(\.feedPush) private var feedPush
    /// внутри вкладки «Лента» — пушим в общий стек, иначе — в свой
    private func go(_ r: FeedRoute) { if let feedPush { feedPush(r) } else { route = r } }

    var body: some View {
        List {
            ForEach(items) { a in
                Button {
                    if let p = a.post { go(.post(p.open ?? p.id)) } else { go(.user(a.actor.id)) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(url: API.media(a.actor.photo), name: a.actor.name ?? "?", size: 44)
                            Image(systemName: icon(a.kind))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(color(a.kind), in: Circle())
                                .overlay(Circle().stroke(Color.oxBg, lineWidth: 2))
                                .offset(x: 4, y: 4)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            (Text(a.actor.name ?? "").bold() + Text(" " + title(a.kind)).foregroundColor(Color.oxHint))
                                .font(.subheadline)
                            if let t = a.post?.text, !t.isEmpty {
                                Text(RichText.plain(t)).font(.subheadline).lineLimit(2)
                            }
                            if let at = a.at { Text(FeedTime.ago(at)).font(.caption).foregroundStyle(Color.oxHint) }
                        }
                        Spacer()
                        if a.unread == true { Circle().fill(Color.lime).frame(width: 8, height: 8) }
                    }
                }
                .buttonStyle(.plain)
                .reassemblesRow()
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(Color.oxBg)
        .overlay {
            if loaded && items.isEmpty {
                ContentUnavailableView("Пока тихо", systemImage: "heart", description: Text("Здесь будут лайки, ответы и новые подписчики"))
            } else if !loaded { ProgressView() }
        }
        .navigationTitle("Активность")
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .oxRefreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if let r: ActivityResponse = try? await API.call("/feed/activity") { items = r.items }
        loaded = true
        let _: OK? = try? await API.call("/feed/activity/read", method: "POST")
    }

    private func icon(_ k: String) -> String {
        switch k {
        case "like": return "heart.fill"
        case "reply": return "arrowshape.turn.up.left.fill"
        case "follow": return "person.fill"
        case "repost": return "arrow.2.squarepath"
        case "quote": return "quote.opening"
        case "vote": return "chart.bar.fill"
        case "mention": return "at"
        default: return "bell.fill"
        }
    }
    private func color(_ k: String) -> Color {
        switch k {
        case "like": return Color(hex: 0xFF3B5C)
        case "reply": return Color(hex: 0x3FD6C9)
        case "follow": return Color(hex: 0x8E7CFF)
        case "repost", "quote": return Color.lime
        default: return Color(hex: 0xF0A030)
        }
    }
    private func title(_ k: String) -> String {
        switch k {
        case "like": return "оценил(а) вашу ветку"
        case "reply": return "ответил(а)"
        case "follow": return "подписался(лась) на вас"
        case "repost": return "сделал(а) репост"
        case "quote": return "процитировал(а)"
        case "vote": return "проголосовал(а) в опросе"
        case "mention": return "упомянул(а) вас"
        default: return ""
        }
    }
}

// MARK: - Поиск по ленте

struct FeedSearchView: View {
    @State private var q = ""
    @State private var result: FSearch?
    @State private var suggest: [FPerson] = []
    @State private var route: FeedRoute?
    @Environment(\.feedPush) private var feedPush
    /// внутри вкладки «Лента» — пушим в общий стек, иначе — в свой
    private func go(_ r: FeedRoute) { if let feedPush { feedPush(r) } else { route = r } }

    var body: some View {
        List {
            if result == nil && !suggest.isEmpty {
                Section("Кого почитать") {
                    ForEach(suggest) { u in personRow(u) }
                }
            }
            if let r = result {
                if let us = r.users, !us.isEmpty {
                    Section("Люди") { ForEach(us) { u in personRow(u) } }
                }
                if let ps = r.posts, !ps.isEmpty {
                    Section("Ветки") {
                        ForEach(ps) { p in
                            ThreadPost(post: p, onOpen: { go(.post(p.id)) }, onUser: { go(.user($0)) })
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                if (r.users ?? []).isEmpty && (r.posts ?? []).isEmpty {
                    ContentUnavailableView.search(text: q)
                }
            }
        }
        .listStyle(.plain)
        .background(Color.oxBg)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Люди и ветки")
        .onSubmit(of: .search) { Task { await search() } }
        .navigationTitle("Поиск")
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .task {
            if let r: FPeople = try? await API.call("/feed/suggest") { suggest = r.items }
        }
    }

    private func personRow(_ u: FPerson) -> some View {
        Button { go(.user(u.id)) } label: {
            HStack(spacing: 12) {
                Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(u.name ?? "").font(.subheadline.bold())
                        if u.trainer == true { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.limeInk) }
                    }
                    Text(u.bio ?? u.city ?? "").font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func search() async {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { result = nil; return }
        result = try? await API.call("/feed/search", query: ["q": t]) as FSearch
    }
}

// MARK: - ИИ-тренер

struct AICoachView: View {
    @State private var items: [AIMessage] = []
    @State private var text = ""
    @State private var sending = false
    @State private var enabled = true
    @State private var left: Int?
    @State private var local = OnDeviceCoach.shared
    @State private var typingId: Int?
    @AppStorage("ox.ai.last") private var lastPreview = ""
    /// Готовый запрос, который отправится сразу при открытии (например, из выбора мышц на фигуре)
    var initial: String? = nil

    private let hints = ["Составь тренировку на сегодня", "Как накачать грудь дома?", "Сколько белка мне нужно?", "Разбери мою неделю"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 10) {
                        AIAvatar(size: 92, active: sending || typingId != nil)
                            .padding(.bottom, 6)
                        Text("OXION AI").font(.title2.bold())
                        Text("Твой тренер и помощник по приложению: составит тренировку, разберёт статистику, подберёт тренера и откроет нужный раздел")
                            .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                        Label(local.useLocal ? "Думает на iPhone · без интернета" : "Думает на сервере OXION",
                              systemImage: local.useLocal ? "iphone.gen3" : "cloud.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.limeInk)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.lime.opacity(0.12), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    if items.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(hints, id: \.self) { h in
                                Button { text = h; Task { await send() } } label: { Chip(text: h) }.buttonStyle(.plain)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                        let next = i + 1 < items.count ? items[i + 1].role : (sending && m.role == "user" ? "assistant" : nil)
                        let last = next != m.role
                        messageRow(m, last: last)
                            .id(m.id)
                            .padding(.bottom, last ? 6 : 0)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
                    }
                    if sending {
                        HStack(alignment: .bottom, spacing: 8) {
                            AIAvatar(size: 34, active: true)
                            AIThinkingBubble()
                            Spacer()
                        }
                        .id("thinking")
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottomLeading)))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            // чат «прилипает» к низу, пока растёт ответ: без ручных прокруток и рывков
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: items.count) { withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: sending) { if sending { withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("bottom", anchor: .bottom) } } }
        }
        .background(Color.oxBg)
        .navigationTitle("OXION AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Где думает тренер", selection: Binding(get: { local.useLocal }, set: { v in
                        if v && !local.isAvailable {
                            OxAlert.show(icon: "apple.intelligence", title: "ИИ на iPhone недоступен", message: local.reason)
                            return
                        }
                        local.useLocal = v
                        local.reset()
                        if v, !local.reason.isEmpty { OxAlert.show(icon: "apple.intelligence", title: "ИИ на iPhone", message: local.reason) }
                    })) {
                        Label("Сервер OXION", systemImage: "cloud").tag(false)
                        Label("На iPhone — без интернета", systemImage: "iphone.gen3").tag(true)
                    }
                } label: { Image(systemName: local.useLocal ? "apple.intelligence" : "cloud") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    OxAlert.confirm(icon: "trash.fill", title: "Очистить переписку?", action: "Очистить", destructive: true) {
                        Task {
                            let _: OK? = try? await API.call("/ai/messages", method: "DELETE")
                            items = []
                        }
                    }
                } label: { Image(systemName: "trash") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if let left { Text("Осталось вопросов сегодня: \(left)").font(.caption2).foregroundStyle(Color.oxHint) }
                HStack(spacing: 8) {
                    TextField(enabled || local.useLocal ? "Спросите тренера…" : "ИИ-тренер пока не подключён", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .task {
            if let r: AIMessages = try? await API.call("/ai/messages") {
                items = r.items
                enabled = r.enabled ?? true
            }
            if let initial, !initial.isEmpty, text.isEmpty, !sending {
                text = initial
                await send()
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ m: AIMessage, last: Bool) -> some View {
        if m.role == "user" {
            HStack {
                Spacer(minLength: 56)
                Text(m.content)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(Color.onLime)
                    .background(Color.lime, in: TailBubbleShape(mine: true, radius: 18, tail: last))
            }
        } else {
            let typing = typingId == m.id
            HStack(alignment: .bottom, spacing: 8) {
                if last { AIAvatar(size: 34, active: typing) } else { Color.clear.frame(width: 34, height: 1) }
                VStack(alignment: .leading, spacing: 10) {
                    AITypingText(text: m.content, animate: typing) {
                        withAnimation(.smooth(duration: 0.45)) { typingId = nil }
                        Haptic.success()
                    }
                    if !typing {
                        if let plan = m.plan { AIPlanCard(plan: plan).transition(.opacity.combined(with: .offset(y: 10))) }
                        if let b = m.buttons, !b.isEmpty { AIActionButtons(buttons: b).transition(.opacity.combined(with: .offset(y: 6))) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.primary.opacity(0.08), in: TailBubbleShape(mine: false, radius: 18, tail: last))
                Spacer(minLength: 24)
            }
        }
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !enabled && !local.useLocal { OxAlert.soon("ИИ-тренер"); return }
        text = ""
        withAnimation(.smooth(duration: 0.35)) {
            items.append(AIMessage(id: -Int(Date().timeIntervalSince1970), role: "user", content: t, plan: nil, createdAt: nil))
            sending = true
        }
        OxSound.play(.sent)
        defer { if sending { withAnimation(.smooth(duration: 0.3)) { sending = false } } }
        if local.useLocal {
            // ответ на iPhone: показываем текст по мере генерации
            let id = -Int(Date().timeIntervalSince1970 * 10)
            withAnimation(.smooth(duration: 0.35)) {
                sending = false
                items.append(AIMessage(id: id, role: "assistant", content: "…", plan: nil, createdAt: nil))
            }
            do {
                _ = try await local.ask(t) { part in
                    if let i = items.firstIndex(where: { $0.id == id }) {
                        items[i] = AIMessage(id: id, role: "assistant", content: part, plan: nil, createdAt: nil)
                    }
                }
                Haptic.success()
            } catch {
                items.removeAll { $0.id == id }
                OxAlert.error("ИИ на iPhone: \(error.localizedDescription)")
            }
            return
        }
        do {
            let r: AIReply = try await API.call("/ai/chat", method: "POST", body: ["text": t, "today": RU.dayFormatter.string(from: Date())])
            left = r.left
            lastPreview = String(r.content.prefix(120))
            // «думает» плавно сменяется ответом, который печатается по словам
            withAnimation(.smooth(duration: 0.4)) {
                sending = false
                typingId = r.id
                items.append(AIMessage(id: r.id, role: r.role, content: r.content, plan: r.plan, createdAt: r.createdAt, buttons: r.buttons))
            }
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

struct AIPlanCard: View {
    let plan: JSONValue
    @State private var shown = 0
    @State private var saved = false
    @State private var saving = false

    var body: some View {
        let ex = plan["exercises"]?.array ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard.fill").foregroundStyle(Color.limeInk)
                Text(plan["title"]?.string ?? "План тренировки").font(.headline).foregroundStyle(Color.limeInk)
            }
            ForEach(Array(ex.enumerated()), id: \.offset) { i, e in
                if i < shown {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.caption.bold().monospacedDigit()).foregroundStyle(Color.onLime)
                            .frame(width: 20, height: 20).background(Color.lime, in: Circle())
                        Text(e["name"]?.string ?? "").font(.subheadline)
                        Spacer()
                        Text(detail(e)).font(.caption.monospacedDigit()).foregroundStyle(Color.oxHint)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().controlSize(.small) }
                    Image(systemName: saved ? "checkmark.circle.fill" : "calendar.badge.plus")
                    Text(saved ? "Добавлено в дневник" : "В дневник на сегодня")
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .disabled(saved || saving)
            .padding(.top, 4)
            .opacity(shown >= ex.count ? 1 : 0)
        }
        .padding(12)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            guard shown == 0 else { return }
            for i in 0...ex.count {
                try? await Task.sleep(for: .milliseconds(i == 0 ? 120 : 140))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shown = i + 1 }
                if i < ex.count { Haptic.tap(.soft) }
            }
        }
    }

    private func detail(_ e: JSONValue) -> String {
        var s = [e["sets"]?.string.map { "\($0)×" }, e["reps"]?.string].compactMap { $0 }.joined()
        if let sec = e["seconds"]?.int, sec > 0 { s += (s.isEmpty ? "" : " ") + "\(sec) с" }
        if let km = e["km"]?.string, km != "0" { s += (s.isEmpty ? "" : " ") + "\(km) км" }
        if let w = e["weight"]?.string, w != "0" { s += " · \(w) кг" }
        return s
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let _: OK = try await API.call("/ai/apply", method: "POST",
                                           body: ["date": RU.dayFormatter.string(from: Date()), "plan": plan.any])
            Haptic.success()
            withAnimation { saved = true }
            OxAlert.show(icon: "checkmark.circle.fill", title: "Добавлено в дневник", message: "Тренировка появилась на сегодня")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
