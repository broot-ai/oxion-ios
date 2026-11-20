import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Панель OXION: Small / Medium / Large / StandBy

enum SmallKind: String, AppEnum {
    case trainer, motivation, week, start
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Маленький виджет"
    static var caseDisplayRepresentations: [SmallKind: DisplayRepresentation] = [
        .trainer: "Тренер дня", .motivation: "Мотивация дня", .week: "Тренировки за неделю", .start: "Быстрый старт"
    ]
}

struct DashboardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Панель OXION"
    static var description = IntentDescription("Тренер дня, прогресс недели, план и достижения")
    @Parameter(title: "Маленький виджет показывает", default: .week)
    var small: SmallKind
}

struct DashEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let small: SmallKind
}

struct DashProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashEntry { DashEntry(date: Date(), snap: .placeholder, small: .week) }

    func snapshot(for configuration: DashboardIntent, in context: Context) async -> DashEntry {
        DashEntry(date: Date(), snap: WidgetSnapshot.load() ?? .placeholder, small: configuration.small)
    }

    func timeline(for configuration: DashboardIntent, in context: Context) async -> Timeline<DashEntry> {
        // данные кладёт приложение в общую папку; без неё (тестовая установка) — демо-данные с пометкой
        let snap = WidgetSnapshot.load() ?? .placeholder
        let next = Calendar.current.date(byAdding: .minute, value: 90, to: Date()) ?? Date()
        return Timeline(entries: [DashEntry(date: Date(), snap: snap, small: configuration.small)], policy: .after(next))
    }
}

