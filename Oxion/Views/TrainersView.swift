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
    // фильтры
    var dirs: Set<String> = []
    var format: String?
    var priceMax: Int?
    var expMin: Int?
    var todayOnly = false
    var favOnly = false
    // витрина
    var home: TrainersHome?

    var filtering: Bool {
        !dirs.isEmpty || format != nil || priceMax != nil || expMin != nil || todayOnly || favOnly
            || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var filterCount: Int { (format != nil ? 1 : 0) + (priceMax != nil ? 1 : 0) + (expMin != nil ? 1 : 0) + (todayOnly ? 1 : 0) + (favOnly ? 1 : 0) }

    private var generation = 0

    func loadHome() async {
        if let h: TrainersHome = try? await API.call("/trainers/home") { home = h }
    }

    func load(reset: Bool) async {
        if !reset && (loading || !hasMore) { return }
        generation += 1
        let gen = generation
        loading = true
        var q = ["sort": sort, "offset": String(reset ? 0 : offset)]
        let text = query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { q["q"] = text }
        if !dirs.isEmpty { q["dirs"] = dirs.sorted().joined(separator: ",") }
        if let format { q["format"] = format }
        if let priceMax { q["pmax"] = String(priceMax) }
        if let expMin { q["exp"] = String(expMin) }
        if todayOnly { q["today"] = "1" }
        if favOnly { q["fav"] = "1" }
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

    func resetFilters() {
        dirs = []; format = nil; priceMax = nil; expMin = nil; todayOnly = false; favOnly = false
    }
}

struct TrainersView: View {
    @Environment(AppModel.self) private var model
    @State private var store = TrainersStore()
    @State private var showFilters = false

    private let sorts: [(String, String, String)] = [
        ("match", "Подходят мне", "target"), ("rating", "По рейтингу", "star"),
        ("soon", "Ближайшее окно", "clock"), ("popular", "Популярные", "person.3"),
        ("price_asc", "Сначала дешевле", "arrow.down"), ("price_desc", "Сначала дороже", "arrow.up"), ("new", "Новые", "sparkles")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    directionChips
                    if !store.filtering, let h = store.home {
                        showcase(h)
                    }
                    listHeader
                    list
                }
                .padding(.vertical, 8)
            }
            .background(Color.oxBg)
            .navigationTitle("Тренеры")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { id in
                TrainerDetailView(id: id)
            }
            .navigationDestination(item: Binding(get: { model.openTrainerId }, set: { model.openTrainerId = $0 })) { id in
                TrainerDetailView(id: id)
            }
            .sheet(isPresented: Binding(get: { model.showFavorites }, set: { model.showFavorites = $0 })) {
                NavigationStack { FavoritesView() }
            }
            .sheet(isPresented: $showFilters) {
                TrainerFiltersSheet(store: store) { Task { await store.load(reset: true) } }
            }
            .searchable(text: $store.query, prompt: "Имя, направление, описание")
            .onSubmit(of: .search) {
                Task { await store.load(reset: true) }
            }
            .onChange(of: store.query) {
                if store.query.isEmpty { Task { await store.load(reset: true) } }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showFavorites = true } label: { Image(systemName: "heart") }
                        .accessibilityLabel("Избранные")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $store.sort) {
                            ForEach(sorts, id: \.0) { s in
                                Label(s.1, systemImage: s.2).tag(s.0)
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
            .oxRefreshable {
                async let a: Void = store.loadHome()
                async let b: Void = store.load(reset: true)
                _ = await (a, b)
            }
            .task {
                if !model.trainerQuery.isEmpty { takeQuery() }
                if store.home == nil { await store.loadHome() }
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

    // MARK: шапка

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Найдите своего тренера")
                    .font(.title2.bold())
                Group {
                    if let h = store.home, let total = h.total {
                        Text("\(total) \(RU.plural(total, "тренер", "тренера", "тренеров"))") + Text(h.city.map { " · \($0)" } ?? "")
                    } else {
                        Text("Загружаем каталог…")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showFilters = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .overlay(alignment: .topTrailing) {
                        if store.filterCount > 0 {
                            Text("\(store.filterCount)").font(.caption2.bold()).foregroundStyle(Color.onLime)
                                .frame(width: 18, height: 18).background(Color.lime, in: Circle())
                        }
                    }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Фильтры")
        }
        .padding(.horizontal)
    }

    private var directionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickChip("Свободны сегодня", icon: "clock.badge.checkmark", on: store.todayOnly) {
                    store.todayOnly.toggle()
                }
                let dirs = (store.home?.directions ?? []).filter { $0.n > 0 }.sorted { $0.n > $1.n }
                ForEach(dirs, id: \.name) { d in
                    quickChip(d.name, icon: DirectionIcon.of(d.name), count: d.n, on: store.dirs.contains(d.name)) {
                        if store.dirs.contains(d.name) { store.dirs.remove(d.name) } else { store.dirs.insert(d.name) }
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
    }

    private func quickChip(_ t: String, icon: String, count: Int? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.snappy) { action() }
            Task { await store.load(reset: true) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(t)
                if let count { Text("\(count)").foregroundStyle(on ? Color.onLime.opacity(0.7) : .secondary) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(on ? Color.onLime : Color.primary)
            .background(on ? Color.lime : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: подборки

    @ViewBuilder
    private func showcase(_ h: TrainersHome) -> some View {
        if let my = h.my, !my.isEmpty {
            section("Мои тренеры", icon: "person.crop.circle.badge.checkmark") {
                ForEach(my) { t in
                    NavigationLink(value: t.userId) { MyTrainerCard(t: t) }.buttonStyle(.plain)
                }
            }
        }
        if let a = h.today, !a.isEmpty {
            section("Свободны сегодня", icon: "clock.badge.checkmark", sub: "Можно записаться прямо сейчас") {
                ForEach(a) { t in NavigationLink(value: t.userId) { TrainerMiniCard(t: t) }.buttonStyle(.plain) }
            }
        }
        if let a = h.match, !a.isEmpty {
            section("Под вашу цель", icon: "target", sub: h.goal) {
                ForEach(a) { t in NavigationLink(value: t.userId) { TrainerMiniCard(t: t) }.buttonStyle(.plain) }
            }
        }
        if let a = h.top, !a.isEmpty {
            section("Лучшие по отзывам", icon: "star.fill") {
                ForEach(a) { t in NavigationLink(value: t.userId) { TrainerMiniCard(t: t) }.buttonStyle(.plain) }
            }
        }
        if let a = h.popular, a.count > 2 {
            section("Популярные", icon: "flame.fill", sub: "Больше всего клиентов") {
                ForEach(a) { t in NavigationLink(value: t.userId) { TrainerMiniCard(t: t) }.buttonStyle(.plain) }
            }
        }
        if let a = h.fresh, !a.isEmpty {
            section("Новые в Oxion", icon: "sparkles") {
                ForEach(a) { t in NavigationLink(value: t.userId) { TrainerMiniCard(t: t) }.buttonStyle(.plain) }
            }
        }
    }

    private func section<C: View>(_ title: String, icon: String, sub: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon).font(.title3.bold())
                if let sub, !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) { content() }
                    .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: список

    private var listHeader: some View {
        HStack {
            Text(store.filtering ? "Найдено" : "Все тренеры").font(.title3.bold())
            if store.filtering {
                Text("\(store.items.count)\(store.hasMore ? "+" : "")").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            if store.filtering {
                Button("Сбросить") {
                    store.resetFilters(); store.query = ""
                    Task { await store.load(reset: true) }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Text(sorts.first { $0.0 == store.sort }?.1 ?? "").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var list: some View {
        if let e = store.errorText, store.items.isEmpty {
            ErrorStateView(message: e) {
                Task { await store.load(reset: true) }
            }
            .padding(.top, 20)
        }
        ForEach(store.items) { t in
            NavigationLink(value: t.userId) {
                TrainerCard(t: t)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .onAppear {
                if t.id == store.items.last?.id {
                    Task { await store.load(reset: false) }
                }
            }
        }
        if store.loading {
            ProgressView().frame(maxWidth: .infinity).padding(24)
        } else if store.items.isEmpty && store.errorText == nil {
            ContentUnavailableView {
                Label("Тренеров не нашлось", systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("Попробуйте убрать часть фильтров")
            } actions: {
                if store.filtering {
                    Button("Сбросить фильтры") {
                        store.resetFilters(); store.query = ""
                        Task { await store.load(reset: true) }
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime)
                }
            }
            .padding(.top, 20)
        }
    }

    private func takeQuery() {
        store.query = model.trainerQuery
        model.trainerQuery = ""
    }
}

// MARK: - Иконки направлений

enum DirectionIcon {
    static func of(_ d: String) -> String {
        switch d {
        case "Силовые": return "dumbbell.fill"
        case "Похудение": return "flame.fill"
        case "Набор массы": return "figure.strengthtraining.traditional"
        case "Функциональный": return "figure.cross.training"
        case "Кроссфит": return "figure.highintensity.intervaltraining"
        case "Йога": return "figure.yoga"
        case "Пилатес": return "figure.pilates"
        case "Бокс": return "figure.boxing"
        case "Растяжка": return "figure.flexibility"
        case "Реабилитация": return "cross.case.fill"
        case "Бег": return "figure.run"
        case "Плавание": return "figure.pool.swim"
        default: return "figure.mixed.cardio"
        }
    }
    static func format(_ f: String) -> String {
        switch f {
        case "В зале": return "building.2.fill"
        case "Онлайн": return "video.fill"
        case "На выезде": return "car.fill"
        default: return "mappin"
        }
    }
}

enum SlotText {
    /// «сегодня 18:00», «завтра 9:30», «пт 12:00»
    static func short(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return "сегодня \(time)" }
        if cal.isDateInTomorrow(d) { return "завтра \(time)" }
        return d.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))) + " " + time
    }
}

// MARK: - Карточки

/// Аватар тренера с точкой «в сети»
struct TrainerAvatar: View {
    let t: Trainer
    var size: CGFloat = 44
    var body: some View {
        Avatar(url: API.media(t.photo), name: t.name ?? "?", size: size)
            .overlay(Circle().stroke(Color.oxBg, lineWidth: 2.5))
            .overlay(alignment: .bottomTrailing) {
                if t.online == true {
                    Circle().fill(Color.green).frame(width: size * 0.26, height: size * 0.26)
                        .overlay(Circle().stroke(Color.oxBg, lineWidth: 2))
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
                .frame(height: 220)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        if t.match == true {
                            badge("Под вашу цель", icon: "target", tint: Color.lime)
                        }
                        if let d = t.nextDate, Calendar.current.isDateInToday(d) {
                            badge("Свободен сегодня", icon: "clock", tint: .green)
                        }
                    }
                    .padding(10)
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
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 10) {
                        TrainerAvatar(t: t, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name ?? "Тренер").font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                            if let d = t.directions, !d.isEmpty {
                                Text(d.joined(separator: " · ")).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let r = t.rating, r > 0 {
                            Label(String(format: "%.1f", r), systemImage: "star.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.35), in: Capsule())
                        }
                    }
                    .padding(12)
                }

            HStack(spacing: 14) {
                if let p = t.price {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(p) ₽").font(.headline).foregroundStyle(Color.limeInk)
                        Text("за занятие").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                info(icon: "person.2.fill", value: "\(t.clients ?? 0)", label: "клиентов")
                if let e = t.experience, e > 0 {
                    info(icon: "clock.fill", value: "\(e)", label: RU.plural(e, "год", "года", "лет"))
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(t.formats ?? [], id: \.self) { f in
                        Image(systemName: DirectionIcon.format(f)).font(.caption)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.07), in: Circle())
                            .accessibilityLabel(f)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12)

            if let d = t.nextDate {
                Label("Ближайшее окно: \(SlotText.short(d))", systemImage: "calendar.badge.clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.limeInk)
                    .padding(.horizontal, 14).padding(.top, 8)
            }
            Spacer().frame(height: 14)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func badge(_ t: String, icon: String, tint: Color) -> some View {
        Label(t, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
    }

    private func info(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(value, systemImage: icon).font(.subheadline.weight(.semibold)).labelStyle(.titleAndIcon)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Небольшая карточка для горизонтальных подборок
struct TrainerMiniCard: View {
    let t: Trainer
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: API.media(t.cover), icon: "figure.strengthtraining.traditional")
                .frame(width: 180, height: 150)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    TrainerAvatar(t: t, size: 36).padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if let r = t.rating, r > 0 {
                        Label(String(format: "%.1f", r), systemImage: "star.fill")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name ?? "Тренер").font(.subheadline.bold()).lineLimit(1)
                Text((t.directions ?? []).prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let p = t.price { Text("\(p) ₽").font(.caption.bold()).foregroundStyle(Color.limeInk) }
                    if let d = t.nextDate {
                        Text("· \(SlotText.short(d))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 180)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// «Мой тренер» — широкая карточка с быстрыми действиями
struct MyTrainerCard: View {
    let t: Trainer
    var body: some View {
        HStack(spacing: 12) {
            TrainerAvatar(t: t, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name ?? "Тренер").font(.headline).lineLimit(1)
                Text(t.link == "active" ? "Занимаетесь вместе" : "Заявка отправлена")
                    .font(.caption.bold())
                    .foregroundStyle(t.link == "active" ? Color.limeInk : .orange)
                if let d = t.nextDate {
                    Text("Свободно: \(SlotText.short(d))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Фильтры

struct TrainerFiltersSheet: View {
    @Bindable var store: TrainersStore
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let prices = [1000, 1500, 2000, 3000, 5000]
    private let exps = [1, 3, 5, 10]
    private let formats = ["В зале", "Онлайн", "На выезде"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Формат") {
                    Picker("Формат", selection: $store.format) {
                        Text("Любой").tag(String?.none)
                        ForEach(formats, id: \.self) { f in
                            Label(f, systemImage: DirectionIcon.format(f)).tag(String?.some(f))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Цена занятия") {
                    Picker("До", selection: $store.priceMax) {
                        Text("Любая").tag(Int?.none)
                        ForEach(prices, id: \.self) { p in Text("до \(p) ₽").tag(Int?.some(p)) }
                    }
                }
                Section("Опыт") {
                    Picker("От", selection: $store.expMin) {
                        Text("Любой").tag(Int?.none)
                        ForEach(exps, id: \.self) { e in Text("от \(e) \(RU.plural(e, "года", "лет", "лет"))").tag(Int?.some(e)) }
                    }
                }
                Section {
                    Toggle(isOn: $store.todayOnly) { Label("Свободны сегодня", systemImage: "clock.badge.checkmark") }
                    Toggle(isOn: $store.favOnly) { Label("Только избранные", systemImage: "heart") }
                }
                if store.filterCount > 0 || !store.dirs.isEmpty {
                    Section {
                        Button("Сбросить всё", role: .destructive) { store.resetFilters() }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Показать") { apply(); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct TrainerDetailView: View {
    let id: Int
    @State private var t: TrainerDetail?
    @State private var errorText: String?
    @State private var chat: ChatRef?
    @State private var opening = false
    @State private var booking = false
    @State private var bookSlot: Int?
    @State private var reviewing = false
    @State private var allReviews = false
    @State private var bioOpen = false

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
        .background(Color.oxBg)
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
                        bookSlot = nil
                        booking = true
                    } label: {
                        VStack(spacing: 0) {
                            Label("Записаться", systemImage: "calendar.badge.plus").font(.headline)
                            if let p = t.price { Text("\(p) ₽ за занятие").font(.caption2).opacity(0.8) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
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
                        .padding(.vertical, 8)
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
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            if let t {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: URL(string: "/#trainer/\(t.userId)", relativeTo: AppSettings.serverURL)?.absoluteURL ?? AppSettings.serverURL,
                              subject: Text(t.name ?? "Тренер"),
                              message: Text("Тренер в Oxion: \(t.name ?? "")")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $booking) {
            BookingSheet(trainerId: id, trainerName: t?.name ?? "Тренер", preselect: bookSlot) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $reviewing) {
            ReviewSheet(trainerId: id, name: t?.name ?? "Тренер", initial: t?.myReview) { Task { await load() } }
        }
        .sheet(isPresented: $allReviews) {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(t?.reviews ?? []) { ReviewRow(r: $0) }
                    }
                    .padding(16)
                }
                .navigationTitle("Отзывы")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ t: TrainerDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gallery(t)

                // имя, статус
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Avatar(url: API.media(t.photo), name: t.name ?? "?", size: 58)
                            .overlay(alignment: .bottomTrailing) {
                                if t.online == true {
                                    Circle().fill(Color.green).frame(width: 15, height: 15)
                                        .overlay(Circle().stroke(Color.oxBg, lineWidth: 2.5))
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name ?? "Тренер").font(.title.bold()).lineLimit(2).minimumScaleFactor(0.8)
                            Text(statusLine(t)).font(.subheadline).foregroundStyle(t.online == true ? .green : .secondary)
                        }
                    }
                    if let link = t.myLink {
                        Label(link == "active" ? "Вы занимаетесь у этого тренера" : "Ваша заявка ждёт подтверждения",
                              systemImage: link == "active" ? "checkmark.seal.fill" : "hourglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(link == "active" ? Color.limeInk : .orange)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background((link == "active" ? Color.lime : Color.orange).opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal)

                stats(t).padding(.horizontal)

                if let slots = t.nextSlots, !slots.isEmpty { slotsBlock(slots) }

                if let d = t.directions, !d.isEmpty {
                    block("Направления") {
                        FlowLabelChips(items: d) { name in
                            Label(name, systemImage: DirectionIcon.of(name))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                    }
                }

                if (t.formats ?? []).count + (t.districts ?? []).count > 0 {
                    block("Где занимается") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(t.formats ?? [], id: \.self) { f in
                                Label(f, systemImage: DirectionIcon.format(f)).font(.subheadline)
                            }
                            if let ds = t.districts, !ds.isEmpty {
                                Label((t.city.map { $0 + ": " } ?? "") + ds.joined(separator: ", "), systemImage: "mappin.and.ellipse")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else if let city = t.city {
                                Label(city, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let bio = t.bio, !bio.isEmpty {
                    block("О тренере") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bio)
                                .font(.body)
                                .lineLimit(bioOpen ? nil : 6)
                            if bio.count > 280 {
                                Button(bioOpen ? "Свернуть" : "Читать полностью") { withAnimation { bioOpen.toggle() } }
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }

                reviewsBlock(t)
            }
            .padding(.bottom, 100)
        }
        .oxNoUnderlap()
    }

    private func statusLine(_ t: TrainerDetail) -> String {
        if t.online == true { return "в сети" }
        var parts: [String] = []
        if let ls = t.lastSeen {
            parts.append("был(а) " + Date(timeIntervalSince1970: ls / 1000).formatted(.relative(presentation: .named)))
        }
        if let s = t.since {
            parts.append("в Oxion с " + Date(timeIntervalSince1970: s / 1000).formatted(.dateTime.month(.wide).year()))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func gallery(_ t: TrainerDetail) -> some View {
        let photos = (t.photos ?? []).compactMap { API.media($0.url) }
        if photos.isEmpty {
            RemoteImage(url: nil, icon: "figure.strengthtraining.traditional")
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 12)
        } else {
            TabView {
                ForEach(photos, id: \.self) { u in
                    RemoteImage(url: u)
                        .frame(height: 400)
                        .clipped()
                }
            }
            .tabViewStyle(.page)
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    private func stats(_ t: TrainerDetail) -> some View {
        HStack(spacing: 0) {
            stat(t.rating.map { $0 > 0 ? String(format: "%.1f", $0) : "—" } ?? "—", "\(t.reviewsCount ?? 0) \(RU.plural(t.reviewsCount ?? 0, "отзыв", "отзыва", "отзывов"))", icon: "star.fill", tint: .yellow)
            Divider().frame(height: 36)
            stat("\(t.clients ?? 0)", RU.plural(t.clients ?? 0, "клиент", "клиента", "клиентов"), icon: "person.2.fill", tint: Color.limeInk)
            Divider().frame(height: 36)
            stat("\(t.sessions ?? 0)", "занятий", icon: "checkmark.circle.fill", tint: .blue)
            Divider().frame(height: 36)
            stat("\(t.experience ?? 0)", RU.plural(t.experience ?? 0, "год опыта", "года опыта", "лет опыта"), icon: "clock.fill", tint: .orange)
        }
        .padding(.vertical, 14)
        .oxCardBG(22)
    }

    private func stat(_ v: String, _ l: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
                Text(v).font(.headline.monospacedDigit())
            }
            Text(l).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func slotsBlock(_ slots: [Slot]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ближайшие окна").font(.title3.bold())
                Spacer()
                Button("Все") { bookSlot = nil; booking = true }.font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(slots) { s in
                        Button {
                            Haptic.tap()
                            bookSlot = s.id
                            booking = true
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(dayLabel(s.date)).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(s.date.formatted(.dateTime.hour().minute())).font(.title3.bold().monospacedDigit())
                                Text("\(s.minutes ?? 60) мин" + (s.price.map { " · \($0) ₽" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(minWidth: 96, alignment: .leading)
                            .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.lime.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "СЕГОДНЯ" }
        if cal.isDateInTomorrow(d) { return "ЗАВТРА" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))).uppercased()
    }

    private func block<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(22)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func reviewsBlock(_ t: TrainerDetail) -> some View {
        let reviews = t.reviews ?? []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Отзывы").font(.title3.bold())
                if !reviews.isEmpty { Text("\(reviews.count)").font(.title3).foregroundStyle(.secondary) }
                Spacer()
                if reviews.count > 3 { Button("Все") { allReviews = true }.font(.subheadline.weight(.semibold)) }
            }
            if !reviews.isEmpty, let dist = t.ratingDist, dist.count == 5 {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", t.rating ?? 0)).font(.system(size: 40, weight: .bold, design: .rounded))
                        StarsView(value: t.rating ?? 0, size: 12)
                    }
                    VStack(spacing: 3) {
                        let mx = max(1, dist.max() ?? 1)
                        ForEach((1...5).reversed(), id: \.self) { star in
                            HStack(spacing: 6) {
                                Text("\(star)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 10)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.08))
                                        Capsule().fill(Color.yellow).frame(width: g.size.width * CGFloat(dist[star - 1]) / CGFloat(mx))
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
            }
            if reviews.isEmpty {
                Text(t.canReview == true ? "Пока нет отзывов — станьте первым" : "Пока нет отзывов. Отзыв можно оставить после занятия.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(reviews.prefix(3)) { ReviewRow(r: $0) }
            if t.canReview == true {
                Button { reviewing = true } label: {
                    Label(t.myReview == nil ? "Оставить отзыв" : "Изменить мой отзыв", systemImage: "star.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(22)
        .padding(.horizontal)
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
            OxAlert.error(error.localizedDescription)
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

struct StarsView: View {
    let value: Double
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= value + 0.25 ? "star.fill" : (Double(i) - 0.5 <= value ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct ReviewRow: View {
    let r: TrainerReview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(url: API.media(r.photo), name: r.name ?? "?", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name ?? "Клиент").font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        StarsView(value: Double(r.rating), size: 10)
                        if let at = r.at {
                            Text(Date(timeIntervalSince1970: at / 1000), format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let t = r.text, !t.isEmpty { Text(t).font(.subheadline) }
            if let reply = r.reply, !reply.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ответ тренера").font(.caption.bold()).foregroundStyle(Color.limeInk)
                    Text(reply).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ReviewSheet: View {
    let trainerId: Int
    let name: String
    let initial: MyReview?
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var text = ""
    @State private var busy = false
    private let hints = ["", "Плохо", "Так себе", "Нормально", "Хорошо", "Отлично!"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Как вам занятия с \(name)?").font(.title3.bold()).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { i in
                        Button {
                            Haptic.tap()
                            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { rating = i }
                        } label: {
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .font(.system(size: 38))
                                .foregroundStyle(i <= rating ? Color.yellow : Color.secondary)
                                .scaleEffect(i == rating ? 1.15 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(hints[rating]).font(.headline).foregroundStyle(.secondary).frame(height: 20)
                TextField("Что понравилось, что можно улучшить", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer()
            }
            .padding(20)
            .navigationTitle("Отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }.bold().disabled(rating == 0 || busy)
                }
                if initial != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Удалить отзыв", role: .destructive) { Task { await remove() } }
                    }
                }
            }
            .onAppear {
                if let initial { rating = initial.rating; text = initial.text ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            let _: OK = try await API.call("/trainers/\(trainerId)/review", method: "POST", body: ["rating": rating, "text": text])
            Haptic.success()
            done(); dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func remove() async {
        let _: OK? = try? await API.call("/trainers/\(trainerId)/review", method: "DELETE")
        done(); dismiss()
    }
}

/// Чипы с переносом строк
struct FlowLabelChips<C: View>: View {
    let items: [String]
    let chip: (String) -> C
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { chip($0) }
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
