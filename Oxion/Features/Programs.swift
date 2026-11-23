import SwiftUI

// План на 4 недели (как Gym Strength в Fitness+), «Твой статус» (как новое приложение Здоровье)
// и экран «Что нового в Oxion».

// MARK: - Модели

struct ProgramExercise: Codable, Hashable {
    var name: String
    var sets: Int
    var reps: Int?
    var seconds: Int?
    var km: Double?
    var weight: Double?
    var muscle: String?
}

struct ProgramDay: Codable, Hashable, Identifiable {
    var title: String
    var groups: [String]
    var exercises: [ProgramExercise]
    var id: String { title }
}

struct ProgramWeek: Codable, Hashable, Identifiable {
    let n: Int
    let title: String
    let note: String
    var id: Int { n }
}

struct ProgramPlan: Codable {
    let title: String
    let summary: String?
    let goal: String?
    let level: String?
    let minutes: Int?
    let days: [ProgramDay]
    let weeks: [ProgramWeek]

    /// обратно на сервер — тем же JSON, что пришёл
    var dict: [String: Any] {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        guard let d = try? enc.encode(self), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
}

struct ProgramApplyResult: Decodable { let created: Int; let firstDate: String?; let lastDate: String? }

// MARK: - План на 4 недели

struct ProgramBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0  // 0 — обложка, 1 — настройки, 2 — план
    @State private var goal = "gain"
    @State private var level = "middle"
    @State private var days = 3
    @State private var minutes = 60
    @State private var place = "gym"
    @State private var focus = ""
    @State private var building = false
    @State private var plan: ProgramPlan?
    @State private var weekdays: [Int] = [1, 3, 5]
    @State private var start = Date()
    @State private var applying = false

