import SwiftUI

// MARK: - Профиль собеседника из чата (как в Telegram):
// аватар в шапке переписки «вырастает» в большое фото, назад — сжимается обратно (zoom-переход iOS).

enum PeerStatus {
    /// «в сети» / «был(а) в 21:40» / «был(а) 12 нояб.»
    static func text(_ lastSeen: Double?) -> String {
        guard let ms = lastSeen, ms > 0 else { return "был(а) недавно" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let ago = Date().timeIntervalSince(d)
        if ago < 300 { return "в сети" }
        if ago < 3600 { return "был(а) \(Int(ago / 60)) мин назад" }
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateFormat = Calendar.current.isDateInToday(d) ? "в HH:mm" : "d MMM в HH:mm"
        return "был(а) " + f.string(from: d)
    }
    static func online(_ lastSeen: Double?) -> Bool {
        guard let ms = lastSeen else { return false }
        return Date().timeIntervalSince1970 - ms / 1000 < 300
    }
}

struct ChatPeerProfileView: View {
    let peer: Peer
    let chatId: Int
    let messages: [Message]
    let shielded: Bool
    let shieldLockedByPeer: Bool
    var onCall: (Bool) -> Void
    var onToggleShield: () -> Void

    @Environment(ChatsStore.self) private var chats
    @State private var user: FUser?
    @State private var posts: [FeedItem] = []
    @State private var tab = 0
    @State private var pull: CGFloat = 0
    @State private var searching = false
    @State private var query = ""

