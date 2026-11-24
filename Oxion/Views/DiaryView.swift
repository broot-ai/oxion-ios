import SwiftUI

/// Предустановки для шторки «Новая тренировка»: дата из календаря, группа из «давно не тренировали»
struct NewWorkoutPreset: Identifiable {
    let id = UUID()
    var date: Date? = nil
    var groups: [String] = []
}

enum DiaryGroups {
    static let all: [(key: String, name: String)] = [
        ("chest", "Грудь"), ("back", "Спина"), ("legs", "Ноги"), ("glutes", "Ягодицы"),
        ("shoulders", "Дельты"), ("arms", "Руки"), ("abs", "Пресс"), ("cardio", "Кардио")
    ]

    static func name(_ key: String) -> String { all.first { $0.key == key }?.name ?? key }

    /// группы тренировки, сведённые к общим (quads → legs, biceps → arms …)
    static func keys(_ w: Workout) -> Set<String> {
        Set((w.groups ?? []).compactMap { g -> String? in
            let k = MuscleArt.group(g) ?? g
            return (k == "biceps" || k == "triceps") ? "arms" : k
        })
    }
}

struct DiaryView: View {
    @State private var stats: Stats?
    @State private var workouts: [Workout] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var newPreset: NewWorkoutPreset?
    @State private var addWeight = false
    @State private var openWorkout: Int?
    @State private var toast: String?
    @State private var filter: String?          // группа мышц
    @State private var day: String?             // выбранный день в календаре
    @State private var busy = false

