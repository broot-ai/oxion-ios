import SwiftUI
import UIKit

// MARK: - Партнёры OXION: залы, компании, события, магазины, приглашения

struct ClubPerson: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let photo: String?
    let rating: Double?
    let workouts: Int?
    let at: Double?
    let role: String?
}

struct ClubStats: Decodable {
    let members: Int?
    let newWeek: Int?
    let fromQr: Int?
    let checkinsWeek: Int?
    let activeWeek: Int?
    let trainers: Int?
    let bookingsMonth: Int?
}

struct Club: Decodable, Identifiable {
    let id: Int
    let kind: String
    let kindTitle: String?
    let code: String
    let name: String
    let city: String?
    let address: String?
    let about: String?
    let photo: String?
    let promo: String?
    let startsAt: Double?
    let members: Int?
    let role: String?
    let admin: Bool?
    let link: String?
    let trainers: [ClubPerson]?
    let leaders: [ClubPerson]?
    let checkedToday: Bool?
    let checkinsToday: Int?
    let stats: ClubStats?
    let recent: [ClubPerson]?

    var isMember: Bool { role != nil }
    var url: URL {
        URL(string: AppSettings.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/g/" + code)!
    }
    var qrURL: URL { URL(string: url.absoluteString + "?src=qr")! }
    var icon: String { PartnerKind(rawValue: kind)?.icon ?? "building.2.fill" }
    var tint: Color { PartnerKind(rawValue: kind)?.tint ?? .lime }
}

enum PartnerKind: String, CaseIterable, Identifiable {
    case gym, trainer, shop, blogger, company, event
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gym: "Зал или студия"
        case .trainer: "Частный тренер"
        case .shop: "Магазин спортпита"
        case .blogger: "Фитнес-блогер"
        case .company: "Корпоративный спорт"
        case .event: "Забег или турнир"
        }
    }
    var pitch: String {
        switch self {
        case .gym: "QR-постер на ресепшен, отметки посещений, рейтинг клуба и статистика"
        case .trainer: "Клиенты, запись и оплата через приложение, ваш QR-код"
        case .shop: "Ваша скидка в разделе партнёров для всех пользователей OXION"
        case .blogger: "Личная ссылка-приглашение и счётчик пришедших подписчиков"
        case .company: "Клуб компании: рейтинг сотрудников по тренировкам"
        case .event: "Страница события, регистрация по QR и рейтинг участников"
        }
    }
    var icon: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .trainer: "figure.strengthtraining.traditional"
        case .shop: "bag.fill"
        case .blogger: "megaphone.fill"
        case .company: "building.2.fill"
        case .event: "flag.checkered"
        }
    }
    var tint: Color {
        switch self {
        case .gym: .lime
        case .trainer: Color(hex: 0x3FD6C9)
        case .shop: Color(hex: 0xFF9F0A)
        case .blogger: Color(hex: 0xFF375F)
        case .company: Color(hex: 0x0A84FF)
        case .event: Color(hex: 0xBF5AF2)
        }
    }
}

// MARK: - Главный экран «Партнёры»

struct PartnersHubView: View {
    @Environment(AppModel.self) private var model
    struct Mine: Decodable { let items: [Club]; let owner: Bool? }
    struct Promo: Decodable, Identifiable { let id: Int; let name: String; let city: String?; let promo: String?; let about: String? }
    struct Promos: Decodable { let items: [Promo] }
    struct RefMe: Decodable { let code: String; let joined: Int?; let invitedBy: String? }

    @State private var clubs: [Club] = []
    @State private var owner = false
    @State private var promos: [Promo] = []
    @State private var ref: RefMe?
    @State private var loaded = false
    @State private var scanning = false
    @State private var myCard = false
    @State private var openCode: ClubOpen?
    @State private var requestKind: PartnerKind?
    @State private var enterRef = false
    @State private var refInput = ""

