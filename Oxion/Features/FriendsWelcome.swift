import SwiftUI

// «Друзья» — как «Поделиться» в Apple Фитнес: активность тех, на кого подписан, подбодрить, предложения.
// «Встречайте Oxion» — приветствие в стиле Apple Фитнес при первом запуске.

struct FriendsActivity: Decodable {
    struct Me: Decodable { let week: Int; let goal: Int }
    struct Friend: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let week: Int; let goal: Int; let setsToday: Int?; let last: String?; let mutual: Bool? }
    struct Suggestion: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let source: String? }
    let me: Me
    let friends: [Friend]
    let suggestions: [Suggestion]
}

struct FriendsActivityView: View {
    @State private var data: FriendsActivity?
    @State private var error: String?
    @State private var hidden: Set<Int> = Set(UserDefaults.standard.array(forKey: "friends.hidden") as? [Int] ?? [])
    @State private var added: Set<Int> = []
    @State private var cheered: Set<Int> = []
    @State private var openUser: Int?
    @State private var privacy = false

    private let invite = "Тренируйся со мной в Oxion 💪 Будем следить за прогрессом друг друга: https://fit-app.brootai.workers.dev"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let d = data {
                    if d.friends.isEmpty { emptyHero } else { myWeek(d.me); friendsList(d.friends) }
                    let sugg = d.suggestions.filter { !hidden.contains($0.id) && !added.contains($0.id) }
                    if !sugg.isEmpty { suggestions(sugg) }
                } else {
                    LoadingOrError(error: error) { Task { await load() } }.frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.oxBg)
        .navigationTitle("Друзья")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: invite) { Image(systemName: "person.badge.plus") }
            }
        }
        .oxRefreshable { await load() }
        .task { await load() }
        .navigationDestination(item: $openUser) { UserProfileView(userId: $0) }
        .sheet(isPresented: $privacy) { privacySheet }
    }

    // пусто — как в Фитнесе: иконка, текст, «Пригласить друга»
    private var emptyHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill").font(.system(size: 54)).foregroundStyle(.secondary).padding(.top, 20)
            Text("Общий доступ к активности").font(.title3.bold())
            Text("Подписывайтесь на друзей, чтобы видеть их тренировки, подбадривать и поддерживать друг друга.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            ShareLink(item: invite) {
                Text("Пригласить друга").font(.headline).frame(maxWidth: 280).padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 6)
            Button("Как используются данные…") { privacy = true }.font(.subheadline).foregroundStyle(Color.limeInk)
        }
        .frame(maxWidth: .infinity)
    }

    private func myWeek(_ m: FriendsActivity.Me) -> some View {
        HStack(spacing: 14) {
            ring(m.week, m.goal, size: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Моя неделя").font(.headline)
                Text("\(m.week) из \(m.goal) тренировок").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .oxCardBG(22)
        .padding(.horizontal, 16)
    }

    private func friendsList(_ list: [FriendsActivity.Friend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Друзья").font(.title3.bold()).padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(list) { f in
                    HStack(spacing: 12) {
                        Button { openUser = f.id } label: {
                            Avatar(url: API.media(f.photo), name: f.name ?? "?", size: 46)
                                .overlay(alignment: .bottomTrailing) { ring(f.week, f.goal, size: 20).background(Color.oxCard, in: Circle()) }
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(f.name ?? "Друг").font(.subheadline.bold()).lineLimit(1)
                                if f.mutual == true { Image(systemName: "arrow.left.arrow.right").font(.caption2).foregroundStyle(Color.limeInk) }
                            }
                            Text("\(f.week) из \(f.goal) на неделе" + ((f.setsToday ?? 0) > 0 ? " · сегодня \(f.setsToday!) подх." : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if let l = f.last { Text("Последняя: \(RU.human(l))").font(.caption2).foregroundStyle(Color.oxHint) }
                        }
                        Spacer()
                        Button { Task { await cheer(f) } } label: {
                            Image(systemName: cheered.contains(f.id) ? "checkmark" : "hands.clap.fill")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .disabled(cheered.contains(f.id))
                        .accessibilityLabel("Подбодрить")
                    }
                    .padding(.vertical, 10)
                    if f.id != list.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .oxCardBG(22)
            .padding(.horizontal, 16)
        }
    }

    // предложения — горизонтальные карточки с «Добавить» и крестиком, как в Фитнесе
    private func suggestions(_ list: [FriendsActivity.Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Предложения друзей").font(.title3.bold()).padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(list) { s in
                        VStack(spacing: 8) {
                            Avatar(url: API.media(s.photo), name: s.name ?? "?", size: 86).padding(.top, 14)
                            Text(s.name ?? "Пользователь").font(.headline).lineLimit(1)
                            Text(s.source ?? "").font(.caption).foregroundStyle(.secondary)
                            Button { Task { await follow(s.id) } } label: {
                                Text("Добавить").font(.subheadline.bold()).padding(.horizontal, 10)
                            }
                            .buttonStyle(.glass)
                            .padding(.top, 6).padding(.bottom, 14)
                        }
                        .frame(width: 160)
                        .oxCardBG(22)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation { hidden.insert(s.id) }
                                UserDefaults.standard.set(Array(hidden), forKey: "friends.hidden")
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func ring(_ v: Int, _ goal: Int, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.lime.opacity(0.2), lineWidth: size * 0.14)
            Circle().trim(from: 0, to: min(1, Double(v) / Double(max(1, goal))))
                .stroke(Color.lime, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .padding(size * 0.08)
    }

    private var privacySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Color.lime)
            Text("Что видят друзья").font(.title3.bold())
            Text("Друзья видят только число ваших тренировок за неделю, количество подходов сегодня и дату последней тренировки. Веса, замеры, фото прогресса и питание остаются закрытыми — питание видит только ваш тренер, если вы разрешили.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oxBg)
        .fitSheet()
    }

    private func load() async {
        do { data = try await API.call("/friends/activity"); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func follow(_ id: Int) async {
        do {
            let _: OK = try await API.call("/feed/users/\(id)/follow", method: "POST")
            Haptic.success()
            withAnimation { _ = added.insert(id) }
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    /// «Подбодрить» — короткое сообщение в личный чат
    private func cheer(_ f: FriendsActivity.Friend) async {
        struct Opened: Decodable { let id: Int }
        do {
            let c: Opened = try await API.call("/chats/open", method: "POST", body: ["user_id": f.id])
            let _: Message = try await API.call("/chats/\(c.id)/messages", method: "POST", body: ["text": "👏 Так держать! \(f.week) из \(f.goal) на этой неделе 💪"])
            Haptic.success()
            withAnimation { _ = cheered.insert(f.id) }
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - «Встречайте Oxion» (в стиле Apple Фитнес)

struct WelcomeFlow: View {
    var onDone: () -> Void
    @State private var page = 0

    private struct Row { let icon: String; let title: String; let text: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case 0:
                    page(title: "Встречайте Oxion", header: nil, rows: [
                        Row(icon: "circle.dashed.inset.filled", title: "Следите за активностью", text: "Кольца, тренировки, медали и прогресс — на главном экране."),
                        Row(icon: "figure.run", title: "Отслеживайте тренировки", text: "Подходы, веса, пробежки с GPS и пульс с часов."),
                        Row(icon: "person.crop.circle.badge.checkmark", title: "Тренируйтесь с тренером", text: "Найдите тренера, получайте план и разбор техники."),
                        Row(icon: "person.2.fill", title: "Делитесь с друзьями", text: "Подбадривайте друг друга и закрывайте кольца вместе.")
                    ])
                case 1:
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(Color.lime)
                            .frame(maxWidth: .infinity).padding(.bottom, 24)
                        Text("Ваши данные о тренировках и здоровье под защитой").font(.title.bold())
                        Text("Вес, замеры, фото прогресса и питание видите только вы — и ваш тренер, если вы ему разрешите. Данные со здоровья iPhone не покидают устройство без вашего согласия.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                default:
                    page(title: "Тренировки на iPhone", header: "Записывайте тренировки и закрывайте кольца.", rows: [
                        Row(icon: "figure.strengthtraining.traditional", title: "Отслеживание данных", text: "Темп, дистанция, подходы. Подключите часы или пульсометр — данных станет больше."),
                        Row(icon: "music.note", title: "Музыка", text: "Любимая музыка во время тренировки включается сама.")
                    ])
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)
            Spacer()
            Button {
                Haptic.tap()
                if page < 2 { withAnimation(.spring(duration: 0.45)) { page += 1 } } else { onDone() }
            } label: {
                Text(page < 2 ? "Продолжить" : "Начать").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .padding(.top, 70)
        .padding(.bottom, 20)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func page(title: String, header: String?, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.largeTitle.bold())
                if let header { Text(header).font(.title3).foregroundStyle(.secondary) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: r.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.onLime)
                        .frame(width: 46, height: 46)
                        .background(Color.lime, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.headline)
                        Text(r.text).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

enum Welcome {
    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: "ox.welcome.seen") }
        set { UserDefaults.standard.set(newValue, forKey: "ox.welcome.seen") }
    }
}
