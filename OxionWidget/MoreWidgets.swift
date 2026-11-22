import WidgetKit
import SwiftUI

// Дополнительные виджеты: экран «Домой», экран блокировки и режим ожидания (StandBy).
// Данные кладёт приложение в общую папку (WidgetSnapshot). Без неё — демо-данные.

struct SnapEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry { SnapEntry(date: Date(), snap: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        completion(SnapEntry(date: Date(), snap: WidgetSnapshot.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let e = SnapEntry(date: Date(), snap: WidgetSnapshot.load() ?? .placeholder)
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(60 * 60))))
    }
}

private let oxOrange = Color(red: 1.0, green: 0.62, blue: 0.26)

private struct WidgetBG: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.055, blue: 0.06)
            RadialGradient(colors: [Color.oxLime.opacity(0.16), .clear], center: .topTrailing, startRadius: 4, endRadius: 220)
        }
    }
}

// MARK: - Кольца недели

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ox.rings", provider: SnapProvider()) { e in
            RingsView(s: e.snap).containerBackground(for: .widget) { WidgetBG() }
                .widgetURL(URL(string: "oxion://progress"))
        }
        .configurationDisplayName("Кольца недели")
        .description("Тренировки, подходы и калории за неделю — как кольца активности. Красиво смотрится в режиме ожидания.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct Rings: View {
    let values: [(Double, Color)]
    var line: CGFloat = 11
    var body: some View {
        ZStack {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let inset = CGFloat(i) * (line + 3)
                Circle().stroke(v.1.opacity(0.2), lineWidth: line).padding(inset)
                Circle().trim(from: 0, to: max(0.001, min(1, v.0)))
                    .stroke(v.1, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(inset)
            }
        }
    }
}

struct RingsView: View {
    @Environment(\.widgetFamily) private var family
    let s: WidgetSnapshot

    private var w: Double { Double(s.weekDone) / Double(max(1, s.weekGoal)) }
    private var setsGoal: Int { max(1, s.weekGoal) * 15 }
    private var kcalGoal: Int { max(1, s.weekGoal) * 400 }
    private var sets: Double { Double(s.weekSets) / Double(setsGoal) }
    private var kcal: Double { Double(s.weekKcal) / Double(kcalGoal) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, w)) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(s.weekDone)/\(s.weekGoal)").font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("Неделя \(s.weekDone)/\(s.weekGoal)").font(.headline)
                }
                .widgetAccentable()
                Gauge(value: min(1, w)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text("\(s.weekSets) подх. · \(s.weekKcal) ккал · серия \(s.streak)").font(.caption2).lineLimit(1)
            }
        case .accessoryInline:
            Label("\(s.weekDone)/\(s.weekGoal) тренировки · серия \(s.streak) дн.", systemImage: "flame.fill")
        case .systemMedium:
            HStack(spacing: 18) {
                Rings(values: [(w, .oxLime), (sets, .oxSky), (kcal, oxOrange)], line: 12)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    row("Тренировки", "\(s.weekDone)/\(s.weekGoal)", .oxLime)
                    row("Подходы", "\(s.weekSets)/\(setsGoal)", .oxSky)
                    row("Калории", "\(s.weekKcal)/\(kcalGoal)", oxOrange)
                    if s.streak > 0 {
                        Label("Серия \(s.streak) дн.", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(oxOrange)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        default:
            VStack(spacing: 6) {
                Rings(values: [(w, .oxLime), (sets, .oxSky), (kcal, oxOrange)], line: 10)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(s.weekDone)").font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("из \(s.weekGoal)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                Text("Неделя").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
    }

    private func row(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(c)
        }
    }
}

// MARK: - Сегодня: фигура с мышцами дня

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ox.today", provider: SnapProvider()) { e in
            TodayView(s: e.snap).containerBackground(for: .widget) { WidgetBG() }
                .widgetURL(URL(string: "oxion://workout"))
        }
        .configurationDisplayName("Тренировка дня")
        .description("Что качаем сегодня: фигура с подсвеченными мышцами, время и быстрый старт.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TodayView: View {
    @Environment(\.widgetFamily) private var family
    let s: WidgetSnapshot

    private var muscle: String {
        let order = ["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs", "cardio"]
        return s.todayGroups?.first(where: { order.contains($0) }) ?? "none"
    }
    private var groupsText: String {
        let names = ["chest": "Грудь", "back": "Спина", "shoulders": "Плечи", "biceps": "Бицепс", "triceps": "Трицепс",
                     "abs": "Пресс", "glutes": "Ягодицы", "legs": "Ноги", "cardio": "Кардио"]
        return (s.todayGroups ?? []).compactMap { names[$0] }.prefix(3).joined(separator: " · ")
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill").font(.title3).widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.todayTitle ?? "Отдых").font(.headline).lineLimit(1)
                    Text(s.todayTime.map { "в \($0)" } ?? (s.todayTitle == nil ? "тренировок нет" : "сегодня"))
                        .font(.caption)
                    if !groupsText.isEmpty { Text(groupsText).font(.caption2).lineLimit(1) }
                }
            }
        case .systemMedium:
            HStack(spacing: 12) {
                Image("muscle-\(muscle)").resizable().scaledToFit().frame(width: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text("СЕГОДНЯ").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Color.oxLime)
                    Text(s.todayTitle ?? "День отдыха").font(.system(size: 19, weight: .bold)).lineLimit(2)
                    if !groupsText.isEmpty { Text(groupsText).font(.caption).foregroundStyle(.secondary) }
                    if let t = s.todayTime { Label(t, systemImage: "clock").font(.caption.bold()) }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        link("Начать", "play.fill", "oxion://workout", primary: true)
                        link("3D", "figure.stand", "oxion://body", primary: false)
                        link("Бег", "figure.run", "oxion://run", primary: false)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        default:
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("СЕГОДНЯ").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Color.oxLime)
                    Text(s.todayTitle ?? "Отдых").font(.system(size: 15, weight: .bold)).lineLimit(3).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let t = s.todayTime {
                        Text(t).font(.system(size: 20, weight: .bold, design: .rounded))
                    } else {
                        Text(groupsText.isEmpty ? "Восстановление" : groupsText).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image("muscle-\(muscle)").resizable().scaledToFit().frame(width: 44)
            }
            .foregroundStyle(.white)
        }
    }

    private func link(_ t: String, _ icon: String, _ url: String, primary: Bool) -> some View {
        Link(destination: URL(string: url)!) {
            Label(t, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10).frame(height: 28)
                .foregroundStyle(primary ? Color.black : .white)
                .background(primary ? Color.oxLime : Color.white.opacity(0.14), in: Capsule())
        }
    }
}