struct DashboardView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: DashEntry

    private var s: WidgetSnapshot { entry.snap }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .systemLarge, .systemExtraLarge: large
            default: small
            }
        }
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            if s.isDemo && family != .systemSmall {
                Text("ДЕМО").font(.system(size: 8, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.oxLime.opacity(0.25), in: Capsule()).foregroundStyle(Color.oxLime)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color.oxDeep
                LinearGradient(colors: [Color.oxLime.opacity(0.22), .clear], startPoint: .bottomTrailing, endPoint: .center)
            }
        }
    }

    // MARK: Small (в режиме StandBy без фона — крупнее)

    @ViewBuilder
    private var small: some View {
        switch entry.small {
        case .trainer:
            VStack(alignment: .leading, spacing: 4) {
                header("Тренер дня")
                Spacer(minLength: 0)
                Initials(name: s.trainerName ?? "?", size: showsBackground ? 38 : 50)
                Text(s.trainerName ?? "Найдите тренера").font(.headline).lineLimit(1)
                Text(s.trainerInfo ?? "Каталог Oxion").font(.caption2).foregroundStyle(Color.oxHint2).lineLimit(1)
            }
            .widgetURL(URL(string: "oxion://trainers"))
        case .motivation:
            VStack(alignment: .leading, spacing: 4) {
                header("Мотивация")
                Spacer(minLength: 0)
                Text(s.quote).font(.system(size: showsBackground ? 14 : 17, weight: .semibold)).minimumScaleFactor(0.6).lineLimit(5)
            }
            .widgetURL(URL(string: "oxion://home"))
        case .start:
            VStack(alignment: .leading, spacing: 6) {
                header("Тренировка")
                Spacer(minLength: 0)
                Text(s.todayTitle ?? "Начать тренировку").font(.headline).lineLimit(2)
                Link(destination: URL(string: "oxion://diary")!) {
                    Label("Старт", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.oxLime, in: Capsule())
                }
            }
        case .week:
            VStack(alignment: .leading, spacing: 4) {
                header("Неделя")
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Color.oxLime.opacity(0.2), lineWidth: showsBackground ? 9 : 12)
                    Circle().trim(from: 0, to: min(1, Double(s.weekDone) / Double(max(1, s.weekGoal))))
                        .stroke(Color.oxLime, style: StrokeStyle(lineWidth: showsBackground ? 9 : 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(s.weekDone)").font(.system(size: showsBackground ? 26 : 38, weight: .bold, design: .rounded))
                        Text("из \(s.weekGoal)").font(.caption2).foregroundStyle(Color.oxHint2)
                    }
                }
                .frame(width: showsBackground ? 76 : 110, height: showsBackground ? 76 : 110)
                .frame(maxWidth: .infinity)
            }
            .widgetURL(URL(string: "oxion://diary"))
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header("Неделя")
                Text("\(s.weekDone)/\(s.weekGoal)").font(.system(size: 30, weight: .bold, design: .rounded))
                WeekDots(done: s.weekDone, goal: s.weekGoal)
                Spacer(minLength: 0)
                Text("\(s.weekSets) подх. · \(s.weekKcal) ккал").font(.caption2).foregroundStyle(Color.oxHint2)
            }
            .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.favorites.isEmpty ? "Рекомендуем" : "Избранные").font(.caption.bold()).foregroundStyle(Color.oxLime).textCase(.uppercase)
                ForEach(Array((s.favorites.isEmpty ? s.trainers : s.favorites).prefix(3).enumerated()), id: \.offset) { _, t in
                    Link(destination: URL(string: "oxion://trainer/\(t.id)")!) {
                        TrainerRowW(t: t)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Large — персональная фитнес-панель

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("Моя панель")
                Spacer()
                if s.streak > 0 { Text("🔥 \(s.streak) нед.").font(.caption.bold()).foregroundStyle(Color.oxLime) }
            }
            HStack(spacing: 8) {
                StatW(value: "\(s.weekDone)/\(s.weekGoal)", label: "тренировок")
                StatW(value: "\(s.weekSets)", label: "подходов")
                StatW(value: "\(s.weekKcal)", label: "ккал")
                StatW(value: "\(s.achievementsDone)/\(s.achievementsTotal)", label: "наград")
            }
            if let g = s.goalTitle {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("🎯 \(g)").font(.subheadline.bold()).lineLimit(1)
                        Spacer()
                        Text("\(s.goalPct ?? 0)%").font(.subheadline.bold()).foregroundStyle(Color.oxLime)
                    }
                    ProgressView(value: Double(s.goalPct ?? 0), total: 100).tint(Color.oxLime)
                }
            }
            Text("ПЛАН").font(.caption2.bold()).foregroundStyle(Color.oxHint2)
            if s.upcoming.isEmpty {
                Text("Тренировок не запланировано").font(.caption).foregroundStyle(Color.oxHint2)
            }
            ForEach(Array(s.upcoming.prefix(3).enumerated()), id: \.offset) { _, p in
                HStack {
                    Circle().fill(Color.oxLime).frame(width: 6, height: 6)
                    Text(p.title).font(.caption.bold()).lineLimit(1)
                    Spacer()
                    Text(p.when).font(.caption2).foregroundStyle(Color.oxHint2)
                }
            }
            Text("ТРЕНЕРЫ ДЛЯ ВАС").font(.caption2.bold()).foregroundStyle(Color.oxHint2)
            HStack(spacing: 8) {
                ForEach(Array(s.trainers.prefix(3).enumerated()), id: \.offset) { _, t in
                    Link(destination: URL(string: "oxion://trainer/\(t.id)")!) {
                        VStack(spacing: 3) {
                            Initials(name: t.name, size: 34)
                            Text(t.name.components(separatedBy: " ").first ?? t.name).font(.caption2.bold()).lineLimit(1)
                            if let p = t.price { Text("\(p) ₽").font(.system(size: 9)).foregroundStyle(Color.oxHint2) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func header(_ t: String) -> some View {
        HStack(spacing: 5) {
            Image("ox-logo-w").resizable().scaledToFit().frame(width: 12, height: 16)
            Text(t).font(.caption2.bold()).foregroundStyle(Color.oxLime).textCase(.uppercase)
        }
    }
}

struct Initials: View {
    let name: String
    var size: CGFloat = 36
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Color.oxLime)
            .frame(width: size, height: size)
            .background(Color.oxLime.opacity(0.18), in: Circle())
    }
}

struct WeekDots: View {
    let done: Int
    let goal: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, goal), id: \.self) { i in
                Capsule().fill(i < done ? Color.oxLime : Color.white.opacity(0.15)).frame(height: 6)
            }
        }
    }
}

struct StatW: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9)).foregroundStyle(Color.oxHint2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TrainerRowW: View {
    let t: WTrainer
    var body: some View {
        HStack(spacing: 8) {
            Initials(name: t.name, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.name).font(.caption.bold()).lineLimit(1)
                Text([t.info, t.price.map { "\($0) ₽" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Color.oxHint2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let r = t.rating, r > 0 { Text("★ \(String(format: "%.1f", r))").font(.system(size: 10, weight: .bold)).foregroundStyle(.yellow) }
        }
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OxionDashboard", intent: DashboardIntent.self, provider: DashProvider()) { entry in
            DashboardView(entry: entry)
        }
        .configurationDisplayName("Панель OXION")
        .description("Неделя, план, тренеры и достижения. В режиме StandBy — крупные цифры.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
