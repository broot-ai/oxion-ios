import SwiftUI
import Observation

@MainActor
@Observable
final class FeedStore {
    var items: [FeedItem] = []
    var next: String?
    var loading = false
    var errorText: String?
    var noCity = false
    var tab: String = AppSettings.startFeed

    private var generation = 0

    func load(reset: Bool) async {
        if !reset && (loading || next == nil) { return }
        generation += 1
        let gen = generation
        loading = true
        var q = ["tab": tab]
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
        for i in items.indices where items[i].post.id == id {
            change(&items[i].post)
        }
    }

    func remove(_ id: Int) {
        items.removeAll { $0.post.id == id }
    }
}

/// Действия с постом — общие для ленты и экрана ветки.
enum PostActions {
    static func toggle(_ what: String, id: Int, on: Bool) async -> Bool {
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/\(what)", method: on ? "POST" : "DELETE")
            return true
        } catch { return false }
    }

    static func report(_ id: Int, reason: ReportReason) async -> String {
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/report", method: "POST", body: ["reason": reason.rawValue])
            return "Спасибо, жалоба отправлена"
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

struct FeedView: View {
    @State private var store = FeedStore()
    @State private var path: [PostRef] = []
    @State private var composing = false
    @State private var toast: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Picker("Лента", selection: $store.tab) {
                        Text("Для вас").tag("foryou")
                        Text("Подписки").tag("following")
                        Text("Мой город").tag("city")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if let e = store.errorText, store.items.isEmpty {
                        ErrorStateView(message: e) {
                            Task { await store.load(reset: true) }
                        }
                        .padding(.top, 40)
                    }

                    ForEach(store.items) { item in
                        PostCard(post: item.post,
                                 repostBy: item.repostBy?.name,
                                 onChange: { change in store.update(item.post.id, change) },
                                 onDeleted: { store.remove(item.post.id) },
                                 onToast: { toast = $0 },
                                 onOpen: { path.append(PostRef(id: item.post.id)) })
                        .onAppear {
                            if item.id == store.items.last?.id {
                                Task { await store.load(reset: false) }
                            }
                        }
                    }

                    if store.loading {
                        ProgressView().padding(24)
                    } else if store.items.isEmpty && store.errorText == nil {
                        ContentUnavailableView(
                            store.noCity ? "Город не указан" : "Пока пусто",
                            systemImage: "flame",
                            description: Text(store.noCity
                                              ? "Укажите город в профиле, чтобы видеть посты рядом"
                                              : "Здесь появятся посты")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Лента")
            .navigationDestination(for: PostRef.self) { ref in
                PostDetailView(postId: ref.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Новый пост")
                }
            }
            .sheet(isPresented: $composing) {
                ComposerView(parentId: nil) { _ in
                    Task { await store.load(reset: true) }
                }
            }
            .refreshable { await store.load(reset: true) }
            .task {
                if store.items.isEmpty { await store.load(reset: true) }
            }
            .onChange(of: store.tab) {
                Haptic.tap(.soft)
                Task { await store.load(reset: true) }
            }
            .toast($toast)
        }
    }
}

struct PostCard: View {
    let post: Post
    var repostBy: String? = nil
    var onChange: ((inout Post) -> Void) -> Void
    var onDeleted: () -> Void
    var onToast: (String) -> Void
    var onOpen: (() -> Void)? = nil

    @State private var reporting = false
    @State private var confirmDelete = false

    var body: some View {
        let p = post
        VStack(alignment: .leading, spacing: 10) {
            if let rb = repostBy {
                Label("\(rb) сделал репост", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Avatar(url: API.media(p.author.photo), name: p.author.name ?? "?", size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(p.author.name ?? "Без имени")
                            .font(.subheadline.weight(.semibold))
                        if p.author.trainer == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Color.lime)
                        }
                    }
                    if let at = p.at {
                        Text(Date(timeIntervalSince1970: at / 1000), format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    if p.mine == true {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    } else {
                        Button {
                            reporting = true
                        } label: {
                            Label("Пожаловаться", systemImage: "exclamationmark.bubble")
                        }
                        Button {
                            Task {
                                if await PostActions.toggle("hide", id: p.id, on: true) {
                                    onDeleted()
                                    onToast("Пост скрыт")
                                }
                            }
                        } label: {
                            Label("Не интересно", systemImage: "eye.slash")
                        }
                    }
                    ShareLink(item: AppSettings.serverURL.absoluteString + "/#post/\(p.id)") {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
            }

            if let r = p.replyToName, !r.isEmpty {
                Text("в ответ \(r)")
                    .font(.caption)
                    .foregroundStyle(Color.lime.opacity(0.8))
            }

            if let t = p.text, !t.isEmpty {
                Text(t)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if AppSettings.autoloadPhotos, let photos = p.photos, !photos.isEmpty {
                PhotoStrip(urls: photos.compactMap { API.media($0) })
            }

            HStack(spacing: 22) {
                Button {
                    let was = p.liked ?? false
                    onChange { $0.liked = !was; $0.likes = max(0, ($0.likes ?? 0) + (was ? -1 : 1)) }
                    Task {
                        if !(await PostActions.toggle("like", id: p.id, on: !was)) {
                            onChange { $0.liked = was; $0.likes = max(0, ($0.likes ?? 0) + (was ? 1 : -1)) }
                        }
                    }
                    Haptic.tap(was ? .light : .medium)
                } label: {
                    Label("\(p.likes ?? 0)", systemImage: p.liked == true ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(p.liked == true ? Color.red : Color.secondary)

                Label("\(p.replies ?? 0)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)

                Button {
                    let was = p.reposted ?? false
                    if p.mine == true { return }
                    onChange { $0.reposted = !was; $0.reposts = max(0, ($0.reposts ?? 0) + (was ? -1 : 1)) }
                    Haptic.tap()
                    Task {
                        if !(await PostActions.toggle("repost", id: p.id, on: !was)) {
                            onChange { $0.reposted = was; $0.reposts = max(0, ($0.reposts ?? 0) + (was ? 1 : -1)) }
                        } else if !was {
                            onToast("Репост сделан")
                        }
                    }
                } label: {
                    Label("\(p.reposts ?? 0)", systemImage: "arrow.2.squarepath")
                }
                .foregroundStyle(p.reposted == true ? Color.lime : Color.secondary)

                Spacer()

                Button {
                    let was = p.saved ?? false
                    onChange { $0.saved = !was }
                    Haptic.tap()
                    Task {
                        if !(await PostActions.toggle("save", id: p.id, on: !was)) {
                            onChange { $0.saved = was }
                        }
                    }
                } label: {
                    Image(systemName: p.saved == true ? "bookmark.fill" : "bookmark")
                }
                .foregroundStyle(p.saved == true ? Color.lime : Color.secondary)
            }
            .font(.subheadline)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onOpen?() }
        .padding(.horizontal)
        .confirmationDialog("Пожаловаться на пост", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { r in
                Button(r.title) {
                    Task { onToast(await PostActions.report(p.id, reason: r)) }
                }
            }
        }
        .confirmationDialog("Удалить пост?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    if let err = await PostActions.delete(p.id) { onToast(err) } else { onDeleted(); onToast("Пост удалён") }
                }
            }
        }
    }
}

struct PhotoStrip: View {
    let urls: [URL]

    var body: some View {
        if urls.count == 1 {
            RemoteImage(url: urls[0])
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { u in
                        RemoteImage(url: u)
                            .frame(width: 230, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}