    var body: some View {
        List {
            Section {
                Button { scanning = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.onLime)
                            .frame(width: 52, height: 52)
                            .background(Color.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Сканер OXION").font(.headline)
                            Text("QR зала на ресепшене, тренера, события или друга").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Button { myCard = true } label: {
                    Label("Моя QR-визитка", systemImage: "person.crop.square.filled.and.at.rectangle")
                }
            }

            Section {
                if clubs.isEmpty && loaded {
                    Text("Пока нет клубов. Отсканируйте QR-код в вашем зале — и он появится здесь.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(clubs) { c in
                    NavigationLink { ClubView(id: c.id) } label: { ClubRow(club: c) }
                }
            } header: { Text("Мои клубы") }

            if !promos.isEmpty {
                Section {
                    ForEach(promos) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.name).font(.headline)
                                Spacer()
                                if let c = p.city { Text(c).font(.caption).foregroundStyle(.secondary) }
                            }
                            if let pr = p.promo {
                                Text(pr).font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: 0xFF9F0A))
                            }
                            if let a = p.about, !a.isEmpty { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        .padding(.vertical, 2)
                    }
                } header: { Text("Скидки партнёров") } footer: { Text("Покажите экран на кассе партнёра.") }
            }

            Section {
                if let ref {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(ref.code).font(.system(.title2, design: .monospaced).weight(.bold))
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(ref.joined ?? 0)").font(.title2.weight(.bold)).foregroundStyle(Color.lime)
                                Text(RU.plural(ref.joined ?? 0, "пришёл", "пришли", "пришли")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ShareLink(item: refURL(ref.code), message: Text("Тренируйся со мной в OXION")) {
                            Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.lime)
                        .foregroundStyle(Color.onLime)
                    }
                    .padding(.vertical, 4)
                    if ref.invitedBy == nil {
                        Button("Ввести код друга") { enterRef = true }
                    }
                } else {
                    ProgressView()
                }
            } header: { Text("Пригласить друзей") } footer: {
                Text("Блогерам и тренерам: эта ссылка считает, сколько людей пришло именно от вас.")
            }

            Section {
                ForEach(PartnerKind.allCases) { k in
                    Button { requestKind = k } label: {
                        HStack(spacing: 14) {
                            OxRowIcon(icon: k.icon, tint: k.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.title).foregroundStyle(.primary)
                                Text(k.pitch).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Стать партнёром") } footer: {
                Text("Заявка уходит команде OXION. После одобрения клуб и QR-постер появятся у вас в этом разделе.")
            }

            if owner {
                Section {
                    NavigationLink { PartnerRequestsView() } label: { Label("Заявки партнёров", systemImage: "tray.full.fill") }
                    NavigationLink { ClubCreateView { load() } } label: { Label("Создать клуб вручную", systemImage: "plus.circle.fill") }
                } header: { Text("Команда OXION") }
            }
        }
        .navigationTitle("Партнёры")
        .task { load() }
        .refreshable { load() }
        .fullScreenCover(isPresented: $scanning) {
            QRScanScreen { code in
                scanning = false
                handle(code)
            }
        }
        .sheet(isPresented: $myCard) { MyCardSheet() }
        .sheet(item: $openCode) { o in NavigationStack { ClubView(code: o.id, source: o.source) } }
        .sheet(item: $requestKind) { k in NavigationStack { PartnerRequestForm(kind: k) } }
        .alert("Код друга", isPresented: $enterRef) {
            TextField("Например, K7MX2Q", text: $refInput).textInputAutocapitalization(.characters)
            Button("Отмена", role: .cancel) {}
            Button("Готово") { claim(refInput) }
        }
    }

    private func refURL(_ code: String) -> URL {
        URL(string: AppSettings.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/r/" + code)!
    }

    private func load() {
        Task {
            if let r: Mine = try? await API.call("/clubs/mine") { clubs = r.items; owner = r.owner ?? false }
            if let p: Promos = try? await API.call("/partners/promos") { promos = p.items }
            ref = try? await API.call("/refs/me")
            loaded = true
        }
    }

    private func claim(_ code: String) {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { return }
        Task {
            do {
                let _: OK = try await API.call("/refs/claim", method: "POST", body: ["code": c])
                Haptic.success()
                OxAlert.show(icon: "person.2.fill", title: "Готово", message: "Код друга засчитан")
                load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }

    private func handle(_ code: String) {
        switch QRLinks.parse(code) {
        case .url(let u):
            if let r = ProfileLink.route(for: u) {
                let p = r.split(separator: "/").map(String.init)
                if p.first == "club", p.count > 1 { openCode = ClubOpen(id: p[1], source: p.count > 2 ? p[2] : "qr"); return }
                if p.first == "ref", p.count > 1 { claim(p[1]); return }
                model.handle(route: r)
            } else {
                UIApplication.shared.open(u)
            }
        case .trainer(let id): model.handle(route: "trainer/\(id)")
        case .user(let id): model.handle(route: "user/\(id)")
        case .text(let t):
            UIPasteboard.general.string = t
            OxAlert.show(icon: "qrcode", title: "Текст из QR скопирован", message: t)
        }
    }
}

struct ClubOpen: Identifiable { let id: String; var source: String = "link" }

struct ClubRow: View {
    let club: Club
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: club.icon)
                .font(.headline)
                .foregroundStyle(club.tint)
                .frame(width: 44, height: 44)
                .background(club.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name).font(.headline).lineLimit(1)
                Text([club.kindTitle, club.city].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if club.admin == true {
                Text("АДМИН").font(.caption2.weight(.heavy)).foregroundStyle(Color.onLime)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.lime, in: Capsule())
            }
        }
    }
}

// MARK: - Экран клуба

struct ClubView: View {
    var id: Int?
    var code: String?
    var source: String = "app"
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var club: Club?
    @State private var error: String?
    @State private var busy = false
    @State private var poster = false
    @State private var editing = false
    @State private var addMember = false
    @State private var memberName = ""
    @State private var memberRole = "trainer"
    @State private var autoDone = false

