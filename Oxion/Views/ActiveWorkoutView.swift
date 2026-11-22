import SwiftUI
import ActivityKit

// MARK: - Настройка перед стартом: подходы, повторения, вес, отдых

struct StartWorkoutSheet: View {
    let workout: WorkoutFull
    var onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlanItem] = []
    @State private var rest = 90

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $rest, in: 0...300, step: 15) {
                        HStack {
                            Image(systemName: "timer").foregroundStyle(Color.lime)
                            Text("Отдых между подходами")
                            Spacer()
                            Text(rest == 0 ? "без отдыха" : "\(rest / 60):\(String(format: "%02d", rest % 60))")
                                .foregroundStyle(Color.lime).monospacedDigit()
                        }
                    }
                    .onChange(of: rest) { for i in items.indices { items[i].restSec = rest } }
                } footer: {
                    Text("После каждого подхода таймер отдыха запустится сам. Его видно в Dynamic Island и на экране блокировки.")
                }

                ForEach($items) { $it in
                    Section {
                        Stepper("Подходов: \(it.sets)", value: $it.sets, in: 1...12)
                        Stepper(it.type == "t" ? "Секунд: \(it.reps)" : "Повторений: \(it.reps)", value: $it.reps, in: 1...(it.type == "t" ? 600 : 100))
                        if it.type == "wr" {
                            HStack {
                                Text("Вес, \(it.unit)")
                                Spacer()
                                TextField("0", value: $it.weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                    } header: {
                        HStack(spacing: 10) {
                            MuscleThumb(key: it.muscle, size: 30, name: it.name)
                            Text(it.name)
                        }
                    }
                }
            }
            .navigationTitle(workout.title?.isEmpty == false ? workout.title! : "Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start()
                } label: {
                    Label("Начать тренировку", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
                .disabled(items.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .onAppear { build() }
        }
    }

    private func build() {
        guard items.isEmpty else { return }
        items = (workout.exercises ?? []).map { ex in
            let last = ex.sets.last
            let type = ex.type ?? "wr"
            return PlanItem(weId: ex.id, exerciseId: ex.exerciseId, name: ex.name, type: type,
                            unit: ex.unit ?? (type == "t" ? "сек" : "кг"), muscle: ex.muscle,
                            sets: max(3, ex.sets.count), reps: last?.reps ?? last?.duration ?? (type == "t" ? 60 : 12),
                            weight: last?.weight, restSec: rest)
        }
    }

    private func start() {
        WorkoutEngine.shared.start(WorkoutState(workoutId: workout.id, title: workout.title?.isEmpty == false ? workout.title! : "Тренировка", items: items))
        Haptic.success()
        dismiss()
        onStarted()
    }
}

// MARK: - Экран идущей тренировки

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var engine = WorkoutEngine.shared
    @State private var reps = 0
    @State private var weight: Double?
    @State private var vision = false
    @State private var flat = FlatDetector()
    @State private var hub = BLEHub.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x15200C), Color.oxBg, Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let s = engine.state {
                if s.phase == .finished {
                    summary(s)
                } else if flat.flat {
                    // телефон лежит на полу/скамье экраном вверх — режим «Табло»
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in ScoreboardView(s: s, now: ctx.date) }
                        .ignoresSafeArea()
                        .transition(.opacity.combined(with: .scale(scale: 1.05)))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        content(s, now: ctx.date)
                    }
                    .overlay(alignment: .topTrailing) {
                        if hub.hrFresh {
                            Label("\(hub.heartRate)", systemImage: "heart.fill")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color(hex: 0xFF3B5C))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .glassEffect(.regular, in: .capsule)
                                .padding(.trailing, 16).padding(.top, 4)
                                .contentTransition(.numericText())
                        }
                    }
                }
            } else {
                ContentUnavailableView("Тренировка не начата", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .environment(\.colorScheme, .dark)
        .fullScreenCover(isPresented: $vision) { VisionCoachView() }
        .task(id: engine.state?.restEndsAt) {
            // сигнал «отдых окончен» — ровно в момент окончания, без секундного цикла
            guard let end = engine.state?.restEndsAt, engine.state?.phase == .resting else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled, engine.state?.phase == .resting { OxHaptics.play(.restOver) }
        }
        .onAppear { syncInputs(); flat.start(); BLEHub.shared.start() }
        .onDisappear { flat.stop() }
        .onChange(of: engine.state?.current) { syncInputs() }
        .onChange(of: engine.state?.items[safe: engine.state?.current ?? 0]?.doneSets) { syncInputs() }
    }

    private func syncInputs() {
        guard let it = engine.state?.currentItem else { return }
        reps = it.reps
        weight = it.weight
    }

    // MARK: идёт тренировка

    private func content(_ s: WorkoutState, now: Date) -> some View {
        let it = s.currentItem
        let resting = s.phase == .resting
        let paused = s.phase == .paused
        let restOver = s.restOver(now)
        return VStack(spacing: 18) {
            // шапка
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.headline).frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                Spacer()
                VStack(spacing: 2) {
                    Text(s.title).font(.subheadline.bold()).lineLimit(1)
                    Text(clock(s.elapsed(now)))
                        .font(.system(.title3, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(paused ? Color.oxHint : Color.lime)
                }
                Spacer()
                // пульс с Apple Watch, если часы прислали его за последние 30 секунд
                if let at = WatchLink.shared.heartRateAt, now.timeIntervalSince(at) < 30, WatchLink.shared.heartRate > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").foregroundStyle(Color(hex: 0xFF5A4E))
                            .symbolEffect(.pulse)
                        Text("\(WatchLink.shared.heartRate)").font(.subheadline.bold().monospacedDigit())
                    }
                    .frame(width: 56)
                } else {
                    Image("ox-logo").resizable().scaledToFit().frame(width: 30, height: 40)
                }
            }

            VStack(spacing: 6) {
                ProgressView(value: Double(s.setsDoneAll), total: Double(max(1, s.setsTotalAll))).tint(Color.lime)
                HStack {
                    Text("Подходов \(s.setsDoneAll) из \(s.setsTotalAll)")
                    Spacer()
                    Text("Упражнений \(s.exercisesDone) из \(s.items.count)")
                }
                .font(.caption)
                .foregroundStyle(Color.oxHint)
            }

            // главная карточка
            VStack(spacing: 12) {
                Text(paused ? "ПАУЗА" : resting ? (restOver ? "ОТДЫХ ОКОНЧЕН" : "ОТДЫХ") : "ПОДХОД")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(paused ? Color.orange : Color.lime)
                if resting || (paused && s.pausedFrom == .resting) {
                    let total = Double(max(1, it?.restSec ?? 1))
                    let left = s.restLeft(now)
                    ZStack {
                        Circle().stroke(Color.lime.opacity(0.15), lineWidth: 14)
                        Circle().trim(from: 0, to: left / total)
                            .stroke(Color.lime, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: left)
                        VStack(spacing: 2) {
                            Text(clock(left)).font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                            Text("дальше: \(it?.name ?? "")").font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                        }
                    }
                    .frame(width: 200, height: 200)
                } else {
                    MuscleFigure(key: it?.muscle, height: 150, name: it?.name)
                }
                Text(it?.name ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                if let it {
                    Text("Подход \(min(it.doneSets + 1, it.sets)) из \(it.sets) · осталось \(max(0, it.sets - it.doneSets))")
                        .foregroundStyle(Color.oxHint)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .glassEffect(.regular.tint(Color.lime.opacity(0.06)), in: .rect(cornerRadius: 32))

            // повторения и вес для этого подхода
            if let it, !resting && !paused {
                HStack(spacing: 12) {
                    adjust(it.type == "t" ? "сек" : "повт.", value: "\(reps)") { reps = max(1, reps - 1) } plus: { reps += 1 }
                    if it.type == "wr" {
                        adjust(it.unit, value: weightText) { weight = max(0, (weight ?? 0) - 2.5) } plus: { weight = (weight ?? 0) + 2.5 }
                    }
                }
            }

            if let n = s.nextItem {
                HStack {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.oxHint)
                    Text("Следующее: ").foregroundStyle(Color.oxHint) + Text(n.name)
                    Spacer()
                }
                .font(.subheadline)
            }

            Spacer(minLength: 0)

            // кнопки
            VStack(spacing: 10) {
                if paused {
                    big("Продолжить", "play.fill") { engine.resume() }
                } else if resting {
                    big(restOver ? "Следующий подход" : "Пропустить отдых", restOver ? "arrow.right" : "forward.fill") { engine.nextSet() }
                } else {
                    big("Завершить подход", "checkmark") {
                        engine.completeSet(reps: reps, weight: it?.type == "wr" ? weight : nil)
                        OxHaptics.play(engine.state?.phase == .finished ? .workoutDone : .setDone)
                    }
                }
                HStack(spacing: 10) {
                    if !paused && !resting {
                        small("Камера", "camera.viewfinder") { vision = true }
                    }
                    if !paused {
                        small("Пауза", "pause.fill") { engine.pause() }
                    }
                    small("Завершить", "stop.fill", destructive: true) {
                        OxAlert.confirm(icon: "flag.checkered", title: "Завершить тренировку?",
                                        message: "Выполненные подходы уже сохранены в дневнике", action: "Завершить") {
                            engine.finish()
                            OxHaptics.play(.workoutDone)
                        }
                    }
                }
            }

            if !engine.liveActivitiesEnabled {
                Button { PermPrompt.show(.liveActivities, denied: true) } label: {
                    Label("Live Activities выключены — как включить", systemImage: "platter.filled.top.iphone")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var weightText: String {
        guard let w = weight else { return "—" }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    private func adjust(_ label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 44, height: 50) }
            VStack(spacing: 0) {
                Text(value).font(.title3.bold().monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(Color.oxHint)
            }
            .frame(minWidth: 56)
            Button(action: plus) { Image(systemName: "plus").frame(width: 44, height: 50) }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func big(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
    }

    private func small(_ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .tint(destructive ? Color(hex: 0xFF5A4E) : .primary)
        .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
    }

    // MARK: итоги

    private func summary(_ s: WorkoutState) -> some View {
        let volume = s.items.reduce(0.0) { $0 + Double(min($1.doneSets, $1.sets)) * Double($1.reps) * ($1.weight ?? 0) }
        return VStack(spacing: 20) {
            Spacer()
            Image("ox-logo").resizable().scaledToFit().frame(height: 110)
                .shadow(color: Color.lime.opacity(0.6), radius: 30)
            Text("Тренировка завершена!").font(.largeTitle.bold()).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                StatTile(title: "время", value: clock(s.elapsed()), icon: "clock.fill")
                StatTile(title: "подходов", value: "\(s.setsDoneAll)", icon: "repeat")
                StatTile(title: "кг объём", value: "\(Int(volume))", icon: "scalemass.fill")
            }
            Text("Все подходы сохранены в дневник Oxion")
                .font(.subheadline).foregroundStyle(Color.oxHint)
            Spacer()
            ShareWorkoutButton(card: WorkoutResultCard(
                title: s.title, date: Date(), duration: clock(s.elapsed()), sets: s.setsDoneAll, volume: Int(volume),
                lines: s.items.filter { $0.doneSets > 0 }.map { it in
                    let w = (it.weight ?? 0) > 0 ? " × \(Int(it.weight ?? 0)) кг" : ""
                    return (it.name, "\(min(it.doneSets, it.sets)) × \(it.reps)" + w)
                }))
            big("Готово", "checkmark") {
                Task { await WorkoutSync.flush() }
                engine.clear()
                dismiss()
            }
        }
        .padding(20)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return s >= 3600 ? String(format: "%ld:%02ld:%02ld", s / 3600, s % 3600 / 60, s % 60) : String(format: "%ld:%02ld", s / 60, s % 60)
    }
}

// MARK: - Полоска «идёт тренировка» над таббаром

struct ActiveWorkoutBar: View {
    @State private var engine = WorkoutEngine.shared
    var onOpen: () -> Void

    var body: some View {
        if let s = engine.state, s.phase != .notStarted {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image("ox-logo").resizable().scaledToFit().frame(width: 22, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.phase == .finished ? "Тренировка завершена" : (s.currentItem?.name ?? s.title))
                            .font(.subheadline.bold()).lineLimit(1)
                        Text(status(s)).font(.caption).foregroundStyle(Color.oxHint)
                    }
                    Spacer()
                    if s.phase == .resting, let end = s.restEndsAt, end > Date() {
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.headline.monospacedDigit()).foregroundStyle(Color.lime)
                            .frame(width: 60, alignment: .trailing)
                    } else if s.phase == .exercising {
                        Text(timerInterval: s.startedAt.addingTimeInterval(s.pausedTotal)...Date.distantFuture, countsDown: false)
                            .font(.headline.monospacedDigit()).foregroundStyle(Color.lime)
                            .frame(width: 70, alignment: .trailing)
                    } else if s.phase == .paused {
                        Image(systemName: "pause.fill").foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(Color.lime.opacity(0.12)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private func status(_ s: WorkoutState) -> String {
        switch s.phase {
        case .resting: return s.restOver() ? "Отдых окончен — следующий подход" : "Отдых"
        case .paused: return "Пауза"
        case .finished: return "Нажмите, чтобы посмотреть итоги"
        default:
            let it = s.currentItem
            return "Подход \(min((it?.doneSets ?? 0) + 1, it?.sets ?? 1)) из \(it?.sets ?? 0)"
        }
    }
}

// MARK: - Идущая тренировка как системная полоса над таббаром (как мини-плеер в «Музыке»)

struct WorkoutAccessory: ViewModifier {
    @State private var engine = WorkoutEngine.shared
    var open: () -> Void

    private var active: Bool { (engine.state?.phase ?? .notStarted) != .notStarted }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: active) {
                WorkoutAccessoryContent(open: open)
            }
        } else {
            content.overlay(alignment: .bottom) {
                ActiveWorkoutBar(onOpen: open).padding(.bottom, 92)
            }
        }
    }
}

struct WorkoutAccessoryContent: View {
    @State private var engine = WorkoutEngine.shared
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var open: () -> Void

    var body: some View {
        if let s = engine.state, s.phase != .notStarted {
            HStack(spacing: 10) {
                Button(action: open) {
                    HStack(spacing: 10) {
                        Image(systemName: s.phase == .resting ? "hourglass" : s.phase == .paused ? "pause.fill" : "dumbbell.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.lime)
                            .frame(width: 28, height: 28)
                            .background(Color.lime.opacity(0.18), in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.phase == .finished ? "Тренировка завершена" : (s.currentItem?.name ?? s.title))
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            if placement != .inline {
                                Text(statusText(s)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        timer(s)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if placement != .inline, s.phase == .exercising {
                    Button { engine.completeSet() } label: {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.onLime)
                            .frame(width: 32, height: 32)
                            .background(Color.lime, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Подход сделан")
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder private func timer(_ s: WorkoutState) -> some View {
        if s.phase == .resting, let end = s.restEndsAt, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Color.lime)
                .frame(width: 52, alignment: .trailing)
        } else if s.phase == .exercising {
            Text(timerInterval: s.startedAt.addingTimeInterval(s.pausedTotal)...Date.distantFuture, countsDown: false)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func statusText(_ s: WorkoutState) -> String {
        switch s.phase {
        case .resting: return s.restOver() ? "Отдых окончен — следующий подход" : "Отдых"
        case .paused: return "Пауза"
        case .finished: return "Нажмите, чтобы посмотреть итоги"
        default:
            let it = s.currentItem
            return "Подход \(min((it?.doneSets ?? 0) + 1, it?.sets ?? 1)) из \(it?.sets ?? 0)"
        }
    }
}
