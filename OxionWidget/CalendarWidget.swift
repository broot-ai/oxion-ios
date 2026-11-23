import WidgetKit
import SwiftUI
import AppIntents

// Календарь тренировок: месяц с отметками.
// ● лайм — тренировка проведена · ◯ лайм — запланирована · точка — была в плане, но пустая.
// В среднем и большом виджете стрелками можно листать месяц (прошлый / текущий / следующий).

private enum CalNav {
    static let offsetKey = "widget_cal_offset"
    static let atKey = "widget_cal_offset_at"
    /// через 10 минут виджет сам возвращается к текущему месяцу
    static let ttl: TimeInterval = 600

    static var offset: Int {
        guard let d = WidgetShared.defaults else { return 0 }
        let at = d.double(forKey: atKey)
        guard at > 0, Date().timeIntervalSince1970 - at < ttl else { return 0 }
        return d.integer(forKey: offsetKey)
    }

    static func shift(_ by: Int) {
        guard let d = WidgetShared.defaults else { return }
        d.set(max(-1, min(1, offset + by)), forKey: offsetKey)
        d.set(Date().timeIntervalSince1970, forKey: atKey)
    }
}

struct CalendarShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Листать месяц"
    static var isDiscoverable = false
    @Parameter(title: "Шаг") var step: Int
    init() {}
    init(step: Int) { self.step = step }
    func perform() async throws -> some IntentResult {
        CalNav.shift(step)
        return .result()
    }
}

struct CalEntry: TimelineEntry {
    let date: Date
    let cal: WidgetCalendar
    let snap: WidgetSnapshot
    var offset = 0
    var demo = false
}

struct CalProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalEntry {
        CalEntry(date: Date(), cal: .placeholder, snap: .placeholder, demo: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let c = WidgetCalendar.load()
        completion(CalEntry(date: Date(), cal: c ?? .placeholder, snap: WidgetSnapshot.load() ?? .placeholder,
                            offset: CalNav.offset, demo: c == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        Task {
            var c = WidgetCalendar.load()
            // старше 30 минут — пробуем обновить с сервера сами
            if c == nil || Date().timeIntervalSince(c?.updatedAt ?? .distantPast) > 1800, let fresh = await WidgetCalendar.fetch() {
                fresh.save()
                c = fresh
            }
            let now = Date()
            let off = CalNav.offset
            let e = CalEntry(date: now, cal: c ?? .placeholder, snap: WidgetSnapshot.load() ?? .placeholder, offset: off, demo: c == nil)
            let cal = Calendar.current
            let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now).addingTimeInterval(30)
            let next = off != 0 ? now.addingTimeInterval(CalNav.ttl + 5) : min(midnight, now.addingTimeInterval(3600))
            completion(Timeline(entries: [e], policy: .after(next)))
        }
    }
}

// MARK: - Модель сетки

private struct Month {
    let start: Date
    let title: String
    let days: [Date?]       // пустые — до первого числа (неделя с понедельника)
    let today: String

    init(offset: Int, now: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        start = cal.date(byAdding: .month, value: offset, to: first) ?? first
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        let y = cal.component(.year, from: start)
        let name = f.string(from: start).capitalized
        title = y == cal.component(.year, from: now) ? name : "\(name) \(y)"
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let lead = (cal.component(.weekday, from: start) + 5) % 7
        var d: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { d.append(cal.date(byAdding: .day, value: i, to: start)) }
        while d.count % 7 != 0 { d.append(nil) }
        days = d
        today = WidgetCalendar.day(now)
    }

    var rows: Int { days.count / 7 }
    var keys: [String] { days.compactMap { $0.map(WidgetCalendar.day) } }
}

private enum DayState { case done, planned, missed, none }

private extension WidgetCalendar {
    func state(_ key: String) -> DayState {
        if done.contains(key) { return .done }
        if planned.contains(key) { return .planned }
        if missed.contains(key) { return .missed }
        return .none
    }
}

private let weekLetters = ["П", "В", "С", "Ч", "П", "С", "В"]

// MARK: - Ячейка дня

private struct DayCell: View {
    let date: Date
    let state: DayState
    let isToday: Bool
    let size: CGFloat

