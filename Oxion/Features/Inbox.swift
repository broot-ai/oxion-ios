import SwiftUI

// Уведомления: системные события + заявки клиентов (для тренера).
// Колокольчик на главной справа от PRO, счётчик непрочитанных.

struct InboxUser: Decodable, Hashable { let id: Int; let name: String?; let photo: String? }

struct InboxItem: Decodable, Identifiable {
    let id: Int
    let kind: String?
    let title: String?
    let text: String?
    let at: Double?
    let read: Bool?
    let hash: String?
    let user: InboxUser?
    var isRequest: Bool { kind == "request" }
    var date: Date? { at.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct InboxResponse: Decodable { let unread: Int?; let requests: Int?; let items: [InboxItem] }
struct InboxCount: Decodable { let unread: Int?; let requests: Int? }

@MainActor
@Observable
final class InboxStore {
    static let shared = InboxStore()
    var unread = 0
    var requests = 0

    func refresh() {
        Task {
            if let c: InboxCount = try? await API.call("/inbox/count") {
                unread = c.unread ?? 0
                requests = c.requests ?? 0
            }
        }
    }
}

/// Кружок с колокольчиком и счётчиком
struct InboxBell: View {
    @State private var store = InboxStore.shared
    var body: some View {
        NavigationLink { InboxView() } label: {
            Image(systemName: store.unread > 0 ? "bell.badge.fill" : "bell.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if store.unread > 0 {
                        Text(store.unread > 99 ? "99+" : "\(store.unread)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(Color.red, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(store.unread > 0 ? "Уведомления: \(store.unread)" : "Уведомления")
        .onAppear { store.refresh() }
    }
}

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var data: InboxResponse?
    @State private var errorText: String?
    @State private var busy: Int?
    @State private var card: InboxUser?
    @State private var filter = 0

    private var items: [InboxItem] {
        let all = data?.items ?? []
        switch filter {
        case 1: return all.filter(\.isRequest)
        case 2: return all.filter { !$0.isRequest }
        default: return all
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if (data?.requests ?? 0) > 0 {
                    Picker("", selection: $filter) {
                        Text("Все").tag(0)
                        Text("Заявки · \(data?.requests ?? 0)").tag(1)
                        Text("Системные").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                if let _ = data {
                    if items.isEmpty {
                        ContentUnavailableView("Уведомлений нет", systemImage: "bell.slash",
                                               description: Text("Здесь появятся заявки клиентов, записи и системные события"))
                            .padding(.top, 60)
                    }
                    ForEach(items) { it in row(it) }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Уведомления")
        .navigationDestination(item: $card) { u in ClientCardView(userId: u.id, name: u.name ?? "Пользователь") }
        .oxRefreshable { await load() }
        .task { await load() }
        .onDisappear {
            Task {
                let _: OK? = try? await API.call("/inbox/read", method: "POST", body: [:])
                InboxStore.shared.refresh()
            }
        }
    }

    @ViewBuilder
    private func row(_ it: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let u = it.user {
                    Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 46)
                } else {
                    IconBubble(icon: "bell.fill", size: 46)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if it.isRequest {
                            Text("ЗАЯВКА").font(.caption2.bold()).foregroundStyle(Color.onLime)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.lime, in: Capsule())
                        }
                        if let d = it.date {
                            Text(d, format: .relative(presentation: .named)).font(.caption).foregroundStyle(Color.oxHint)
                        }
                        Spacer()
                        if it.read == false { Circle().fill(Color.lime).frame(width: 8, height: 8) }
                    }
                    Text(it.title ?? "").font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let t = it.text, !t.isEmpty {
                        Text(t).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if it.isRequest, let u = it.user {
                HStack(spacing: 8) {
                    Button { card = u } label: {
                        Label("Профиль", systemImage: "person.text.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { Task { await decide(u.id, accept: false) } } label: {
                        Image(systemName: "xmark").frame(width: 30)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Отклонить")
                    Button { Task { await decide(u.id, accept: true) } } label: {
                        Label(busy == u.id ? "…" : "Принять", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime)
                }
                .font(.subheadline.weight(.semibold))
                .disabled(busy != nil)
            } else if it.user != nil || it.hash != nil {
                HStack(spacing: 8) {
                    if let u = it.user, model.me?.mode == "trainer" {
                        Button { card = u } label: { Label("Профиль", systemImage: "person.text.rectangle") }
                            .buttonStyle(.glass)
                    }
                    if let h = it.hash, !h.isEmpty {
                        Button { model.handle(route: h) } label: { Label("Открыть", systemImage: "arrow.up.right") }
                            .buttonStyle(.glass)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(22)
        .contextMenu {
            if !it.isRequest {
                Button(role: .destructive) { Task { await remove(it) } } label: { Label("Удалить", systemImage: "trash") }
            }
        }
    }

    private func load() async {
        do {
            data = try await API.call("/inbox")
            errorText = nil
            InboxStore.shared.unread = data?.unread ?? 0
        } catch { errorText = error.localizedDescription }
    }

    private func decide(_ id: Int, accept: Bool) async {
        busy = id
        defer { busy = nil }
        do {
            let _: OK = try await API.call("/coach/clients/\(id)", method: accept ? "POST" : "DELETE", body: [:])
            accept ? Haptic.success() : Haptic.tap()
            OxAlert.show(icon: accept ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark",
                         title: accept ? "Клиент добавлен" : "Заявка отклонена",
                         message: accept ? "Теперь вы видите его дневник" : "")
            await load()
            BookingStore.shared.refreshTrainer()
            InboxStore.shared.refresh()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func remove(_ it: InboxItem) async {
        let _: OK? = try? await API.call("/inbox/\(it.id)", method: "DELETE")
        await load()
    }
}

// MARK: - Карточка клиента для тренера

struct ClientCard: Decodable {
    struct Weight: Decodable { let kg: Double?; let date: String?; let delta30: Double?; let history: [WPoint]? }
    struct WPoint: Decodable, Identifiable { let date: String; let kg: Double; var id: String { date } }
    struct Stats: Decodable { let workouts: Int?; let streak: Int?; let month: Int?; let lastDate: String?; let lastTitle: String?; let sessions: Int? }
    struct Group: Decodable, Identifiable { let key: String; let n: Int; var id: String { key } }
    struct Record: Decodable, Identifiable { let name: String; let weight: Double?; let reps: Int?; var id: String { name } }
    struct Medal: Decodable, Identifiable { let key: String; let title: String?; let medal: String?; let group: String?; var id: String { key } }
    struct Trainer: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let status: String?; let since: Double? }

    let id: Int
    let name: String?
    let username: String?
    let photo: String?
    let city: String?
    let goal: String?
    let level: String?
    let weekGoal: Int?
    let bio: String?
    let since: Double?
    let lastSeen: Double?
    let linkStatus: String?
    let weight: Weight?
    let stats: Stats?
    let groups: [Group]?
    let records: [Record]?
    let medals: [Medal]?
    let trainers: [Trainer]?
}

struct ClientCardView: View {
    let userId: Int
    let name: String
    @State private var c: ClientCard?
    @State private var errorText: String?
    @State private var chat: ChatRef?
    @State private var busy = false

    var body: some View {
        ScrollView {
            if let c {
                VStack(spacing: 14) {
                    header(c)
                    if c.linkStatus == "pending" { requestBar }
                    statsGrid(c)
                    if let w = c.weight { weightCard(w) }
                    if let g = c.groups, !g.isEmpty { groupsCard(g) }
                    if let r = c.records, !r.isEmpty { recordsCard(r) }
                    medalsCard(c.medals ?? [])
                    trainersCard(c.trainers ?? [])
                }
                .padding(16)
            } else {
                LoadingOrError(error: errorText) { Task { await load() } }.padding(.top, 80)
            }
        }
        .background(Color.oxBg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
        .oxRefreshable { await load() }
        .task { await load() }
    }

    private func header(_ c: ClientCard) -> some View {
        VStack(spacing: 10) {
            Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 92)
            Text(c.name ?? name).font(.title2.bold())
            HStack(spacing: 6) {
                if let u = c.username, !u.isEmpty { Text("@\(u)") }
                if let city = c.city, !city.isEmpty { Text("· \(city)") }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let bio = c.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let g = c.goal, !g.isEmpty { chip("target", "Цель: \(g)") }
                if let l = c.level, !l.isEmpty { chip("chart.bar.fill", l) }
                chip("calendar", "\(c.weekGoal ?? 3)/нед")
            }
            Button {
                Task {
                    do {
                        let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": c.id])
                        chat = ChatRef(id: r.id, name: c.name ?? name)
                    } catch { OxAlert.error(error.localizedDescription) }
                }
            } label: { Label("Написать", systemImage: "bubble.left.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .oxCardBG(24)
    }

    private func chip(_ icon: String, _ t: String) -> some View {
        Label(t, systemImage: icon).font(.caption.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private var requestBar: some View {
        HStack(spacing: 8) {
            Button { Task { await decide(false) } } label: { Label("Отклонить", systemImage: "xmark").frame(maxWidth: .infinity) }
                .buttonStyle(.glass)
            Button { Task { await decide(true) } } label: { Label("Принять клиента", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Color.lime)
        }
        .font(.headline)
        .controlSize(.large)
        .disabled(busy)
    }

    private func statsGrid(_ c: ClientCard) -> some View {
        let s = c.stats
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("dumbbell.fill", "Тренировок всего", "\(s?.workouts ?? 0)")
            tile("calendar.badge.clock", "За 30 дней", "\(s?.month ?? 0)")
            tile("flame.fill", "Недель подряд", "\(s?.streak ?? 0)")
            tile("clock.arrow.circlepath", "Последняя", s?.lastDate.map { RU.human($0) } ?? "—")
        }
    }

    private func tile(_ icon: String, _ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.limeInk)
            Text(v).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(20)
    }

    private func weightCard(_ w: ClientCard.Weight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Вес тела", systemImage: "scalemass.fill").font(.caption.bold()).foregroundStyle(Color.limeInk)
            HStack(alignment: .firstTextBaseline) {
                Text(w.kg.map { String(format: "%.1f кг", $0) } ?? "—").font(.title.bold())
                if let d = w.delta30, d != 0 {
                    Text(String(format: "%+.1f кг", d)).font(.subheadline.bold())
                        .foregroundStyle(d < 0 ? Color.lime : .orange)
                }
                Spacer()
                if let date = w.date { Text(RU.human(date)).font(.caption).foregroundStyle(.secondary) }
            }
            if let h = w.history, h.count > 1 {
                let lo = (h.map(\.kg).min() ?? 0) - 0.5, hi = (h.map(\.kg).max() ?? 1) + 0.5
                GeometryReader { geo in
                    Path { p in
                        for (i, pt) in h.enumerated() {
                            let x = geo.size.width * CGFloat(i) / CGFloat(h.count - 1)
                            let y = geo.size.height * (1 - CGFloat((pt.kg - lo) / max(0.1, hi - lo)))
                            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 60)
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    private func groupsCard(_ g: [ClientCard.Group]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Что тренирует (30 дней)", systemImage: "figure.strengthtraining.traditional").font(.caption.bold()).foregroundStyle(Color.limeInk)
            let mx = g.map(\.n).max() ?? 1
            ForEach(g) { x in
                HStack {
                    Text(Muscles.fallback[x.key] ?? x.key).font(.subheadline).frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Color.lime.opacity(0.85))
                            .frame(width: max(8, geo.size.width * CGFloat(x.n) / CGFloat(mx)))
                    }
                    .frame(height: 8)
                    Text("\(x.n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    private func recordsCard(_ r: [ClientCard.Record]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Лучшие веса", systemImage: "trophy.fill").font(.caption.bold()).foregroundStyle(Color.limeInk)
            ForEach(r) { x in
                HStack {
                    Text(x.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(x.weight.map { String(format: "%g кг", $0) } ?? "—").font(.subheadline.bold().monospacedDigit())
                }
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    private func medalsCard(_ m: [ClientCard.Medal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Достижения · \(m.count)", systemImage: "medal.fill").font(.caption.bold()).foregroundStyle(Color.limeInk)
            if m.isEmpty {
                Text("Пока нет медалей").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(m) { x in
                            VStack(spacing: 4) {
                                if let img = x.medal, UIImage(named: img) != nil {
                                    Image(img).resizable().scaledToFit().frame(width: 54, height: 54)
                                } else {
                                    Image(systemName: "medal.fill").font(.title).frame(width: 54, height: 54)
                                }
                                Text(x.title ?? "").font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: 72)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(22)
    }

    private func trainersCard(_ t: [ClientCard.Trainer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Другие тренеры", systemImage: "person.2.fill").font(.caption.bold()).foregroundStyle(Color.limeInk)
            if t.isEmpty {
                Text("Раньше ни с кем не занимался в Oxion").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(t) { x in
                HStack(spacing: 10) {
                    Avatar(url: API.media(x.photo), name: x.name ?? "?", size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(x.name ?? "Тренер").font(.subheadline.weight(.semibold))
                        if let s = x.since {
                            Text("с \(Date(timeIntervalSince1970: s / 1000).formatted(.dateTime.month(.wide).year()))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(x.status == "active" ? "занимается" : "заявка").font(.caption.bold())
                        .foregroundStyle(x.status == "active" ? Color.limeInk : .secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(22)
    }

    private func load() async {
        do { c = try await API.call("/coach/clients/\(userId)/card"); errorText = nil } catch { errorText = error.localizedDescription }
    }

    private func decide(_ accept: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let _: OK = try await API.call("/coach/clients/\(userId)", method: accept ? "POST" : "DELETE", body: [:])
            accept ? Haptic.success() : Haptic.tap()
            BookingStore.shared.refreshTrainer()
            InboxStore.shared.refresh()
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
