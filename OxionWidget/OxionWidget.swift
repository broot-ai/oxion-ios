import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Что показывать (настраивается долгим нажатием на виджет → «Изменить виджет»)

enum WidgetContent: String, AppEnum {
    case auto, quote, goal, reminder

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Содержимое"
    static var caseDisplayRepresentations: [WidgetContent: DisplayRepresentation] = [
        .auto: "Автоматически",
        .quote: "Мотивационная цитата",
        .goal: "Моя цель",
        .reminder: "Напоминание о тренировке"
    ]
}

struct OxionWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Oxion"
    static var description = IntentDescription("Цитата дня, ваша цель или напоминание о тренировке")

    @Parameter(title: "Показывать", default: .auto)
    var content: WidgetContent
}

// MARK: - Данные

struct OxionEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let content: WidgetContent

    /// «Автоматически»: есть тренировка сегодня → напоминание; есть цель → цель; иначе цитата
    var resolved: WidgetContent {
        guard content == .auto else { return content }
        if snap.todayTitle != nil { return .reminder }
        if snap.goalTitle != nil { return .goal }
        if snap.weekDone < snap.weekGoal && Calendar.current.component(.hour, from: date) >= 17 { return .reminder }
        return .quote
    }
}

struct OxionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OxionEntry {
        OxionEntry(date: Date(), snap: .placeholder, content: .auto)
    }

    func snapshot(for configuration: OxionWidgetIntent, in context: Context) async -> OxionEntry {
        OxionEntry(date: Date(), snap: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder), content: configuration.content)
    }

    func timeline(for configuration: OxionWidgetIntent, in context: Context) async -> Timeline<OxionEntry> {
        var snap = WidgetSnapshot.load()
        // виджет может сам обновиться с сервера, если приложение передало вход
        if let fresh = await WidgetAPIResponse.fetch() {
            fresh.save()
            snap = fresh
        }
        var s = snap ?? WidgetSnapshot(quote: WidgetSnapshot.localQuote().0, quoteAuthor: WidgetSnapshot.localQuote().1,
                                       reminder: "Откройте Oxion, чтобы увидеть цель и тренировки")
        let q = WidgetSnapshot.localQuote()
        if snap == nil || Calendar.current.isDateInToday(s.updatedAt) == false { s.quote = q.0; s.quoteAuthor = q.1 }
        let now = Date()
        let entry = OxionEntry(date: now, snap: s, content: configuration.content)
        // обновляем раз в час и обязательно после полуночи — новая цитата дня
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
        return Timeline(entries: [entry], policy: .after(min(nextHour, midnight.addingTimeInterval(60))))
    }
}

// MARK: - Цвета Oxion

extension Color {
    static let oxLime = Color(red: 0.698, green: 0.933, blue: 0.216)
    static let oxDeep = Color(red: 0.059, green: 0.063, blue: 0.071)
    static let oxHint2 = Color(red: 0.54, green: 0.54, blue: 0.51)
}

// MARK: - Вид

