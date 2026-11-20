import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false
    @State private var notifText = ""
    @State private var editing = false
    @State private var web: WebTarget?
    @State private var deleteInfo = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
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
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        Button {
                            editing = true
                        } label: {
                            Label("Изменить профиль", systemImage: "pencil")
                        }
                    }

                    Section("Аккаунт") {
                        LabeledContent("Город", value: me.city ?? "не указан")
                        LabeledContent("Цель в неделю", value: "\(me.weekGoal ?? 3) \(RU.plural(me.weekGoal ?? 3, "тренировка", "тренировки", "тренировок"))")
                    }
                }

                Section {
                    Button { web = WebTarget(path: "") } label: {
                        Label("Полная версия Oxion", systemImage: "square.grid.2x2.fill")
                    }
                    NavigationLink {
                        ShopView()
                    } label: {
                        Label("Магазин спортпита", systemImage: "cart.fill")
                    }
                    Button { web = WebTarget(path: "/#morders") } label: {
                        Label("Мои заказы", systemImage: "shippingbox.fill")
                    }
                    Button { web = WebTarget(path: "/#goals") } label: {
                        Label("Цели", systemImage: "target")
                    }
                    Button { web = WebTarget(path: "/#records") } label: {
                        Label("Рекорды", systemImage: "trophy.fill")
                    }
                    Button { web = WebTarget(path: "/#challenges") } label: {
                        Label("Челленджи", systemImage: "flag.checkered")
                    }
                    Button { web = WebTarget(path: "/#mycoach") } label: {
                        Label("Мой тренер", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    if model.me?.mode == "trainer" || model.me?.hasTrainer == true {
                        Button { web = WebTarget(path: "/#myprofile") } label: {
                            Label("Моя анкета тренера", systemImage: "person.text.rectangle.fill")
                        }
                        Button { web = WebTarget(path: "/#cclients") } label: {
                            Label("Мои клиенты", systemImage: "person.2.fill")
                        }
                    }
                    Button { web = WebTarget(path: "/#work") } label: {
                        Label("Работа в Oxion", systemImage: "briefcase.fill")
                    }
                    if model.me?.admin == true {
                        Button { web = WebTarget(path: "/#phome") } label: {
                            Label("Панель платформы", systemImage: "shield.lefthalf.filled")
                        }
                    }
                } header: {
                    Text("Ещё в Oxion")
                } footer: {
                    Text("Эти разделы пока открываются в веб-версии внутри приложения. Вход сохраняется автоматически.")
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
                    if let url = supportURL {
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
                    Button(role: .destructive) {
                        deleteInfo = true
                    } label: {
                        Label("Удалить аккаунт", systemImage: "person.crop.circle.badge.xmark")
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
            .alert("Удаление аккаунта", isPresented: $deleteInfo) {
                if let url = supportURL {
                    Button("Написать в поддержку") { openURL(url) }
                }
                Button("Закрыть", role: .cancel) {}
            } message: {
                Text("Напишите в поддержку — аккаунт и все данные удалят. Скоро это можно будет сделать прямо здесь одной кнопкой.")
            }
            .sheet(isPresented: $editing) {
                EditProfileSheet()
            }
            .fullScreenCover(item: $web) { t in
                WebAppView(path: t.path)
            }
            .task { await refreshNotifText() }
    }

    private var supportURL: URL? {
        guard let s = model.meta?.supportTg, !s.isEmpty else { return nil }
        return URL(string: "https://t.me/\(s.replacingOccurrences(of: "@", with: ""))")
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

struct WebTarget: Identifiable {
    let id = UUID()
    let path: String
}

struct EditProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var weekGoal = 3
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    TextField("Как вас зовут", text: $name)
                }
                Section("Город") {
                    if let cities = model.meta?.cities, !cities.isEmpty {
                        Picker("Город", selection: $city) {
                            ForEach(cities, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.navigationLink)
                    } else {
                        Text(city.isEmpty ? "не указан" : city)
                    }
                }
                Section("Цель") {
                    Stepper("\(weekGoal) \(RU.plural(weekGoal, "тренировка", "тренировки", "тренировок")) в неделю",
                            value: $weekGoal, in: 1...7)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .onAppear {
                name = model.me?.displayName ?? ""
                city = model.me?.city ?? ""
                weekGoal = model.me?.weekGoal ?? 3
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = ["week_goal": weekGoal]
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty && n != model.me?.displayName { body["name"] = n }
        if !city.isEmpty && city != model.me?.city { body["city"] = city }
        do {
            let _: OK = try await API.call("/me", method: "PATCH", body: body)
            await model.loadMe()
            Haptic.success()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
