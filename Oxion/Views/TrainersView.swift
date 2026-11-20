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
            .refreshable { await store.load(reset: true) }
            .task {
                if store.items.isEmpty { await store.load(reset: true) }
            }
        }
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
                            .foregroundStyle(Color.lime)
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
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct TrainerDetailView: View {
    let id: Int
    @State private var t: TrainerDetail?
    @State private var errorText: String?

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
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
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
