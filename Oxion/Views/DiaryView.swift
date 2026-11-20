import SwiftUI

struct DiaryView: View {
    @State private var stats: Stats?
    @State private var workouts: [Workout] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var newWorkout = false
    @State private var addWeight = false
    @State private var openWorkout: Int?
    @State private var toast: String?

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
                        WeekCard(stats: s)
                        HStack(spacing: 12) {
                            StatTile(title: "Подходов", value: "\(s.sets ?? 0)", icon: "repeat")
                            StatTile(title: "Ккал", value: "\(s.calories ?? 0)", icon: "flame.fill")
                            Button {
                                addWeight = true
                            } label: {
                                StatTile(title: "Вес, кг  +",
                                         value: s.lastWeight.map { String(format: "%.1f", $0.kg) } ?? "—",
                                         icon: "scalemass.fill")
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            ExercisesView()
                        } label: {
                            HStack {
                                Image(systemName: "dumbbell.fill")
                                    .foregroundStyle(Color.lime)
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Тренировки")
                                .font(.title3.bold())
                                .padding(.top, 8)
                            ForEach(workouts) { w in
                                Button {
                                    openWorkout = w.id
                                } label: {
                                    WorkoutRow(w: w)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if stats != nil && !loading {
                        ContentUnavailableView("Тренировок пока нет",
                                               systemImage: "figure.run",
                                               description: Text("Нажмите «+», чтобы записать первую"))
                    }

                    if loading && stats == nil {
                        ProgressView().padding(40)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Дневник")
            .navigationDestination(item: $openWorkout) { id in
                WorkoutDetailView(workoutId: id) {
                    Task { await load() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newWorkout = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новая тренировка")
                }
            }
            .sheet(isPresented: $newWorkout) {
                NewWorkoutSheet { id in
                    Task {
                        await load()
                        openWorkout = id
                    }
                }
            }
            .sheet(isPresented: $addWeight) {
                WeightSheet(current: stats?.lastWeight?.kg) {
                    toast = "Вес сохранён"
                    Task { await load() }
                }
            }
            .refreshable { await load() }
            .task {
                if stats == nil { await load() }
            }
            .toast($toast)
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

struct WeekCard: View {
    let stats: Stats

    var body: some View {
        let done = stats.workouts ?? 0
        let goal = max(1, stats.weekGoal ?? 3)
        let progress = min(1.0, Double(done) / Double(goal))
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.lime.opacity(0.15), lineWidth: 14)
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
                if let t = stats.today, (t.workouts ?? 0) > 0 {
                    Text("Сегодня: \(t.sets ?? 0) подходов")
                        .font(.subheadline)
                        .foregroundStyle(Color.lime)
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
                .foregroundStyle(Color.lime)
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
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(Color.lime)
                .frame(width: 44, height: 44)
                .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Новая тренировка

struct NewWorkoutSheet: View {
    var onCreated: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var title = ""
    @State private var hasTime = false
    @State private var time = Date()
    @State private var calories = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название (например, «Грудь и трицепс»)", text: $title)
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
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = ["date": RU.dayFormatter.string(from: date), "title": title, "groups": [String]()]
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
