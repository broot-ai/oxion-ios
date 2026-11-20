import SwiftUI

/// Вкладка поиска (отдельная круглая кнопка справа в таббаре): библиотека упражнений.
struct ExercisesView: View {
    @Environment(AppModel.self) private var model
    @State private var all: [Exercise] = []
    @State private var query = ""
    @State private var muscle: String?
    @State private var errorText: String?
    @State private var loaded = false

    private var filtered: [Exercise] {
        all.filter { e in
            (muscle == nil || e.muscle == muscle) &&
            (query.isEmpty || e.name.localizedCaseInsensitiveContains(query))
        }
    }

    private var muscleKeys: [String] {
        if let m = model.meta?.muscles, !m.isEmpty { return m.map(\.key) }
        return Muscles.order
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                muscle = nil
                                Haptic.tap(.soft)
                            } label: {
                                Chip(text: "Все", selected: muscle == nil)
                            }
                            ForEach(muscleKeys, id: \.self) { key in
                                Button {
                                    muscle = (muscle == key) ? nil : key
                                    Haptic.tap(.soft)
                                } label: {
                                    Chip(text: model.muscleName(key), selected: muscle == key)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let e = errorText, all.isEmpty {
                    Section {
                        ErrorStateView(message: e) {
                            Task { await load() }
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(filtered) { e in
                        NavigationLink(value: e) {
                            HStack(spacing: 12) {
                                RemoteImage(url: API.media(e.image), icon: "dumbbell")
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name)
                                        .font(.body.weight(.medium))
                                    Text(model.muscleName(e.muscle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if e.own == true {
                                    Spacer()
                                    Text("моё")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.lime)
                                }
                            }
                        }
                    }
                } footer: {
                    if loaded && !all.isEmpty {
                        Text("\(filtered.count) \(RU.plural(filtered.count, "упражнение", "упражнения", "упражнений"))")
                    }
                }
            }
            .navigationTitle("Упражнения")
            .navigationDestination(for: Exercise.self) { e in
                ExerciseDetailView(e: e)
            }
            .searchable(text: $query, prompt: "Найти упражнение")
            .overlay {
                if !loaded && errorText == nil {
                    ProgressView()
                }
            }
            .refreshable { await load() }
            .task {
                if all.isEmpty { await load() }
            }
        }
    }

    private func load() async {
        do {
            let r: ExercisesResponse = try await API.call("/exercises")
            all = r.items
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        loaded = true
    }
}

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let e: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if e.image != nil {
                    RemoteImage(url: API.media(e.image), icon: "dumbbell")
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                HStack(spacing: 10) {
                    StatPill(icon: "figure.strengthtraining.traditional", text: model.muscleName(e.muscle))
                    if let t = typeName(e.type) {
                        StatPill(icon: "slider.horizontal.3", text: t)
                    }
                }
                if let tech = e.technique, !tech.isEmpty {
                    Text("Техника")
                        .font(.headline)
                    Text(tech)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Описание техники пока не добавлено.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(e.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private func typeName(_ t: String?) -> String? {
        switch t {
        case "wr": return "Вес × повторы"
        case "r": return "Повторы"
        case "t": return "Время"
        case "dt": return "Дистанция + время"
        default: return nil
        }
    }
}
