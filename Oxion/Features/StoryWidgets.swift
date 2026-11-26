import SwiftUI
import UIKit

// MARK: - Виджеты результатов для историй: кольцо недели, последняя тренировка, рекорды, серия,
// итоги, вес, шаги и кнопки тренера «Записаться». Без фона (по умолчанию), стекло или лайм — по нажатию.

struct StoryWidgetData: Decodable, Equatable {
    struct Week: Decodable, Equatable { let done: Int; let goal: Int; let days: [String]; let sets: Int; let calories: Int; let volume: Int }
    struct Ex: Decodable, Equatable { let name: String; let sets: [Set_]? }
    struct Set_: Decodable, Equatable { let w: Double?; let r: Int? }
    struct Last: Decodable, Equatable { let id: Int; let title: String?; let date: String?; let exercises: [Ex]?; let setsN: Int?; let volume: Int? }
    struct Rec: Decodable, Equatable { let name: String; let weight: Double?; let reps: Int?; let e1rm: Double?; let date: String? }
    struct Total: Decodable, Equatable { let workouts: Int; let volume: Int; let since: String? }
    struct Weight: Decodable, Equatable { let kg: Double; let date: String?; let delta: Double? }
    struct Trainer: Decodable, Equatable { let id: Int; let price: Int?; let experience: Int?; let rating: Double?; let reviews: Int?; let directions: [String]?; let nextSlot: Double? }
    let name: String?
    let photo: String?
    let week: Week
    let streakDays: Int
    let streakWeeks: Int
    let last: Last?
    let records: [Rec]
    let total: Total
    let weight: Weight?
    let trainer: Trainer?
    // заполняется на телефоне
    var steps: Int? = nil
    var kcal: Int? = nil
    var userId: Int? = nil
}

enum StoryWidgetKind: String, CaseIterable, Identifiable {
    case weekRing, weekDays, lastWorkout, record, streak, total, weight, activity, book, trainerCard, profile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekRing: "Кольцо недели"
        case .weekDays: "Моя неделя"
        case .lastWorkout: "Последняя тренировка"
        case .record: "Рекорд"
        case .streak: "Серия"
        case .total: "Итоги"
        case .weight: "Вес"
        case .activity: "Шаги сегодня"
        case .book: "Кнопка «Записаться»"
        case .trainerCard: "Карточка тренера"
        case .profile: "Мой профиль"
        }
    }
}

enum WFmt {
    static func kg(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
    static func tons(_ kg: Int) -> String {
        kg >= 1000 ? String(format: "%.1f т", Double(kg) / 1000).replacingOccurrences(of: ".", with: ",") : "\(kg) кг"
    }
    static func date(_ s: String?) -> String {
        guard let s, s.count == 10 else { return "" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "ru_RU")
        guard let d = f.date(from: s) else { return s }
        if Calendar.current.isDateInToday(d) { return "сегодня" }
        if Calendar.current.isDateInYesterday(d) { return "вчера" }
        let o = DateFormatter(); o.locale = Locale(identifier: "ru_RU"); o.dateFormat = "d MMMM"
        return o.string(from: d)
    }
    static func slot(_ ms: Double?) -> String? {
        guard let ms else { return nil }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let o = DateFormatter(); o.locale = Locale(identifier: "ru_RU")
        o.dateFormat = Calendar.current.isDateInToday(d) ? "'сегодня в' HH:mm" : (Calendar.current.isDateInTomorrow(d) ? "'завтра в' HH:mm" : "d MMMM 'в' HH:mm")
        return o.string(from: d)
    }
}

/// Общий «каркас» виджета: без фона / стекло / лайм
private struct WBox<C: View>: View {
    let variant: Int
    var pad: CGFloat = 16
    @ViewBuilder var content: C
    var body: some View {
        content
            .foregroundStyle(variant == 2 ? Color.onLime : .white)
            .padding(variant == 0 ? 4 : pad)
            .background {
                if variant == 1 {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                } else if variant == 2 {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.lime)
                }
            }
            .shadow(color: .black.opacity(variant == 0 ? 0.55 : 0.25), radius: variant == 0 ? 6 : 12, y: 2)
    }
}

struct StoryWidgetView: View {
    let kind: StoryWidgetKind
    let d: StoryWidgetData
    var variant = 0

