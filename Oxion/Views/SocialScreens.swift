import SwiftUI

// MARK: - Профиль человека в ленте

struct UserProfileView: View {
    let userId: Int
    @Environment(AppModel.self) private var model
    @State private var u: FUser?
    @State private var tab = "posts"
    @State private var posts: [FeedItem] = []
    @State private var errorText: String?
    @State private var route: FeedRoute?
    @State private var chat: ChatRef?
    @State private var compose: ComposeRequest?
    @State private var showCard = false

    private func statusLine(_ u: FUser) -> String {
        var parts: [String] = []
        if u.trainer == true { parts.append("тренер") }
        if let c = u.city, !c.isEmpty { parts.append(c) }
        if parts.isEmpty { parts.append("\(u.followers ?? 0) подписчиков") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if let u {
                TGProfileScaffold(name: u.name ?? "Без имени", status: statusLine(u), photo: API.media(u.photo), verified: u.trainer == true) {
                    actionTiles(u)
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        infoCard(u).padding(.horizontal, 16).padding(.top, 16)
                        Picker("", selection: $tab) {
                            Text("Ветки").tag("posts")
                            Text("Ответы").tag("replies")
                            Text("Медиа").tag("media")
                            Text("Репосты").tag("reposts")
                        }
                        .pickerStyle(.segmented)
                        .padding(16)
                        if let pin = u.pinned, tab == "posts" {
                            Label("Закреплено", systemImage: "pin.fill").font(.caption).foregroundStyle(Color.oxHint).padding(.horizontal, 16)
                            ThreadPost(post: pin, onOpen: { route = .post(pin.id) }, onUser: { _ in }, onCompose: { compose = $0 })
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                        if posts.isEmpty {
                            Text("Пока ничего нет").foregroundStyle(Color.oxHint).frame(maxWidth: .infinity).padding(40)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(posts) { item in
                                ThreadPost(post: item.post,
                                           onOpen: { route = .post(item.post.chainOf ?? item.post.id) },
                                           onUser: { if $0 != userId { route = .user($0) } },
                                           onChange: { change in
                                               for i in posts.indices where posts[i].post.id == item.post.id { change(&posts[i].post) }
                                           },
                                           onRemove: { posts.removeAll { $0.post.id == item.post.id } },
                                           onCompose: { compose = $0 })
                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .background(Color.oxBg)
                }
            } else {
                LoadingOrError(error: errorText) { Task { await load() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.oxBg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
        .sheet(item: $compose) { ComposerView(request: $0) { _ in Task { await loadPosts() } } }
        .fullScreenCover(isPresented: $showCard) { MyCardSheet() }
        .onChange(of: tab) { Task { await loadPosts() } }
        .task { await load() }
    }

    @ViewBuilder
    private func actionTiles(_ u: FUser) -> some View {
        let share = AppSettings.serverURL.absoluteString + "/#u/\(u.id)"
        HStack(spacing: 8) {
            if u.me == true {
                TGActionTile(title: "визитка", icon: "qrcode") { showCard = true }
                ShareLink(item: share) { TGActionTile(title: "поделиться", icon: "square.and.arrow.up").tileLabel }
                    .buttonStyle(TGTileStyle())
            } else {
                TGActionTile(title: "написать", icon: "bubble.left.fill") { Task { await openChat(u) } }
                TGActionTile(title: u.isFollowing == true ? "подписаны" : "подписаться",
                             icon: u.isFollowing == true ? "checkmark" : "plus",
                             tint: u.isFollowing == true ? .white : Color.lime) {
                    Task { await toggle("follow", !(u.isFollowing ?? false)) }
                }
                TGActionTile(title: u.muted == true ? "показывать" : "звук", icon: u.muted == true ? "bell.slash.fill" : "bell.fill") {
                    Task { await toggle("mute", !(u.muted ?? false)) }
                }
                Menu {
                    Button { Task { await toggle("notify", true) } } label: { Label("Уведомлять о новых ветках", systemImage: "bell") }
                    ShareLink(item: share) { Label("Поделиться профилем", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        OxAlert.confirm(icon: "hand.raised.fill", title: u.blocked == true ? "Разблокировать?" : "Заблокировать \(u.name ?? "")?",
                                        action: u.blocked == true ? "Разблокировать" : "Заблокировать", destructive: u.blocked != true) {
                            Task { await toggle("block", !(u.blocked ?? false)) }
                        }
                    } label: { Label(u.blocked == true ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised") }
                } label: {
                    TGActionTile(title: "ещё", icon: "ellipsis").tileLabel
                }
            }
        }
    }

    private func infoCard(_ u: FUser) -> some View {
        var rows: [TGInfoCard.Row] = []
        if let b = u.bio, !b.isEmpty { rows.append(.init(label: "о себе", value: b)) }
        if let c = u.city, !c.isEmpty { rows.append(.init(label: "город", value: c, icon: "mappin")) }
        rows.append(.init(label: "подписчики и подписки", value: "\(u.followers ?? 0) подписчиков · \(u.following ?? 0) подписок"))
        if let s = u.streak, s > 0 { rows.append(.init(label: "серия", value: "🔥 \(s) нед. без пропусков")) }
        if let m = u.monthWorkouts, m > 0 { rows.append(.init(label: "тренировок за месяц", value: "\(m)", icon: "dumbbell.fill")) }
        if u.followsMe == true { rows.append(.init(label: "", value: "Подписан(а) на вас", icon: "person.fill.checkmark")) }
        return TGInfoCard(rows: rows)
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

    var body: some View {
        List {
            ForEach(items) { a in
                Button {
                    if let p = a.post { route = .post(p.open ?? p.id) } else { route = .user(a.actor.id) }
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
                                Text(t).font(.subheadline).lineLimit(2)
                            }
                            if let at = a.at { Text(FeedTime.ago(at)).font(.caption).foregroundStyle(Color.oxHint) }
                        }
                        Spacer()
                        if a.unread == true { Circle().fill(Color.lime).frame(width: 8, height: 8) }
                    }
                }
                .buttonStyle(.plain)
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
                            ThreadPost(post: p, onOpen: { route = .post(p.id) }, onUser: { route = .user($0) })
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
        Button { route = .user(u.id) } label: {
            HStack(spacing: 12) {
                Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(u.name ?? "").font(.subheadline.bold())
                        if u.trainer == true { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.lime) }
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

    private let hints = ["Составь тренировку на сегодня", "Как накачать грудь дома?", "Сколько белка мне нужно?", "Разбери мою неделю"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(AngularGradient(colors: [Color.lime, Color(hex: 0x3FD6C9), Color(hex: 0x58F670), Color.lime], center: .center))
                            .frame(width: 84, height: 84)
                            .blur(radius: 2)
                            .shadow(color: Color.lime.opacity(0.5), radius: 20)
                        Text("ИИ-тренер").font(.title2.bold())
                        Text("Составит тренировку на сегодня и ответит на вопросы о питании и технике")
                            .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                        Label(local.useLocal ? "Думает на iPhone · без интернета" : "Думает на сервере OXION",
                              systemImage: local.useLocal ? "iphone.gen3" : "cloud.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.lime)
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
                    }
                    ForEach(items) { m in
                        HStack {
                            if m.role == "user" { Spacer(minLength: 50) }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(m.content)
                                if let plan = m.plan, m.role != "user" {
                                    AIPlanCard(plan: plan)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(m.role == "user" ? Color.oxBg : Color.primary)
                            .background(m.role == "user" ? Color.lime : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            if m.role != "user" { Spacer(minLength: 30) }
                        }
                        .id(m.id)
                    }
                    if sending {
                        HStack(spacing: 8) { ProgressView(); Text("Думаю…").foregroundStyle(Color.oxHint) }
                    }
                }
                .padding(16)
            }
            .onChange(of: items.count) { if let id = items.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
        }
        .background(Color.oxBg)
        .navigationTitle("ИИ-тренер")
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
        }
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !enabled && !local.useLocal { OxAlert.soon("ИИ-тренер"); return }
        text = ""
        items.append(AIMessage(id: -Int(Date().timeIntervalSince1970), role: "user", content: t, plan: nil, createdAt: nil))
        sending = true
        defer { sending = false }
        if local.useLocal {
            // ответ на iPhone: показываем текст по мере генерации
            let id = -Int(Date().timeIntervalSince1970 * 10)
            items.append(AIMessage(id: id, role: "assistant", content: "…", plan: nil, createdAt: nil))
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
            items.append(AIMessage(id: r.id, role: r.role, content: r.content, plan: r.plan, createdAt: r.createdAt))
            left = r.left
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

struct AIPlanCard: View {
    let plan: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(plan["title"]?.string ?? "План тренировки", systemImage: "list.bullet.clipboard.fill")
                .font(.headline).foregroundStyle(Color.lime)
            ForEach(Array((plan["exercises"]?.array ?? []).enumerated()), id: \.offset) { _, e in
                HStack {
                    Text(e["name"]?.string ?? "").font(.subheadline)
                    Spacer()
                    Text([e["sets"]?.string.map { "\($0)×" }, e["reps"]?.string].compactMap { $0 }.joined())
                        .font(.caption).foregroundStyle(Color.oxHint)
                }
            }
            Button {
                Task {
                    do {
                        let _: OK = try await API.call("/ai/apply", method: "POST", body: ["date": RU.dayFormatter.string(from: Date())])
                        Haptic.success()
                        OxAlert.show(icon: "checkmark.circle.fill", title: "Добавлено в дневник", message: "Тренировка появилась на сегодня")
                    } catch { OxAlert.error(error.localizedDescription) }
                }
            } label: {
                Label("В дневник на сегодня", systemImage: "calendar.badge.plus").font(.subheadline.bold())
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