    var body: some View {
        Group {
            if let club { content(club) }
            else if let error {
                ContentUnavailableView("Клуб не найден", systemImage: "building.2", description: Text(error))
            } else { ProgressView() }
        }
        .navigationTitle(club?.name ?? "Клуб")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $poster) { if let club { ClubPosterView(club: club) } }
        .sheet(isPresented: $editing) { if let club { NavigationStack { ClubEditView(club: club) { Task { await load() } } } } }
        .alert("Добавить в клуб", isPresented: $addMember) {
            TextField("@имя пользователя", text: $memberName).textInputAutocapitalization(.never)
            Button("Тренер") { memberRole = "trainer"; add() }
            Button("Администратор") { memberRole = "admin"; add() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Тренер появится на странице клуба, администратор увидит статистику и постер") }
    }

    @ViewBuilder private func content(_ c: Club) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: c.icon)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(c.tint)
                            .frame(width: 64, height: 64)
                            .background(c.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(.title2.weight(.bold))
                            Text([c.kindTitle, c.city].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let a = c.address, !a.isEmpty { Label(a, systemImage: "mappin.and.ellipse").font(.subheadline) }
                    if let s = c.startsAt, s > 0 {
                        Label(Date(timeIntervalSince1970: s / 1000).formatted(date: .long, time: .shortened), systemImage: "calendar").font(.subheadline)
                    }
                    if let ab = c.about, !ab.isEmpty { Text(ab).font(.subheadline).foregroundStyle(.secondary) }
                    if let p = c.promo, !p.isEmpty {
                        Label(p, systemImage: "tag.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: 0xFF9F0A))
                    }
                    HStack(spacing: 18) {
                        stat("\(c.members ?? 0)", RU.plural(c.members ?? 0, "участник", "участника", "участников"))
                        stat("\(c.checkinsToday ?? 0)", "сегодня в клубе")
                    }
                    actionButton(c)
                }
                .padding(.vertical, 6)
            }

            if let t = c.trainers, !t.isEmpty {
                Section("Тренеры клуба") {
                    ForEach(t) { p in
                        Button {
                            dismiss()
                            model.handle(route: "trainer/\(p.id)")
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(url: API.media(p.photo), name: p.name ?? "", size: 40)
                                Text(p.name ?? "Тренер").foregroundStyle(.primary)
                                Spacer()
                                if let r = p.rating { Label(String(format: "%.1f", r), systemImage: "star.fill").font(.caption).foregroundStyle(.yellow) }
                            }
                        }
                    }
                }
            }

            Section {
                if (c.leaders ?? []).isEmpty {
                    Text("На этой неделе ещё никто не тренировался. Начните первым!").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array((c.leaders ?? []).enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.headline.monospacedDigit()).frame(width: 24)
                            .foregroundStyle(i == 0 ? Color.lime : .secondary)
                        Avatar(url: API.media(p.photo), name: p.name ?? "", size: 36)
                        Text(p.name ?? "Участник")
                        Spacer()
                        Text("\(p.workouts ?? 0) " + RU.plural(p.workouts ?? 0, "трен.", "трен.", "трен."))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Рейтинг недели") } footer: { Text("Считаются тренировки, записанные в дневнике OXION за 7 дней.") }

            if c.admin == true { adminSections(c) }

            if c.isMember && c.role != "admin" {
                Section {
                    Button("Выйти из клуба", role: .destructive) { leave(c) }
                }
            }
        }
    }

