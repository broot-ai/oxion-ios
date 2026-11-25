import SwiftUI

/// «Главная» — как в PWA Oxion: приветствие, поиск тренеров, цель недели, кольца, тренер для вас,
/// ИИ-тренер, здоровье, быстрые разделы и сегодняшние тренировки.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var stats: Stats?
    @State private var featured: Trainer?
    @State private var todayWorkouts: [Workout] = []
    @State private var search = ""
    @State private var push: HomeRoute?
    @State private var openTrainer: Int?
    @State private var openWorkout: Int?
    @State private var showProfile = false
    @State private var newWorkout = false
    @State private var showExercises = false
    @State private var showShop = false
    @State private var showVision = false

    @State private var ringsInfo = false
    private var goal: Int { max(1, model.me?.weekGoal ?? 3) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    weekBlock.reassembles(1)
                    HomeMuscleCard().reassembles(2)
                    Group {
                        if model.me?.mode == "trainer" {
                            HomeTrainerCard()
                        } else {
                            HomeSessionCard { openTrainer = $0 }
                        }
                    }
                    .reassembles(3)
                    todaySquares
                    if model.me?.mode != "trainer" { featuredBlock.reassembles(5) }
                    FitnessPlusBanner { push = .fitnessPlus }.reassembles(6)
                    quickCards.reassembles(7)
                    todayBlock.reassembles(8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color.oxBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openTrainer) { id in TrainerDetailView(id: id) }
            .navigationDestination(item: $openWorkout) { id in
                WorkoutDetailView(workoutId: id) { Task { await load() } }
            }
            .navigationDestination(isPresented: $showProfile) { ProfileView(embedded: true) }
            .navigationDestination(isPresented: $showExercises) { ExercisesView() }
            .navigationDestination(isPresented: $showShop) { ShopView() }
            .fullScreenCover(isPresented: $showVision) { VisionCoachView() }
            .sheet(isPresented: $newWorkout) {
                NewWorkoutSheet { id in
                    Task { await load(); openWorkout = id }
                }
            }
            .navigationDestination(item: $push) { r in
                switch r {
                case .pro: SubscriptionView()
                case .coach: AICoachView()
                case .health: HealthView()
                case .challenges: ChallengesView()
                case .records: RecordsView()
                case .ecosystem: EcosystemView()
                case .fitnessPlus: FitnessPlusView()
                }
            }
            .reassemblyRefreshable { await load() }
            .task { await load() }
            .onOxionRefresh { await load() }
            .sheet(isPresented: $ringsInfo) { RingsDetailSheet(rings: todayRings) }
        }
    }

    // MARK: блоки

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showProfile = true
            } label: {
                HStack(spacing: 12) {
                    Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 50)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(greeting)
                            .font(.subheadline)
                            .foregroundStyle(Color.oxHint)
                        Text(model.me?.displayName ?? "")
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if model.me?.mode == "trainer" {
                Button {
                    push = .pro
                } label: {
                    Label("PRO", systemImage: "crown.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .glassEffect(.regular.tint(Color.lime.opacity(0.3)).interactive(), in: .capsule)
            }
            InboxBell()
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.oxHint)
            TextField("Поиск тренеров…", text: $search)
                .submitLabel(.search)
                .onSubmit { model.trainerQuery = search; model.selectedTab = .trainers }
            Button {
                model.trainerQuery = search
                model.selectedTab = .trainers
            } label: {
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.lime, in: Circle())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Цель на неделю")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(stats?.workouts ?? 0)")
                    .foregroundStyle(Color.limeInk)
                    .font(.headline)
                + Text("/\(goal)")
                    .font(.headline)
            }
            WeekPills(done: Set(stats?.daysDone ?? []))
            HStack(spacing: 8) {
                AnimatedFire(size: 40)
                    .frame(width: 24, height: 28)
                Text(motivation)
                    .font(.subheadline)
                    .foregroundStyle(Color.oxHint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .oxCardBG(20)
        }
    }

    private var motivation: String {
        guard let s = stats else { return "Загружаем вашу неделю…" }
        let w = s.workouts ?? 0
        let left = goal - w
        if w == 0 { return "Пусть сегодня начнётся ваша трансформация — запланируйте первую тренировку!" }
        if left > 0 { return "Осталось \(left) \(RU.plural(left, "тренировка", "тренировки", "тренировок")) до цели недели. Вы справитесь!" }
        return "Цель недели выполнена. Отличная работа! 🔥"
    }

    private var todayRings: [RingData] {
        let w = stats?.workouts ?? 0
        let sets = stats?.today?.sets ?? 0
        let kcal = stats?.today?.calories ?? 0
        return [
            RingData(value: Double(w), max: Double(goal), color: Color(hex: 0xB2EE37), label: "Тренировки за неделю", text: "\(w) / \(goal)"),
            RingData(value: Double(sets), max: 20, color: Color(hex: 0x58F670), label: "Подходы сегодня", text: "\(sets) / 20"),
            RingData(value: Double(kcal), max: 500, color: Color(hex: 0x3FD6C9), label: "Ккал сегодня", text: "\(kcal) / 500")
        ]
    }

    /// «Сегодня»: кольца — отдельный квадрат (нажатие — подробности), рядом — быстрый старт тренировки
    private var todaySquares: some View {
        HStack(spacing: 12) {
            Button { ringsInfo = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Сегодня").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Color.oxHint)
                    }
                    Spacer(minLength: 6)
                    ActivityRings(rings: todayRings)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .oxCardBG(26)
            }
            .buttonStyle(.plain)
            .reassembles(4)

            Button { newWorkout = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(Color.onLime)
                        .frame(width: 48, height: 48)
                        .background(Color.lime, in: Circle())
                    Spacer()
                    Text("Новая тренировка").font(.headline)
                    Text("\(stats?.today?.sets ?? 0) подходов сегодня").font(.caption).foregroundStyle(Color.oxHint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .aspectRatio(1, contentMode: .fit)
                .oxCardBG(26)
            }
            .buttonStyle(.plain)
            .reassembles(6)
        }
    }

    private var ringsCard: some View {
        let w = stats?.workouts ?? 0
        let sets = stats?.today?.sets ?? 0
        let kcal = stats?.today?.calories ?? 0
        let rings: [RingData] = [
            RingData(value: Double(w), max: Double(goal), color: Color(hex: 0xB2EE37), label: "Тренировки за неделю", text: "\(w) / \(goal)"),
            RingData(value: Double(sets), max: 20, color: Color(hex: 0x58F670), label: "Подходы сегодня", text: "\(sets) / 20"),
            RingData(value: Double(kcal), max: 500, color: Color(hex: 0x3FD6C9), label: "Ккал сегодня", text: "\(kcal) / 500")
        ]
        return VStack(alignment: .leading, spacing: 4) {
            Text("Сегодня")
                .font(.title3.weight(.medium))
            Text("Закройте кольца")
                .font(.subheadline)
                .foregroundStyle(Color.oxHint)
            HStack(spacing: 18) {
                ActivityRings(rings: rings)
                    .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rings) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label)
                                .font(.caption)
                                .foregroundStyle(Color.oxHint)
                            Text(r.text)
                                .font(.headline)
                        }
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Capsule().fill(r.color).frame(width: 3)
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oxCardBG(26)
    }

    @ViewBuilder
    private var featuredBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Тренер для вас")
                    .font(.title3.weight(.semibold))
                Spacer()
                Label("Под вашу цель", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(Color.lime.opacity(0.25)), in: .capsule)
            }
            if let t = featured {
                Button {
                    openTrainer = t.userId
                } label: {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.name ?? "Тренер")
                                .font(.title3.bold())
                            Text((t.directions ?? []).joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Color.oxHint)
                                .lineLimit(2)
                            HStack(spacing: 10) {
                                Label("\(t.experience ?? 0) \(RU.plural(t.experience ?? 0, "год", "года", "лет"))", systemImage: "clock")
                                if let r = t.rating, (t.reviewsCount ?? 0) > 0 {
                                    Label(String(format: "%.1f", r), systemImage: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Color.oxHint)
                            if let p = t.price {
                                (Text("\(p) ₽").font(.headline) + Text(" / занятие").font(.caption).foregroundColor(Color.oxHint))
                                    .padding(.top, 2)
                            }
                            Spacer(minLength: 6)
                            Text("Смотреть анкету")
                                .font(.subheadline.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.lime, in: Capsule())
                        }
                        .padding(16)
                        Spacer(minLength: 0)
                        RemoteImage(url: API.media(t.cover), icon: "person.fill")
                            .frame(width: 130)
                            .frame(maxHeight: .infinity)
                            .clipped()
                    }
                    .frame(height: 210)
                    .background(Color.oxCard)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.lime.opacity(0.18)))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    model.selectedTab = .trainers
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Найдите своего тренера")
                            .font(.title3.bold())
                        Text("Каталог тренеров вашего города")
                            .foregroundStyle(Color.oxHint)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .oxCardBG(26)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coachCard: some View {
        Button {
            push = .coach
        } label: {
            HStack(spacing: 14) {
                AIAvatar(size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ИИ-тренер")
                        .font(.headline)
                    Text("Составит тренировку на сегодня и ответит на вопросы")
                        .font(.subheadline)
                        .foregroundStyle(Color.oxHint)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.oxHint)
            }
            .padding(16)
            .oxCardBG(24)
        }
        .buttonStyle(.plain)
    }

    private var quickCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                QuickCard(icon: "camera.viewfinder", tint: Color.lime, title: "OXION Vision", sub: "Камера считает повторы") {
                    showVision = true
                }
                QuickCard(icon: "book.fill", tint: Color(hex: 0x58F670), title: "Справочник", sub: "Мышцы и техника") {
                    showExercises = true
                }
            }
            HStack(spacing: 12) {
                QuickCard(icon: "flag.checkered", tint: Color(hex: 0x8E7CFF), title: "Челленджи", sub: "Соревнования с призами") {
                    push = .challenges
                }
                QuickCard(icon: "heart.text.square.fill", tint: Color(hex: 0xFF5A4E), title: "Здоровье", sub: "Шаги, сон, пульс") {
                    push = .health
                }
            }
        }
    }

    private var todayBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сегодня в дневнике")
                .font(.title3.weight(.semibold))
            if todayWorkouts.isEmpty {
                Button {
                    newWorkout = true
                } label: {
                    Label("Запланировать тренировку", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
            } else {
                ForEach(todayWorkouts) { w in
                    Button {
                        openWorkout = w.id
                    } label: {
                        WorkoutRow(w: w)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: загрузка

    private func load() async {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let ws = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let we = cal.date(byAdding: .day, value: 6, to: ws) ?? now
        let f = RU.dayFormatter
        let today = f.string(from: now)
        if let s: Stats = try? await API.call("/stats", query: ["from": f.string(from: ws), "to": f.string(from: we), "today": today]) {
            stats = s
        }
        if let w: WorkoutsResponse = try? await API.call("/workouts", query: ["from": today, "to": today]) {
            todayWorkouts = w.items
        }
        if model.me?.mode != "trainer",
           let t: TrainersResponse = try? await API.call("/trainers", query: ["sort": "match"]) {
            featured = t.items.first
        }
    }
}

enum HomeRoute: Hashable { case pro, coach, health, challenges, records, ecosystem, fitnessPlus }

// MARK: - Элементы главной

struct WeekPills: View {
    let done: Set<String>

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let d = cal.date(byAdding: .day, value: i, to: start) ?? now
                let key = RU.dayFormatter.string(from: d)
                let isToday = cal.isDateInToday(d)
                let isDone = done.contains(key)
                VStack(spacing: 4) {
                    Text(names[i])
                        .font(.caption2)
                        .foregroundStyle(isDone ? Color.black.opacity(0.7) : Color.oxHint)
                    Text("\(cal.component(.day, from: d))")
                        .font(.headline)
                        .foregroundStyle(isDone ? Color.black : Color.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isDone ? Color.lime : Color.oxCard, in: Capsule())
                .overlay(Capsule().stroke(isToday ? Color.lime : Color.clear, lineWidth: 1.5))
            }
        }
    }
}

struct RingData: Identifiable {
    let id = UUID()
    let value: Double
    let max: Double
    let color: Color
    let label: String
    let text: String
}

/// Кольцо (бублик) как фигура — для жидкого стекла
struct RingTrackShape: Shape {
    var inset: CGFloat
    var line: CGFloat
    func path(in rect: CGRect) -> Path {
        Circle().path(in: rect.insetBy(dx: inset + line / 2, dy: inset + line / 2))
            .strokedPath(StrokeStyle(lineWidth: line))
    }
}

/// Заполненная часть кольца — дуга со скруглёнными концами
struct RingArcShape: Shape {
    var inset: CGFloat
    var line: CGFloat
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset + line / 2, dy: inset + line / 2)
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2,
                 startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * max(0.0001, progress)), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: line, lineCap: .round))
    }
}

