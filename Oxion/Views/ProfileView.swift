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
    @State private var showCard = false

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
                    nav("OXION OS — экосистема Apple", "sparkles.rectangle.stack.fill", Color.lime) { EcosystemView() }
                    nav("Доступы и разрешения", "checkmark.shield.fill", Color(hex: 0x0A84FF)) { PermissionsView() }
                    nav("Номер телефона", "phone.fill", Color(hex: 0x34A853)) { PhoneSettingsView() }
                }
                Section("Тренировки") {
                    nav("Прогресс тела", "chart.line.uptrend.xyaxis", Color.lime) { ProgressHubView() }
                    nav("Рекорды и достижения", "trophy.fill", Color(hex: 0xF0A030)) { RecordsView() }
                    nav("Челленджи", "flag.checkered", Color(hex: 0x3FD6C9)) { ChallengesView() }
                    nav("Цели", "target", Color(hex: 0xFF5A4E)) { GoalsView() }
                    nav("Мой тренер", "person.crop.circle.badge.checkmark", Color(hex: 0x8E7CFF)) { MyCoachView() }
                    nav("Здоровье", "heart.text.square.fill", Color(hex: 0xFF3B5C)) { HealthView() }
                    nav("ИИ-тренер", "sparkles", Color.lime) { AICoachView() }
                }
                Section("Покупки") {
                    nav("Магазин спортпита", "bag.fill", Color(hex: 0xF0A030)) { ShopView() }
                    nav("Мои заказы", "shippingbox.fill", Color(hex: 0x3FD6C9)) { OrdersView() }
                }
                if model.me?.mode == "trainer" || model.me?.hasTrainer == true {
                    Section("Для тренера") {
                        nav("Моя анкета тренера", "person.text.rectangle.fill", Color.lime) { TrainerEditView() }
                        nav("Мои клиенты", "person.2.fill", Color(hex: 0x58F670)) { ClientsView() }
                        nav("PRO-размещение", "crown.fill", Color(hex: 0xF0A030)) { SubscriptionView() }
                    }
                }
                Section("Ещё") {
                    nav("Мой профиль в ленте", "person.crop.square.fill", Color(hex: 0x8E7CFF)) { UserProfileView(userId: model.me?.id ?? 0) }
                    Button { showCard = true } label: { row("Моя визитка и QR", "qrcode", Color.lime) }
                    nav("Работа в Oxion", "briefcase.fill", Color(hex: 0x3FD6C9)) { WorkView() }
                    if model.me?.admin == true {
                        nav("Панель платформы", "shield.lefthalf.filled", Color(hex: 0xFF5A4E)) { PlatformView() }
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
                        OxAlert.show(icon: "person.crop.circle.badge.xmark", tint: Color(hex: 0xFF5A4E), title: "Удаление аккаунта",
                                     message: "Аккаунт и все данные будут удалены. В тестовой версии удаление делает поддержка.",
                                     buttons: [OxAlertButton(title: "Написать в поддержку", role: .destructive) { if let u = supportURL { openURL(u) } },
                                               OxAlertButton(title: "Отмена", role: .cancel)])
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
            .oxRefreshable { await model.loadMe() }
            .onChange(of: confirmLogout) {
                if confirmLogout {
                    confirmLogout = false
                    OxAlert.confirm(icon: "rectangle.portrait.and.arrow.right", title: "Выйти из аккаунта?", message: "Войти снова можно через Telegram-бота",
                                    action: "Выйти", destructive: true) { Task { await model.logout() } }
                }
            }
            .sheet(isPresented: $editing) {
                EditProfileSheet()
            }
            .sheet(isPresented: $showCard) { MyCardSheet() }
            .task { await refreshNotifText() }
    }

    private func row(_ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).foregroundStyle(.primary)
        }
    }

    private func nav<D: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            row(title, icon, tint)
        }
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