    private let goals = [("lose", "Похудеть", "flame.fill"), ("gain", "Набрать массу", "dumbbell.fill"), ("tone", "Форма", "figure.mixed.cardio"),
                         ("sport", "Соревнования", "trophy.fill"), ("health", "Здоровье", "heart.fill")]
    private let levels = [("beginner", "Новичок"), ("middle", "Средний"), ("pro", "Продвинутый")]
    private let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch step {
                case 0: cover
                case 1: settings
                default: if let plan { preview(plan) }
                }
            }
            .padding(16)
            .animation(.smooth(duration: 0.35), value: step)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle(step == 2 ? "Ваш план" : "План на 4 недели")
        .navigationBarTitleDisplayMode(step == 0 ? .large : .inline)
        .overlay {
            if building {
                VStack(spacing: 14) {
                    AIAvatar(size: 64, active: true)
                    Text("ИИ собирает план…").font(.headline)
                    Text("Подбираем упражнения из библиотеки Oxion").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: building)
        .onAppear {
            if let g = model.me?.goal, goals.contains(where: { $0.0 == g }) { goal = g }
            if let l = model.me?.level, levels.contains(where: { $0.0 == l }) { level = l }
            start = Self.nextMonday()
        }
    }

    // MARK: обложка, как у Apple

    private var cover: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Сделано для зала").font(.title2.bold())
                Text("Выберите цель и сколько раз в неделю хотите тренироваться. ИИ-тренер Oxion соберёт программу на 4 недели с прогрессией и сам разложит её по дневнику.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    stat("flag.checkered.2.crossed", "Длительность", "4 недели")
                    stat("calendar", "Дней в неделю", "2–5")
                    stat("figure.strengthtraining.traditional", "Упражнений", "100+")
                }
                .padding(.vertical, 6)
                Button { withAnimation { step = 1 } } label: {
                    Text("Собрать план").font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.lime, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text("Как устроены 4 недели").font(.title3.bold()).padding(.top, 6)
            ForEach(Self.weeksInfo, id: \.0) { w in
                HStack(spacing: 14) {
                    Text("\(w.0)").font(.title3.bold().monospacedDigit()).foregroundStyle(.black)
                        .frame(width: 40, height: 40).background(Color.lime, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.1).font(.headline)
                        Text(w.2).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static let weeksInfo = [(1, "Втягивание", "Базовый объём, техника и рабочие веса"), (2, "Объём", "+2 повторения в каждом подходе"),
                            (3, "Пик", "+1 подход к каждому упражнению"), (4, "Разгрузка", "Объём −30%, восстановление")]

    private func stat(_ icon: String, _ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: настройки

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Цель") {
                FlowLayout(spacing: 8) {
                    ForEach(goals, id: \.0) { g in
                        chip(g.1, icon: g.2, on: goal == g.0) { goal = g.0 }
                    }
                }
            }
            section("Уровень") {
                HStack(spacing: 8) { ForEach(levels, id: \.0) { l in chip(l.1, on: level == l.0) { level = l.0 } } }
            }
            section("Тренировок в неделю") {
                HStack(spacing: 8) {
                    ForEach(2...5, id: \.self) { n in
                        chip("\(n)", on: days == n) {
                            days = n
                            weekdays = Self.defaultDays(n)
                        }
                    }
                }
            }
            section("Длительность тренировки") {
                HStack(spacing: 8) { ForEach([30, 45, 60, 90], id: \.self) { m in chip("\(m) мин", on: minutes == m) { minutes = m } } }
            }
            section("Где тренируетесь") {
                HStack(spacing: 8) {
                    chip("Зал", icon: "dumbbell.fill", on: place == "gym") { place = "gym" }
                    chip("Дом", icon: "house.fill", on: place == "home") { place = "home" }
                }
            }
            section("Пожелания (необязательно)") {
                TextField("Например: больше спины, без становой", text: $focus, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(14)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Button { Task { await build() } } label: {
                Label("Собрать план с ИИ", systemImage: "sparkles").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.lime, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(building)
        }
    }

    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t).font(.headline)
            c()
        }
    }

    private func chip(_ t: String, icon: String? = nil, on: Bool, tap: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            withAnimation(.smooth(duration: 0.2)) { tap() }
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.subheadline) }
                Text(t).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(on ? Color.lime : Color(white: 0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: готовый план

    private func preview(_ p: ProgramPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.title).font(.title2.bold())
                if let s = p.summary, !s.isEmpty { Text(s).font(.subheadline).foregroundStyle(.secondary) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(p.weeks) { w in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Неделя \(w.n)").font(.caption.bold()).foregroundStyle(Color.lime)
                            Text(w.title).font(.subheadline.bold())
                            Text(w.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(12)
                        .frame(width: 150, alignment: .leading)
                        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            ForEach(Array(p.days.enumerated()), id: \.offset) { i, d in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(d.title).font(.headline)
                        Spacer()
                        Text(dayNames[(weekdays.sorted()[safe: i] ?? 1) - 1]).font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(.black).background(Color.lime, in: Capsule())
                    }
                    ForEach(Array(d.exercises.enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 10) {
                            MuscleThumb(key: e.muscle ?? d.groups.first ?? "chest", size: 34, name: e.name)
                            Text(e.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(e.reps.map { "\(e.sets)×\($0)" } ?? e.seconds.map { "\(e.sets)×\($0) с" } ?? "\(e.sets) подх.")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            section("Дни недели — выберите \(p.days.count)") {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        let on = weekdays.contains(d)
                        Button {
                            Haptic.tap(.soft)
                            if on { weekdays.removeAll { $0 == d } } else if weekdays.count < p.days.count { weekdays.append(d) }
                        } label: {
                            Text(dayNames[d - 1]).font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .foregroundStyle(on ? Color.black : Color.white)
                                .background(on ? Color.lime : Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            DatePicker("Начать с", selection: $start, in: Date()..., displayedComponents: .date)
                .font(.headline)
            Button { Task { await apply(p) } } label: {
                HStack {
                    if applying { ProgressView().tint(.black) }
                    Text("Добавить в дневник · \(p.days.count * 4) тренировок").font(.headline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.lime, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(applying || weekdays.count != p.days.count)
            .opacity(weekdays.count == p.days.count ? 1 : 0.5)
            Button("Собрать заново") { Task { await build() } }
                .font(.subheadline).frame(maxWidth: .infinity)
        }
    }

    // MARK: логика

    static func defaultDays(_ n: Int) -> [Int] {
        switch n { case 2: [2, 5]; case 3: [1, 3, 5]; case 4: [1, 2, 4, 5]; default: [1, 2, 3, 5, 6] }
    }

    static func nextMonday() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today) // 1 — воскресенье
        let iso = (wd + 5) % 7 + 1
        return iso == 1 ? today : cal.date(byAdding: .day, value: 8 - iso, to: today) ?? today
    }

    private func build() async {
        building = true
        defer { building = false }
        do {
            let p: ProgramPlan = try await API.call("/ai/program", method: "POST", body: [
                "goal": goal, "level": level, "days": days, "minutes": minutes, "place": place, "focus": focus])
            weekdays = Self.defaultDays(p.days.count)
            withAnimation(.smooth(duration: 0.35)) { plan = p; step = 2 }
            Haptic.success()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func apply(_ p: ProgramPlan) async {
        applying = true
        defer { applying = false }
        do {
            let r: ProgramApplyResult = try await API.call("/ai/program/apply", method: "POST", body: [
                "program": p.dict, "start": RU.dayFormatter.string(from: start), "weekdays": weekdays.sorted()])
            OxHaptics.play(.workoutDone)
            OxAlert.show(icon: "calendar.badge.checkmark", title: "План в дневнике",
                         message: "Добавлено тренировок: \(r.created). Первая — \(r.firstDate ?? "")")
            dismiss()
            model.selectedTab = .diary
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - «Твой статус»

struct StatusArea: Decodable, Identifiable {
    let key: String
    let name: String
    let icon: String
    let score: Int?
    let value: String
    let hint: String
    var id: String { key }
    var color: Color {
        switch key {
        case "training": Color.lime
        case "balance": Color(hex: 0x3FD6C9)
        case "consistency": Color(hex: 0xFF8A3D)
        case "sleep": Color(hex: 0x7B7BFF)
        case "activity": Color(hex: 0x2E9BFF)
        default: Color(hex: 0xFF3B6B)
        }
    }
}

struct StatusResponse: Decodable {
    let overall: Int
    let label: String
    let areas: [StatusArea]
    let summary: String?
    let healthConnected: Bool?
}

struct StatusView: View {
    @State private var data: StatusResponse?
    @State private var error: String?
    @State private var appear = false
    @State private var showProgram = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let d = data {
                    StatusFlower(areas: d.areas, appear: appear)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Твой статус сейчас").font(.largeTitle.bold())
                        HStack(spacing: 8) {
                            Text("\(d.overall)").font(.title.bold().monospacedDigit()).foregroundStyle(Color.lime)
                                .contentTransition(.numericText(value: Double(d.overall)))
                            Text(d.label).font(.title3.weight(.semibold))
                        }
                        if let s = d.summary, !s.isEmpty {
                            Text(s).font(.title3).foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    if d.healthConnected != true {
                        Label("Подключите «Здоровье», чтобы учитывать сон, шаги и пульс", systemImage: "heart.text.square")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(spacing: 10) {
                        ForEach(d.areas) { a in areaRow(a) }
                    }
                    Button { showProgram = true } label: {
                        Label("Собрать план на 4 недели", systemImage: "sparkles").font(.headline).foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.lime, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if let error {
                    ErrorStateView(message: error) { Task { await load() } }.padding(.top, 60)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Статус")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProgram) { NavigationStack { ProgramBuilderView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func areaRow(_ a: StatusArea) -> some View {
        HStack(spacing: 14) {
            Image(systemName: a.icon).font(.headline).foregroundStyle(a.color)
                .frame(width: 40, height: 40).background(a.color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(a.name).font(.headline)
                    Spacer()
                    Text(a.score.map { "\($0)" } ?? "—").font(.headline.monospacedDigit()).foregroundStyle(a.score == nil ? Color.secondary : a.color)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(a.color).frame(width: g.size.width * CGFloat(appear ? (a.score ?? 0) : 0) / 100)
                    }
                }
                .frame(height: 6)
                Text("\(a.value) · \(a.hint)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        do {
            let r: StatusResponse = try await API.call("/me/status", query: ["ai": "1"])
            data = r
            error = nil
            appear = false
            withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.1)) { appear = true }
        } catch { self.error = error.localizedDescription }
    }
}

/// «цветок» из лепестков, как в новом приложении Здоровье: заполненность лепестка — оценка области
struct StatusFlower: View {
    let areas: [StatusArea]
    let appear: Bool

    var body: some View {
        ZStack {
            ForEach(Array(areas.enumerated()), id: \.offset) { i, a in
                let angle = Double(i) / Double(max(1, areas.count)) * 360
                let k = CGFloat(a.score ?? 0) / 100
                ZStack {
                    // контур — всегда, заливка — по оценке
                    PetalShape().stroke(a.color.opacity(a.score == nil ? 0.35 : 0.8), lineWidth: 2)
                    PetalShape().fill(a.color.opacity(0.22 + 0.7 * k))
                        .scaleEffect(appear ? max(0.35, k) : 0.2, anchor: .bottom)
                    Image(systemName: a.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-angle))
                        .offset(y: 30)
                }
                .frame(width: 92, height: 120)
                .offset(y: -66)
                .rotationEffect(.degrees(angle))
                .opacity(appear ? 1 : 0)
                .animation(.spring(duration: 0.9, bounce: 0.25).delay(Double(i) * 0.06), value: appear)
            }
        }
    }
}

/// лепесток: скруглённый треугольник, острым концом к центру
struct PetalShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tip = CGPoint(x: r.midX, y: r.maxY)
        p.move(to: tip)
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.32),
                   control1: CGPoint(x: r.midX - r.width * 0.2, y: r.maxY - r.height * 0.12),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.minY + r.height * 0.32),
                       control: CGPoint(x: r.midX, y: r.minY - r.height * 0.18))
        p.addCurve(to: tip,
                   control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.55),
                   control2: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY - r.height * 0.12))
        p.closeSubpath()
        return p
    }
}

// MARK: - «Что нового в Oxion»

enum WhatsNew {
    static let version = "2026.11.23"
    static var shouldShow: Bool { UserDefaults.standard.string(forKey: "ox.whatsnew") != version }
    static func markSeen() { UserDefaults.standard.set(version, forKey: "ox.whatsnew") }

    static let items: [(String, String, String)] = [
        ("map.fill", "Карта спортивных мест", "Залы, стадионы, бассейны и магазины спортпита Oxion рядом с вами."),
        ("sparkles", "План на 4 недели", "ИИ-тренер собирает программу с прогрессией и раскладывает её по дневнику."),
        ("circle.hexagongrid.fill", "Твой статус", "Тренировки, сон, активность и восстановление — одним взглядом."),
        ("person.3.fill", "Группы и каналы", "Общайтесь командой и ведите свой канал тренировок."),
        ("safari.fill", "Встроенный браузер", "Ссылки открываются прямо в Oxion, можно свернуть и вернуться."),
    ]
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Что нового в Oxion")
                .font(.largeTitle.bold())
                .padding(.top, 56)
                .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { i, it in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: it.0)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.lime)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.1).font(.headline)
                            Text(it.2).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 14)
                    .animation(.smooth(duration: 0.5).delay(0.08 * Double(i)), value: appear)
                }
            }
            Spacer()
            Button {
                WhatsNew.markSeen()
                Haptic.success()
                dismiss()
            } label: {
                Text("Продолжить").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.lime, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
        .onAppear { appear = true }
    }
}
