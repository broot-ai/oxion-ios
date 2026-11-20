import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false
    @State private var notifText = ""

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    Section {
                        HStack(spacing: 16) {
                            Avatar(url: API.media(me.photoUrl), name: me.displayName, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(me.displayName)
                                    .font(.title2.bold())
                                if let u = me.username, !u.isEmpty {
                                    Text("@\(u)")
                                        .foregroundStyle(.secondary)
                                }
                                Text(me.mode == "trainer" ? "Тренер" : "Клиент")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular.tint(Color.lime.opacity(0.3)), in: .capsule)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Аккаунт") {
                        LabeledContent("Город", value: me.city ?? "не указан")
                        LabeledContent("Цель в неделю", value: "\(me.weekGoal ?? 3) \(RU.plural(me.weekGoal ?? 3, "тренировка", "тренировки", "тренировок"))")
                    }
                }

                Section {
                    Button {
                        Task { await askNotifications() }
                    } label: {
                        Label("Уведомления", systemImage: "bell.badge.fill")
                    }
                    if !notifText.isEmpty {
                        Text(notifText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("Настройки Oxion в iPhone", systemImage: "gearshape.fill")
                    }
                } header: {
                    Text("Настройки")
                } footer: {
                    Text("Тактильный отклик, ленту при запуске и автозагрузку фото можно поменять в «Настройки» → Oxion.")
                }

                Section("Поддержка") {
                    if let s = model.meta?.supportTg, !s.isEmpty,
                       let url = URL(string: "https://t.me/\(s.replacingOccurrences(of: "@", with: ""))") {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Написать в поддержку", systemImage: "paperplane.fill")
                        }
                    }
                    Button {
                        openURL(API.page("legal/privacy"))
                    } label: {
                        Label("Политика конфиденциальности", systemImage: "hand.raised.fill")
                    }
                    Button {
                        openURL(API.page("legal/terms"))
                    } label: {
                        Label("Пользовательское соглашение", systemImage: "doc.text.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Oxion \(AppSettings.version)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Профиль")
            .refreshable { await model.loadMe() }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    Task { await model.logout() }
                }
            }
            .task { await refreshNotifText() }
        }
    }

    private func askNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotifText()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func refreshNotifText() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notifText = "Разрешены. Пуши с сервера заработают после подключения аккаунта разработчика Apple."
        case .denied:
            notifText = "Запрещены. Нажмите, чтобы открыть настройки и разрешить."
        default:
            notifText = ""
        }
    }
}
