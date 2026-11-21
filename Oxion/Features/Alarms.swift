import SwiftUI
import AlarmKit
import UserNotifications
import AppIntents

// MARK: - Будильники OXION (AlarmKit, iOS 26)
// Конец отдыха звенит как настоящий будильник — даже в беззвучном режиме и в фокусировании.
// Плюс еженедельный будильник «Пора на тренировку».

@MainActor
enum OxAlarms {
    private static let d = UserDefaults.standard
    static var restEnabled: Bool {
        get { d.bool(forKey: "alarm_rest") }
        set { d.set(newValue, forKey: "alarm_rest") }
    }
    private static var restId: UUID? {
        get { d.string(forKey: "alarm_rest_id").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "alarm_rest_id") }
    }
    static var reminderIds: [UUID] {
        get { (d.stringArray(forKey: "alarm_remind_ids") ?? []).compactMap(UUID.init(uuidString:)) }
        set { d.set(newValue.map(\.uuidString), forKey: "alarm_remind_ids") }
    }

    static var authorized: Bool { AlarmManager.shared.authorizationState == .authorized }

    static func authorize() async -> Bool {
        if authorized { return true }
        let st = try? await AlarmManager.shared.requestAuthorization()
        return st == .authorized
    }

    /// Подписка на события тренировки (вызывается при запуске)
    static func attach() {
        WorkoutEngine.onEvent = { e, s in
            OxAlarms.handle(e, s)
            WorkoutMusic.shared.handle(e)
            ScreenLock.shared.handle(e)
            if e == .finished { GameHub.shared.workoutFinished(s) }
        }
    }

    private static func handle(_ e: WorkoutEngine.Event, _ s: WorkoutState) {
        switch e {
        case .setDone, .resumed:
            if s.phase == .resting, let end = s.restEndsAt {
                let sec = Int(end.timeIntervalSinceNow.rounded())
                Task { await scheduleRest(seconds: sec, next: s.currentItem?.name ?? "") }
            }
        case .restSkipped, .paused, .finished, .started:
            cancelRest()
        }
    }

    // MARK: конец отдыха

    static func scheduleRest(seconds: Int, next: String) async {
        cancelRest()
        guard restEnabled, seconds >= 5, await authorize() else { return }
        let alert = AlarmPresentation.Alert(
            title: "Отдых окончен",
            stopButton: AlarmButton(text: "Готов", textColor: .black, systemImageName: "figure.strengthtraining.traditional"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil)
        let countdown = AlarmPresentation.Countdown(
            title: "Отдых",
            pauseButton: AlarmButton(text: "Пауза", textColor: .white, systemImageName: "pause.fill"))
        let paused = AlarmPresentation.Paused(
            title: "Отдых на паузе",
            resumeButton: AlarmButton(text: "Дальше", textColor: .white, systemImageName: "play.fill"))
        let attrs = AlarmAttributes<OxAlarmMeta>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: OxAlarmMeta(kind: "rest", next: next),
            tintColor: .lime)
        let id = UUID()
        let cfg = AlarmManager.AlarmConfiguration<OxAlarmMeta>.timer(
            duration: TimeInterval(seconds), attributes: attrs,
            stopIntent: nil, secondaryIntent: nil, sound: .default)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)
            restId = id
            // обычное уведомление «отдых окончен» больше не нужно — звенит будильник
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["oxion-rest-end"])
        } catch {
            restId = nil
        }
    }

    static func cancelRest() {
        guard let id = restId else { return }
        try? AlarmManager.shared.cancel(id: id)
        restId = nil
    }

    // MARK: напоминание о тренировке по дням недели

    static func setReminder(hour: Int, minute: Int, days: Set<Locale.Weekday>) async -> Bool {
        clearReminders()
        guard !days.isEmpty, await authorize() else { return false }
        let alert = AlarmPresentation.Alert(
            title: "Пора на тренировку",
            stopButton: AlarmButton(text: "Иду", textColor: .black, systemImageName: "checkmark"),
            secondaryButton: AlarmButton(text: "OXION", textColor: .white, systemImageName: "arrow.up.forward.app"),
            secondaryButtonBehavior: .custom)
        let attrs = AlarmAttributes<OxAlarmMeta>(
            presentation: AlarmPresentation(alert: alert),
            metadata: OxAlarmMeta(kind: "remind"),
            tintColor: .lime)
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: hour, minute: minute),
            repeats: .weekly(Array(days))))
        let id = UUID()
        let cfg = AlarmManager.AlarmConfiguration<OxAlarmMeta>.alarm(
            schedule: schedule, attributes: attrs,
            stopIntent: nil, secondaryIntent: OpenDiaryFromAlarmIntent(), sound: .default)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: cfg)
            reminderIds = [id]
            return true
        } catch {
            return false
        }
    }

    static func clearReminders() {
        for id in reminderIds { try? AlarmManager.shared.cancel(id: id) }
        reminderIds = []
    }
}