    private var chatItem: ChatItem? { chats.items.first { $0.id == chatId } }
    private var photos: [String] { messages.compactMap { $0.deleted == true ? nil : $0.photo } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                actions.padding(.top, 14)
                info.padding(.top, 14)
                tabs.padding(.top, 18)
                tabContent.padding(.top, 10)
            }
            .padding(.bottom, 40)
        }
        .onScrollGeometryChange(for: CGFloat.self) { g in -(g.contentOffset.y + g.contentInsets.top) } action: { _, v in pull = max(0, v) }
        .ignoresSafeArea(edges: .top)
        .background(Color.oxBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $searching) { searchSheet }
        .task { await load() }
    }

    // MARK: большое фото

    private var header: some View {
        let h: CGFloat = 430 + pull
        return ZStack(alignment: .bottomLeading) {
            Group {
                if let u = API.media(peer.photo ?? user?.photo) {
                    RemoteImage(url: u)
                } else {
                    LinearGradient(colors: [Color.lime.opacity(0.6), Color(hex: 0x1E3A12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Text(String((peer.name ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 120, weight: .heavy)).foregroundStyle(.white.opacity(0.85)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(peer.name ?? "Пользователь").font(.system(size: 30, weight: .bold))
                    if peer.trainer == true || user?.trainer == true {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.limeInk)
                    }
                }
                HStack(spacing: 5) {
                    if PeerStatus.online(peer.lastSeen) { Circle().fill(Color.lime).frame(width: 7, height: 7) }
                    Text(PeerStatus.text(peer.lastSeen)).font(.subheadline)
                        .foregroundStyle(PeerStatus.online(peer.lastSeen) ? Color.lime : .white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(height: h)
        .offset(y: -pull)
        .padding(.bottom, -pull)
    }

    // MARK: кнопки как в Telegram

    private var actions: some View {
        HStack(spacing: 8) {
            action("phone.fill", "звонок") { onCall(false) }
            action("video.fill", "видео") { onCall(true) }
            action(chatItem?.muted == true ? "bell.slash.fill" : "bell.fill", chatItem?.muted == true ? "без звука" : "звук") {
                if let c = chatItem { Task { await chats.setMuted(c, c.muted != true) } }
            }
            action("magnifyingglass", "поиск") { searching = true }
            Menu {
                Button { onToggleShield() } label: {
                    Label(shielded ? "Выключить защиту от снимков" : "Защитить от снимков экрана", systemImage: shielded ? "lock.open" : "lock.shield")
                }
                .disabled(shielded && shieldLockedByPeer)
                if let c = chatItem {
                    Button { Task { await chats.setPinned(c, c.pinned != true) } } label: {
                        Label(c.pinned == true ? "Открепить чат" : "Закрепить чат", systemImage: c.pinned == true ? "pin.slash" : "pin")
                    }
                    Button { Task { await chats.setArchived(c, c.archived != true) } } label: {
                        Label(c.archived == true ? "Вернуть из архива" : "В архив", systemImage: "archivebox")
                    }
                }
                NavigationLink { UserProfileView(userId: peer.id) } label: {
                    Label("Профиль в ленте", systemImage: "person.crop.circle")
                }
            } label: {
                actionLabel("ellipsis", "ещё")
            }
        }
        .padding(.horizontal, 12)
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button { OxHaptics.play(.select); run() } label: { actionLabel(icon, title) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
            Text(title).font(.caption2.weight(.medium))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    // MARK: данные

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            if peer.trainer == true || user?.trainer == true {
                infoRow("роль", "Тренер OXION", accent: true)
            }
            if let c = user?.city, !c.isEmpty { infoRow("город", c) }
            if let b = user?.bio, !b.isEmpty { infoRow("о себе", b) }
            if let u = user {
                infoRow("в OXION", "\(u.posts ?? 0) публикаций · \(u.followers ?? 0) подписчиков"
                        + ((u.monthWorkouts ?? 0) > 0 ? " · \(u.monthWorkouts!) тренировок за месяц" : ""))
            }
            if shielded {
                infoRow("переписка", shieldLockedByPeer ? "Собеседник включил защиту от снимков" : "Защищена от снимков экрана", accent: true)
            }
        }
        .oxCardBG(20)
        .padding(.horizontal, 12)
    }

    private func infoRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Color.oxHint)
            Text(value).font(.body).foregroundStyle(accent ? Color.limeInk : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: вкладки

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Публикации", "Медиа"].enumerated()), id: \.offset) { i, t in
                Button { withAnimation(.snappy) { tab = i } } label: {
                    Text(t).font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .foregroundStyle(tab == i ? Color.black : Color.primary)
                        .background(tab == i ? Color.lime : Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        if tab == 0 {
            if posts.isEmpty {
                Text("Публикаций пока нет").foregroundStyle(Color.oxHint).padding(.top, 30)
            } else {
                VStack(spacing: 10) {
                    ForEach(posts) { it in
                        NavigationLink { PostDetailView(postId: it.post.chainOf ?? it.post.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                if let t = it.post.text, !t.isEmpty {
                                    Text(t).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(5)
                                }
                                if let p = it.post.photos?.first, let u = API.media(p) {
                                    RemoteImage(url: u).frame(height: 180).frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                HStack(spacing: 14) {
                                    Label("\(it.post.likes ?? 0)", systemImage: "heart")
                                    Label("\(it.post.replies ?? 0)", systemImage: "bubble.right")
                                }
                                .font(.caption).foregroundStyle(Color.oxHint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .oxCardBG(18)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        } else {
            if photos.isEmpty {
                Text("Фото из переписки появятся здесь").foregroundStyle(Color.oxHint).padding(.top, 30)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(photos.reversed(), id: \.self) { p in
                        RemoteImage(url: API.media(p))
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: поиск по переписке

    private var searchSheet: some View {
        NavigationStack {
            List {
                let found = messages.filter { m in
                    !query.isEmpty && (m.text ?? "").localizedCaseInsensitiveContains(query)
                }
                ForEach(found.reversed()) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.mine ? "Вы" : (peer.name ?? "Собеседник")).font(.caption.bold()).foregroundStyle(Color.limeInk)
                        Text(m.text ?? "").font(.subheadline)
                        Text(ChatTime.short(m.at ?? 0)).font(.caption2).foregroundStyle(Color.oxHint)
                    }
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Поиск по переписке", systemImage: "magnifyingglass", description: Text("Введите слово из сообщения"))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Слово из сообщения")
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { searching = false } } }
        }
    }

    private func load() async {
        async let u: FUser? = try? API.call("/feed/users/\(peer.id)")
        async let p: FeedResponse? = try? API.call("/feed/users/\(peer.id)/posts", query: ["tab": "posts"])
        let (uu, pp) = await (u, p)
        user = uu
        posts = pp?.items ?? []
    }
}