struct OxionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OxionEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: lockRect
            case .accessoryCircular: lockCircle
            case .accessoryInline: Text(inlineText)
            default: home
            }
        }
        .widgetURL(URL(string: entry.resolved == .goal ? "oxion://goals" : entry.resolved == .reminder ? "oxion://diary" : "oxion://home"))
        .containerBackground(for: .widget) {
            ZStack {
                Color.oxDeep
                RadialGradient(colors: [Color.oxLime.opacity(0.35), .clear], center: .bottomTrailing, startRadius: 4, endRadius: 220)
            }
        }
    }

    private var inlineText: String {
        switch entry.resolved {
        case .goal: return "🎯 \(entry.snap.goalTitle ?? "Цель") · \(entry.snap.goalPct ?? 0)%"
        case .reminder: return "💪 \(entry.snap.reminder)"
        default: return "🔥 \(entry.snap.quote)"
        }
    }

    // главный экран
    @ViewBuilder
    private var home: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 6) {
                Image("ox-logo-w")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 20)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Color.oxLime)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            switch entry.resolved {
            case .goal: goalView
            case .reminder: reminderView
            default: quoteView
            }
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        switch entry.resolved {
        case .goal: return "Моя цель"
        case .reminder: return "Тренировка"
        default: return "Цитата дня"
        }
    }

    private var quoteView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("«\(entry.snap.quote)»")
                .font(family == .systemSmall ? .system(size: 15, weight: .semibold) : .system(size: 19, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(family == .systemSmall ? 5 : 4)
            Spacer(minLength: 0)
            if let a = entry.snap.quoteAuthor {
                Text("— \(a)").font(.caption).foregroundStyle(Color.oxHint2)
            }
        }
    }

    @ViewBuilder
    private var goalView: some View {
        if let g = entry.snap.goalTitle {
            let pct = Double(entry.snap.goalPct ?? 0)
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.oxLime.opacity(0.2), lineWidth: 8)
                        Circle().trim(from: 0, to: pct / 100)
                            .stroke(Color.oxLime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(pct))%").font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .frame(width: 62, height: 62)
                    Spacer(minLength: 0)
                    Text(g).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.7)
                }
            } else {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.oxLime.opacity(0.2), lineWidth: 10)
                        Circle().trim(from: 0, to: pct / 100)
                            .stroke(Color.oxLime, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(pct))%").font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g).font(.headline).lineLimit(2)
                        if let d = entry.snap.goalDetail { Text(d).font(.subheadline).foregroundStyle(Color.oxHint2) }
                        Spacer(minLength: 0)
                        Text("Неделя: \(entry.snap.weekDone) из \(entry.snap.weekGoal)").font(.caption).foregroundStyle(Color.oxLime)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Цель не задана").font(.headline)
                Text("Поставьте цель в Oxion — прогресс будет здесь").font(.caption).foregroundStyle(Color.oxHint2)
                Spacer(minLength: 0)
            }
        }
    }

    private var reminderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = entry.snap.todayTitle {
                Text(t).font(family == .systemSmall ? .headline : .title3.bold()).lineLimit(2)
                if let time = entry.snap.todayTime {
                    Label(time, systemImage: "clock.fill").font(.subheadline).foregroundStyle(Color.oxLime)
                }
            } else {
                Text(entry.snap.reminder).font(family == .systemSmall ? .subheadline.bold() : .headline).lineLimit(3)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<max(1, entry.snap.weekGoal), id: \.self) { i in
                    Capsule()
                        .fill(i < entry.snap.weekDone ? Color.oxLime : Color.white.opacity(0.15))
                        .frame(height: 6)
                }
            }
            Text("Неделя: \(entry.snap.weekDone) из \(entry.snap.weekGoal)")
                .font(.caption2)
                .foregroundStyle(Color.oxHint2)
        }
    }

    // экран блокировки
    private var lockRect: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.resolved {
            case .goal:
                Text("🎯 \(entry.snap.goalTitle ?? "Цель")").font(.headline).lineLimit(1)
                ProgressView(value: Double(entry.snap.goalPct ?? 0), total: 100)
                Text("\(entry.snap.goalPct ?? 0)% · \(entry.snap.goalDetail ?? "")").font(.caption).lineLimit(1)
            case .reminder:
                Text("💪 Oxion").font(.headline)
                Text(entry.snap.reminder).font(.caption).lineLimit(2)
            default:
                Text(entry.snap.quote).font(.caption).lineLimit(3)
            }
        }
    }

    private var lockCircle: some View {
        Gauge(value: Double(min(entry.snap.weekDone, entry.snap.weekGoal)), in: 0...Double(max(1, entry.snap.weekGoal))) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(entry.snap.weekDone)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Виджет

struct OxionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OxionWidget", intent: OxionWidgetIntent.self, provider: OxionProvider()) { entry in
            OxionWidgetView(entry: entry)
        }
        .configurationDisplayName("Oxion")
        .description("Цитата дня, ваша цель или напоминание о тренировке")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct OxionWidgetBundle: WidgetBundle {
    var body: some Widget {
        OxionWidget()
    }
}
