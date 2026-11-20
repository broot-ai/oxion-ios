import SwiftUI
import UIKit
import Observation

// MARK: - Хранилище ленты

@MainActor
@Observable
final class FeedStore {
    var items: [FeedItem] = []
    var next: String?
    var loading = false
    var errorText: String?
    var noCity = false
    var tab: String = AppSettings.startFeed
    var topic: String?

    private var generation = 0

    func load(reset: Bool) async {
        if !reset && (loading || next == nil) { return }
        generation += 1
        let gen = generation
        loading = true
        var q = ["tab": tab]
        if let topic { q = ["tab": "topic", "topic": topic] }
        if !reset, let n = next { q["cursor"] = n }
        do {
            let r: FeedResponse = try await API.call("/feed", query: q)
            guard gen == generation else { return }
            if reset {
                items = r.items
            } else {
                let have = Set(items.map(\.id))
                items += r.items.filter { !have.contains($0.id) }
            }
            next = r.next?.value
            noCity = r.noCity ?? false
            errorText = nil
        } catch {
            guard gen == generation else { return }
            errorText = error.localizedDescription
        }
        loading = false
    }

    func update(_ id: Int, _ change: (inout Post) -> Void) {
        for i in items.indices where items[i].post.id == id { change(&items[i].post) }
    }

    func remove(_ id: Int) { items.removeAll { $0.post.id == id } }
    func removeAuthor(_ uid: Int) { items.removeAll { $0.post.author.id == uid } }
}

// MARK: - Навигация внутри ленты

enum FeedRoute: Hashable {
    case post(Int)
    case user(Int)
    case activity
    case search
    case coach
    case topic(String, String)
}

/// Экран для маршрута ленты — используется во всех стеках, где есть посты
struct FeedDestination: View {
    let route: FeedRoute
    var body: some View {
        switch route {
        case .post(let id): PostDetailView(postId: id)
        case .user(let id): UserProfileView(userId: id)
        case .activity: ActivityView()
        case .search: FeedSearchView()
        case .coach: AICoachView()
        case .topic(let key, let name): TopicFeedView(key: key, name: name)
        }
    }
}

// MARK: - Лента (как в PWA: ветки в стиле Threads)

struct FeedView: View {
    @Environment(AppModel.self) private var model
    @State private var store = FeedStore()
    @State private var path: [FeedRoute] = []
    @State private var compose: ComposeRequest?

    private let tabs: [(String, String)] = [("foryou", "Для вас"), ("following", "Подписки"), ("city", "Мой город")]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    tabBar
                    newPostRow
                    topicsRow
                    Divider().overlay(Color.white.opacity(0.06))

                    if let e = store.errorText, store.items.isEmpty {
                        ErrorStateView(message: e) { Task { await store.load(reset: true) } }
                            .padding(.top, 40)
                    }

                    ForEach(store.items) { item in
                        ThreadPost(post: item.post,
                                   repostBy: item.repostBy?.name,
                                   onOpen: { path.append(.post(item.post.chainOf ?? item.post.id)) },
                                   onUser: { path.append(.user($0)) },
                                   onChange: { change in store.update(item.post.id, change) },
                                   onRemove: { store.remove(item.post.id) },
                                   onRemoveAuthor: { store.removeAuthor($0) },
                                   onCompose: { compose = $0 })
                            .onAppear {
                                if item.id == store.items.last?.id { Task { await store.load(reset: false) } }
                            }
                        Divider().overlay(Color.white.opacity(0.06))
                    }

