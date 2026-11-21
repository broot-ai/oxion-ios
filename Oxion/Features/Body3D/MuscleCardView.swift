import SwiftUI
import Charts

// Карточка мышцы и выбор упражнений для тренировки.

struct MuscleCardView: View {
    let part: MusclePartID
    let intel: MuscleIntelligenceManager
    var onAdd: (MuscleInfo) -> Void
    var onRelated: (String) -> Void
    @State private var exercises: [Exercise] = []
    @State private var loadingEx = true

    private var info: MuscleInfo? { MuscleDataManager.info(part.muscle) }

    var body: some View {
        if let info {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(info)
                        section("Анатомия") {
                            Text(info.about).font(.callout)
                        }
                        section("Основные функции") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(info.functions, id: \.self) { f in
                                    Label(f, systemImage: "checkmark.circle.fill")
                                        .font(.callout)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.lime, .primary)
                                }
                            }
                        }
                        activity(info)
                        section("Упражнения для развития") {
                            if loadingEx {
                                ProgressView().frame(maxWidth: .infinity)
                            } else if exercises.isEmpty {
                                Text("В справочнике пока нет упражнений для этой группы").foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(exercises.prefix(6)) { e in
                                        HStack {
                                            Image(systemName: "dumbbell.fill").foregroundStyle(Color.limeInk).frame(width: 26)
                                            Text(e.name).font(.callout)
                                            Spacer()
                                        }
                                        .padding(.vertical, 9)
                                        Divider().opacity(0.4)
                                    }
                                }
                            }
                        }
                        if !info.related.isEmpty {
                            section("Связанные мышцы") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(info.related, id: \.self) { r in
                                            Button { onRelated(r) } label: {
                                                Text(MuscleDataManager.info(r)?.name ?? r)
                                                    .font(.subheadline.weight(.semibold))
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                            }
                                            .buttonStyle(.glass)
                                        }
                                    }
                                }
                            }
                        }
                        Button { onAdd(info) } label: {
                            Label("Добавить в тренировку", systemImage: "plus.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                    }
                    .padding(20)
                }
                .task {
                    exercises = await WorkoutIntegrationManager.exercises(for: info)
                    loadingEx = false
                }
            }
        }
    }

    private func header(_ info: MuscleInfo) -> some View {
        let st = intel.status(for: info.group)
        return VStack(alignment: .leading, spacing: 8) {
            Text(info.region.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Color.limeInk)
            Text(info.name).font(.largeTitle.bold())
            HStack(spacing: 8) {
                chip(part.side == .l ? "Левая сторона" : "Правая сторона", "arrow.left.and.right")
                chip(st.title + " · оценка", st.icon, st.color)
            }
        }
    }

    private func chip(_ t: String, _ icon: String, _ c: Color = .secondary) -> some View {
        Label(t, systemImage: icon).font(.caption.weight(.semibold))
            .foregroundStyle(c == .secondary ? Color.secondary : c)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }

    @ViewBuilder
    private func activity(_ info: MuscleInfo) -> some View {
        let l = intel.load(for: info.group)
        section("Тренировочная активность") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    metric("\(l?.sets7 ?? 0)", "подходов\n7 дней")
                    metric("\(l?.sets30 ?? 0)", "подходов\n30 дней")
                    metric("\(l?.sessions30 ?? 0)", "тренировок\n30 дней")
                    metric(lastText(info.group), "последняя")
                }
                if let w = l?.weeks, w.contains(where: { $0 > 0 }) {
                    Chart {
                        ForEach(Array(w.enumerated().reversed()), id: \.offset) { i, v in
                            BarMark(x: .value("Неделя", i == 0 ? "эта" : "−\(i)"), y: .value("Подходы", v))
                                .foregroundStyle(i == 0 ? Color.lime : Color.lime.opacity(0.45))
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 120)
                    .chartYAxis { AxisMarks(position: .leading) }
                } else {
                    Text("За 8 недель нет записанных подходов в этой группе").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Измерено: записанные подходы по группе «\(groupName(info.group))» — приложение не делит их на части мышцы и стороны тела. Статус восстановления — расчётная оценка по дням и объёму, не медицинский показатель.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func groupName(_ g: String) -> String { Muscles.fallback[g] ?? g }

    private func lastText(_ g: String) -> String {
        guard let d = intel.daysSince(g) else { return "—" }
        return d == 0 ? "сегодня" : d == 1 ? "вчера" : "\(d) дн."
    }

    private func metric(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title3.bold().monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            c()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ExercisePickSheet: View {
    let info: MuscleInfo
    @Environment(\.dismiss) private var dismiss
    @State private var all: [Exercise] = []
    @State private var picked: Set<Int> = []
    @State private var loading = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Упражнения добавятся в тренировку на сегодня. Если её нет — создадим новую.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if all.isEmpty {
                    Text("Нет упражнений для этой группы").foregroundStyle(.secondary)
                } else {
                    Section("Рекомендуем для «\(info.name)»") {
                        ForEach(all) { e in
                            Button {
                                if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
                                Haptic.tap()
                            } label: {
                                HStack {
                                    Image(systemName: picked.contains(e.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(e.id) ? Color.limeInk : .secondary)
                                        .font(.title3)
                                        .contentTransition(.symbolEffect(.replace))
                                    Text(e.name).foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("В тренировку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Добавить (\(picked.count))").bold() }
                    }
                    .disabled(picked.isEmpty || saving)
                }
            }
            .task {
                all = await WorkoutIntegrationManager.exercises(for: info)
                loading = false
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let list = all.filter { picked.contains($0.id) }
        do {
            try await WorkoutIntegrationManager.add(exercises: list, groups: [info.group], title: Muscles.fallback[info.group] ?? info.name)
            Haptic.success()
            OxAlert.show(icon: "checkmark.circle.fill", title: "Добавлено", message: "\(list.count) упр. в тренировку на сегодня — она в Дневнике.")
            dismiss()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// Аналитика нагрузки по всем группам
struct MuscleLoadOverview: View {
    let intel: MuscleIntelligenceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if intel.distribution.isEmpty {
                        Text("За 30 дней нет записанных подходов").foregroundStyle(.secondary)
                    } else {
                        Chart(intel.distribution, id: \.0) { k, v in
                            BarMark(x: .value("Доля", v), y: .value("Группа", Muscles.fallback[k] ?? k))
                                .foregroundStyle(Color.lime)
                                .cornerRadius(4)
                        }
                        .chartXAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
                        .frame(height: 220)
                    }
                } header: { Text("Распределение подходов · 30 дней") }

                Section("По группам") {
                    ForEach(["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs"], id: \.self) { k in
                        let l = intel.load(for: k)
                        let st = intel.status(for: k)
                        HStack {
                            Circle().fill(st.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Muscles.fallback[k] ?? k).font(.body.weight(.semibold))
                                Text("7 дн: \(l?.sets7 ?? 0) подх. · 30 дн: \(l?.sets30 ?? 0) подх. · \(l?.sessions30 ?? 0) трен.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(st.title).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section {
                    Text("Сравнение левой и правой стороны недоступно: подходы записываются без деления на стороны. Цвета «нагрузка / восстановлена» — расчёт по дням и объёму, а не медицинская оценка.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Нагрузка на мышцы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .refreshable { await intel.refresh() }
        }
    }
}
