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

    func toggleLike(_ id: Int) async {
        guard let i = items.firstIndex(where: { $0.post.id == id }) else { return }
        let was = items[i].post.liked ?? false
        items[i].post.liked = !was
        items[i].post.likes = max(0, (items[i].post.likes ?? 0) + (was ? -1 : 1))
        Haptic.tap(was ? .light : .medium)
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/like", method: was ? "DELETE" : "POST")
        } catch {
            if let j = items.firstIndex(where: { $0.post.id == id }) {
                items[j].post.liked = was
                items[j].post.likes = max(0, (items[j].post.likes ?? 0) + (was ? 1 : -1))
            }
        }
    }

    func toggleSave(_ id: Int) async {
        guard let i = items.firstIndex(where: { $0.post.id == id }) else { return }
        let was = items[i].post.saved ?? false
        items[i].post.saved = !was
        Haptic.tap()
        do {
            let _: OK = try await API.call("/feed/posts/\(id)/save", method: was ? "DELETE" : "POST")
        } catch {
            if let j = items.firstIndex(where: { $0.post.id == id }) {
                items[j].post.saved = was
            }
        }
    }
}

struct FeedView: View {
    @State private var store = FeedStore()

    var body: some View {
        NavigationStack {
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
                        PostCard(item: item,
                                 onLike: { Task { await store.toggleLike(item.post.id) } },
                                 onSave: { Task { await store.toggleSave(item.post.id) } })
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
            .refreshable { await store.load(reset: true) }
            .task {
                if store.items.isEmpty { await store.load(reset: true) }
            }
            .onChange(of: store.tab) {
                Haptic.tap(.soft)
                Task { await store.load(reset: true) }
            }
        }
    }
}

struct PostCard: View {
    let item: FeedItem
    var onLike: () -> Void
    var onSave: () -> Void

    var body: some View {
        let p = item.post
        VStack(alignment: .leading, spacing: 10) {
            if let rb = item.repostBy {
                Label("\(rb.name ?? "Кто-то") сделал репост", systemImage: "arrow.2.squarepath")
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
            }

            if let t = p.text, !t.isEmpty {
                Text(t)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if AppSettings.autoloadPhotos, let photos = p.photos, !photos.isEmpty {
                PhotoStrip(urls: photos.compactMap { API.media($0) })
            }

            HStack(spacing: 22) {
                Button(action: onLike) {
                    Label("\(p.likes ?? 0)", systemImage: p.liked == true ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(p.liked == true ? Color.red : Color.secondary)

                Label("\(p.replies ?? 0)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)

                Label("\(p.reposts ?? 0)", systemImage: "arrow.2.squarepath")
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onSave) {
                    Image(systemName: p.saved == true ? "bookmark.fill" : "bookmark")
                }
                .foregroundStyle(p.saved == true ? Color.lime : Color.secondary)
            }
            .font(.subheadline)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
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
