import SwiftUI
import UIKit
import PhotosUI

// Общие элементы экранов профиля

struct SectionCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.title3.weight(.semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IconBubble: View {
    let icon: String
    var tint: Color = .lime
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
    }
}

struct LoadingOrError: View {
    let error: String?
    var retry: () -> Void
    var body: some View {
        if let error {
            ErrorStateView(message: error, retry: retry).padding(.top, 40)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        }
    }
}

// MARK: - PRO (размещение анкеты тренера)

struct SubscriptionView: View {
    @Environment(AppModel.self) private var model
    @State private var t: MyTrainer?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    OxBlob(height: 230)
                    VStack(spacing: 6) {
                        Label("PRO", systemImage: "crown.fill")
                            .font(.title.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(Color.white.opacity(0.25)), in: .capsule)
                        Text(t?.published == true ? "Анкета в каталоге" : "Ваша анкета в каталоге тренеров")
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.85))
                    }
                    .allowsHitTesting(false)
                }
                .padding(.top, 8)
                VStack(alignment: .leading, spacing: 14) {
                    benefit("magnifyingglass", "Клиенты находят вас в каталоге своего города")
                    benefit("sparkles", "Попадание в «Тренер для вас» под цель клиента")
                    benefit("bubble.left.and.bubble.right.fill", "Чаты с клиентами, назначение тренировок и целей")
                    benefit("chart.line.uptrend.xyaxis", "Дневники и прогресс клиентов в одном месте")
                    benefit("checkmark.seal.fill", "Значок тренера в ленте и профиле")
                }
                .padding(18)
                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if let t {
                    if t.published == true, let until = t.paidUntil {
                        Label("Опубликована до \(Date(timeIntervalSince1970: until / 1000).formatted(date: .long, time: .omitted))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.lime)
                    } else if let miss = t.missing, !miss.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Чтобы опубликовать, заполните анкету:").font(.subheadline.bold())
                            ForEach(miss, id: \.self) { m in Label(m, systemImage: "circle").font(.subheadline).foregroundStyle(Color.oxHint) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(spacing: 4) {
                    Text("\(model.meta?.subPrice ?? 990) ₽")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("за \(model.meta?.subDays ?? 30) дней размещения")
                        .foregroundStyle(Color.oxHint)
                }
                Button {
                    OxAlert.paymentsOff()
                } label: {
                    Text(t?.published == true ? "Продлить размещение" : "Оплатить и опубликовать")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                NavigationLink {
                    TrainerEditView()
                } label: {
                    Text("Редактировать анкету")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Color.oxBg)
        .oxNoUnderlap()
        .navigationTitle("PRO")
        .navigationBarTitleDisplayMode(.inline)
        .task { t = try? await API.call("/my/trainer") as MyTrainer }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            IconBubble(icon: icon, size: 36)
            Text(text).font(.subheadline)
            Spacer()
        }
    }
}

// MARK: - Анкета тренера

struct TrainerEditView: View {
    @Environment(AppModel.self) private var model
    @State private var t: MyTrainer?
    @State private var bio = ""
    @State private var price = ""
    @State private var directions: Set<String> = []
    @State private var formats: Set<String> = []
    @State private var saving = false
    @State private var photoPick: PhotosPickerItem?
    @State private var errorText: String?

    var body: some View {
        Form {
            if let t {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.published == true ? "В каталоге" : "Не опубликована")
                                .font(.headline)
                                .foregroundStyle(t.published == true ? Color.lime : .orange)
                            if let r = t.rating, r > 0 {
                                Text("Рейтинг \(String(format: "%.1f", r)) · отзывов \(t.reviewsCount ?? 0)").font(.caption).foregroundStyle(Color.oxHint)
                            }
                        }
                        Spacer()
                        NavigationLink("PRO") { SubscriptionView() }
                            .fixedSize()
                    }
                    if let miss = t.missing, !miss.isEmpty {
                        Text("Не хватает: " + miss.joined(separator: ", ")).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("Фото") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(t.photos ?? [], id: \.stableId) { p in
                                RemoteImage(url: API.media(p.url))
                                    .frame(width: 90, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            PhotosPicker(selection: $photoPick, matching: .images) {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Фото").font(.caption)
                                }
                                .frame(width: 90, height: 120)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                Section("О себе") {
                    TextField("Опыт, подход, достижения", text: $bio, axis: .vertical)
                        .lineLimit(4...12)
                }
                Section("Стоимость занятия, ₽") {
                    TextField("Например, 1500", text: $price).keyboardType(.numberPad)
                }
                Section("Направления") {
                    chips(model.meta?.directions ?? [], selection: $directions)
                }
                Section("Форматы") {
                    chips(model.meta?.formats ?? [], selection: $formats)
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            } else {
                LoadingOrError(error: errorText) { Task { await load() } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Моя анкета")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }.disabled(saving || t == nil)
            }
        }
        .onChange(of: photoPick) { Task { await uploadPhoto() } }
        .task { await load() }
    }

    private func chips(_ all: [String], selection: Binding<Set<String>>) -> some View {
        FlowChips(items: all, selected: selection.wrappedValue) { v in
            if selection.wrappedValue.contains(v) { selection.wrappedValue.remove(v) } else { selection.wrappedValue.insert(v) }
            Haptic.tap(.soft)
        }
    }

    private func load() async {
        do {
            let r: MyTrainer = try await API.call("/my/trainer")
            t = r
            bio = r.bio ?? ""
            price = r.price.map(String.init) ?? ""
            directions = Set(r.directions ?? [])
            formats = Set(r.formats ?? [])
        } catch { errorText = error.localizedDescription }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = ["bio": bio, "directions": Array(directions), "formats": Array(formats)]
        if let p = Int(price) { body["price"] = p }
        do {
            let r: MyTrainer = try await API.call("/my/trainer", method: "PATCH", body: body)
            t = r
            Haptic.success()
            OxAlert.show(icon: "checkmark.circle.fill", title: "Анкета сохранена")
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func uploadPhoto() async {
        guard let item = photoPick, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let jpg = API.jpeg(img) else { return }
        photoPick = nil
        do {
            let _: OK = try await API.upload("/my/trainer/photos", data: jpg)
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Чипсы с переносом строк
struct FlowChips: View {
    let items: [String]
    let selected: Set<String>
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { v in
                Button { onTap(v) } label: { Chip(text: v, selected: selected.contains(v)) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Рекорды и достижения

struct RecordsView: View {
    @State private var records: [RecordItem] = []
    @State private var ach: AchievementsResponse?
    @State private var tab = 0
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $tab) {
                    Text("Рекорды").tag(0)
                    Text("Достижения").tag(1)
                }
                .pickerStyle(.segmented)

                if tab == 0 {
                    if loaded && records.isEmpty {
                        ContentUnavailableView("Рекордов пока нет", systemImage: "trophy", description: Text("Записывайте подходы в дневнике — лучшие результаты появятся здесь"))
                    }
                    ForEach(records) { r in
                        HStack(spacing: 14) {
                            Text("🏆").font(.title2)
                                .frame(width: 48, height: 48)
                                .background(Color(hex: 0xF0A030).opacity(0.18), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.headline)
                                Text(r.best).font(.title3.bold()).foregroundStyle(Color.lime)
                                HStack(spacing: 10) {
                                    if let e = r.e1rm { Text("1ПМ ≈ \(Int(e)) кг") }
                                    if let d = r.lastDate { Text(RU.human(d)) }
                                }
                                .font(.caption)
                                .foregroundStyle(Color.oxHint)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                } else if let a = ach {
                    HStack(spacing: 12) {
                        StatTile(title: "получено", value: "\(a.done ?? 0)/\(a.total ?? 0)", icon: "rosette")
                        StatTile(title: "недель подряд", value: "\(a.streak ?? 0)", icon: "flame.fill")
                        StatTile(title: "тренировок", value: "\(a.workouts ?? 0)", icon: "dumbbell.fill")
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(a.items) { x in
                            VStack(spacing: 8) {
                                Text(x.icon).font(.system(size: 40))
                                    .grayscale(x.done ? 0 : 1)
                                    .opacity(x.done ? 1 : 0.45)
                                Text(x.title).font(.subheadline.bold()).multilineTextAlignment(.center)
                                Text(x.desc ?? "").font(.caption).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                                ProgressView(value: Double(x.pct ?? 0), total: 100)
                                    .tint(Color.lime)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(x.done ? Color.lime.opacity(0.5) : Color.clear))
                        }
                    }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Рекорды")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: RecordsResponse = try await API.call("/records")
            records = r.items
            ach = try? await API.call("/achievements") as AchievementsResponse
        } catch { errorText = error.localizedDescription }
        loaded = true
    }
}

// MARK: - Челленджи

struct ChallengesView: View {
    @State private var items: [Challenge] = []
    @State private var loaded = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if loaded && items.isEmpty {
                    ContentUnavailableView("Челленджей пока нет", systemImage: "flag.checkered", description: Text("Скоро здесь появятся соревнования с призами"))
                }
                ForEach(items) { c in
                    NavigationLink {
                        ChallengeDetailView(id: c.id)
                    } label: {
                        ChallengeCard(c: c)
                    }
                    .buttonStyle(.plain)
                }
                if !loaded { LoadingOrError(error: errorText) { Task { await load() } } }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Челленджи")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: ChallengesResponse = try await API.call("/challenges")
            items = r.items
            loaded = true
        } catch { errorText = error.localizedDescription }
    }
}

struct ChallengeCard: View {
    let c: Challenge
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBubble(icon: "flag.checkered", tint: Color(hex: 0x3FD6C9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.headline)
                    Text("\(fmt(c.target)) \(c.unit ?? "")").font(.subheadline).foregroundStyle(Color.oxHint)
                }
                Spacer()
                if c.joined == true {
                    Text("Участвую").font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.lime, in: Capsule()).foregroundStyle(.black)
                }
            }
            if c.joined == true, let my = c.my, let t = c.target, t > 0 {
                ProgressView(value: min(my, t), total: t).tint(Color.lime)
                Text("\(fmt(my)) из \(fmt(t))").font(.caption).foregroundStyle(Color.oxHint)
            }
            HStack(spacing: 12) {
                Label("\(c.members ?? 0)", systemImage: "person.2.fill")
                if let s = c.starts, let e = c.ends { Label("\(RU.human(s)) — \(RU.human(e))", systemImage: "calendar") }
            }
            .font(.caption)
            .foregroundStyle(Color.oxHint)
            if let p = c.prize, !p.isEmpty {
                Label(p, systemImage: "gift.fill").font(.subheadline).foregroundStyle(Color(hex: 0xF0A030))
            }
        }
        .padding(16)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

struct ChallengeDetailView: View {
    let id: Int
    @State private var c: Challenge?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            if let c {
                VStack(alignment: .leading, spacing: 16) {
                    ChallengeCard(c: c)
                    if let p = c.place { Label("Ваше место: \(p)", systemImage: "medal.fill").font(.headline).foregroundStyle(Color.lime) }
                    Button {
                        Task { await join(!(c.joined ?? false)) }
                    } label: {
                        Text(c.joined == true ? "Выйти из челленджа" : "Участвовать")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(c.joined == true ? Color.white.opacity(0.2) : Color.lime)
                    .controlSize(.large)
                    if let board = c.board, !board.isEmpty {
                        Text("Таблица лидеров").font(.title3.bold())
                        ForEach(Array(board.enumerated()), id: \.element.id) { i, b in
                            HStack(spacing: 12) {
                                Text(i < 3 ? ["🥇", "🥈", "🥉"][i] : "\(i + 1)").frame(width: 30)
                                Avatar(url: API.media(b.photo), name: b.name ?? "?", size: 36)
                                Text(b.name ?? "").font(.subheadline)
                                Spacer()
                                Text(String(Int(b.value ?? 0))).font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(16)
            } else {
                LoadingOrError(error: errorText) { Task { await load() } }
            }
        }
        .background(Color.oxBg)
        .navigationTitle("Челлендж")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { c = try await API.call("/challenges/\(id)") as Challenge } catch { errorText = error.localizedDescription }
    }

    private func join(_ on: Bool) async {
        do {
            let _: OK = try await API.call("/challenges/\(id)/join", method: on ? "POST" : "DELETE")
            Haptic.success()
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Цели

struct GoalsView: View {
    @State private var items: [Goal] = []
    @State private var loaded = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loaded && items.isEmpty {
                    ContentUnavailableView("Целей пока нет", systemImage: "target", description: Text("Цели ставит тренер или вы сами — например, «пожать 100 кг»"))
                }
                ForEach(items) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            IconBubble(icon: g.status == "done" ? "checkmark.seal.fill" : "target", tint: g.status == "done" ? Color.lime : Color(hex: 0x3FD6C9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title ?? g.exercise ?? "Цель").font(.headline)
                                if let t = g.trainer?.name { Text("от тренера \(t)").font(.caption).foregroundStyle(Color.oxHint) }
                            }
                            Spacer()
                            Text("\(g.pct ?? 0)%").font(.title3.bold()).foregroundStyle(Color.lime)
                        }
                        ProgressView(value: Double(g.pct ?? 0), total: 100).tint(Color.lime)
                        HStack {
                            if let c = g.current, let t = g.target {
                                Text("\(String(format: "%.0f", c)) → \(String(format: "%.0f", t)) \(g.unit ?? "")")
                            }
                            Spacer()
                            if let d = g.daysLeft, g.status != "done" { Text(d >= 0 ? "осталось \(d) дн." : "срок прошёл") }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.oxHint)
                    }
                    .padding(16)
                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                if !loaded { LoadingOrError(error: errorText) { Task { await load() } } }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Цели")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: GoalsResponse = try await API.call("/goals")
            items = r.items
            loaded = true
        } catch { errorText = error.localizedDescription }
    }
}

// MARK: - Мой тренер

struct MyCoachView: View {
    @Environment(AppModel.self) private var model
    @State private var data: CoachMy?
    @State private var errorText: String?
    @State private var chat: ChatRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let d = data {
                    if (d.trainers ?? []).isEmpty {
                        VStack(spacing: 12) {
                            ContentUnavailableView("Тренер не подключён", systemImage: "person.crop.circle.badge.questionmark",
                                                   description: Text("Найдите тренера в каталоге или отсканируйте его QR — он увидит ваш дневник и сможет вести вас"))
                            Button {
                                model.selectedTab = .trainers
                            } label: {
                                Text("Найти тренера").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                        }
                    }
                    ForEach(d.trainers ?? []) { t in
                        HStack(spacing: 12) {
                            Avatar(url: API.media(t.photo), name: t.name ?? "?", size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.name ?? "Тренер").font(.headline)
                                Text(t.status == "active" ? "Ведёт вас" : "Ожидает подтверждения").font(.caption).foregroundStyle(Color.oxHint)
                                if let p = t.price { Text("\(p) ₽ / занятие").font(.caption).foregroundStyle(Color.lime) }
                            }
                            Spacer()
                            Button {
                                Task { await openChat(t) }
                            } label: { Image(systemName: "bubble.left.fill") }
                                .buttonStyle(.glass)
                        }
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    if let b = d.bookings, !b.isEmpty {
                        SectionCard(title: "Записи на занятия") {
                            ForEach(b) { x in
                                HStack {
                                    IconBubble(icon: "calendar", size: 36)
                                    VStack(alignment: .leading) {
                                        Text(x.startsAt.map { Date(timeIntervalSince1970: $0 / 1000).formatted(date: .abbreviated, time: .shortened) } ?? "").font(.subheadline.bold())
                                        Text("\(x.place ?? "") · \(x.minutes ?? 60) мин").font(.caption).foregroundStyle(Color.oxHint)
                                    }
                                    Spacer()
                                    if let p = x.price { Text("\(p) ₽").font(.subheadline) }
                                }
                            }
                        }
                    }
                    if let c = d.checks, !c.isEmpty {
                        SectionCard(title: "Проверка техники") {
                            ForEach(c) { x in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("🎥 \(x.exercise ?? "Упражнение")").font(.subheadline.bold())
                                    Text(x.answer ?? "Ждёт ответа тренера").font(.caption).foregroundStyle(Color.oxHint)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    NavigationLink { GoalsView() } label: {
                        HStack {
                            IconBubble(icon: "target", tint: Color(hex: 0x3FD6C9))
                            Text("Мои цели").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
                        }
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Мой тренер")
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do { data = try await API.call("/coach/my") as CoachMy } catch { errorText = error.localizedDescription }
    }

    private func openChat(_ t: CoachTrainer) async {
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": t.id])
            chat = ChatRef(id: r.id, name: t.name ?? "Тренер")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Мои клиенты

struct ClientsView: View {
    @Environment(AppModel.self) private var model
    @State private var data: ClientsResponse?
    @State private var errorText: String?
    @State private var showQR = false
    @State private var chat: ChatRef?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Button {
                    showQR = true
                } label: {
                    HStack(spacing: 12) {
                        IconBubble(icon: "qrcode", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Пригласить клиента").font(.headline)
                            Text("Покажите QR — клиент подключится к вам").font(.caption).foregroundStyle(Color.oxHint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
                    }
                    .padding(14)
                    .glassEffect(.regular.tint(Color.lime.opacity(0.12)).interactive(), in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)

                if let d = data {
                    if d.items.isEmpty {
                        ContentUnavailableView("Клиентов пока нет", systemImage: "person.2", description: Text("Когда клиент подключится по вашему QR или ссылке, он появится здесь"))
                    }
                    ForEach(d.items) { c in
                        HStack(spacing: 12) {
                            Avatar(url: API.media(c.photo), name: c.name ?? "?", size: 50)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name ?? "Клиент").font(.headline)
                                Text("Неделя: \(c.weekN ?? 0) из \(c.weekGoal ?? 3)" + (c.lastDate.map { " · был \(RU.human($0).lowercased())" } ?? ""))
                                    .font(.caption).foregroundStyle(Color.oxHint)
                                ProgressView(value: Double(min(c.weekN ?? 0, c.weekGoal ?? 3)), total: Double(max(1, c.weekGoal ?? 3)))
                                    .tint(Color.lime)
                            }
                            Spacer()
                            if let n = c.checksNew, n > 0 {
                                Text("\(n)").font(.caption.bold()).foregroundStyle(.black).padding(6).background(Color.lime, in: Circle())
                            }
                            Button {
                                Task { await openChat(c) }
                            } label: { Image(systemName: "bubble.left.fill") }
                                .buttonStyle(.glass)
                        }
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Мои клиенты")
        .navigationDestination(item: $chat) { ChatView(chatId: $0.id, title: $0.name) }
        .sheet(isPresented: $showQR) { MyCardSheet() }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do { data = try await API.call("/coach/clients") as ClientsResponse } catch { errorText = error.localizedDescription }
    }

    private func openChat(_ c: ClientItem) async {
        do {
            let r: IdResponse = try await API.call("/chats/open", method: "POST", body: ["user_id": c.id])
            chat = ChatRef(id: r.id, name: c.name ?? "Клиент")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Здоровье (Apple Health напрямую)

struct HealthView: View {
    @State private var hk = HealthKitManager.shared
    @State private var server: HealthResponse?
    @State private var asking = false
    @State private var metric = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !hk.enabled {
                    connectCard
                } else {
                    let today = hk.days.last
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        tile("figure.walk", "Шаги сегодня", today?.steps.map { String(Int($0)) } ?? "—", Color.lime)
                        tile("flame.fill", "Активные ккал", today?.kcal.map { String(Int($0)) } ?? "—", Color(hex: 0xF0A030))
                        tile("bed.double.fill", "Сон", sleepText(today?.sleepMin), Color(hex: 0x8E7CFF))
                        tile("heart.fill", "Пульс покоя", today?.restHr.map { "\(Int($0)) уд/мин" } ?? "—", Color(hex: 0xFF5A4E))
                        tile("figure.run", "Дистанция", today?.distanceKm.map { String(format: "%.1f км", $0) } ?? "—", Color(hex: 0x3FD6C9))
                        tile("scalemass.fill", "Вес", hk.weight.map { String(format: "%.1f кг", $0) } ?? "—", Color(hex: 0x58F670))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $metric) {
                            Text("Шаги").tag(0)
                            Text("Ккал").tag(1)
                            Text("Сон").tag(2)
                        }
                        .pickerStyle(.segmented)
                        WeekBars(values: hk.days.map { d in
                            metric == 0 ? (d.steps ?? 0) : metric == 1 ? (d.kcal ?? 0) : (d.sleepMin ?? 0) / 60
                        }, dates: hk.days.map(\.date), color: metric == 0 ? Color.lime : metric == 1 ? Color(hex: 0xF0A030) : Color(hex: 0x8E7CFF),
                           unit: metric == 2 ? "ч" : "")
                        .frame(height: 170)
                    }
                    .padding(16)
                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack {
                        Image(systemName: "checkmark.icloud.fill").foregroundStyle(Color.lime)
                        Text(hk.lastSync.map { "Отправлено в Oxion \($0.formatted(date: .omitted, time: .shortened)) — тренер видит ваши данные" }
                             ?? "Данные отправляются в Oxion автоматически")
                            .font(.caption)
                            .foregroundStyle(Color.oxHint)
                    }
                    Button {
                        Task {
                            await hk.refreshAndSync()
                            Haptic.success()
                        }
                    } label: {
                        HStack {
                            if hk.loading { ProgressView() }
                            Text("Обновить сейчас")
                        }
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    Text("Доступ можно изменить: Настройки iPhone → Здоровье → Доступ к данным → Oxion.")
                        .font(.caption)
                        .foregroundStyle(Color.oxHint)
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Здоровье")
        .refreshable { await hk.refreshAndSync() }
        .task {
            if hk.enabled { await hk.refreshAndSync() }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(LinearGradient(colors: [Color(hex: 0xFF5A7A), Color(hex: 0xFF2D55)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Подключите «Здоровье»").font(.title3.bold())
                    Text("Apple Health").font(.subheadline).foregroundStyle(Color.oxHint)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Шаги, активные калории и дистанция", systemImage: "figure.walk")
                Label("Сон и пульс покоя", systemImage: "bed.double.fill")
                Label("Вес — сразу в дневник", systemImage: "scalemass.fill")
                Label("Тренер видит ваш прогресс", systemImage: "person.2.fill")
            }
            .font(.subheadline)
            .labelStyle(TintedIconLabel(tint: Color.lime))
            Text("Oxion только читает данные и ничего не меняет в «Здоровье».")
                .font(.caption)
                .foregroundStyle(Color.oxHint)
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if asking { ProgressView() }
                    Text("Разрешить доступ")
                }
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(asking || !hk.available)
            if !hk.available {
                Text("«Здоровье» недоступно на этом устройстве").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func connect() async {
        asking = true
        defer { asking = false }
        do {
            try await hk.requestAccess()
            await hk.refreshAndSync()
            Haptic.success()
            if hk.days.allSatisfy({ $0.steps == nil && $0.kcal == nil }) {
                OxAlert.show(icon: "heart.text.square.fill", tint: Color(hex: 0xFF5A4E), title: "Данных пока нет",
                             message: "Если вы не разрешили доступ, включите его: Настройки → Здоровье → Доступ к данным → Oxion.")
            }
        } catch {
            OxAlert.show(icon: "heart.slash.fill", tint: Color(hex: 0xFF5A4E), title: "Прямой доступ пока закрыт",
                         message: "Тестовая установка через Sideloadly не дала приложению право на «Здоровье». Можно подключиться через команду iPhone «Здоровье • Oxion» — данные будут приходить так же.",
                         buttons: [OxAlertButton(title: "Подключить через Команды", role: .primary) { Task { await shortcut() } },
                                   OxAlertButton(title: "Закрыть", role: .cancel)])
        }
    }

    /// Запасной путь: команда iPhone, которая сама отправляет данные «Здоровья» на сервер Oxion
    private func shortcut() async {
        struct Key: Decodable { let url: String?; let connect: String? }
        var key: Key? = try? await API.call("/health/key")
        if key?.connect == nil { key = try? await API.call("/health/key", method: "POST") }
        if let c = key?.connect, let url = URL(string: c) {
            await UIApplication.shared.open(url)
        } else {
            OxAlert.error("Не удалось получить ссылку для команды")
        }
    }

    private func sleepText(_ m: Double?) -> String {
        guard let m, m > 0 else { return "—" }
        return "\(Int(m) / 60) ч \(Int(m) % 60) м"
    }

    private func tile(_ icon: String, _ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBubble(icon: icon, tint: tint, size: 38)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(Color.oxHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Столбики за неделю
struct WeekBars: View {
    let values: [Double]
    let dates: [Date]
    let color: Color
    var unit = ""

    var body: some View {
        let mx = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 6) {
                    Text(v >= 1000 ? String(format: "%.1fк", v / 1000) : (unit == "ч" ? String(format: "%.1f", v) : String(Int(v))))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.oxHint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    GeometryReader { g in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(i == values.count - 1 ? color : color.opacity(0.45))
                                .frame(height: max(4, g.size.height * v / mx))
                        }
                    }
                    Text(i < dates.count ? dayName(dates[i]) : "")
                        .font(.caption2)
                        .foregroundStyle(Color.oxHint)
                }
            }
        }
    }

    private func dayName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EE"
        return f.string(from: d).capitalized
    }
}

// MARK: - Заказы

struct OrdersView: View {
    @State private var items: [MOrder] = []
    @State private var loaded = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if loaded && items.isEmpty {
                    ContentUnavailableView("Заказов пока нет", systemImage: "shippingbox", description: Text("Оформленные заказы спортпита появятся здесь"))
                }
                ForEach(items) { o in
                    HStack(spacing: 12) {
                        RemoteImage(url: API.media(o.photo), icon: "shippingbox.fill")
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Заказ № \(o.num?.value ?? o.id.value ?? "")").font(.headline)
                            Text("\(o.storeName ?? "") · \(o.lines ?? 0) поз.").font(.caption).foregroundStyle(Color.oxHint)
                            Text(o.statusName ?? o.status ?? "").font(.caption.bold()).foregroundStyle(Color.lime)
                        }
                        Spacer()
                        Text(rub(o.totalKop)).font(.headline)
                    }
                    .padding(14)
                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                if !loaded { LoadingOrError(error: errorText) { Task { await load() } } }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Мои заказы")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let r: MOrders = try await API.call("/m/orders")
            items = r.items
            loaded = true
        } catch { errorText = error.localizedDescription }
    }
}

// MARK: - Работа в Oxion

struct WorkView: View {
    @Environment(AppModel.self) private var model
    @State private var me: MMe?
    @State private var applying = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Зарабатывайте вместе с Oxion: доставляйте заказы или продавайте спортивное питание.")
                    .font(.subheadline)
                    .foregroundStyle(Color.oxHint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                jobCard(icon: "bicycle", tint: Color.lime, title: "Курьер",
                        lead: "Доставляйте спортпит из магазинов вашего города. Пешком, на велосипеде или машине.",
                        points: ["Сумма за доставку видна до того, как берёте заказ", "Свободный график: включили «На линии» — получаете заказы",
                                 "Вывод по СБП на карту", "Только имя, телефон и город"],
                        button: courierButton) { courierAction() }
                jobCard(icon: "storefront.fill", tint: Color(hex: 0xF0A030), title: "Свой магазин",
                        lead: "Продавайте спортивное питание тем, кто тренируется: протеин, креатин, батончики.",
                        points: ["Комиссия только с выполненных заказов", "Доставку берут на себя курьеры платформы",
                                 "Подключение — лично с владельцами сервиса по QR"],
                        button: (me?.stores ?? []).isEmpty ? "Открыть магазин" : "Мой магазин") {
                    OxAlert.show(icon: "qrcode.viewfinder", title: "Подключение магазина",
                                 message: "Магазины подключаются лично: владельцы Oxion показывают QR-приглашение, и заявка одобряется сразу. Напишите в поддержку, чтобы договориться о встрече.")
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Работа в Oxion")
        .sheet(isPresented: $applying) { CourierApplySheet { Task { await load() } } }
        .task { await load() }
    }

    private var courierButton: String {
        switch me?.courier?.status {
        case "active": return "Кабинет курьера"
        case "pending": return "Заявка на проверке"
        default: return "Стать курьером"
        }
    }

    private func courierAction() {
        switch me?.courier?.status {
        case "active": OxAlert.soon("Кабинет курьера")
        case "pending": OxAlert.show(icon: "hourglass", title: "Заявка на проверке", message: "Владельцы Oxion проверят заявку и пришлют ответ в бота.")
        default: applying = true
        }
    }

    private func jobCard(icon: String, tint: Color, title: String, lead: String, points: [String], button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IconBubble(icon: icon, tint: tint, size: 52)
            Text(title).font(.title2.bold())
            Text(lead).font(.subheadline).foregroundStyle(Color.oxHint)
            ForEach(points, id: \.self) { p in
                Label(p, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.primary)
                    .labelStyle(TintedIconLabel(tint: tint))
            }
            Button(action: action) {
                Text(button).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .controlSize(.large)
        }
        .padding(18)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func load() async { me = try? await API.call("/m/me") as MMe }
}

struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

struct CourierApplySheet: View {
    var onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var transport = "foot"

    var body: some View {
        NavigationStack {
            Form {
                Section("О вас") {
                    TextField("Имя", text: $name)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                    Picker("Город", selection: $city) {
                        ForEach(model.meta?.cities ?? [], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Как будете доставлять") {
                    Picker("Транспорт", selection: $transport) {
                        Label("Пешком", systemImage: "figure.walk").tag("foot")
                        Label("Велосипед", systemImage: "bicycle").tag("bike")
                        Label("Самокат", systemImage: "scooter").tag("scooter")
                        Label("Машина", systemImage: "car.fill").tag("car")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Стать курьером")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Отправить") { Task { await send() } } }
            }
            .onAppear {
                name = model.me?.displayName ?? ""
                city = model.me?.city ?? (model.meta?.cities?.first ?? "")
            }
        }
    }

    private func send() async {
        do {
            let _: OK = try await API.call("/m/courier/apply", method: "POST",
                                           body: ["name": name, "phone": phone, "city": city, "transport": transport])
            Haptic.success()
            dismiss()
            onDone()
            OxAlert.show(icon: "checkmark.seal.fill", title: "Заявка отправлена", message: "Мы проверим её и пришлём ответ в бота.")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - Панель владельцев платформы

struct PlatformView: View {
    @State private var s: PlatformSummary?
    @State private var tickets: [Ticket] = []
    @State private var invite: PartnerInvite?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let s {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        tile("Заказы\nсегодня", s.ordersToday, "cart.fill", Color.lime)
                        tile("Магазины", s.storesActive, "storefront.fill", Color(hex: 0xF0A030))
                        tile("Курьеры\nна линии", s.couriersOnline, "bicycle", Color(hex: 0x3FD6C9))
                        tile("Заявки\nмагазинов", s.storesPending, "tray.full.fill", Color(hex: 0x8E7CFF))
                        tile("Заявки\nкурьеров", s.couriersPending, "person.badge.clock.fill", Color(hex: 0x8E7CFF))
                        tile("Споры", s.disputesOpen, "exclamationmark.bubble.fill", Color(hex: 0xFF5A4E))
                    }
                    SectionCard(title: "Пригласить партнёра лично") {
                        Text("Покажите QR владельцу магазина или курьеру — заявка одобрится сразу.")
                            .font(.subheadline).foregroundStyle(Color.oxHint)
                        HStack(spacing: 10) {
                            Button { Task { await makeInvite("store") } } label: {
                                Label("Магазин", systemImage: "storefront").frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            .buttonStyle(.glassProminent)
                            Button { Task { await makeInvite("courier") } } label: {
                                Label("Курьер", systemImage: "bicycle").frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                    NavigationLink { NFCTagsAdminView() } label: {
                        HStack {
                            IconBubble(icon: "wave.3.right.circle.fill", size: 38)
                            Text("NFC-метки клубов").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
                        }
                        .padding(14)
                        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    SectionCard(title: "Обращения в поддержку") {
                        if tickets.isEmpty {
                            Text("Открытых обращений нет").foregroundStyle(Color.oxHint)
                        }
                        ForEach(tickets) { t in
                            NavigationLink {
                                TicketView(id: t.id)
                            } label: {
                                HStack(spacing: 12) {
                                    IconBubble(icon: t.lastFrom == "user" ? "envelope.badge.fill" : "envelope.open.fill",
                                               tint: t.lastFrom == "user" ? Color(hex: 0xFF5A4E) : Color.oxHint, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("#\(t.id) \(t.subject ?? "")").font(.subheadline.bold()).lineLimit(1)
                                        Text(t.lastText ?? "").font(.caption).foregroundStyle(Color.oxHint).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
                                }
                                .padding(12)
                                .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Панель платформы")
        .sheet(item: Binding(get: { invite.map { InviteBox(inv: $0) } }, set: { if $0 == nil { invite = nil } })) { box in
            NavigationStack {
                VStack(spacing: 18) {
                    QRView(text: box.inv.link).frame(maxWidth: 280)
                    Text(box.inv.kind == "courier" ? "Приглашение курьера" : "Приглашение магазина").font(.title3.bold())
                    Text("Действует \(box.inv.expiresInDays ?? 7) дн.").foregroundStyle(Color.oxHint)
                    ShareLink(item: box.inv.link) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("QR-приглашение")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func tile(_ title: String, _ v: Int?, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text("\(v ?? 0)").font(.title2.bold())
            Text(title).font(.caption2).foregroundStyle(Color.oxHint).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(12)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        do {
            s = try await API.call("/m/platform/summary") as PlatformSummary
            if let t: TicketsResponse = try? await API.call("/m/platform/tickets") { tickets = t.items }
        } catch { errorText = error.localizedDescription }
    }

    private func makeInvite(_ kind: String) async {
        do {
            invite = try await API.call("/m/platform/invites", method: "POST", body: ["kind": kind, "days": 7]) as PartnerInvite
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

struct InviteBox: Identifiable { let inv: PartnerInvite; var id: String { inv.token } }

struct TicketView: View {
    let id: Int
    @State private var t: TicketFull?
    @State private var reply = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(t?.messages ?? []) { m in
                    HStack {
                        if m.fromAdmin == 1 { Spacer(minLength: 50) }
                        Text(m.text ?? "")
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(m.fromAdmin == 1 ? Color.oxBg : Color.primary)
                            .background(m.fromAdmin == 1 ? Color.lime : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        if m.fromAdmin != 1 { Spacer(minLength: 50) }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle("Обращение #\(id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(t?.status == "closed" ? "Открыть" : "Закрыть") {
                    Task { await setStatus(t?.status == "closed" ? "reopen" : "close") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                TextField("Ответ поддержки", text: $reply, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .task { await load() }
    }

    private func load() async { t = try? await API.call("/m/platform/tickets/\(id)") as TicketFull }

    private func send() async {
        do {
            t = try await API.call("/m/platform/tickets/\(id)", method: "POST", body: ["text": reply]) as TicketFull
            reply = ""
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func setStatus(_ s: String) async {
        do {
            let _: OK = try await API.call("/m/platform/tickets/\(id)/\(s)", method: "POST")
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