// MARK: - Экран настроек будильников

struct AlarmSettingsView: View {
    @State private var rest = OxAlarms.restEnabled
    @State private var remind = !OxAlarms.reminderIds.isEmpty
    @State private var time = Calendar.current.date(from: DateComponents(
        hour: UserDefaults.standard.object(forKey: "alarm_remind_h") as? Int ?? 19,
        minute: UserDefaults.standard.object(forKey: "alarm_remind_m") as? Int ?? 0)) ?? Date()
    @State private var days: Set<Locale.Weekday> = Set((UserDefaults.standard.stringArray(forKey: "alarm_remind_days") ?? ["monday", "wednesday", "friday"])
        .compactMap { Locale.Weekday(rawValue: $0) })

    private let week: [(Locale.Weekday, String)] = [(.monday, "Пн"), (.tuesday, "Вт"), (.wednesday, "Ср"), (.thursday, "Чт"), (.friday, "Пт"), (.saturday, "Сб"), (.sunday, "Вс")]

    var body: some View {
        List {
            Section {
                Toggle("Будильник конца отдыха", isOn: $rest).tint(Color.lime)
                    .onChange(of: rest) {
                        Task {
                            if rest, !(await OxAlarms.authorize()) {
                                rest = false
                                OxAlert.show(icon: "alarm.fill", tint: Color(hex: 0xF0A030), title: "Нет доступа к будильникам",
                                             message: "Разрешите: Настройки → Oxion → Будильники и таймеры.")
                                return
                            }
                            OxAlarms.restEnabled = rest
                        }
                    }
            } footer: {
                Text("Отдых между подходами заканчивается настоящим будильником — он звенит даже в беззвучном режиме и при включённом фокусировании, с отсчётом на экране блокировки и в Dynamic Island.")
            }

            Section {
                Toggle("Будильник «Пора на тренировку»", isOn: $remind).tint(Color.lime)
                if remind {
                    DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                    HStack(spacing: 6) {
                        ForEach(week, id: \.1) { d, t in
                            Button {
                                if days.contains(d) { days.remove(d) } else { days.insert(d) }
                            } label: {
                                Text(t).font(.caption.bold())
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(days.contains(d) ? Color.black : Color.primary)
                                    .background(days.contains(d) ? Color.lime : Color.primary.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Сохранить будильник") { Task { await saveReminder() } }
                }
            } footer: {
                Text("Звенит в выбранные дни. Кнопка «OXION» на будильнике сразу открывает дневник.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.oxBg)
        .navigationTitle("Будильники")
        .onChange(of: remind) { if !remind { OxAlarms.clearReminders() } }
    }

    private func saveReminder() async {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let h = c.hour ?? 19, m = c.minute ?? 0
        UserDefaults.standard.set(h, forKey: "alarm_remind_h")
        UserDefaults.standard.set(m, forKey: "alarm_remind_m")
        UserDefaults.standard.set(days.map(\.rawValue), forKey: "alarm_remind_days")
        if await OxAlarms.setReminder(hour: h, minute: m, days: days) {
            OxHaptics.play(.setDone)
            OxAlert.show(icon: "alarm.fill", title: "Будильник сохранён", message: String(format: "%02d:%02d", h, m) + " · " + week.filter { days.contains($0.0) }.map(\.1).joined(separator: ", "))
        } else {
            OxAlert.show(icon: "alarm.fill", tint: Color(hex: 0xF0A030), title: "Не удалось поставить будильник",
                         message: "Выберите дни и разрешите будильники: Настройки → Oxion.")
        }
    }
}

/// Кнопка «OXION» на будильнике: открыть дневник
struct OpenDiaryFromAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Открыть дневник OXION"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("diary")
        return .result()
    }
}