    private var accent: Color { variant == 2 ? Color.onLime : Color.lime }
    private var dim: Color { variant == 2 ? Color.onLime.opacity(0.65) : .white.opacity(0.75) }

    var body: some View {
        switch kind {
        case .weekRing: weekRing
        case .weekDays: weekDays
        case .lastWorkout: lastWorkout
        case .record: record
        case .streak: streak
        case .total: total
        case .weight: weight
        case .activity: activity
        case .book: book
        case .trainerCard: trainerCard
        case .profile: profile
        }
    }

    // кольцо: тренировки за неделю
    private var weekRing: some View {
        let p = min(1, Double(d.week.done) / Double(max(1, d.week.goal)))
        return WBox(variant: variant) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(accent.opacity(0.22), lineWidth: 18)
                    Circle().trim(from: 0, to: max(0.02, p))
                        .stroke(AngularGradient(colors: variant == 2 ? [Color.onLime, Color.onLime] : [Color(hex: 0x8FCB1E), Color.lime, Color(hex: 0xD4FF6A)], center: .center),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(d.week.done)/\(d.week.goal)").font(.system(size: 42, weight: .heavy, design: .rounded))
                        Text("за неделю").font(.system(size: 14, weight: .semibold)).foregroundStyle(dim)
                    }
                }
                .frame(width: 150, height: 150)
                HStack(spacing: 14) {
                    stat("\(d.week.sets)", "подходов")
                    stat(WFmt.tons(d.week.volume), "поднято")
                }
            }
        }
    }

    private var weekDays: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        return WBox(variant: variant) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    FlameMark(size: 18)
                    Text("Моя неделя").font(.system(size: 18, weight: .bold))
                    Spacer(minLength: 8)
                    Text("\(d.week.done) из \(d.week.goal)").font(.system(size: 16, weight: .semibold)).foregroundStyle(dim)
                }
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        let day = cal.date(byAdding: .day, value: i, to: start) ?? start
                        let on = d.week.days.contains(f.string(from: day))
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(on ? accent : accent.opacity(0.18)).frame(width: 34, height: 34)
                                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(variant == 2 ? Color.lime : Color.onLime) }
                            }
                            Text(names[i]).font(.system(size: 12, weight: .semibold)).foregroundStyle(dim)
                        }
                    }
                }
            }
            .frame(width: 300)
        }
    }

    private var lastWorkout: some View {
        WBox(variant: variant) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.last?.title ?? "Тренировка").font(.system(size: 20, weight: .bold)).lineLimit(1)
                        Text(WFmt.date(d.last?.date)).font(.system(size: 13, weight: .medium)).foregroundStyle(dim)
                    }
                }
                HStack(spacing: 18) {
                    stat("\(d.last?.exercises?.count ?? 0)", "упражн.")
                    stat("\(d.last?.setsN ?? 0)", "подходов")
                    stat(WFmt.tons(d.last?.volume ?? 0), "тоннаж")
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array((d.last?.exercises ?? []).prefix(4).enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 6, height: 6)
                            Text(e.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 6)
                            if let s = e.sets?.first(where: { ($0.w ?? 0) > 0 }), let w = s.w {
                                Text("\(WFmt.kg(w))×\(s.r ?? 0)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(dim)
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("ПОВТОРИТЬ ТРЕНИРОВКУ").font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(variant == 2 ? Color.lime : Color.onLime)
                .padding(.horizontal, 14).frame(height: 34)
                .background(variant == 2 ? Color.onLime : Color.lime, in: Capsule())
            }
            .frame(width: 290, alignment: .leading)
        }
    }

    private var record: some View {
        let r = d.records.first
        return WBox(variant: variant) {
            VStack(spacing: 4) {
                Text("🏆").font(.system(size: 46))
                Text("ЛИЧНЫЙ РЕКОРД").font(.system(size: 13, weight: .heavy)).tracking(1.5).foregroundStyle(accent)
                Text(r?.name ?? "—").font(.system(size: 20, weight: .bold)).lineLimit(1)
                Text("\(WFmt.kg(r?.weight)) кг × \(r?.reps ?? 0)").font(.system(size: 38, weight: .heavy, design: .rounded))
                if let e = r?.e1rm { Text("≈ \(WFmt.kg(e)) кг на 1 раз").font(.system(size: 13, weight: .medium)).foregroundStyle(dim) }
            }
            .frame(minWidth: 220)
        }
    }

    private var streak: some View {
        let days = d.streakDays >= 2
        let n = days ? d.streakDays : d.streakWeeks
        return WBox(variant: variant) {
            HStack(spacing: 10) {
                Text("🔥").font(.system(size: 54))
                VStack(alignment: .leading, spacing: -4) {
                    Text("\(n)").font(.system(size: 54, weight: .heavy, design: .rounded))
                    Text(days ? "\(RU.plural(n, "день", "дня", "дней")) подряд" : "\(RU.plural(n, "неделя", "недели", "недель")) подряд")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(dim)
                }
            }
        }
    }

    private var total: some View {
        WBox(variant: variant) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) { FlameMark(size: 18); Text("Мои итоги в OXION").font(.system(size: 16, weight: .bold)) }
                HStack(spacing: 22) {
                    big("\(d.total.workouts)", RU.plural(d.total.workouts, "тренировка", "тренировки", "тренировок"))
                    big(WFmt.tons(d.total.volume), "поднято")
                }
                if let s = d.total.since { Text("с \(WFmt.date(s))").font(.system(size: 13, weight: .medium)).foregroundStyle(dim) }
            }
        }
    }

    private var weight: some View {
        WBox(variant: variant) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ВЕС").font(.system(size: 13, weight: .heavy)).tracking(1.5).foregroundStyle(accent)
                Text("\(WFmt.kg(d.weight?.kg)) кг").font(.system(size: 44, weight: .heavy, design: .rounded))
                if let dl = d.weight?.delta, dl != 0 {
                    Label("\(dl > 0 ? "+" : "−")\(WFmt.kg(abs(dl))) кг за месяц", systemImage: dl < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(dim)
                }
            }
        }
    }

    private var activity: some View {
        let steps = d.steps ?? 0
        let p = min(1, Double(steps) / 10000)
        return WBox(variant: variant) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color(hex: 0x30D158).opacity(0.25), lineWidth: 12)
                    Circle().trim(from: 0, to: max(0.02, p)).stroke(Color(hex: 0x30D158), style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "figure.walk").font(.system(size: 24, weight: .bold))
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 0) {
                    Text(steps.formatted()).font(.system(size: 36, weight: .heavy, design: .rounded))
                    Text("шагов сегодня" + ((d.kcal ?? 0) > 0 ? " · \(d.kcal!) ккал" : "")).font(.system(size: 14, weight: .semibold)).foregroundStyle(dim)
                }
            }
        }
    }

    // ----- тренер -----
    private var book: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 22, weight: .bold))
            Text("ЗАПИСАТЬСЯ").font(.system(size: 24, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(variant == 2 ? Color.white : Color.onLime)
        .padding(.horizontal, 22).frame(height: 60)
        .background(variant == 1 ? Color.white : (variant == 2 ? Color.black : Color.lime), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private var trainerCard: some View {
        WBox(variant: variant == 0 ? 1 : variant) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.name ?? "Тренер").font(.system(size: 20, weight: .bold)).lineLimit(1)
                        Text("Личный тренер в OXION").font(.system(size: 13, weight: .medium)).foregroundStyle(dim)
                    }
                }
                HStack(spacing: 16) {
                    if let r = d.trainer?.rating, r > 0 { stat("★ \(WFmt.kg(r))", "\(d.trainer?.reviews ?? 0) отз.") }
                    if let e = d.trainer?.experience, e > 0 { stat("\(e)", RU.plural(e, "год", "года", "лет") + " опыта") }
                    if let p = d.trainer?.price, p > 0 { stat("\(p) ₽", "занятие") }
                }
                if let dirs = d.trainer?.directions, !dirs.isEmpty {
                    Text(dirs.joined(separator: " · ")).font(.system(size: 13, weight: .medium)).foregroundStyle(dim).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                    Text(WFmt.slot(d.trainer?.nextSlot).map { "ЗАПИСАТЬСЯ · \($0)" } ?? "ЗАПИСАТЬСЯ").font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(Color.onLime)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Color.lime, in: Capsule())
            }
            .frame(width: 290, alignment: .leading)
        }
    }

    private var profile: some View {
        HStack(spacing: 10) {
            FlameMark(size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.name ?? "OXION").font(.system(size: 18, weight: .bold)).lineLimit(1)
                Text("Открыть профиль в OXION").font(.system(size: 12, weight: .medium)).opacity(0.7)
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(variant == 1 ? Color.black : .white)
        .padding(.leading, 12).padding(.trailing, 16).frame(height: 58)
        .background(variant == 1 ? AnyShapeStyle(Color.white) : (variant == 2 ? AnyShapeStyle(Color.lime.opacity(0.9)) : AnyShapeStyle(Color.black.opacity(0.55))), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(variant == 0 ? 0.25 : 0), lineWidth: 1))
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 20, weight: .heavy, design: .rounded)).lineLimit(1)
            Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(dim)
        }
    }

    private func big(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 34, weight: .heavy, design: .rounded)).lineLimit(1)
            Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(dim)
        }
    }

    /// виджет показывать только если есть данные
    static func available(_ k: StoryWidgetKind, _ d: StoryWidgetData) -> Bool {
        switch k {
        case .weekRing, .weekDays, .profile: true
        case .lastWorkout: d.last != nil
        case .record: !d.records.isEmpty
        case .streak: d.streakDays >= 2 || d.streakWeeks >= 1
        case .total: d.total.workouts > 0
        case .weight: d.weight != nil
        case .activity: (d.steps ?? 0) > 0
        case .book, .trainerCard: d.trainer != nil
        }
    }
}