                    if store.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(24)
                    } else if store.items.isEmpty && store.errorText == nil {
                        ContentUnavailableView(
                            store.noCity ? "Город не выбран" : (store.tab == "following" ? "Здесь будут ваши подписки" : "Пока пусто"),
                            systemImage: store.tab == "following" ? "person.2" : "flame",
                            description: Text(store.noCity ? "Выберите город в профиле — покажем, что пишут рядом"
                                              : store.tab == "following" ? "Подпишитесь на тренеров и людей с похожей целью"
                                              : "Станьте первым — расскажите о тренировке"))
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color.oxBg)
            .navigationTitle("Лента")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { compose = ComposeRequest() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Новая публикация")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { path.append(.coach) } label: { Image(systemName: "sparkles") }
                    Button { path.append(.search) } label: { Image(systemName: "magnifyingglass") }
                    Button { path.append(.activity) } label: { Image(systemName: "heart") }
                }
            }
            .navigationDestination(for: FeedRoute.self) { FeedDestination(route: $0) }
            .sheet(item: $compose) { req in
                ComposerView(request: req) { id in
                    if req.parent == nil { path.append(.post(id)) }
                    Task { await store.load(reset: true) }
                }
            }
            .oxRefreshable { await store.load(reset: true) }
            .task { if store.items.isEmpty { await store.load(reset: true) } }
            .onChange(of: store.tab) {
                Haptic.tap(.soft)
                Task { await store.load(reset: true) }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { t in
                Button {
                    if store.tab == t.0 { Task { await store.load(reset: true) } }
                    store.tab = t.0
                } label: {
                    VStack(spacing: 8) {
                        Text(t.1)
                            .font(.subheadline.weight(store.tab == t.0 ? .semibold : .regular))
                            .foregroundStyle(store.tab == t.0 ? Color.primary : Color.oxHint)
                        Capsule()
                            .fill(store.tab == t.0 ? Color.lime : Color.clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var newPostRow: some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.me?.displayName ?? "Вы").font(.subheadline.weight(.semibold))
                Text("Что нового?").font(.subheadline).foregroundStyle(Color.oxHint)
            }
            Spacer()
            HStack(spacing: 4) {
                quick("photo.on.rectangle", .photo)
                quick("dumbbell", .workout)
                quick("chart.bar.xaxis", .poll)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { compose = ComposeRequest() }
    }

    private func quick(_ icon: String, _ preset: ComposeRequest.Preset) -> some View {
        Button {
            compose = ComposeRequest(preset: preset)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.oxHint)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var topicsRow: some View {
        if let topics = model.meta?.feedTopics, !topics.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topics) { t in
                        Button {
                            path.append(.topic(t.key, t.name))
                        } label: {
                            Text("\(t.icon ?? "") \(t.name)")
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.oxCard, in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Пост в стиле ветки

struct ThreadPost: View {
    let post: Post
    var repostBy: String? = nil
    var big = false
    var showLine = false
    var onOpen: (() -> Void)? = nil
    var onUser: (Int) -> Void = { _ in }
    var onChange: ((inout Post) -> Void) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onRemoveAuthor: (Int) -> Void = { _ in }
    var onCompose: (ComposeRequest) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @State private var heart = false

    var body: some View {
        let p = post
        VStack(alignment: .leading, spacing: 6) {
            if let rb = repostBy {
                Label("\(rb) сделал(а) репост", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(Color.oxHint)
                    .padding(.leading, 52)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    Button { onUser(p.author.id) } label: {
                        Avatar(url: API.media(p.author.photo), name: p.author.name ?? "?", size: 40)
                    }
                    .buttonStyle(.plain)
                    if showLine {
                        Capsule().fill(Color.white.opacity(0.14)).frame(width: 2).frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    header(p)
                    if p.trainerAnswer == true {
                        Text("🎓 Ответ тренера").font(.caption.bold()).foregroundStyle(Color.lime)
                    }
                    if let r = p.replyToName, !r.isEmpty {
                        (Text("в ответ ").foregroundColor(Color.oxHint) + Text(r).bold())
                            .font(.caption)
                    }
                    if p.status == "hidden" {
                        Text("Скрыто модератором — видите только вы").font(.caption).foregroundStyle(.orange)
                    }
                    if let t = p.text, !t.isEmpty {
                        Text(t)
                            .font(big ? .title3 : .body)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen?() }
                    }
                    if AppSettings.autoloadPhotos, let photos = p.photos, !photos.isEmpty {
                        PhotoStrip(urls: photos.compactMap { API.media($0) })
                            .onTapGesture(count: 2) { doubleLike() }
                            .onTapGesture { onOpen?() }
                            .overlay {
                                if heart {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 84))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 10)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                    }
                    if let w = p.workout { PostWorkoutCard(w: w) }
                    if let pr = p.product { PostProductCard(p: pr) }
                    if let poll = p.poll { PollView(poll: poll) { opt in Task { await vote(opt) } } }
                    if let q = p.quote { QuoteCard(q: q) }
                    if big, let at = p.at {
                        Text(Date(timeIntervalSince1970: at / 1000).formatted(date: .long, time: .shortened) + (p.edited == true ? " · изменено" : ""))
                            .font(.caption)
                            .foregroundStyle(Color.oxHint)
                    } else if p.edited == true {
                        Text("изменено").font(.caption2).foregroundStyle(Color.oxHint)
                    }
                    actions(p)
                    if !big, (p.chainCount ?? 1) > 1 {
                        let n = (p.chainCount ?? 1) - 1
                        Button { onOpen?() } label: {
                            Text("Ещё \(n) \(RU.plural(n, "часть", "части", "частей")) ветки ›")
                                .font(.subheadline)
                                .foregroundStyle(Color.lime)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func header(_ p: Post) -> some View {
        HStack(spacing: 5) {
            Button { onUser(p.author.id) } label: {
                Text(p.author.name ?? "Без имени").font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .buttonStyle(.plain)
            if p.author.trainer == true {
                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.lime)
            }
            if let tp = p.topic, let t = model.meta?.feedTopics?.first(where: { $0.key == tp }) {
                Text("› \(t.icon ?? "") \(t.name)")
                    .font(.caption)
                    .foregroundStyle(Color.oxHint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let at = p.at {
                Text(FeedTime.ago(at)).font(.caption).foregroundStyle(Color.oxHint)
            }
            PostMenu(post: p, onChange: onChange, onRemove: onRemove, onRemoveAuthor: onRemoveAuthor)
        }
    }

    private func actions(_ p: Post) -> some View {
        HStack(spacing: 2) {
            actionButton(p.liked == true ? "heart.fill" : "heart", p.likes ?? 0, tint: p.liked == true ? Color(hex: 0xFF3B5C) : Color.oxHint) {
                like(p)
            }
            actionButton("bubble.right", p.replies ?? 0, tint: Color.oxHint) {
                if p.canReply == false {
                    OxAlert.show(icon: "lock.fill", title: "Ответы закрыты",
                                 message: p.replyTo == "none" ? "Автор закрыл ответы" : "Отвечать могут только те, на кого подписан автор")
                } else {
                    onCompose(ComposeRequest(parent: p))
                }
            }
            Menu {
                Button {
                    Task { await repost(p) }
                } label: {
                    Label(p.reposted == true ? "Отменить репост" : "Репост", systemImage: "arrow.2.squarepath")
                }
                Button {
                    onCompose(ComposeRequest(quote: p))
                } label: {
                    Label("Цитировать", systemImage: "quote.bubble")
                }
            } label: {
                actionLabel("arrow.2.squarepath", (p.reposts ?? 0) + (p.quotes ?? 0), tint: p.reposted == true ? Color.lime : Color.oxHint)
            }
            ShareLink(item: FeedTime.link(p.id)) {
                actionLabel("paperplane", 0, tint: Color.oxHint)
            }
            Spacer()
        }
        .padding(.leading, -8)
        .padding(.top, 2)
    }

    private func actionButton(_ icon: String, _ n: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(icon, n, tint: tint) }
            .buttonStyle(.plain)
    }

    private func actionLabel(_ icon: String, _ n: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .contentTransition(.symbolEffect(.replace))
            if n > 0 { Text(FeedTime.num(n)).font(.subheadline) }
        }
        .foregroundStyle(tint)
        .frame(minWidth: 44, minHeight: 36, alignment: .leading)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func like(_ p: Post) {
        let was = p.liked ?? false
        onChange { $0.liked = !was; $0.likes = max(0, ($0.likes ?? 0) + (was ? -1 : 1)) }
        Haptic.tap(was ? .light : .medium)
        Task {
            if !(await PostActions.toggle("like", id: p.id, on: !was)) {
                onChange { $0.liked = was; $0.likes = max(0, ($0.likes ?? 0) + (was ? 1 : -1)) }
            }
        }
    }

    private func doubleLike() {
        withAnimation(.spring(duration: 0.3)) { heart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { heart = false }
        }
        if post.liked != true { like(post) }
    }

    private func repost(_ p: Post) async {
        if p.mine == true {
            OxAlert.show(icon: "arrow.2.squarepath", title: "Это ваша ветка", message: "Свои ветки нельзя репостить — можно процитировать")
            return
        }
        let was = p.reposted ?? false
        onChange { $0.reposted = !was; $0.reposts = max(0, ($0.reposts ?? 0) + (was ? -1 : 1)) }
        Haptic.tap()
        if !(await PostActions.toggle("repost", id: p.id, on: !was)) {
            onChange { $0.reposted = was; $0.reposts = max(0, ($0.reposts ?? 0) + (was ? 1 : -1)) }
        }
    }

    private func vote(_ option: Int) async {
        do {
            let upd: Post = try await API.call("/feed/posts/\(post.id)/vote", method: "POST", body: ["option": option])
            onChange { $0.poll = upd.poll }
            Haptic.success()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

// MARK: - «Три точки» поста

struct PostMenu: View {
    let post: Post
    var onChange: ((inout Post) -> Void) -> Void
    var onRemove: () -> Void
    var onRemoveAuthor: (Int) -> Void

    var body: some View {
        Menu {
            if post.mine == true {
                Button {
                    Task {
                        if await PostActions.toggle("pin", id: post.id, on: true) {
                            OxAlert.show(icon: "pin.fill", title: "Закреплено", message: "Ветка закреплена в вашем профиле")
                        }
                    }
                } label: { Label("Закрепить в профиле", systemImage: "pin") }
                Menu {
                    replyToButton("all", "Все")
                    replyToButton("following", "Те, на кого я подписан")
                    replyToButton("none", "Никто")
                } label: { Label("Кто может отвечать", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                Button(role: .destructive) {
                    OxAlert.confirm(icon: "trash.fill", title: "Удалить ветку?", message: "Ответы и репосты тоже исчезнут", action: "Удалить", destructive: true) {
                        Task {
                            if let err = await PostActions.delete(post.id) { OxAlert.error(err) } else { onRemove() }
                        }
                    }
                } label: { Label("Удалить", systemImage: "trash") }
            } else {
                Button {
                    Task { await follow() }
                } label: { Label("Подписаться на автора", systemImage: "person.badge.plus") }
                Button {
                    Task {
                        if await PostActions.toggle("hide", id: post.id, on: true) { onRemove() }
                    }
                } label: { Label("Не интересно", systemImage: "eye.slash") }
                Button {
                    Task {
                        if await userAction("mute") { onRemoveAuthor(post.author.id) }
                    }
                } label: { Label("Скрыть автора", systemImage: "speaker.slash") }
                Button(role: .destructive) {
                    OxAlert.confirm(icon: "hand.raised.fill", title: "Заблокировать \(post.author.name ?? "автора")?",
                                    message: "Вы не будете видеть друг друга в ленте и чатах", action: "Заблокировать", destructive: true) {
                        Task { if await userAction("block") { onRemoveAuthor(post.author.id) } }
                    }
                } label: { Label("Заблокировать", systemImage: "hand.raised") }
                Menu {
                    ForEach(ReportReason.allCases) { r in
                        Button(r.title) {
                            Task {
                                let msg = await PostActions.report(post.id, reason: r)
                                OxAlert.show(icon: "checkmark.shield.fill", title: "Жалоба отправлена", message: msg)
                            }
                        }
                    }
                } label: { Label("Пожаловаться", systemImage: "exclamationmark.bubble") }
            }
            Divider()
            Button {
                let was = post.saved ?? false
                onChange { $0.saved = !was }
                Task { _ = await PostActions.toggle("save", id: post.id, on: !was) }
            } label: { Label(post.saved == true ? "Убрать из сохранённых" : "Сохранить", systemImage: post.saved == true ? "bookmark.fill" : "bookmark") }
            Button {
                UIPasteboard.general.string = FeedTime.link(post.id)
                Haptic.success()
            } label: { Label("Копировать ссылку", systemImage: "link") }
            if let t = post.text, !t.isEmpty {
                Button {
                    UIPasteboard.general.string = t
                    Haptic.success()
                } label: { Label("Копировать текст", systemImage: "doc.on.doc") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.oxHint)
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
    }

    private func replyToButton(_ key: String, _ title: String) -> some View {
        Button {
            Task {
                do {
                    let _: OK = try await API.call("/feed/posts/\(post.id)", method: "PATCH", body: ["reply_to": key])
                    onChange { $0.replyTo = key }
                    Haptic.success()
                } catch { OxAlert.error(error.localizedDescription) }
            }
        } label: {
            if post.replyTo == key { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func follow() async {
        do {
            let _: OK = try await API.call("/feed/users/\(post.author.id)/follow", method: "POST")
            Haptic.success()
            OxAlert.show(icon: "person.fill.checkmark", title: "Вы подписались", message: "Ветки \(post.author.name ?? "автора") появятся во вкладке «Подписки»")
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func userAction(_ what: String) async -> Bool {
        do {
            let _: OK = try await API.call("/feed/users/\(post.author.id)/\(what)", method: "POST")
            Haptic.success()
            return true
        } catch {
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

enum PostActions {
    static func toggle(_ what: String, id: Int, on: Bool) async -> Bool {
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/\(what)", method: on ? "POST" : "DELETE")
            return true
        } catch {
            await MainActor.run { OxAlert.error(error.localizedDescription) }
            return false
        }
    }

    static func report(_ id: Int, reason: ReportReason) async -> String {
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/report", method: "POST", body: ["reason": reason.rawValue])
            return "Спасибо! Модераторы посмотрят"
        } catch {
            return error.localizedDescription
        }
    }

    static func delete(_ id: Int) async -> String? {
        do {
            let _: OK = try await API.call("/feed/posts/\(id)", method: "DELETE")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum FeedTime {
    static func ago(_ ms: Double) -> String {
        let s = Date().timeIntervalSince1970 - ms / 1000
        if s < 60 { return "сейчас" }
        if s < 3600 { return "\(Int(s / 60)) мин" }
        if s < 86400 { return "\(Int(s / 3600)) ч" }
        if s < 7 * 86400 { return "\(Int(s / 86400)) д" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    static func num(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f млн", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(n / 1000) тыс." }
        if n >= 1000 { return String(format: "%.1f тыс.", Double(n) / 1000) }
        return "\(n)"
    }

    static func link(_ id: Int) -> String {
        AppSettings.serverURL.absoluteString + "/#post/\(id)"
    }
}

// MARK: - Вложения поста

struct PhotoStrip: View {
    let urls: [URL]

    var body: some View {
        if urls.count == 1 {
            RemoteImage(url: urls[0])
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(urls, id: \.self) { u in
                        RemoteImage(url: u)
                            .frame(width: 220, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }
}

struct PostWorkoutCard: View {
    let w: JSONValue
    var body: some View {
        let groups = (w["groups"]?.array ?? []).compactMap { $0.string }
        HStack(spacing: 12) {
            MuscleThumb(key: groups.first, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(w["title"]?.string ?? "Тренировка").font(.headline)
                Text("\((w["exercises"]?.array ?? []).count) упр. · \(w["sets"]?.int ?? 0) подх." + ((w["volume"]?.int ?? 0) > 0 ? " · \(w["volume"]?.int ?? 0) кг" : ""))
                    .font(.caption)
                    .foregroundStyle(Color.oxHint)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PostProductCard: View {
    let p: JSONValue
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: API.media(p["photo"]?.string), icon: "bag.fill")
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p["title"]?.string ?? "Товар").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(p["store"]?.string ?? "").font(.caption).foregroundStyle(Color.oxHint)
                Text(rub(p["price_kop"]?.int)).font(.subheadline.bold()).foregroundStyle(Color.lime)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PollView: View {
    let poll: PostPoll
    var onVote: (Int) -> Void

    var body: some View {
        let showResults = poll.mine != nil || poll.closed == true
        let total = max(1, poll.total ?? 0)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { i, o in
                Button {
                    if !showResults { onVote(i) }
                } label: {
                    ZStack(alignment: .leading) {
                        if showResults {
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(poll.mine == i ? Color.lime.opacity(0.35) : Color.white.opacity(0.08))
                                    .frame(width: g.size.width * CGFloat(o.votes ?? 0) / CGFloat(total))
                            }
                        }
                        HStack {
                            Text(o.text).font(.subheadline.weight(poll.mine == i ? .semibold : .regular))
                            if poll.mine == i { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.lime) }
                            Spacer()
                            if showResults { Text("\(Int(Double(o.votes ?? 0) / Double(total) * 100))%").font(.subheadline) }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            Text("\(poll.total ?? 0) \(RU.plural(poll.total ?? 0, "голос", "голоса", "голосов"))" + (poll.closed == true ? " · опрос завершён" : ""))
                .font(.caption)
                .foregroundStyle(Color.oxHint)
        }
    }
}

struct QuoteCard: View {
    let q: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if q["gone"] != nil {
                Text("Ветка удалена").font(.subheadline).foregroundStyle(Color.oxHint)
            } else {
                HStack(spacing: 6) {
                    Avatar(url: API.media(q["author"]?["photo"]?.string), name: q["author"]?["name"]?.string ?? "?", size: 22)
                    Text(q["author"]?["name"]?.string ?? "").font(.caption.bold())
                }
                if let t = q["text"]?.string, !t.isEmpty {
                    Text(t).font(.subheadline).lineLimit(4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.14)))
    }
}

// MARK: - Тема

struct TopicFeedView: View {
    let key: String
    let name: String
    @State private var store = FeedStore()
    @State private var compose: ComposeRequest?
    @State private var route: FeedRoute?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.items) { item in
                    ThreadPost(post: item.post,
                               onOpen: { route = .post(item.post.chainOf ?? item.post.id) },
                               onUser: { route = .user($0) },
                               onChange: { change in store.update(item.post.id, change) },
                               onRemove: { store.remove(item.post.id) },
                               onCompose: { compose = $0 })
                    Divider().overlay(Color.white.opacity(0.06))
                }
                if store.loading { ProgressView().padding() }
                else if store.items.isEmpty {
                    ContentUnavailableView("В теме пока пусто", systemImage: "number", description: Text("Станьте первым"))
                }
            }
        }
        .background(Color.oxBg)
        .navigationTitle(name)
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .sheet(item: $compose) { ComposerView(request: $0) { _ in Task { await store.load(reset: true) } } }
        .task {
            store.topic = key
            await store.load(reset: true)
        }
    }
}