/// Кольца из жидкого стекла: дорожка — прозрачное стекло, заполненная часть — цветное стекло
struct ActivityRings: View {
    let rings: [RingData]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.12
            GlassEffectContainer(spacing: 2) {
                ZStack {
                    ForEach(Array(rings.enumerated()), id: \.offset) { i, r in
                        let inset = CGFloat(i) * (line + 5)
                        let p = r.max > 0 ? min(1, r.value / r.max) : 0
                        // дорожка — бесцветное стекло
                        Color.clear
                            .glassEffect(.regular, in: RingTrackShape(inset: inset, line: line))
                        // заполнено — цветное стекло со свечением
                        if p > 0 {
                            Color.clear
                                .glassEffect(.regular.tint(r.color.opacity(0.85)), in: RingArcShape(inset: inset, line: line, progress: p))
                                .shadow(color: r.color.opacity(0.55), radius: 8)
                                .transition(.opacity)
                                .animation(.spring(duration: 0.9), value: p)
                        }
                    }
                }
            }
            .overlay { RingGlint(rings: rings.count, line: line) }
            .frame(width: size, height: size)
        }
    }
}

/// Блик на стекле, который плавает за наклоном телефона (без 3D-поворота — стекло остаётся живым)
private struct RingGlint: View {
    let rings: Int
    let line: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !PowerSaver.allowsNow(.liveBackgrounds))) { _ in
            let t = TiltMotion.shared
            let angle = Angle.degrees(-135 + t.x * 60 - t.y * 30)
            ZStack {
                ForEach(0..<rings, id: \.self) { i in
                    RingTrackShape(inset: CGFloat(i) * (line + 5), line: line)
                        .fill(AngularGradient(colors: [.white.opacity(0.35), .white.opacity(0), .white.opacity(0), .white.opacity(0.12), .white.opacity(0)],
                                              center: .center, angle: angle))
                        .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { TiltMotion.shared.start() }
        .onDisappear { TiltMotion.shared.stop() }
    }
}

struct QuickCard: View {
    let icon: String
    let tint: Color
    let title: String
    let sub: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(tint, in: Circle())
                Text(title)
                    .font(.headline)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(Color.oxHint)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .oxCardBG(24)
        }
        .buttonStyle(.plain)
    }
}