// MARK: - Выбор виджета

struct StoryWidgetsSheet: View {
    var onPick: (StoryOverlay) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var data: StoryWidgetData?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = data {
                    VStack(alignment: .leading, spacing: 18) {
                        if d.trainer != nil {
                            section("Для тренера", [.book, .trainerCard], d)
                        }
                        section("Мои результаты", [.weekRing, .weekDays, .lastWorkout, .record, .streak, .total, .weight, .activity], d)
                        section("Ссылки", [.profile], d)
                        Text("Нажмите на виджет в истории, чтобы сменить стиль: без фона, стекло или лайм. «Повторить тренировку», «Записаться» и «Профиль» в истории нажимаются.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                    .padding(16)
                } else if failed {
                    ContentUnavailableView("Не удалось загрузить", systemImage: "wifi.slash", description: Text("Проверьте интернет и попробуйте ещё раз"))
                        .padding(.top, 60)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .background(Color(white: 0.08))
            .navigationTitle("Результаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, _ kinds: [StoryWidgetKind], _ d: StoryWidgetData) -> some View {
        let list = kinds.filter { StoryWidgetView.available($0, d) }
        return VStack(alignment: .leading, spacing: 10) {
            if !list.isEmpty { Text(title).font(.headline).foregroundStyle(.white) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(list) { k in
                    Button {
                        var o = StoryOverlay(kind: .widget)
                        o.widget = k
                        o.wdata = d
                        o.center = CGPoint(x: 0.5, y: k == .book || k == .profile ? 0.72 : 0.42)
                        onPick(o)
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                LinearGradient(colors: [Color(hex: 0x2A3A1A), Color(hex: 0x10130E)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                StoryWidgetView(kind: k, d: d)
                                    .scaleEffect(0.48)
                                    .frame(width: 10, height: 10)
                            }
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text(k.title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        do {
            var d: StoryWidgetData = try await API.call("/stories/widgets", query: ["from": f.string(from: start), "to": f.string(from: end), "today": f.string(from: Date())])
            d.userId = model.me?.id
            // шаги и калории — из «Здоровья», если разрешено
            let hk = HealthKitManager.shared
            if hk.enabled {
                if hk.days.isEmpty { await hk.load(days: 1) }
                if let t = hk.days.last(where: { Calendar.current.isDateInToday($0.date) }) {
                    d.steps = t.steps.map { Int($0) }
                    d.kcal = t.kcal.map { Int($0) }
                }
            }
            data = d
        } catch {
            failed = true
        }
    }
}

// MARK: - Тренировка из истории: посмотреть и сохранить себе

struct StoryWorkoutSheet: View {
    let storyId: Int
    @State private var w: JSONValue?
    @State private var failed = false

    var body: some View {
        Group {
            if let w {
                PostWorkoutSheet(postId: 0, w: w, author: nil, saveURL: "/stories/\(storyId)/workout")
            } else if failed {
                ContentUnavailableView("Тренировка недоступна", systemImage: "dumbbell")
            } else {
                ProgressView()
            }
        }
        .task {
            struct R: Decodable { let workout: JSONValue }
            do { let r: R = try await API.call("/stories/\(storyId)/workout"); w = r.workout } catch { failed = true }
        }
    }
}