    private var todayStr: String { RU.dayFormatter.string(from: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let e = errorText, stats == nil {
                        ErrorStateView(message: e) {
                            Task { await load() }
                        }
                        .padding(.top, 40)
                    }

                    if let s = stats {
                        WeekCard(stats: s, streak: streakWeeks)
                        DiaryCalendarStrip(daysWithWorkouts: workoutDays, today: todayStr, selected: $day)
                        HStack(spacing: 12) {
                            StatTile(title: "Подходов", value: "\(s.sets ?? 0)", icon: "repeat")
                            StatTile(title: "Ккал за 30 дн.", value: "\(calories30)", icon: "flame.fill")
                            Button {
                                addWeight = true
                            } label: {
                                StatTile(title: "Вес, кг  +",
                                         value: s.lastWeight.map { String(format: "%.1f", $0.kg) } ?? "—",
                                         icon: "scalemass.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        quickActions
                        if !neglected.isEmpty { neglectedCard }

                        NavigationLink {
                            ExercisesView()
                        } label: {
                            HStack {
                                Image(systemName: "dumbbell.fill")
                                    .foregroundStyle(Color.limeInk)
                                Text("Библиотека упражнений")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)
                    }

                    if !workouts.isEmpty {
                        workoutList
                    } else if stats != nil && !loading {
                        ContentUnavailableView {
                            VStack(spacing: 8) {
                                Image("runner").resizable().scaledToFit().frame(height: 120)
                                Text("Тренировок пока нет")
                            }
                        } description: {
                            Text("Нажмите «+», чтобы записать первую")
                        }
                    }

                    if loading && stats == nil {
                        ProgressView().padding(40)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .animation(.smooth(duration: 0.3), value: filter)
                .animation(.smooth(duration: 0.3), value: day)
            }
            .navigationTitle("Дневник")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openWorkout) { id in
                WorkoutDetailView(workoutId: id) {
                    Task { await load() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPreset = NewWorkoutPreset(date: day.flatMap { RU.dayFormatter.date(from: $0) })
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новая тренировка")
                }
            }
            .sheet(item: $newPreset) { preset in
                NewWorkoutSheet(onCreated: { id in
                    Task {
                        await load()
                        openWorkout = id
                    }
                }, preset: preset)
            }
            .sheet(isPresented: $addWeight) {
                WeightSheet(current: stats?.lastWeight?.kg) {
                    toast = "Вес сохранён"
                    Task { await load() }
                }
            }
            .oxRefreshable { await load() }
            .task {
                if stats == nil { await load() }
            }
            .toast($toast)
        }
    }

    // MARK: быстрые действия

    private var quickActions: some View {
        HStack(spacing: 10) {
            quick("Тренировка", "plus") { newPreset = NewWorkoutPreset() }
            NavigationLink { CardioHubView() } label: {
                quickLabel("Кардио", "figure.run")
            }
            .buttonStyle(.plain)
            quick("Повторить", "arrow.clockwise") {
                if let last = pastWorkouts.first { repeatWorkout(last) }
            }
            .disabled(pastWorkouts.isEmpty || busy)
            .opacity(pastWorkouts.isEmpty ? 0.45 : 1)
        }
    }

    private func quick(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            action()
        } label: { quickLabel(title, icon) }
        .buttonStyle(.plain)
    }

    private func quickLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.limeInk)
                .frame(width: 40, height: 40)
                .background(Color.lime.opacity(0.14), in: Circle())
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    // MARK: давно не тренировали

    private var neglectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Давно не тренировали", systemImage: "exclamationmark.arrow.circlepath")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(neglected, id: \.key) { g in
                        Button {
                            Haptic.tap(.soft)
                            newPreset = NewWorkoutPreset(groups: [g.key == "arms" ? "biceps" : g.key])
                        } label: {
                            HStack(spacing: 10) {
                                MuscleThumb(key: g.key, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(DiaryGroups.name(g.key)).font(.subheadline.bold())
                                    Text(g.days.map { "\($0) \(RU.plural($0, "день", "дня", "дней"))" } ?? "больше 2 мес.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
            Text("Нажмите на группу — откроется новая тренировка с ней")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: список тренировок

    private var workoutList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.map { "Тренировки · " + RU.human($0).lowercased() } ?? "Тренировки")
                    .font(.title3.bold())
                Spacer()
                if day != nil || filter != nil {
                    Button("Сбросить") { day = nil; filter = nil }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.limeInk)
                }
            }
            .padding(.top, 8)

            filterChips

            let planned = filtered.filter { $0.date > todayStr }.sorted { $0.date < $1.date }
            if !planned.isEmpty {
                sectionHeader("Запланировано", count: planned.count)
                ForEach(planned) { w in row(w, planned: true) }
            }
            let past = filtered.filter { $0.date <= todayStr }
            ForEach(sections(past), id: \.title) { sec in
                sectionHeader(sec.title, count: sec.items.count)
                ForEach(sec.items) { w in row(w, planned: false) }
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.largeTitle).foregroundStyle(Color.limeInk)
                    Text(day != nil ? "В этот день тренировок нет" : "Нет тренировок с этой группой")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        newPreset = NewWorkoutPreset(date: day.flatMap { RU.dayFormatter.date(from: $0) },
                                                     groups: filter.map { [$0 == "arms" ? "biceps" : $0] } ?? [])
                    } label: {
                        Label((day ?? "") > todayStr ? "Запланировать" : "Записать тренировку", systemImage: "plus")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Все", on: filter == nil) { filter = nil }
                ForEach(DiaryGroups.all.filter { usedGroups.contains($0.key) }, id: \.key) { g in
                    chip(g.name, on: filter == g.key) { filter = filter == g.key ? nil : g.key }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            action()
        } label: {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.onLime : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Color.lime : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    private func row(_ w: Workout, planned: Bool) -> some View {
        Button {
            openWorkout = w.id
        } label: {
            WorkoutRow(w: w)
                .overlay {
                    if planned {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.lime.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { repeatWorkout(w) } label: { Label("Повторить сегодня", systemImage: "arrow.clockwise") }
            Button { openWorkout = w.id } label: { Label("Открыть", systemImage: "arrow.up.right") }
            Button(role: .destructive) {
                OxAlert.confirm(icon: "trash.fill", title: "Удалить тренировку?",
                                message: "«\(w.title ?? "Тренировка")» и все её подходы будут удалены.",
                                action: "Удалить", destructive: true) {
                    Task { await delete(w) }
                }
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    // MARK: расчёты

    private var pastWorkouts: [Workout] { workouts.filter { $0.date <= todayStr } }

    private var workoutDays: Set<String> { Set(workouts.map(\.date)) }

    private var usedGroups: Set<String> { workouts.reduce(into: Set<String>()) { $0.formUnion(DiaryGroups.keys($1)) } }

    private var filtered: [Workout] {
        workouts.filter { w in
            (day == nil || w.date == day) && (filter == nil || DiaryGroups.keys(w).contains(filter!))
        }
    }

    private var calories30: Int {
        let from = RU.dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        return pastWorkouts.filter { $0.date >= from }.reduce(0) { $0 + ($1.calories ?? 0) }
    }

    /// сколько недель подряд была хотя бы одна тренировка (текущая неделя засчитывается, если уже была)
    private var streakWeeks: Int {
        let cal = Calendar(identifier: .iso8601)
        let weeks = Set(pastWorkouts.compactMap { RU.dayFormatter.date(from: $0.date) }.compactMap {
            cal.dateInterval(of: .weekOfYear, for: $0)?.start
        })
        guard var cur = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(cur) { cur = cal.date(byAdding: .weekOfYear, value: -1, to: cur) ?? cur }
        var n = 0
        while weeks.contains(cur) {
            n += 1
            cur = cal.date(byAdding: .weekOfYear, value: -1, to: cur) ?? cur
        }
        return n
    }

    /// группы, которые не тренировали 5+ дней (из загруженных 60 дней)
    private var neglected: [(key: String, days: Int?)] {
        guard !pastWorkouts.isEmpty else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        var last: [String: Date] = [:]
        for w in pastWorkouts {
            guard let d = RU.dayFormatter.date(from: w.date) else { continue }
            for k in DiaryGroups.keys(w) where (last[k] ?? .distantPast) < d { last[k] = d }
        }
        let out: [(key: String, days: Int?)] = DiaryGroups.all.filter { $0.key != "cardio" }.map { g in
            let days = last[g.key].map { Calendar.current.dateComponents([.day], from: $0, to: today).day ?? 0 }
            return (g.key, days)
        }
        return out.filter { ($0.days ?? 999) >= 5 }.sorted { ($0.days ?? 999) > ($1.days ?? 999) }.prefix(5).map { $0 }
    }

    private struct DiarySection { let title: String; let items: [Workout] }

    /// «Эта неделя», «Прошлая неделя», дальше по месяцам
    private func sections(_ list: [Workout]) -> [DiarySection] {
        let cal = Calendar(identifier: .iso8601)
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        let month = DateFormatter()
        month.locale = Locale(identifier: "ru_RU")
        month.dateFormat = "LLLL"
        var order: [String] = []
        var map: [String: [Workout]] = [:]
        for w in list.sorted(by: { ($0.date, $0.time ?? "") > ($1.date, $1.time ?? "") }) {
            guard let d = RU.dayFormatter.date(from: w.date) else { continue }
            let title: String
            if d >= thisWeek { title = "Эта неделя" }
            else if d >= lastWeek { title = "Прошлая неделя" }
            else { title = month.string(from: d).capitalized }
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(w)
        }
        return order.map { DiarySection(title: $0, items: map[$0] ?? []) }
    }

    // MARK: действия

    /// Копия тренировки на сегодня вместе со всеми упражнениями
    private func repeatWorkout(_ w: Workout) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let full: WorkoutFull = try await API.call("/workouts/\(w.id)")
                let created: WorkoutFull = try await API.call("/workouts", method: "POST", body: [
                    "date": todayStr, "title": w.title ?? "Тренировка", "groups": w.groups ?? []
                ])
                for e in full.exercises ?? [] {
                    let _: WorkoutFull = try await API.call("/workouts/\(created.id)/exercises", method: "POST",
                                                            body: ["exercise_id": e.exerciseId])
                }
                Haptic.success()
                await load()
                openWorkout = created.id
            } catch {
                OxAlert.error(error.localizedDescription)
            }
        }
    }

    private func delete(_ w: Workout) async {
        do {
            let _: OK = try await API.call("/workouts/\(w.id)", method: "DELETE")
            withAnimation(.smooth) { workouts.removeAll { $0.id == w.id } }
            toast = "Тренировка удалена"
            await load()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? today
        let from = cal.date(byAdding: .day, value: -60, to: today) ?? today
        let to = cal.date(byAdding: .day, value: 30, to: today) ?? today
        let f = RU.dayFormatter
        do {
            let s: Stats = try await API.call("/stats", query: [
                "from": f.string(from: weekStart), "to": f.string(from: weekEnd), "today": f.string(from: today)
            ])
            let w: WorkoutsResponse = try await API.call("/workouts", query: [
                "from": f.string(from: from), "to": f.string(from: to)
            ])
            stats = s
            workouts = w.items.sorted { $0.date > $1.date }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Календарная лента: 4 недели назад и неделя вперёд

struct DiaryCalendarStrip: View {
    let daysWithWorkouts: Set<String>
    let today: String
    @Binding var selected: String?

    private var days: [Date] {
        let cal = Calendar.current
        let t = cal.startOfDay(for: Date())
        return (-27...6).compactMap { cal.date(byAdding: .day, value: $0, to: t) }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE"
        return f
    }()

    var body: some View {
        let wd = Self.weekday
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        let key = RU.dayFormatter.string(from: d)
                        let has = daysWithWorkouts.contains(key)
                        let isToday = key == today
                        let on = selected == key
                        Button {
                            Haptic.tap(.soft)
                            selected = on ? nil : key
                        } label: {
                            VStack(spacing: 5) {
                                Text(wd.string(from: d).lowercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(on ? Color.onLime.opacity(0.8) : .secondary)
                                Text("\(Calendar.current.component(.day, from: d))")
                                    .font(.callout.weight(.bold).monospacedDigit())
                                    .foregroundStyle(on ? Color.onLime : (key > today ? .secondary : .primary))
                                Circle()
                                    .fill(has ? (on ? Color.onLime : Color.lime) : .clear)
                                    .frame(width: 6, height: 6)
                            }
                            .frame(width: 42, height: 66)
                            .background(on ? Color.lime : (has ? Color.lime.opacity(0.10) : Color.primary.opacity(0.04)),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isToday && !on ? Color.lime : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .id(key)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onAppear { proxy.scrollTo(today, anchor: .center) }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct WeekCard: View {
    let stats: Stats
    var streak: Int = 0

    var body: some View {
        let done = stats.workouts ?? 0
        let goal = max(1, stats.weekGoal ?? 3)
        let progress = min(1.0, Double(done) / Double(goal))
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.lime.opacity(0.15), lineWidth: 14)
                    .onAppear { Celebrate.weekGoal(done: done, goal: goal) }
                    .onChange(of: done) { Celebrate.weekGoal(done: done, goal: goal) }
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.8), value: progress)
                VStack(spacing: 0) {
                    Text("\(done)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("из \(goal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 6) {
                Text("Эта неделя")
                    .font(.headline)
                Text(done >= goal ? "Цель недели выполнена 🔥" : "Осталось \(goal - done) \(RU.plural(goal - done, "тренировка", "тренировки", "тренировок"))")
                    .foregroundStyle(.secondary)
                if streak >= 2 {
                    Label("\(streak) \(RU.plural(streak, "неделя", "недели", "недель")) подряд", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.limeInk)
                }
                if let t = stats.today, (t.workouts ?? 0) > 0 {
                    Text("Сегодня: \(t.sets ?? 0) подходов")
                        .font(.subheadline)
                        .foregroundStyle(Color.limeInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glassEffect(.regular.tint(Color.lime.opacity(0.08)), in: .rect(cornerRadius: 28))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.limeInk)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct WorkoutRow: View {
    let w: Workout

    var body: some View {
        HStack(spacing: 14) {
            MuscleStackThumb(keys: w.groups ?? [], size: 52, name: w.title)
            VStack(alignment: .leading, spacing: 3) {
                Text((w.title?.isEmpty == false ? w.title : nil) ?? "Тренировка")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(RU.human(w.date))
                    if let t = w.time, !t.isEmpty { Text("· \(t)") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let n = w.exCount, n > 0 {
                    Text("\(n) упр.")
                        .font(.subheadline.weight(.semibold))
                }
                if let c = w.calories, c > 0 {
                    Text("\(c) ккал")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Новая тренировка

struct NewWorkoutSheet: View {
    var onCreated: (Int) -> Void
    var preset: NewWorkoutPreset? = nil
    @State private var appliedPreset = false
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var title = ""
    @State private var hasTime = false
    @State private var time = Date()
    @State private var calories = ""
    @State private var groups: [String] = []
    @State private var saving = false
    @State private var errorText: String?
    @State private var show3D = false

    private let pick: [(String, String, [String])] = [
        ("shoulders", "Дельты", ["shoulders"]), ("chest", "Грудь", ["chest"]), ("arms", "Руки", ["biceps", "triceps"]),
        ("abs", "Пресс", ["abs"]), ("back", "Спина", ["back"]), ("legs", "Ноги", ["legs"]),
        ("glutes", "Ягодицы", ["glutes"]), ("cardio", "Кардио", ["cardio"])
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(pick, id: \.0) { item in
                                let on = item.2.contains { groups.contains($0) }
                                Button {
                                    if on { groups.removeAll { item.2.contains($0) } } else { groups += item.2.filter { !groups.contains($0) } }
                                    Haptic.tap(.soft)
                                } label: {
                                    VStack(spacing: 6) {
                                        MuscleFigure(key: item.0, height: 120)
                                            .opacity(on ? 1 : 0.55)
                                        Text(item.1).font(.subheadline.bold())
                                    }
                                    .frame(width: 92)
                                    .padding(.vertical, 10)
                                    .oxCardBG(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(on ? Color.lime : Color.primary.opacity(0.07), lineWidth: on ? 2 : 1))
                                    .shadow(color: on ? Color.lime.opacity(0.35) : .clear, radius: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowBackground(Color.clear)
                    Button { show3D = true } label: {
                        Label("Выбрать на 3D-модели", systemImage: "figure.arms.open")
                            .font(.subheadline.weight(.semibold))
                    }
                } header: {
                    Text("Что тренируете")
                }
                Section {
                    TextField("Название (например, «День ног»)", text: $title)
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    Toggle("Указать время", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    TextField("Калории (необязательно)", text: $calories)
                        .keyboardType(.numberPad)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .oxFitSheet()
            .navigationTitle("Новая тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
        .onAppear {
            guard !appliedPreset, let p = preset else { return }
            appliedPreset = true
            if let d = p.date { date = d }
            for g in p.groups where !groups.contains(g) { groups.append(g) }
            if g0Title.isEmpty == false, title.isEmpty { title = g0Title }
        }
        .fullScreenCover(isPresented: $show3D) {
            Body3DScreen(onPick: { picked in
                for g in picked where !groups.contains(g) { groups.append(g) }
                if title.isEmpty, let first = pick.first(where: { $0.2.contains { picked.contains($0) } }) { title = "День: " + first.1.lowercased() }
            })
        }
    }

    /// «День: ноги» для тренировки, открытой из «давно не тренировали»
    private var g0Title: String {
        guard let g = preset?.groups.first, let item = pick.first(where: { $0.2.contains(g) }) else { return "" }
        return "День: " + item.1.lowercased()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = ["date": RU.dayFormatter.string(from: date), "title": title, "groups": groups]
        if hasTime {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            body["time"] = f.string(from: time)
        }
        if let c = Int(calories) { body["calories"] = c }
        do {
            let w: WorkoutFull = try await API.call("/workouts", method: "POST", body: body)
            Haptic.success()
            dismiss()
            onCreated(w.id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Вес тела

struct WeightSheet: View {
    var current: Double?
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Вес, кг", text: $kg)
                        .keyboardType(.decimalPad)
                        .font(.title2)
                } footer: {
                    Text("Сохранится на сегодня. Если вес за сегодня уже есть — обновится.")
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Вес тела")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                }
            }
            .onAppear {
                if let current { kg = String(format: "%.1f", current) }
            }
        }
        .presentationDetents([.height(260)])
    }

    private func save() async {
        guard let v = Double(kg.replacingOccurrences(of: ",", with: ".")) else {
            errorText = "Введите число, например 72.5"
            return
        }
        do {
            let _: OK = try await API.call("/weights", method: "POST",
                                           body: ["date": RU.dayFormatter.string(from: Date()), "kg": v])
            Haptic.success()
            onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
