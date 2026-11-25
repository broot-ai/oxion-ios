import SwiftUI

// MARK: - OXION+ — витрина всего про фитнес (как Apple Fitness+ / YouTube для тренировок)
// Обложка «Месяц бесплатно», разделы-кружки, бесплатные тренировки с видео (WorkoutDB),
// программы на 4 недели, рекомендации, тренеры, плейлисты и советы из ленты.

private struct PremiumTrialInfo: Decodable {
    let active: Bool
    let until: Double?
    let plans: [PremiumPlan]
    let trial: Bool?
}

struct FitnessPlusView: View {
    @Environment(AppModel.self) private var model
    @State private var prem: PremiumTrialInfo?
    @State private var free: [WDBItem] = []
    @State private var recs: [WDBItem] = []
    @State private var coaches: [Trainer] = []
    @State private var showPremium = false
    @State private var trying = false
    @State private var section: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    chips(proxy)
                    hero.padding(.horizontal, 16)
                    categories.id("cats")
                    if !free.isEmpty { freeBlock.id("free") }
                    programs.id("programs")
                    if !recs.isEmpty { recsBlock.id("recs") }
                    cardioBlock.id("cardio")
                    if !coaches.isEmpty { coachesBlock.id("coaches") }
                    playlists.id("music")
                    tips.id("tips")
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPremium) { NavigationStack { PremiumView() } }
        .task { await load() }
        .oxRefreshable { await load() }
        .onOxionRefresh { await load() }
    }

    // MARK: шапка

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.7, green: 1, blue: 0.6), Color.lime], startPoint: .top, endPoint: .bottom))
            Text(verbatim: "OXION+").font(.system(size: 40, weight: .heavy))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func chips(_ proxy: ScrollViewProxy) -> some View {
        let items: [(String, String)] = [("Силовые в зале", "free"), ("Тренировки", "cats"), ("Программы", "programs"),
                                         ("Кардио", "cardio"), ("Тренеры", "coaches"), ("Музыка", "music"), ("Советы", "tips")]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: \.1) { it in
                    Button {
                        Haptic.tap()
                        withAnimation(.snappy) { proxy.scrollTo(it.1, anchor: .top) }
                    } label: {
                        Text(it.0).font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    // MARK: обложка «Месяц бесплатно»

    private var hero: some View {
        VStack(spacing: 0) {
            collage
                .frame(height: 300)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color(white: 0.11)], startPoint: .top, endPoint: .bottom).frame(height: 110)
                }
                .clipped()
            VStack(spacing: 12) {
                if prem?.active == true {
                    Text("Premium активен").font(.system(size: 30, weight: .heavy))
                    if let u = prem?.until {
                        Text("до \(Date(timeIntervalSince1970: u / 1000).formatted(.dateTime.day().month(.wide).year()))")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink { CardioHubView() } label: {
                        Text("Начать тренировку").font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                } else {
                    Text(prem?.trial == false ? "OXION Premium" : "Месяц бесплатно")
                        .font(.system(size: 32, weight: .heavy))
                    Text("Новые тренировки, программы и ИИ-тренер для любого уровня подготовки.")
                        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        Task { await startTrial() }
                    } label: {
                        Group {
                            if trying { ProgressView().tint(Color.onLime) }
                            else { Text(prem?.trial == false ? "Оформить Premium" : "Попробовать бесплатно") }
                        }
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                    .padding(.top, 6)
                    if let p = prem?.plans.first(where: { $0.months == 1 }) {
                        Text(prem?.trial == false ? "\(p.price) ₽ в мес." : "1 мес. бесплатно, затем \(p.price) ₽ в мес.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Button { showPremium = true } label: {
                        Label("Посмотреть годовой план", systemImage: "chevron.right.circle.fill")
                            .labelStyle(TrailingIconLabel())
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// коллаж из 6 фото: ряды 2 · 2 · 2 со смещением средней строки, как у Apple
    private var collage: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let gap: CGFloat = 5
            let rh = (h - gap * 2) / 3
            VStack(spacing: gap) {
                HStack(spacing: gap) { tile(1).frame(width: w * 0.49); tile(2) }.frame(height: rh)
                HStack(spacing: gap) { tile(3).frame(width: w * 0.24); tile(4).frame(width: w * 0.5); tile(5) }.frame(height: rh)
                HStack(spacing: gap) { tile(6).frame(width: w * 0.49); tile(2, flip: true) }.frame(height: rh)
            }
        }
    }

    private func tile(_ i: Int, flip: Bool = false) -> some View {
        Image("fplus-\(i)")
            .resizable()
            .scaledToFill()
            .scaleEffect(x: flip ? -1 : 1, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: разделы

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Тренировки", sub: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    circle("Силовая", "figure.strengthtraining.traditional") { WorkoutDBCatalogView() }
                    circle("Кардио", "figure.run") { CardioHubView() }
                    circle("Камера", "camera.viewfinder") { VisionCoachView() }
                    circle("3D-тело", "figure.arms.open") { Body3DScreen() }
                    circle("План", "calendar.badge.plus") { ProgramBuilderView() }
                    circle("Музыка", "music.note") { WorkoutMusicView() }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private func circle<D: View>(_ t: String, _ icon: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.lime)
                    .frame(width: 84, height: 84)
                    .background(Color(white: 0.17), in: Circle())
                Text(t).font(.footnote.weight(.semibold)).foregroundStyle(Color.lime)
            }
        }
        .buttonStyle(.plain)
    }

    private var freeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Бесплатные тренировки", sub: "Упражнения с видео — без подписки")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(free) { e in
                        NavigationLink { WDBExerciseView(id: e.id, preview: e) } label: { videoCard(e, width: 240) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private func videoCard(_ e: WDBItem, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: API.media(e.poster ?? e.gif), icon: "dumbbell")
                .frame(width: width, height: width * 0.56)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if e.video != nil {
                        Label("Видео", systemImage: "play.fill").font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
            Text(e.name).font(.headline).lineLimit(2).frame(width: width, alignment: .leading)
            Text([e.bodyPartRu, e.equipmentRu, WDBText.difficulty(e.difficulty)].compactMap { $0 }.joined(separator: " • "))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).frame(width: width, alignment: .leading)
        }
    }

    private var programs: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Программы", sub: "План на 4 недели — ИИ-тренер разложит его по дням")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    program("Набор массы", ["figure.strengthtraining.traditional", "dumbbell.fill"], [Color(hex: 0x8A1F12), Color(hex: 0xE2552B)])
                    program("Похудение", ["figure.run", "flame.fill"], [Color(hex: 0x1C2B8F), Color(hex: 0x4D5BF0)])
                    program("Сила и выносливость", ["figure.cross.training", "bolt.heart.fill"], [Color(hex: 0x145A32), Color(hex: 0x58C26B)])
                    program("Мобильность и растяжка", ["figure.flexibility", "figure.yoga"], [Color(hex: 0x5A1C6E), Color(hex: 0xC151D4)])
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private func program(_ t: String, _ icons: [String], _ colors: [Color]) -> some View {
        NavigationLink { ProgramBuilderView() } label: {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing)
                Text(t).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                    .multilineTextAlignment(.leading).padding(18)
                HStack(spacing: 18) {
                    ForEach(icons, id: \.self) { Image(systemName: $0).font(.system(size: 34, weight: .semibold)) }
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(18)
            }
            .frame(width: 260, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var recsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Новые рекомендации для вас", sub: nil)
            VStack(spacing: 12) {
                ForEach(recs.prefix(5)) { e in
                    NavigationLink { WDBExerciseView(id: e.id, preview: e) } label: {
                        HStack(spacing: 14) {
                            RemoteImage(url: API.media(e.poster ?? e.gif), icon: "dumbbell")
                                .frame(width: 170, height: 96)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Text("НОВАЯ").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white).padding(6)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                Text([e.bodyPartRu, e.equipmentRu].compactMap { $0 }.joined(separator: " • "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var cardioBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Кардио", sub: "Бег, ходьба, велосипед — с GPS, пульсом и отрезками")
            NavigationLink { CardioHubView() } label: {
                ZStack(alignment: .bottomLeading) {
                    Image("fplus-3").resizable().scaledToFill().frame(height: 190).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Время двигаться").font(.system(size: 26, weight: .heavy))
                        Text("Выберите вид и цель — OXION посчитает всё сам").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Color.lime)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(18)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private var coachesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Тренеры OXION", sub: "Лучшие по отзывам в вашем городе")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(coaches) { t in
                        NavigationLink { TrainerDetailView(id: t.userId) } label: { TrainerMiniCard(t: t) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Плейлисты для тренировок", sub: "Музыка под силовые, кардио и рекорды")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let colors: [[Color]] = [[Color(hex: 0xE2552B), Color(hex: 0x3B0F05)], [Color(hex: 0x6E4BFF), Color(hex: 0x14093B)],
                                             [Color(hex: 0x1FA463), Color(hex: 0x05301A)], [Color(hex: 0xD4A017), Color(hex: 0x3B2A02)]]
                    ForEach(Array(PumpCollections.all.enumerated()), id: \.offset) { i, c in
                        NavigationLink { WorkoutMusicView() } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    LinearGradient(colors: colors[i % colors.count], startPoint: .topTrailing, endPoint: .bottomLeading)
                                    Image(systemName: c.icon).font(.system(size: 56, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                                }
                                .frame(width: 220, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                Text(c.name).font(.headline)
                                Text("\(c.tracks.count) треков").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Советы тренеров", sub: "Посты тренеров OXION из ленты")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    tip("Прогресс и восстановление", "progress", 5)
                    tip("Питание для роста мышц", "food", 6)
                    tip("Силовые: техника и веса", "strength", 1)
                    tip("Мотивация и привычки", "motivation", 4)
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    private func tip(_ t: String, _ key: String, _ img: Int) -> some View {
        NavigationLink { TopicFeedView(key: key, name: t) } label: {
            ZStack(alignment: .topLeading) {
                Image("fplus-\(img)").resizable().scaledToFill().frame(width: 280, height: 180).clipped()
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                Text(t).font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .multilineTextAlignment(.leading).padding(16)
            }
            .frame(width: 280, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func title(_ t: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(.system(size: 26, weight: .heavy))
            if let sub { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: данные

    private func load() async {
        async let p: PremiumTrialInfo? = try? API.call("/premium")
        async let a: WDBList? = try? API.call("/wdb/exercises", query: ["limit": "10"])
        async let b: WDBList? = try? API.call("/wdb/exercises", query: ["limit": "10", "bodyPart": "upper legs"])
        async let h: TrainersHome? = try? API.call("/trainers/home")
        let (pp, aa, bb, hh) = await (p, a, b, h)
        if let pp { prem = pp }
        if let aa { free = aa.items }
        if let bb, !bb.items.isEmpty { recs = bb.items } else if let aa { recs = Array(aa.items.reversed()) }
        if let hh { coaches = (hh.top ?? []) + (hh.popular ?? []).filter { t in !(hh.top ?? []).contains { $0.userId == t.userId } } }
    }

    private func startTrial() async {
        guard prem?.trial != false else { showPremium = true; return }
        trying = true
        defer { trying = false }
        do {
            let _: OK = try await API.call("/premium/trial", method: "POST", body: [:])
            Haptic.success()
            OxAlert.show(icon: "crown.fill", title: "Premium на месяц включён", message: "Все функции OXION Premium открыты")
            await PremiumStatus.shared.refresh(force: true)
            await load()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// значок справа от текста
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}