/// Подробности по кольцам «Сегодня»
struct RingsDetailSheet: View {
    let rings: [RingData]
    @Environment(\.dismiss) private var dismiss

    private func hint(_ r: RingData) -> String {
        let left = max(0, r.max - r.value)
        if left == 0 { return "Кольцо закрыто — отличная работа!" }
        switch r.label {
        case let l where l.contains("Тренировки"): return "Осталось \(Int(left)) \(RU.plural(Int(left), "тренировка", "тренировки", "тренировок")) до цели недели"
        case let l where l.contains("Подходы"): return "Ещё \(Int(left)) подходов — и кольцо закроется"
        default: return "Ещё \(Int(left)) ккал активности сегодня"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Сегодня").font(.title2.bold()).padding(.top, 22)
            ActivityRings(rings: rings).frame(width: 170, height: 170)
            VStack(spacing: 0) {
                ForEach(rings) { r in
                    HStack(spacing: 12) {
                        Circle().fill(r.color).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.label).font(.subheadline.bold())
                            Text(hint(r)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(r.text).font(.headline.monospacedDigit())
                            Text("\(Int(min(100, r.value / max(1, r.max) * 100)))%").font(.caption).foregroundStyle(r.color)
                        }
                    }
                    .padding(.vertical, 12)
                    if r.id != rings.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .oxCardBG(22)
            .padding(.horizontal, 16)
            Button { dismiss() } label: { Text("Понятно").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                .controlSize(.large)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
    }
}

/// Баннер OXION+ на главной
struct FitnessPlusBanner: View {
    var action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    Image("fplus-2").resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                    Image("fplus-4").resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                }
                .frame(height: 170)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill").foregroundStyle(Color.lime)
                            Text(verbatim: "OXION+").font(.title2.weight(.heavy))
                        }
                        Text("Тренировки с видео, программы, тренеры и музыка").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right.circle.fill").font(.title).foregroundStyle(Color.lime)
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
