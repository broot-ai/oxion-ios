import SwiftUI
import RealityKit
import UniformTypeIdentifiers

// OXION BODY 3D — главный экран: Студия / AR / Движение.

struct Body3DView: UIViewRepresentable {
    let controller: Body3DController
    func makeUIView(context: Context) -> ARView { controller.makeView() }
    func updateUIView(_ v: ARView, context: Context) {}
    static func dismantleUIView(_ v: ARView, coordinator: ()) {
        v.session.pause()
    }
}

struct Body3DScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var ctrl = Body3DController()
    @State private var card: MusclePartID?
    @State private var addFor: MuscleInfo?
    @State private var aiPrompt: PromptBox?
    @State private var importing = false
    @State private var showMotion = false
    @State private var showGuide = false
    @State private var showStats = false

    struct PromptBox: Identifiable { let id = UUID(); let text: String }

    private var sel: MuscleSelectionManager { ctrl.selection }

    var body: some View {
        ZStack {
            Body3DView(controller: ctrl)
                .ignoresSafeArea()

            if ctrl.loading {
                ProgressView("Загружаю модель…").tint(Color.lime).foregroundStyle(.white)
            } else if let e = ctrl.errorText {
                ContentUnavailableView {
                    Label("Модель не загрузилась", systemImage: "figure.stand")
                } description: { Text(e) } actions: {
                    Button("Повторить") { Task { await ctrl.load() } }.buttonStyle(.glassProminent).tint(Color.lime)
                }
                .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                topBar
                if ctrl.mode == .ar { arBanner }
                if ctrl.colorMode == .load && ctrl.mode == .studio { legend }
                Spacer()
                bottom
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sel.selected)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sel.focused)
        .animation(.easeInOut(duration: 0.25), value: ctrl.mode)
        .animation(.easeInOut(duration: 0.25), value: ctrl.placed)
        .onAppear {
            ctrl.onTap = { _ in }
        }
        .onDisappear { ctrl.teardown() }
        .sheet(item: $card) { p in
            MuscleCardView(part: p, intel: ctrl.intel,
                           onAdd: { info in card = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addFor = info } },
                           onRelated: { m in ctrl.selection.select(muscle: m); ctrl.refreshTargets(); ctrl.focus(m); card = nil })
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
        }
        .sheet(item: $addFor) { info in
            ExercisePickSheet(info: info)
                .presentationDetents([.large])
        }
        .sheet(item: $aiPrompt) { p in
            NavigationStack {
                AICoachView(initial: p.text)
                    .navigationTitle("ИИ-тренер")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { aiPrompt = nil } } }
            }
        }
        .sheet(isPresented: $showGuide) { Body3DModelGuide(source: ctrl.source) }
        .sheet(isPresented: $showStats) { MuscleLoadOverview(intel: ctrl.intel).presentationDetents([.medium, .large]) }
        .fullScreenCover(isPresented: $showMotion) { BodyTrackingScreen() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.usdz]) { r in
            guard case .success(let url) = r else { return }
            do {
                try Body3DAsset.installCustom(from: url)
                Task { await ctrl.load(); if ctrl.source != .custom { OxAlert.show(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Модель не подошла", message: "В файле нет объектов с именами мышц. Показываю встроенную модель.") } }
            } catch { OxAlert.error(error.localizedDescription) }
        }
    }

    // MARK: верх

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Закрыть")

            Spacer()
            HStack(spacing: 4) {
                ForEach(Body3DMode.allCases) { m in
                    Button {
                        Task { await ctrl.setMode(m) }
                        Haptic.tap()
                    } label: {
                        Text(m.title).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(ctrl.mode == m ? Color.onLime : .white)
                            .background(ctrl.mode == m ? Color.lime : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Task { await ctrl.setMode(.studio) }
                    showMotion = true
                } label: {
                    Text("Движение").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            Spacer()

            Menu {
                Section("Вид") {
                    Button { ctrl.face(back: false) } label: { Label("Спереди", systemImage: "person.fill") }
                    Button { ctrl.face(back: true) } label: { Label("Сзади", systemImage: "person.fill.turn.down") }
                    Button { ctrl.resetView() } label: { Label("Исходное положение", systemImage: "arrow.counterclockwise") }
                    if ctrl.mode == .ar && ctrl.placed {
                        Button { ctrl.replace() } label: { Label("Переставить модель", systemImage: "arrow.down.to.line") }
                    }
                }
                Section("Цвета") {
                    Picker("Цвета", selection: Binding(get: { ctrl.colorMode }, set: { ctrl.colorMode = $0 })) {
                        Label("Анатомия", systemImage: "figure.stand").tag(Body3DColorMode.anatomy)
                        Label("Нагрузка", systemImage: "flame").tag(Body3DColorMode.load)
                    }
                    Button { showStats = true } label: { Label("Аналитика нагрузки", systemImage: "chart.bar.xaxis") }
                }
                Section("Выбор") {
                    Toggle(isOn: Binding(get: { sel.bothSides }, set: { sel.bothSides = $0 })) {
                        Label("Обе стороны сразу", systemImage: "arrow.left.and.right")
                    }
                    if !sel.selected.isEmpty {
                        Button(role: .destructive) { sel.clear(); ctrl.refreshTargets() } label: { Label("Снять выбор", systemImage: "xmark.circle") }
                    }
                }
                Section("Модель") {
                    Button { importing = true } label: { Label("Загрузить свою модель (USDZ)", systemImage: "square.and.arrow.down") }
                    if Body3DAsset.hasCustom {
                        Button(role: .destructive) { Body3DAsset.removeCustom(); Task { await ctrl.load() } } label: { Label("Вернуть встроенную", systemImage: "arrow.uturn.backward") }
                    }
                    Button { showGuide = true } label: { Label("Как подготовить модель", systemImage: "questionmark.circle") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44).contentShape(Circle())
            } primaryAction: {
                ctrl.flip(); Haptic.tap()
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder private var arBanner: some View {
        if let e = ctrl.arError {
            Label(e, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .rect(cornerRadius: 18))
                .padding(.horizontal, 16)
        } else if !ctrl.arHint.isEmpty {
            Label(ctrl.arHint, systemImage: ctrl.placed ? "hand.tap" : "viewfinder")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .transition(.opacity)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([MuscleStatus.high, .recovered, .low, .natural], id: \.self) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.color).frame(width: 9, height: 9)
                    Text(s == .natural ? "Обычно" : s == .high ? "Нагрузка" : s == .recovered ? "Восст." : "Мало")
                        .font(.caption2.weight(.semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: низ

    private var bottom: some View {
        VStack(spacing: 12) {
            if let f = sel.focused, let info = MuscleDataManager.info(f.muscle) {
                focusCard(f, info)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if sel.selected.isEmpty && !ctrl.loading && (ctrl.mode == .studio || ctrl.placed) {
                Text("Нажми на мышцу · один палец — вращать · два — двигать и масштаб · двойной тап — развернуть")
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if !sel.selected.isEmpty { actionPanel }
        }
        .padding(.bottom, 6)
    }

    private func focusCard(_ p: MusclePartID, _ info: MuscleInfo) -> some View {
        let st = ctrl.intel.status(for: info.group)
        let load = ctrl.intel.load(for: info.group)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.name).font(.title3.bold())
                    Text("\(info.region) · \(p.side == .l ? "левая" : "правая") сторона")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Label(st.title, systemImage: st.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(st == .natural ? .white : st.color)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(st.color.opacity(0.16), in: Capsule())
            }
            HStack(spacing: 18) {
                stat("\(load?.sets7 ?? 0)", "подходов\nза 7 дней")
                stat("\(load?.sessions30 ?? 0)", "тренировок\nза 30 дней")
                stat(lastText(info.group), "последняя\nтренировка")
            }
            HStack(spacing: 10) {
                Button { card = p } label: {
                    Label("Подробнее", systemImage: "info.circle").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glass)
                Button { addFor = info } label: {
                    Label("В тренировку", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
            }
            .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 10)
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.headline.monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
        }
    }

    private func lastText(_ g: String) -> String {
        guard let d = ctrl.intel.daysSince(g) else { return "—" }
        return d == 0 ? "сегодня" : d == 1 ? "вчера" : "\(d) дн."
    }

    private var actionPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sel.muscles, id: \.self) { m in
                        Button {
                            sel.focused = MusclePartID(muscle: m, side: .l)
                            ctrl.focus(m)
                        } label: {
                            HStack(spacing: 6) {
                                Text(MuscleDataManager.info(m)?.name ?? m).font(.subheadline.weight(.semibold))
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                                    .onTapGesture {
                                        sel.selected = sel.selected.filter { $0.muscle != m }
                                        if sel.focused?.muscle == m { sel.focused = nil }
                                        ctrl.refreshTargets()
                                    }
                            }
                            .foregroundStyle(Color.onLime)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.lime, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)

            HStack(spacing: 10) {
                Button {
                    let names = sel.muscles.compactMap { MuscleDataManager.info($0)?.name.lowercased() }.joined(separator: ", ")
                    aiPrompt = PromptBox(text: "Составь тренировку на сегодня с акцентом на: \(names). Учитывай мой уровень и цель.")
                } label: {
                    Label("План от ИИ", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glass)
                Button { start() } label: {
                    Label("Начать", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
            }
            .font(.headline)
            .padding(.horizontal, 16)
        }
        .padding(.top, 14).padding(.bottom, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 10)
        .foregroundStyle(.white)
    }

    private func close() {
        ctrl.teardown()
        model.showMuscles = false
        dismiss()
    }

    private func start() {
        let groups = MuscleDataManager.groups(of: sel.selected)
        let title = groups.prefix(3).map { model.muscleName($0) }.joined(separator: " + ")
        Haptic.success()
        close()
        let model = model
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            await model.quickWorkout(title: title.isEmpty ? "Тренировка" : title, groups: groups)
        }
    }
}

/// Карточка на главном экране
struct HomeMuscleCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.showMuscles = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.lime.opacity(0.18))
                    Image(systemName: "figure.stand")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.limeInk)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OXION BODY 3D").font(.headline)
                    Text("Выбери мышцы на 3D-фигуре, в AR и собери тренировку")
                        .font(.subheadline)
                        .foregroundStyle(Color.oxHint)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.oxHint)
            }
            .padding(16)
            .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Как подготовить свою профессиональную модель
struct Body3DModelGuide: View {
    let source: Body3DSource
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Сейчас используется", value: source.rawValue)
                }
                Section("Требования к файлу") {
                    Text("Формат USDZ, человек стоит прямо, лицом вперёд (ось −Z смотрит от зрителя), рост любой — приложение само приведёт к 1,8 м.")
                    Text("Каждая мышца — отдельный объект. Имя объекта = ID из списка ниже плюс сторона: _l (левая) или _r (правая). Регистр не важен.")
                    Text("Всё остальное (голова, кисти, стопы) — любые другие имена: будет показано, но не выбирается.")
                }
                Section("ID мышц") {
                    ForEach(MuscleDataManager.all) { m in
                        HStack {
                            Text(m.name)
                            Spacer()
                            Text(m.id + "_l / _r").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Своя 3D-модель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}
