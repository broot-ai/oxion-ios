import SwiftUI

/// Тренировка: упражнения и подходы, добавление и удаление.
struct WorkoutDetailView: View {
    let workoutId: Int
    var onChanged: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var w: WorkoutFull?
    @State private var errorText: String?
    @State private var addingExercise = false
    @State private var setFor: WExercise?
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var starting = false

    var body: some View {
        List {
            if let w {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((w.title?.isEmpty == false ? w.title : nil) ?? "Тренировка")
                            .font(.title2.bold())
                        HStack {
                            Text(RU.human(w.date))
                            if let t = w.time, !t.isEmpty { Text("· \(t)") }
                            if let c = w.calories, c > 0 { Text("· \(c) ккал") }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    if !(w.exercises ?? []).isEmpty {
                        Button {
                            if WorkoutEngine.shared.isActive {
                                model.showActiveWorkout = true
                            } else {
                                starting = true
                            }
                        } label: {
                            Label(WorkoutEngine.shared.isActive ? "Вернуться к тренировке" : "Начать тренировку", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                ForEach(w.exercises ?? []) { ex in
                    Section {
                        if ex.sets.isEmpty {
                            Text("Подходов пока нет")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(ex.sets.enumerated()), id: \.element.id) { idx, s in
                            HStack {
                                Text("\(idx + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.black)
                                    .frame(width: 26, height: 26)
                                    .background(Color.lime, in: Circle())
                                Text(s.text(type: ex.type, unit: ex.unit))
                                    .font(.body.monospacedDigit())
                                Spacer()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await deleteSet(s.id) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                        Button {
                            setFor = ex
                        } label: {
                            Label("Добавить подход", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        HStack {
                            Text(ex.name)
                            Text("· " + model.muscleName(ex.muscle))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button(role: .destructive) {
                                    Task { await deleteExercise(ex.id) }
                                } label: {
                                    Label("Убрать упражнение", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        addingExercise = true
                    } label: {
                        Label("Добавить упражнение", systemImage: "dumbbell.fill")
                            .font(.headline)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить тренировку", systemImage: "trash")
                    }
                }
            } else if let e = errorText {
                ErrorStateView(message: e) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingExercise) {
            ExercisePickerSheet { e in
                Task { await addExercise(e.id) }
            }
        }
        .sheet(item: $setFor) { ex in
            AddSetSheet(ex: ex) { body in
                Task { await addSet(ex.id, body) }
            }
        }
        .sheet(isPresented: $starting) {
            if let w {
                StartWorkoutSheet(workout: w) { model.showActiveWorkout = true }
            }
        }
        .confirmationDialog("Удалить тренировку?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task { await deleteWorkout() }
            }
        }
        .oxRefreshable { await load() }
        .task { await load() }
        .toast($toast)
    }

    private func load() async {
        do {
            let r: WorkoutFull = try await API.call("/workouts/\(workoutId)")
            w = r
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func addExercise(_ id: Int) async {
        do {
            let r: WorkoutFull = try await API.call("/workouts/\(workoutId)/exercises", method: "POST", body: ["exercise_id": id])
            w = r
            Haptic.tap()
            onChanged()
        } catch {
            toast = error.localizedDescription
        }
    }

    private func addSet(_ weId: Int, _ body: [String: Any]) async {
        do {
            let _: OK = try await API.call("/we/\(weId)/sets", method: "POST", body: body)
            Haptic.success()
            await load()
            onChanged()
            Task { await WidgetSync.refresh() }
        } catch {
            toast = error.localizedDescription
        }
    }

    private func deleteSet(_ id: Int) async {
        do {
            let _: OK = try await API.call("/sets/\(id)", method: "DELETE")
            await load()
            onChanged()
        } catch {
            toast = error.localizedDescription
        }
    }

    private func deleteExercise(_ id: Int) async {
        do {
            let _: OK = try await API.call("/we/\(id)", method: "DELETE")
            await load()
            onChanged()
        } catch {
            toast = error.localizedDescription
        }
    }

    private func deleteWorkout() async {
        do {
            let _: OK = try await API.call("/workouts/\(workoutId)", method: "DELETE")
            onChanged()
            dismiss()
        } catch {
            toast = error.localizedDescription
        }
    }
}

extension WExercise: Hashable {
    static func == (a: WExercise, b: WExercise) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Добавить подход: поля зависят от типа упражнения.
struct AddSetSheet: View {
    let ex: WExercise
    var onSave: ([String: Any]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var reps = ""
    @State private var duration = ""
    @State private var distance = ""

    private var type: String { ex.type ?? "wr" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if type == "wr" {
                        TextField("Вес, \(ex.unit ?? "кг")", text: $weight).keyboardType(.decimalPad)
                        TextField("Повторы", text: $reps).keyboardType(.numberPad)
                    } else if type == "r" {
                        TextField("Повторы", text: $reps).keyboardType(.numberPad)
                    } else if type == "t" {
                        TextField("Время, \(ex.unit ?? "сек")", text: $duration).keyboardType(.numberPad)
                    } else {
                        TextField("Дистанция, \(ex.unit ?? "км")", text: $distance).keyboardType(.decimalPad)
                        TextField("Время, мин", text: $duration).keyboardType(.numberPad)
                    }
                } header: {
                    Text(ex.name)
                }
                if let last = ex.sets.last {
                    Section {
                        Button("Повторить прошлый: \(last.text(type: ex.type, unit: ex.unit))") {
                            if let v = last.weight { weight = num(v) }
                            if let v = last.reps { reps = String(v) }
                            if let v = last.duration { duration = String(v) }
                            if let v = last.distance { distance = num(v) }
                        }
                    }
                }
            }
            .navigationTitle("Подход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        var b: [String: Any] = [:]
                        if let v = dbl(weight) { b["weight"] = v }
                        if let v = Int(reps) { b["reps"] = v }
                        if let v = Int(duration) { b["duration"] = v }
                        if let v = dbl(distance) { b["distance"] = v }
                        onSave(b)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dbl(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private func num(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}

/// Выбор упражнения из библиотеки для тренировки.
struct ExercisePickerSheet: View {
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var all: [Exercise] = []
    @State private var query = ""
    @State private var muscle: String?

    private var filtered: [Exercise] {
        all.filter { e in
            (muscle == nil || e.muscle == muscle) &&
            (query.isEmpty || e.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Muscles.order, id: \.self) { key in
                            Button {
                                muscle = (muscle == key) ? nil : key
                            } label: {
                                Chip(text: model.muscleName(key), selected: muscle == key)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(filtered) { e in
                    Button {
                        OxHaptics.play(.select)
                        onPick(e)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            MuscleThumb(key: e.muscle, size: 44, name: e.name)
                            VStack(alignment: .leading) {
                                Text(e.name).foregroundStyle(.primary)
                                Text(model.muscleName(e.muscle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.limeInk)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Найти упражнение")
            .navigationTitle("Упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task {
                if let r: ExercisesResponse = try? await API.call("/exercises") { all = r.items }
            }
        }
    }
}