// MARK: - Серия дней

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ox.streak", provider: SnapProvider()) { e in
            StreakView(s: e.snap).containerBackground(for: .widget) { WidgetBG() }
                .widgetURL(URL(string: "oxion://progress"))
        }
        .configurationDisplayName("Серия 🔥")
        .description("Сколько дней подряд вы держите режим. Крупно — для экрана блокировки и режима ожидания.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct StreakView: View {
    @Environment(\.widgetFamily) private var family
    let s: WidgetSnapshot
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Image(systemName: "flame.fill").font(.system(size: 16)).widgetAccentable()
                    Text("\(s.streak)").font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
        case .accessoryInline:
            Label("Серия \(s.streak) дн.", systemImage: "flame.fill")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [.yellow, oxOrange, .red], startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
                Text("\(s.streak)").font(.system(size: 52, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6)
                Text(s.streak == 1 ? "день подряд" : "дней подряд").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Быстрые действия

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ox.quick", provider: SnapProvider()) { _ in
            QuickActionsView().containerBackground(for: .widget) { WidgetBG() }
        }
        .configurationDisplayName("Быстрые действия")
        .description("Тренировка, бег, отдых 90 секунд, 3D-фигура, тренер-камера и прогресс — в одно касание.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickActionsView: View {
    @Environment(\.widgetFamily) private var family
    private let all: [(String, String, String, Color)] = [
        ("Тренировка", "dumbbell.fill", "oxion://workout", .oxLime),
        ("Бег", "figure.run", "oxion://run", Color(red: 0.35, green: 0.96, blue: 0.44)),
        ("Отдых 90с", "timer", "oxion://rest/90", .oxSky),
        ("Body 3D", "figure.stand", "oxion://body", Color(red: 0.62, green: 0.55, blue: 1)),
        ("Камера", "camera.viewfinder", "oxion://vision", oxOrange),
        ("Прогресс", "chart.line.uptrend.xyaxis", "oxion://progress", Color(red: 1, green: 0.36, blue: 0.45)),
    ]
    var body: some View {
        let items = family == .systemSmall ? Array(all.prefix(4)) : all
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: family == .systemSmall ? 2 : 3)
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(items, id: \.0) { it in
                Link(destination: URL(string: it.2)!) {
                    VStack(spacing: 4) {
                        Image(systemName: it.1).font(.system(size: 17, weight: .semibold)).foregroundStyle(it.3)
                        Text(it.0).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 58 : 56)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .foregroundStyle(.white)
    }
}
