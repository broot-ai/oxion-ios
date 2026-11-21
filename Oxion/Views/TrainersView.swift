import SwiftUI
import Observation

@MainActor
@Observable
final class TrainersStore {
    var items: [Trainer] = []
    var hasMore = false
    var offset = 0
    var loading = false
    var errorText: String?
    var query = ""
    var sort = "match"

    private var generation = 0

    func load(reset: Bool) async {
        if !reset && (loading || !hasMore) { return }
        generation += 1
        let gen = generation
        loading = true
        var q = ["sort": sort, "offset": String(reset ? 0 : offset)]
        let text = query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { q["q"] = text }
        do {
            let r: TrainersResponse = try await API.call("/trainers", query: q)
            guard gen == generation else { return }
            if reset {
                items = r.items
            } else {
                let have = Set(items.map(\.id))
                items += r.items.filter { !have.contains($0.id) }
            }
            hasMore = r.hasMore ?? false
            offset = r.nextOffset ?? items.count
            errorText = nil
        } catch {
            guard gen == generation else { return }
            errorText = error.localizedDescription
        }
        loading = false
    }
}

struct TrainersView: View {
    @Environment(AppModel.self) private var model
    @State private var store = TrainersStore()

    private let sorts: [(String, String)] = [
        ("match", "Подходят мне"), ("rating", "По рейтингу"),
        ("price_asc", "Сначала дешевле"), ("price_desc", "Сначала дороже"), ("new", "Новые")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let e = store.errorText, store.items.isEmpty {
                        ErrorStateView(message: e) {
                            Task { await store.load(reset: true) }
                        }
                        .padding(.top, 40)
                    }

                    ForEach(store.items) { t in
                        NavigationLink(value: t.userId) {
                            TrainerCard(t: t)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if t.id == store.items.last?.id {
                                Task { await store.load(reset: false) }
                            }
                        }
                    }

                    if store.loading {
                        ProgressView().padding(24)
                    } else if store.items.isEmpty && store.errorText == nil {
                        ContentUnavailableView("Тренеров не нашлось",
                                               systemImage: "figure.strengthtraining.traditional",
                                               description: Text("Попробуйте изменить поиск или сортировку"))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Тренеры")
            .navigationDestination(for: Int.self) { id in
                TrainerDetailView(id: id)
            }
            .navigationDestination(item: Binding(get: { model.openTrainerId }, set: { model.openTrainerId = $0 })) { id in
                TrainerDetailView(id: id)
            }
            .sheet(isPresented: Binding(get: { model.showFavorites }, set: { model.showFavorites = $0 })) {
                NavigationStack { FavoritesView() }
            }
            .searchable(text: $store.query, prompt: "Имя или описание")
            .onSubmit(of: .search) {
                Task { await store.load(reset: true) }
            }
            .onChange(of: store.query) {
                if store.query.isEmpty { Task { await store.load(reset: true) } }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $store.sort) {
                            ForEach(sorts, id: \.0) { s in
                                Text(s.1).tag(s.0)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .onChange(of: store.sort) {
                Task { await store.load(reset: true) }
            }
            .oxRefreshable { await store.load(reset: true) }
            .task {
                if !model.trainerQuery.isEmpty { takeQuery() }
                if store.items.isEmpty { await store.load(reset: true) }
            }
            .onChange(of: model.trainerQuery) {
                if !model.trainerQuery.isEmpty {
                    takeQuery()
                    Task { await store.load(reset: true) }
                }
            }
        }
    }

    private func takeQuery() {
        store.query = model.trainerQuery
        model.trainerQuery = ""
    }
}

struct TrainerCard: View {
    let t: Trainer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: API.media(t.cover), icon: "figure.strengthtraining.traditional")
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if t.match == true {
                        Text("Подходит под вашу цель")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(Color.lime.opacity(0.35)), in: .capsule)
                            .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if t.fav == true {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .padding(10)
                            .glassEffect(.regular, in: .circle)
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.name ?? "Тренер")
                        .font(.headline)
                    Spacer()
                    if let r = t.rating, r > 0 {
                        Label(String(format: "%.1f", r), systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
                if let d = t.directions, !d.isEmpty {
                    Text(d.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if let p = t.price {
                        Text("\(p) ₽")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.limeInk)
                    }
                    if let e = t.experience, e > 0 {
                        Text("опыт \(e) \(RU.plural(e, "год", "года", "лет"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct TrainerDetailView: View {
    let id: Int
    @State private var t: TrainerDetail?
    @State private var errorText: String?
    @State private var chat: ChatRef?
    @State private var opening = false
    @State private var booking = false

    var body: some View {
        Group {
            if let t {
                content(t)
            } else if let errorText {
                ErrorStateView(message: errorText) {
                    Task { await load() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(t?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $chat) { ref in
            ChatView(chatId: ref.id, title: ref.name)
        }
        .safeAreaInset(edge: .bottom) {
            if let t, t.isMe != true {
                HStack(spacing: 10) {
                    Button {
                        Haptic.tap()
                        booking = true
                    } label: {
                        Label("Записаться", systemImage: "calendar.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.lime)
                    .foregroundStyle(Color.onLime)
                    Button {
                        Task { await openChat(name: t.name ?? "Тренер") }
                    } label: {
                        Group {
                            if opening { ProgressView() } else { Image(systemName: "bubble.left.and.bubble.right.fill") }
                        }
                        .font(.headline)
                        .frame(width: 44)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(opening)
                }
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .toolbar {
            if let t, t.isMe != true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleFav() }
                    } label: {
                        Image(systemName: t.fav == true ? "heart.fill" : "heart")
                            .foregroundStyle(t.fav == true ? Color.red : Color.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $booking) {
            BookingSheet(trainerId: id, trainerName: t?.name ?? "Тренер")
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ t: TrainerDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let photos = (t.photos ?? []).compactMap { API.media($0.url) }
                if photos.isEmpty {
                    RemoteImage(url: nil, icon: "figure.strengthtraining.traditional")
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(.horizontal, 12)
                } else {
                    TabView {
                        ForEach(photos, id: \.self) { u in
                            RemoteImage(url: u)
                                .frame(height: 380)
                                .clipped()
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(t.name ?? "Тренер")
                        .font(.largeTitle.bold())

                    HStack(spacing: 10) {
                        if let r = t.rating, r > 0 {
                            StatPill(icon: "star.fill", text: String(format: "%.1f", r) + " · \(t.reviewsCount ?? 0)")
                        }
                        if let p = t.price {
                            StatPill(icon: "rublesign", text: "\(p) ₽")
                        }
                        if let e = t.experience, e > 0 {
                            StatPill(icon: "clock", text: "\(e) \(RU.plural(e, "год", "года", "лет"))")
                        }
                    }

                    if let city = t.city {
                        Label(city, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }

                    if let d = t.directions, !d.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(d, id: \.self) { Chip(text: $0) }
                            }
                        }
                    }

                    if let bio = t.bio, !bio.isEmpty {
                        Text("О тренере")
                            .font(.headline)
                            .padding(.top, 4)
                        Text(bio)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 90)
            }
        }
        .oxNoUnderlap()
    }

    private func load() async {
        do {
            let r: TrainerDetail = try await API.call("/trainers/\(id)")
            t = r
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openChat(name: String) async {
        opening = true
        defer { opening = false }
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": id])
            chat = ChatRef(id: r.id, name: name)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleFav() async {
        guard let cur = t else { return }
        let was = cur.fav ?? false
        t?.fav = !was
        Haptic.tap(.medium)
        do {
            let _: FavResponse = try await API.call("/favorites/\(id)", method: was ? "DELETE" : "POST")
        } catch {
            t?.fav = was
        }
    }
}

struct StatPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }
}


/// Избранные тренеры (из Siri, Пункта управления и виджета)
struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Trainer] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if loaded && items.isEmpty {
                    ContentUnavailableView("В избранном пусто", systemImage: "heart", description: Text("Нажмите ♡ в карточке тренера"))
                }
                ForEach(items) { t in
                    NavigationLink { TrainerDetailView(id: t.userId) } label: { TrainerCard(t: t) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Избранные тренеры")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        .task {
            if let r: TrainersResponse = try? await API.call("/favorites") { items = r.items }
            loaded = true
        }
    }
}
