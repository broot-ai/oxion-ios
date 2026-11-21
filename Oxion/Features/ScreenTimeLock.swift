import SwiftUI
import FamilyControls
import ManagedSettings

/// «Не отвлекаться»: на время тренировки выбранные приложения закрываются экраном Экранного времени.
/// Нужно разрешение Apple на Family Controls (запрашивается отдельно у Apple для платного аккаунта).
@MainActor
@Observable
final class ScreenLock {
    static let shared = ScreenLock()

    private let store = ManagedSettingsStore(named: .init("oxion.workout"))
    private let key = "oxion_screenlock_selection"

    var selection = FamilyActivitySelection() { didSet { save() } }
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "oxion_screenlock_on") }
        set { UserDefaults.standard.set(newValue, forKey: "oxion_screenlock_on") }
    }
    var authorized: Bool { AuthorizationCenter.shared.authorizationStatus == .approved }
    var errorText: String?
    var active = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(FamilyActivitySelection.self, from: d) {
            selection = s
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(selection) { UserDefaults.standard.set(d, forKey: key) }
    }

    var count: Int { selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count }

    func authorize() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorText = nil
        } catch {
            errorText = "Экранное время недоступно: \(error.localizedDescription). Нужна сборка с разрешением Apple на Family Controls."
        }
        return authorized
    }

    func lock() {
        guard authorized, count > 0 else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        active = true
    }

    func unlock() {
        store.clearAllSettings()
        active = false
    }

    func handle(_ e: WorkoutEngine.Event) {
        guard enabled else { return }
        switch e {
        case .started, .resumed: lock()
        case .finished: unlock()
        default: break
        }
    }
}

struct ScreenTimeLockView: View {
    @State private var lock = ScreenLock.shared
    @State private var picker = false

    var body: some View {
        List {
            Section {
                Toggle("Блокировать на время тренировки", isOn: Binding(get: { lock.enabled }, set: { v in
                    if v {
                        Task { if await lock.authorize() { lock.enabled = true } }
                    } else {
                        lock.enabled = false
                        lock.unlock()
                    }
                }))
                Button {
                    Task { if await lock.authorize() { picker = true } }
                } label: {
                    LabeledContent("Что блокировать", value: lock.count == 0 ? "не выбрано" : "\(lock.count)")
                }
                .tint(.primary)
            } footer: {
                Text("Во время тренировки выбранные приложения закрыты экраном «Время тренировки». После финиша всё открывается само.")
            }
            if lock.active {
                Section {
                    Button("Снять блокировку сейчас", role: .destructive) { lock.unlock() }
                }
            }
            if let e = lock.errorText {
                Section { Text(e).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .familyActivityPicker(isPresented: $picker, selection: Binding(get: { lock.selection }, set: { lock.selection = $0 }))
        .navigationTitle("Не отвлекаться")
        .navigationBarTitleDisplayMode(.inline)
    }
}