    @ViewBuilder private func adminSections(_ c: Club) -> some View {
        Section {
            Button { poster = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "qrcode")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.onLime)
                        .frame(width: 48, height: 48)
                        .background(Color.lime, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QR-постер для ресепшена").font(.headline).foregroundStyle(.primary)
                        Text("Распечатать, сохранить или отправить в типографию").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ShareLink(item: c.url) { Label("Ссылка на клуб", systemImage: "link") }
            Button { editing = true } label: { Label("Изменить информацию", systemImage: "pencil") }
            Button { memberName = ""; addMember = true } label: { Label("Добавить тренера или админа", systemImage: "person.badge.plus") }
        } header: { Text("Управление") }

        if let s = c.stats {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tile("\(s.members ?? 0)", "участников", "person.3.fill")
                    tile("+\(s.newWeek ?? 0)", "новых за неделю", "arrow.up.right")
                    tile("\(s.fromQr ?? 0)", "пришли по QR", "qrcode")
                    tile("\(s.checkinsWeek ?? 0)", "отметок за неделю", "checkmark.seal.fill")
                    tile("\(s.activeWeek ?? 0)", "тренировались", "flame.fill")
                    tile("\(s.bookingsMonth ?? 0)", "записей к тренерам (30 дн.)", "calendar.badge.clock")
                }
                .padding(.vertical, 4)
            } header: { Text("Статистика") }
        }