    var body: some View {
        let n = Calendar.current.component(.day, from: date)
        ZStack {
            switch state {
            case .done:
                Circle().fill(Color.oxLime)
                    .shadow(color: Color.oxLime.opacity(0.45), radius: size * 0.18)
            case .planned:
                Circle().strokeBorder(Color.oxLime, lineWidth: max(1.2, size * 0.07))
            default:
                if isToday { Circle().fill(.white.opacity(0.14)) }
            }
            if isToday && state != .done {
                Circle().strokeBorder(.white, lineWidth: max(1, size * 0.06)).padding(state == .planned ? size * 0.12 : 0)
            }
            Text("\(n)")
                .font(.system(size: size * 0.46, weight: isToday || state == .done ? .bold : .medium, design: .rounded))
                .foregroundStyle(state == .done ? Color.oxDeep : (state == .missed ? .white.opacity(0.35) : .white.opacity(isToday ? 1 : 0.82)))
                .minimumScaleFactor(0.5)
            if state == .missed {
                Circle().fill(Color(red: 1, green: 0.36, blue: 0.3).opacity(0.8))
                    .frame(width: size * 0.14, height: size * 0.14)
                    .offset(y: size * 0.36)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct MonthGrid: View {
    let month: Month
    let cal: WidgetCalendar
    var cell: CGFloat
    var vgap: CGFloat = 2
    var letters = true

    var body: some View {
        VStack(spacing: vgap) {
            if letters {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(weekLetters[i])
                            .font(.system(size: cell * 0.36, weight: .semibold))
                            .foregroundStyle(i >= 5 ? Color.oxLime.opacity(0.7) : .white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(0..<month.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        Group {
                            if let d = month.days[r * 7 + c] {
                                let k = WidgetCalendar.day(d)
                                DayCell(date: d, state: cal.state(k), isToday: k == month.today, size: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct CalBG: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.055, blue: 0.06)
            RadialGradient(colors: [Color.oxLime.opacity(0.14), .clear], center: .topLeading, startRadius: 4, endRadius: 240)
        }
    }
}

private struct NavArrows: View {
    let offset: Int
    var body: some View {
        HStack(spacing: 6) {
            Button(intent: CalendarShiftIntent(step: -1)) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24).background(.white.opacity(offset > -1 ? 0.1 : 0.04), in: Circle())
                    .foregroundStyle(.white.opacity(offset > -1 ? 0.9 : 0.25))
            }
            .buttonStyle(.plain)
            Button(intent: CalendarShiftIntent(step: 1)) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24).background(.white.opacity(offset < 1 ? 0.1 : 0.04), in: Circle())
                    .foregroundStyle(.white.opacity(offset < 1 ? 0.9 : 0.25))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Виджет

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ox.calendar", provider: CalProvider()) { e in
            CalendarWidgetView(e: e)
                .containerBackground(for: .widget) { CalBG() }
                .widgetURL(URL(string: "oxion://diary"))
        }
        .configurationDisplayName("Календарь тренировок")
        .description("Месяц с отметками: проведённые тренировки, запланированные и пропущенные.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let e: CalEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .systemLarge: large
        default: weekStrip
        }
    }

    private var month: Month { Month(offset: family == .systemSmall ? 0 : e.offset, now: e.date) }

    private func doneCount(_ m: Month) -> Int { Set(m.keys).intersection(e.cal.done).count }
    private func plannedCount(_ m: Month) -> Int { Set(m.keys).intersection(e.cal.planned).count }

    private func header(_ m: Month, big: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(m.title)
                .font(.system(size: big ? 20 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text("\(doneCount(m))")
                .font(.system(size: big ? 20 : 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oxLime)
                .contentTransition(.numericText())
            Image(systemName: "dumbbell.fill").font(.system(size: big ? 12 : 9)).foregroundStyle(Color.oxLime)
        }
    }

    // маленький: текущий месяц целиком
    private var small: some View {
        let m = month
        return VStack(spacing: 4) {
            header(m, big: false)
            MonthGrid(month: m, cal: e.cal, cell: m.rows > 5 ? 15 : 17, vgap: 1)
            Spacer(minLength: 0)
        }
    }

    // средний: сводка слева, месяц справа
    private var medium: some View {
        let m = month
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(m.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                stat("\(doneCount(m))", "проведено", Color.oxLime)
                stat("\(plannedCount(m))", "в плане", .white)
                if e.snap.streak > 0 && e.offset == 0 {
                    Label("\(e.snap.streak) дн. подряд", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                NavArrows(offset: e.offset)
            }
            .frame(width: 104)
            MonthGrid(month: m, cal: e.cal, cell: m.rows > 5 ? 17 : 19, vgap: 1)
        }
    }

    // большой: месяц крупно + легенда + ближайшие тренировки
    private var large: some View {
        let m = month
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                header(m, big: true)
                NavArrows(offset: e.offset).padding(.leading, 6)
            }
            MonthGrid(month: m, cal: e.cal, cell: m.rows > 5 ? 30 : 33, vgap: 4)
            HStack(spacing: 12) {
                legend(Circle().fill(Color.oxLime), "Проведена")
                legend(Circle().strokeBorder(Color.oxLime, lineWidth: 1.5), "В плане")
                legend(Circle().fill(Color(red: 1, green: 0.36, blue: 0.3).opacity(0.8)).padding(3), "Пропущена")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            if let next = e.snap.upcoming.first, e.offset == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(Color.oxLime)
                    Text(next.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(next.when).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer(minLength: 0)
        }
    }

    // экран блокировки: текущая неделя
    private var weekStrip: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: e.date)?.start ?? e.date
        let today = WidgetCalendar.day(e.date)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let done = days.filter { e.cal.done.contains(WidgetCalendar.day($0)) }.count
        return VStack(alignment: .leading, spacing: 3) {
            Text("Неделя · \(done) трен.").font(.system(size: 12, weight: .semibold)).widgetAccentable()
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    let k = WidgetCalendar.day(d)
                    let st = e.cal.state(k)
                    VStack(spacing: 2) {
                        Text(weekLetters[i]).font(.system(size: 9, weight: k == today ? .heavy : .medium))
                        ZStack {
                            if st == .done { Circle().fill(.primary) }
                            else if st == .planned { Circle().strokeBorder(.primary, lineWidth: 1.5) }
                            else { Circle().fill(.primary.opacity(0.18)) }
                        }
                        .frame(width: 13, height: 13)
                        .overlay { if k == today { Circle().strokeBorder(.primary, lineWidth: 1).padding(-2.5) } }
                        .widgetAccentable(st == .done)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func stat(_ v: String, _ t: String, _ c: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(v).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(c)
            Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func legend(_ dot: some View, _ t: String) -> some View {
        HStack(spacing: 4) {
            dot.frame(width: 9, height: 9)
            Text(t)
        }
    }
}
