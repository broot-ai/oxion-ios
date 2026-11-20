import SwiftUI
import UserNotifications

/// «OXION OS» — все возможности iPhone и Apple в одном месте, с честной пометкой, что работает в тестовой версии.
struct EcosystemView: View {
    @State private var engine = WorkoutEngine.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image("ox-logo").resizable().scaledToFit().frame(width: 30, height: 40)
                        Text("OXION OS").font(.title2.bold())
                    }
                    Text("OXION рядом весь день: Dynamic Island, экран блокировки, виджеты, Siri, камера и часы.")
                        .font(.subheadline).foregroundStyle(Color.oxHint)
                }
                .listRowBackground(Color.clear)
            }

            Section("OXION OS 2.0") {
                nav("3D-модель мышц", "Вращение, выбор мышцы, упражнения и тренеры", "figure.arms.open", .works) { BodyExplorerView() }
                nav("Прогресс тела", "Фото, замеры, вес, Progress Replay", "chart.line.uptrend.xyaxis", .works) { ProgressHubView() }
                nav("Голосовой тренер", "Подсказки, счёт повторов, AirPods, команды", "person.wave.2.fill", .works) { AudioCoachSettingsView() }
            }

            Section("Тренировка") {
                item("Dynamic Island и экран блокировки", "Запустите тренировку в дневнике", "platter.filled.top.iphone", .works)
                nav("OXION Vision — подсчёт повторов", "Камера, скелет, приседания, отжимания", "camera.viewfinder", .works) { VisionCoachView() }
                nav("Apple Watch", "Как будет выглядеть приложение для часов", "applewatch", .preview) { WatchPreviewView() }
                nav("Тактильные сигналы", "Сила вибрации и проверка сигналов", "iphone.radiowaves.left.and.right", .works) { HapticsSettingsView() }
            }

            Section("Система") {
                nav("Доступы и разрешения", "Геопозиция, контакты, фото, сеть, Face ID…", "checkmark.shield.fill", .works) { PermissionsView() }
                item("Меню при удержании иконки", "Тренировка, QR-код, новый пост и ещё один пункт", "app.badge.fill", .works)
                nav("Умные уведомления", "Категории и частота", "bell.badge.fill", .works) { SmartNotifySettingsView() }
                nav("Siri и Быстрые команды", "Голосовые команды OXION", "waveform", .works) { SiriHelpView() }
                item("Виджеты и StandBy", "Долгое нажатие на главный экран → «+» → OXION", "square.grid.2x2.fill", .preview)
                item("Пункт управления", "Пункт управления → «+» → «Добавить элемент» → OXION", "switch.2", .works)
                nav("Apple Health", "Шаги, сон, пульс, вес", "heart.fill", .paid) { HealthView() }
            }

            Section("Вместе") {
                nav("NFC check-in в клубе", "Отметка посещения меткой на входе", "wave.3.right.circle.fill", .paid) { NFCCheckInView() }
                nav("SharePlay", "Совместная тренировка в FaceTime", "shareplay", .paid) { SharePlayView() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Экосистема Apple")
    }

    enum Status { case works, preview, paid
        var text: String { self == .works ? "Работает" : self == .preview ? "Превью" : "Нужна подписка $99" }
        var color: Color { self == .works ? .lime : self == .preview ? Color(hex: 0x3FD6C9) : Color(hex: 0xF0A030) }
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ st: Status) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(st.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(sub).font(.caption).foregroundStyle(Color.oxHint)
            }
            Spacer(minLength: 4)
            Text(st.text).font(.system(size: 10, weight: .bold)).foregroundStyle(st.color)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(st.color.opacity(0.15), in: Capsule())
        }
    }

    private func item(_ title: String, _ sub: String, _ icon: String, _ st: Status) -> some View {
        row(title, sub, icon, st)
    }

    private func nav<D: View>(_ title: String, _ sub: String, _ icon: String, _ st: Status, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: { row(title, sub, icon, st) }
    }
}

// MARK: - Тактильные сигналы

struct HapticsSettingsView: View {
    @AppStorage("haptic_level") private var level = "normal"
    @AppStorage("haptics") private var on = true

    var body: some View {
        List {
            Section {
                Toggle("Тактильные сигналы", isOn: $on).tint(Color.lime)
                Picker("Сила", selection: $level) {
                    Text("Выключена").tag("off")
                    Text("Мягкая").tag("soft")
                    Text("Обычная").tag("normal")
                    Text("Сильная").tag("strong")
                }
                .pickerStyle(.segmented)
                .disabled(!on)
            } footer: {
                Text("Вибрация только по делу: подход, конец отдыха, финиш, рекорд, выбор.")
            }
            Section("Проверить") {
                test("Выбор упражнения", "hand.tap.fill", .select)
                test("Подход завершён", "checkmark.circle.fill", .setDone)
                test("Отдых окончен", "timer", .restOver)
                test("Тренировка завершена", "flag.checkered", .workoutDone)
                test("Новый рекорд", "trophy.fill", .record)
            }
        }
        .navigationTitle("Тактильные сигналы")
    }

    private func test(_ t: String, _ icon: String, _ k: OxHaptics.Kind) -> some View {
        Button { OxHaptics.play(k) } label: { Label(t, systemImage: icon) }
    }
}

// MARK: - Умные уведомления

struct SmartNotifySettingsView: View {
    @State private var states: [String: Bool] = [:]
    @State private var authorized = true

    var body: some View {
        List {
            if !authorized {
                Section {
                    Button("Разрешить уведомления") {
                        Task { authorized = await SmartNotify.requestPermission() }
                    }
                }
            }
            Section {
                ForEach(SmartNotify.Category.allCases) { c in
                    Toggle(isOn: Binding(get: { states[c.rawValue] ?? SmartNotify.isOn(c) },
                                         set: { v in states[c.rawValue] = v; SmartNotify.set(c, v) })) {
                        Label(c.title, systemImage: c.icon)
                    }
                    .tint(Color.lime)
                }
            } footer: {
                Text("Не чаще одного уведомления на событие. Расписание пересчитывается, когда вы сворачиваете OXION. Серверные пуши (новые рекомендации тренеров) заработают после подключения аккаунта Apple Developer.")
            }
            Section {
                Button("Пересчитать сейчас") {
                    Task {
                        await SmartNotify.reschedule()
                        Haptic.success()
                    }
                }
            }
        }
        .navigationTitle("Уведомления")
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        }
    }
}

// MARK: - Siri

struct SiriHelpView: View {
    private let phrases: [(String, String)] = [
        ("Запусти тренировку в Oxion", "figure.strengthtraining.traditional"),
        ("Сколько осталось отдыхать в Oxion", "timer"),
        ("Заверши подход в Oxion", "checkmark.circle.fill"),
        ("Следующее упражнение в Oxion", "forward.fill"),
        ("Покажи мою статистику в Oxion", "chart.bar.fill"),
        ("Сколько тренировок я сделал за неделю в Oxion", "calendar"),
        ("Открой избранных тренеров в Oxion", "heart.fill")
    ]

    var body: some View {
        List {
            Section {
                ForEach(phrases, id: \.0) { p in
                    Label("«Привет, Siri, \(p.0.prefix(1).lowercased() + p.0.dropFirst())»", systemImage: p.1)
                        .font(.subheadline)
                }
            } header: {
                Text("Скажите Siri")
            } footer: {
                Text("Команды также есть в приложении «Команды» и в Spotlight. Если Siri не распознаёт — откройте OXION один раз после установки.")
            }
        }
        .navigationTitle("Siri")
    }
}