        if let r = c.recent, !r.isEmpty {
            Section("Участники") {
                ForEach(r) { p in
                    HStack(spacing: 12) {
                        Avatar(url: API.media(p.photo), name: p.name ?? "", size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name ?? "Участник")
                            if let at = p.at {
                                Text(Date(timeIntervalSince1970: at / 1000).formatted(.relative(presentation: .named)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let role = p.role, role != "member" {
                            Text(role == "admin" ? "админ" : "тренер").font(.caption.weight(.semibold)).foregroundStyle(Color.lime)
                        }
                    }
                    .swipeActions {
                        if p.role != "admin" || p.id != model.me?.id {
                            Button("Убрать", role: .destructive) { remove(c, p) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actionButton(_ c: Club) -> some View {
        if !c.isMember {
            Button { join(c) } label: {
                Text("Вступить в клуб").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.onLime)
            .background(Color.lime, in: Capsule())
            .disabled(busy)
        } else if c.checkedToday == true {
            Label("Вы отметились сегодня", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(Color.lime)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.lime.opacity(0.14), in: Capsule())
        } else {
            Button { checkin(c) } label: {
                Label("Отметиться на тренировке", systemImage: "checkmark.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.onLime)
            .background(Color.lime, in: Capsule())
            .disabled(busy)
        }
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.title3.weight(.bold))
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tile(_ v: String, _ t: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color.lime)
            Text(v).font(.title2.weight(.bold))
            Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        do {
            var cid = id
            if cid == nil, let code {
                let b: Club = try await API.call("/clubs/code/" + code)
                cid = b.id
            }
            guard let cid else { return }
            let c: Club = try await API.call("/clubs/\(cid)")
            club = c
            // скан QR на ресепшене: сразу вступаем и отмечаем посещение
            if source == "qr" && !autoDone {
                autoDone = true
                if !c.isMember { join(c, then: true) } else if c.checkedToday != true { checkin(c) }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func join(_ c: Club, then checkinAfter: Bool = false) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let _: Club = try await API.call("/clubs/\(c.id)/join", method: "POST", body: ["source": source == "qr" ? "qr" : (code != nil ? "link" : "app")])
                Haptic.success()
                if checkinAfter {
                    let _: OK = try await API.call("/clubs/\(c.id)/checkin", method: "POST")
                    OxAlert.show(icon: "checkmark.seal.fill", title: "Добро пожаловать!", message: "Вы в клубе «\(c.name)», посещение отмечено")
                }
                await load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }

    private func checkin(_ c: Club) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let _: OK = try await API.call("/clubs/\(c.id)/checkin", method: "POST")
                Haptic.success()
                OxAlert.show(icon: "checkmark.seal.fill", title: "Посещение отмечено", message: "Хорошей тренировки в «\(c.name)»")
                await load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }

    private func leave(_ c: Club) {
        OxAlert.show(icon: "rectangle.portrait.and.arrow.right", tint: .red, title: "Выйти из клуба?", message: c.name, buttons: [
            OxAlertButton(title: "Выйти", role: .destructive) {
                Task {
                    do {
                        let _: OK = try await API.call("/clubs/\(c.id)/leave", method: "POST")
                        await load()
                    } catch { OxAlert.error(error.localizedDescription) }
                }
            },
            OxAlertButton(title: "Отмена", role: .cancel) {}
        ])
    }

    private func add() {
        guard let c = club else { return }
        let n = memberName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let _: OK = try await API.call("/clubs/\(c.id)/members", method: "POST", body: ["username": n, "role": memberRole])
                Haptic.success()
                await load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }

    private func remove(_ c: Club, _ p: ClubPerson) {
        Task {
            do {
                let _: OK = try await API.call("/clubs/\(c.id)/members/\(p.id)", method: "DELETE")
                await load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }
}

// MARK: - Редактирование клуба

struct ClubEditView: View {
    let club: Club
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var address = ""
    @State private var about = ""
    @State private var promo = ""

    var body: some View {
        Form {
            Section("Название") { TextField("Название", text: $name) }
            Section("Где") {
                TextField("Город", text: $city)
                TextField("Адрес", text: $address)
            }
            Section("О клубе") { TextField("Пара слов для клиентов", text: $about, axis: .vertical).lineLimit(3...8) }
            Section {
                TextField("Например: −10% на абонемент по коду OXION", text: $promo)
            } header: { Text("Скидка для пользователей OXION") } footer: {
                Text(club.kind == "shop" ? "Скидка появится в разделе «Партнёры» у всех пользователей." : "Показывается на странице клуба.")
            }
        }
        .navigationTitle("Клуб")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(name.count < 2) }
        }
        .onAppear {
            name = club.name; city = club.city ?? ""; address = club.address ?? ""; about = club.about ?? ""; promo = club.promo ?? ""
        }
    }

    private func save() {
        Task {
            do {
                let _: Club = try await API.call("/clubs/\(club.id)", method: "PATCH",
                                                 body: ["name": name, "city": city, "address": address, "about": about, "promo": promo])
                Haptic.success()
                onSave()
                dismiss()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }
}

// MARK: - Создание клуба (команда OXION)

struct ClubCreateView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "gym"
    @State private var name = ""
    @State private var city = ""
    @State private var address = ""
    @State private var promo = ""
    @State private var hasDate = false
    @State private var date = Date().addingTimeInterval(7 * 86400)
    @State private var busy = false

    var body: some View {
        Form {
            Picker("Тип", selection: $kind) {
                Text("Зал").tag("gym")
                Text("Компания").tag("company")
                Text("Мероприятие").tag("event")
                Text("Магазин").tag("shop")
            }
            .pickerStyle(.segmented)
            Section {
                TextField("Название", text: $name)
                TextField("Город", text: $city)
                TextField("Адрес", text: $address)
                TextField("Скидка (необязательно)", text: $promo)
            }
            if kind == "event" {
                Section { DatePicker("Дата старта", selection: $date) }
            }
            Section {
                Button(busy ? "Создаю…" : "Создать") { create() }.disabled(name.count < 2 || busy)
            } footer: {
                Text("Вы станете администратором. Владельца клуба потом добавьте как админа по @имени.")
            }
        }
        .navigationTitle("Новый клуб")
    }

    private func create() {
        busy = true
        Task {
            defer { busy = false }
            var b: [String: Any] = ["kind": kind, "name": name, "city": city, "address": address, "promo": promo]
            if kind == "event" { b["starts_at"] = Int(date.timeIntervalSince1970 * 1000) }
            do {
                let _: Club = try await API.call("/clubs", method: "POST", body: b)
                Haptic.success()
                onDone()
                dismiss()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }
}

// MARK: - Заявка партнёра

struct PartnerRequestForm: View {
    let kind: PartnerKind
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var contact = ""
    @State private var details = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    OxRowIcon(icon: kind.icon, tint: kind.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.headline)
                        Text(kind.pitch).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField(kind == .blogger || kind == .trainer ? "Имя или ник" : "Название", text: $name)
                TextField("Город", text: $city)
                TextField("Телефон или Telegram", text: $contact)
            }
            Section {
                TextField(placeholder, text: $details, axis: .vertical).lineLimit(3...10)
            } header: { Text("Подробнее") }
            Section {
                Button(busy ? "Отправляю…" : "Отправить заявку") { send() }
                    .disabled(name.count < 2 || contact.count < 3 || busy)
            } footer: { Text("Ответим в течение пары дней. Деньги за подключение не берём.") }
        }
        .navigationTitle("Заявка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
    }

    private var placeholder: String {
        switch kind {
        case .gym: "Адрес, сколько клиентов и тренеров, что хотите получить"
        case .trainer: "Направления, опыт, где тренируете"
        case .shop: "Какую скидку готовы дать пользователям OXION"
        case .blogger: "Ссылки на соцсети и размер аудитории"
        case .company: "Сколько сотрудников, какие активности хотите"
        case .event: "Дата, формат, ожидаемое число участников"
        }
    }

    private func send() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let _: OK = try await API.call("/partners/request", method: "POST",
                                               body: ["kind": kind.rawValue, "name": name, "city": city, "contact": contact, "details": details])
                Haptic.success()
                OxAlert.show(icon: "paperplane.fill", title: "Заявка отправлена", message: "Мы свяжемся с вами по указанному контакту")
                dismiss()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }
}

// MARK: - Очередь заявок (команда OXION)

struct PartnerRequestsView: View {
    struct Req: Decodable, Identifiable {
        struct U: Decodable { let id: Int; let name: String? }
        let id: Int; let kind: String; let name: String; let city: String?; let contact: String?
        let details: String?; let status: String; let user: U?; let at: Double?
    }
    struct Resp: Decodable { let items: [Req] }
    @State private var items: [Req] = []

    var body: some View {
        List {
            if items.isEmpty { Text("Заявок пока нет").foregroundStyle(.secondary) }
            ForEach(items) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        let k = PartnerKind(rawValue: r.kind)
                        Image(systemName: k?.icon ?? "questionmark").foregroundStyle(k?.tint ?? .gray)
                        Text(r.name).font(.headline)
                        Spacer()
                        Text(statusTitle(r.status)).font(.caption.weight(.semibold))
                            .foregroundStyle(r.status == "approved" ? Color.lime : r.status == "rejected" ? .red : .orange)
                    }
                    Text([PartnerKind(rawValue: r.kind)?.title, r.city].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let c = r.contact { Text("Контакт: " + c).font(.subheadline).textSelection(.enabled) }
                    if let d = r.details, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                    if let u = r.user { Text("От: \(u.name ?? "—") · id \(u.id)").font(.caption2).foregroundStyle(.tertiary) }
                    if r.status == "new" {
                        HStack {
                            Button("Одобрить") { act(r, "approve") }.buttonStyle(.borderedProminent).tint(.lime).foregroundStyle(Color.onLime)
                            Button("Отклонить", role: .destructive) { act(r, "reject") }.buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Заявки")
        .task { await load() }
        .refreshable { await load() }
    }

    private func statusTitle(_ s: String) -> String {
        switch s { case "approved": "одобрена"; case "rejected": "отклонена"; default: "новая" }
    }

    private func load() async {
        if let r: Resp = try? await API.call("/partners/requests") { items = r.items }
    }

    private func act(_ r: Req, _ a: String) {
        Task {
            do {
                let _: OK = try await API.call("/partners/requests/\(r.id)/\(a)", method: "POST")
                Haptic.success()
                await load()
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }
}

// MARK: - QR-постер для ресепшена

struct ClubPosterView: View {
    let club: Club
    @Environment(\.dismiss) private var dismiss
    enum Style: String, CaseIterable, Identifiable {
        case dark = "Тёмный", light = "Для печати", sticker = "Наклейка"
        var id: String { rawValue }
    }
    @State private var style: Style = .dark
    @State private var rendered: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Стиль", selection: $style) {
                    ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                GeometryReader { g in
                    let s = posterSize
                    let k = min(g.size.width / s.width, g.size.height / s.height)
                    ClubPoster(club: club, style: style)
                        .frame(width: s.width, height: s.height)
                        .scaleEffect(k)
                        .frame(width: g.size.width, height: g.size.height)
                        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
                    Button { save() } label: { Label("Сохранить", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button { printIt() } label: { Label("Печать", systemImage: "printer.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    if let img = rendered {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(club.name, image: Image(uiImage: img))) {
                            Label("Отправить", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.lime)
                        .foregroundStyle(Color.onLime)
                    }
                }
                .controlSize(.large)
                .padding(.horizontal)
                Text("Клиент сканирует камерой iPhone → вступает в клуб и отмечает посещение. Без OXION откроется страница со ссылкой на скачивание.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            .padding(.vertical)
            .navigationTitle("Постер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task(id: style) { rendered = render() }
        }
    }

    private var posterSize: CGSize { style == .sticker ? CGSize(width: 400, height: 400) : CGSize(width: 595, height: 842) }

    @MainActor private func render() -> UIImage? {
        let r = ImageRenderer(content: ClubPoster(club: club, style: style).frame(width: posterSize.width, height: posterSize.height))
        r.scale = 4
        return r.uiImage
    }

    private func save() {
        guard let img = rendered ?? render() else { return }
        PhotoSaver.save(img) { ok in
            if ok { Haptic.success(); OxAlert.show(icon: "checkmark.circle.fill", title: "Сохранено в «Фото»") }
            else { PermPrompt.show(.photos, denied: true) }
        }
    }

    private func printIt() {
        guard let img = rendered ?? render() else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = style == .dark ? .photo : .general
        info.jobName = "OXION — " + club.name
        let pc = UIPrintInteractionController.shared
        pc.printInfo = info
        pc.printingItem = img
        pc.present(animated: true)
    }
}

/// Сам постер (рисуется и на экране, и в картинку для печати)
struct ClubPoster: View {
    let club: Club
    let style: ClubPosterView.Style

    private var dark: Bool { style == .dark }
    private var fg: Color { dark ? .white : Color(hex: 0x0F1012) }
    private var bg: Color { dark ? Color(hex: 0x0F1012) : .white }
    private let lime = Color(hex: 0xB2EE37)

    var body: some View {
        if style == .sticker { sticker } else { poster }
    }

    private var qr: some View {
        ZStack {
            RoundQR(text: club.qrURL.absoluteString, color: Color(hex: 0x0F1012))
                .padding(18)
            Image(systemName: "flame.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(hex: 0x0F1012))
                .frame(width: 54, height: 54)
                .background(lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(dark ? .clear : Color(hex: 0x0F1012).opacity(0.12), lineWidth: 2))
    }

    private var logo: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: 0x0F1012))
                .frame(width: 36, height: 36)
                .background(lime, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("OXION").font(.system(size: 24, weight: .black)).tracking(2).foregroundStyle(fg)
        }
    }

    private var headline: String {
        switch club.kind {
        case "event": "Регистрация участников"
        case "company": "Тренируемся командой"
        case "shop": "Скидка для OXION"
        default: "Отметься на тренировке"
        }
    }

    private var poster: some View {
        VStack(spacing: 0) {
            HStack {
                logo
                Spacer()
                Text(club.kindTitle?.uppercased() ?? "КЛУБ").font(.system(size: 12, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Color(hex: 0x0F1012))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(lime, in: Capsule())
            }
            Spacer(minLength: 26)
            Text(headline)
                .font(.system(size: 44, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(fg)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(club.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(dark ? lime : Color(hex: 0x4E7A00))
                .padding(.top, 8)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
            qr.frame(width: 300)
            Spacer(minLength: 24)
            HStack(alignment: .top, spacing: 14) {
                step("1", "camera.fill", "Наведите камеру iPhone")
                step("2", "person.badge.plus", "Вступите в клуб")
                step("3", "trophy.fill", club.kind == "shop" ? "Получите скидку" : "Попадите в рейтинг")
            }
            if let p = club.promo, !p.isEmpty {
                Text(p)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0F1012))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(lime, in: Capsule())
                    .padding(.top, 18)
            }
            Spacer(minLength: 20)
            Text("Код клуба: \(club.code)  ·  \(club.url.host ?? "")/g/\(club.code)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(fg.opacity(0.55))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }

    private func step(_ n: String, _ icon: String, _ t: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(dark ? Color.white.opacity(0.08) : Color(hex: 0x0F1012).opacity(0.06)).frame(width: 52, height: 52)
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(dark ? lime : Color(hex: 0x0F1012))
            }
            Text(t).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center).foregroundStyle(fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var sticker: some View {
        VStack(spacing: 14) {
            logo
            qr.frame(width: 250)
            Text(club.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: 0x0F1012)).lineLimit(1)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lime)
    }
}
