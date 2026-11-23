import SwiftUI
import UIKit
import UserNotifications

struct ProfileView: View {
    var embedded = false
    @AppStorage("ox.browser.inapp") private var inAppBrowser = true
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false
    @State private var notifText = ""
    @State private var editing = false
    @State private var showCard = false
    @State private var avatarStudio = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                mainList
            } else {
                resultsList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OxBottomSearchBar(text: $query, focused: $searchFocused, prompt: "Поиск: видео, тренер, Face ID…")
        }
            .navigationTitle("Профиль")
            .toolbar(.hidden, for: .tabBar)   // в профиле внизу только строка поиска
            .fullScreenCover(isPresented: $avatarStudio) { AvatarStudio() }
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
            .fullScreenCover(isPresented: $showCard) { MyCardSheet() }
            .task { await refreshNotifText() }
    }

    private var mainList: some View {
            List {
                if let me = model.me {
                    Section {
                        HStack(spacing: 16) {
                            Button { avatarStudio = true } label: {
                                Avatar(url: API.media(me.photoUrl), name: me.displayName, size: 72)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "face.smiling.inverse")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.onLime)
                                            .frame(width: 26, height: 26)
                                            .background(Color.lime, in: Circle())
                                            .overlay(Circle().stroke(Color.oxBg, lineWidth: 2))
                                    }
                            }
                            .buttonStyle(.plain)
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
                    nav("Твой статус", "circle.hexagongrid.fill", Color(hex: 0x3FD6C9)) { StatusView() }
                    nav("План на 4 недели", "calendar.badge.plus", Color.lime) { ProgramBuilderView() }
                    nav("Прогресс тела", "chart.line.uptrend.xyaxis", Color.lime) { ProgressHubView() }
                    nav("Цели", "target", Color(hex: 0xFF5A4E)) { GoalsView() }
                    nav("Рекорды и достижения", "trophy.fill", Color(hex: 0xF0A030)) { RecordsView() }
                    nav("Челленджи", "flag.checkered", Color(hex: 0x3FD6C9)) { ChallengesView() }
                    nav("Рядом", "dot.radiowaves.left.and.right", Color(hex: 0xB2EE37)) { NearbyPeopleView() }
                }
                Section("Тренер и здоровье") {
                    nav("Мой тренер", "person.crop.circle.badge.checkmark", Color(hex: 0x8E7CFF)) { MyCoachView() }
                    nav("ИИ-тренер", "sparkles", Color.lime) { AICoachView() }
                    nav("Здоровье", "heart.text.square.fill", Color(hex: 0xFF3B5C)) { HealthView() }
                }
                Section("Инструменты") {
                    nav("Пробежка с GPS", "figure.run", Color(hex: 0x58F670)) { RunTrackerView() }
                    Button { model.showMap = true } label: {
                        HStack(spacing: 14) {
                            OxRowIcon(icon: "map.fill", tint: Color(hex: 0x3FD6C9))
                            Text("Карта").foregroundStyle(.primary)
                        }
                    }
                    nav("Сканер еды", "text.viewfinder", Color(hex: 0x3FD6C9)) { LabelScannerView() }
                    nav("Дневник питания", "fork.knife", Color(hex: 0x58C770)) { FoodDiaryView() }
                    nav("Будильники", "alarm.fill", Color(hex: 0xF0A030)) { AlarmSettingsView() }
                    nav("Умные устройства", "dot.radiowaves.left.and.right", Color(hex: 0x3478F6)) { DevicePanelView() }
                }
                Section("Музыка и фокус") {
                    nav("Музыка для тренировки", "music.note", Color(hex: 0xFF3B5C)) { WorkoutMusicView() }
                    nav("Не отвлекаться", "hourglass", Color(hex: 0x8E7CFF)) { ScreenTimeLockView() }
                    nav("Game Center", "gamecontroller.fill", Color(hex: 0x0A84FF)) { GameCenterView() }
                }
                Section("Покупки") {
                    nav("Магазин спортпита", "bag.fill", Color(hex: 0xF0A030)) { ShopView() }
                    nav("Мои заказы", "shippingbox.fill", Color(hex: 0x3FD6C9)) { OrdersView() }
                }
                if model.me?.mode == "trainer" || model.me?.hasTrainer == true {
                    Section("Для тренера") {
                        nav("Моя анкета тренера", "person.text.rectangle.fill", Color.lime) { TrainerEditView() }
                        nav("Мои клиенты", "person.2.fill", Color(hex: 0x58F670)) { ClientsView() }
                        nav("Расписание и запись", "calendar", Color(hex: 0x3FD6C9)) { TrainerScheduleView() }
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
                    nav("Уведомления", "bell.badge.fill", Color(hex: 0xFF5A4E)) { NotificationSettingsView() }
                    nav("Оформление", "paintbrush.fill", Color(hex: 0x8E7CFF)) { AppearanceSettingsView() }
                    nav("Энергосбережение", "battery.50percent", Color(hex: 0xF0A030)) { EnergySettingsView() }
                    nav("Данные и память", "internaldrive.fill", Color(hex: 0x3478F6)) { DataStorageView() }
                    nav("Конфиденциальность и безопасность", "hand.raised.fill", Color(hex: 0x3B8CF5)) { SafetyView() }
                    Toggle(isOn: $inAppBrowser) {
                        HStack(spacing: 14) {
                            OxRowIcon(icon: "safari.fill", tint: Color(hex: 0x3478F6))
                            Text("Открывать ссылки в Oxion")
                        }
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
                    NavigationLink { LegalDocView(doc: .privacy) } label: {
                        Label("Политика конфиденциальности", systemImage: "hand.raised.fill")
                    }
                    NavigationLink { LegalDocView(doc: .terms) } label: {
                        Label("Пользовательское соглашение", systemImage: "doc.text.fill")
                    }
                }

                Section {
                    NavigationLink { LoginKeysView() } label: {
                        Label("Ключи входа · \(Biometry.name)", systemImage: Biometry.icon)
                    }
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        OxAlert.confirm(icon: "person.crop.circle.badge.xmark", title: "Удалить аккаунт?",
                                        message: "Дневник, вес, фото прогресса, анкета тренера и записи будут удалены с сервера. Это нельзя отменить.",
                                        action: "Удалить навсегда", destructive: true) {
                            Task {
                                do {
                                    let _: OK = try await API.call("/me", method: "DELETE")
                                    DeviceLoginKey.remove()
                                    model.logoutLocal()
                                    OxAlert.show(icon: "checkmark.circle.fill", title: "Аккаунт удалён")
                                } catch { OxAlert.error(error.localizedDescription) }
                            }
                        }
                    } label: {
                        Label("Удалить аккаунт", systemImage: "person.crop.circle.badge.xmark")
                    }
                } footer: {
                    Text("Oxion \(AppSettings.version)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
    }

    // MARK: - Поиск по разделам

    private var resultsList: some View {
        let found = OxSearch.search(query, in: searchItems)
        return List {
            if found.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Ничего не нашлось по «\(query)»").font(.headline)
                        Text("Попробуйте другое слово: «видео», «тренер», «вес», «пульс», «тема»…")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Найдено: \(found.count)") {
                    ForEach(found) { it in
                        switch it.kind {
                        case .push(let dest):
                            NavigationLink { dest() } label: { OxSearchRow(item: it) }
                        case .run(let act):
                            Button {
                                searchFocused = false
                                act()
                            } label: { OxSearchRow(item: it) }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchItems: [OxSearchItem] {
        let P = "Профиль", T = "Профиль → Тренировки", H = "Профиль → Тренер и здоровье", I = "Профиль → Инструменты",
            M = "Профиль → Музыка и фокус", B = "Профиль → Покупки", S = "Профиль → Настройки", E = "Профиль → Ещё",
            A = "Приложение", K = "Профиль → Поддержка"
        var list: [OxSearchItem] = []
        list.reserveCapacity(64)
            list.append(OxSearchItem("Изменить профиль", P, "pencil", Color.lime, ["имя", "город", "о себе", "био", "описание", "редактировать", "цель в неделю"], run: { editing = true }))
            list.append(OxSearchItem("Аватар и Memoji", P, "face.smiling.inverse", Color.lime, ["memoji", "мимоджи", "аватарка", "фото профиля", "эмодзи", "картинка", "ава"], run: { avatarStudio = true }))
            list.append(OxSearchItem("OXION OS — экосистема Apple", P, "sparkles.rectangle.stack.fill", Color.lime, ["siri", "сири", "виджеты", "часы", "watch", "live activity", "динамический остров", "команды", "shortcuts", "быстрые команды", "apple"], push: { EcosystemView() }))
            list.append(OxSearchItem("Доступы и разрешения", P, "checkmark.shield.fill", Color(hex: 0x0A84FF), ["камера", "микрофон", "геолокация", "фото", "контакты", "bluetooth", "здоровье", "разрешения", "доступ", "приватность"], push: { PermissionsView() }))
            list.append(OxSearchItem("Номер телефона", P, "phone.fill", Color(hex: 0x34A853), ["телефон", "смс", "sms", "номер", "мобильный"], push: { PhoneSettingsView() }))
            list.append(OxSearchItem("Прогресс тела", T, "chart.line.uptrend.xyaxis", Color.lime, ["вес", "замеры", "фото прогресса", "график", "тело", "объемы", "талия", "похудение", "масса"], push: { ProgressHubView() }))
            list.append(OxSearchItem("Фото до и после", T, "photo.on.rectangle.angled", Color.lime, ["до после", "сравнение", "фото", "трансформация"], push: { BeforeAfterView() }))
            list.append(OxSearchItem("Цели", T, "target", Color(hex: 0xFF5A4E), ["цель", "задачи", "план", "мотивация"], push: { GoalsView() }))
            list.append(OxSearchItem("Рекорды и достижения", T, "trophy.fill", Color(hex: 0xF0A030), ["рекорд", "достижения", "награды", "медали", "ачивки", "пр", "максимум"], push: { RecordsView() }))
            list.append(OxSearchItem("Челленджи", T, "flag.checkered", Color(hex: 0x3FD6C9), ["соревнования", "вызов", "марафон", "челлендж"], push: { ChallengesView() }))
            list.append(OxSearchItem("Рядом", T, "dot.radiowaves.left.and.right", Color(hex: 0xB2EE37), ["uwb", "поблизости", "друзья рядом", "nearby", "найти людей", "кто рядом", "радар"], push: { NearbyPeopleView() }))
            list.append(OxSearchItem("Мой тренер", H, "person.crop.circle.badge.checkmark", Color(hex: 0x8E7CFF), ["тренер", "запись", "записаться", "расписание", "занятие", "персональный", "коуч"], push: { MyCoachView() }))
            list.append(OxSearchItem("ИИ-тренер", H, "sparkles", Color(hex: 0x58F670), ["ai", "ии", "нейросеть", "чат бот", "gpt", "план тренировок", "совет", "помощник", "искусственный интеллект"], push: { AICoachView() }))
            list.append(OxSearchItem("Здоровье", H, "heart.text.square.fill", Color(hex: 0xFF3B5C), ["health", "пульс", "шаги", "сон", "калории", "apple health", "давление", "сердце"], push: { HealthView() }))
            list.append(OxSearchItem("Твой статус", I, "circle.hexagongrid.fill", Color(hex: 0x3FD6C9), ["статус", "здоровье", "сон", "оценка", "восстановление", "health"], push: { StatusView() }))
            list.append(OxSearchItem("План на 4 недели", I, "calendar.badge.plus", Color.lime, ["план", "программа", "4 недели", "gym strength", "ии", "тренировки на месяц"], push: { ProgramBuilderView() }))
            list.append(OxSearchItem("Что нового", I, "sparkles.rectangle.stack", Color.lime, ["новое", "обновление", "что нового"], run: { model.sheet = .whatsNew }))
            list.append(OxSearchItem("Карта", I, "map.fill", Color(hex: 0x3FD6C9), ["карта", "залы", "спортзал", "фитнес", "стадион", "бассейн", "спортпит", "магазин", "рядом", "map"], run: { model.showMap = true }))
            list.append(OxSearchItem("Пробежка с GPS", I, "figure.run", Color(hex: 0x58F670), ["бег", "gps", "карта", "маршрут", "run", "кардио", "пробежка", "километры"], push: { RunTrackerView() }))
            list.append(OxSearchItem("Дневник питания", I, "fork.knife", Color(hex: 0x58C770), ["питание", "калории", "еда", "кбжу", "рацион"], push: { FoodDiaryView() }))
        list.append(OxSearchItem("Сканер еды", I, "text.viewfinder", Color(hex: 0x3FD6C9), ["калории", "бжу", "еда", "питание", "состав", "сканер", "продукты", "белок"], push: { LabelScannerView() }))
            list.append(OxSearchItem("Будильники", I, "alarm.fill", Color(hex: 0xF0A030), ["будильник", "напоминания", "alarm", "утро", "подъем"], push: { AlarmSettingsView() }))
            list.append(OxSearchItem("Умные устройства", I, "dot.radiowaves.left.and.right", Color(hex: 0x3478F6), ["bluetooth", "блютуз", "пульсометр", "датчик", "часы", "наушники", "гаджеты", "колонка"], push: { DevicePanelView() }))
            list.append(OxSearchItem("Отметка в зале по NFC", I, "wave.3.right", Color(hex: 0x3FD6C9), ["nfc", "зал", "отметка", "чекин", "check in", "посещение", "метка"], push: { NFCCheckInView() }))
            list.append(OxSearchItem("Тренировка вместе (SharePlay)", I, "shareplay", Color(hex: 0x34C759), ["facetime", "вместе", "совместная тренировка", "видеозвонок", "shareplay", "с другом"], push: { SharePlayView() }))
            list.append(OxSearchItem("Музыка для тренировки", M, "music.note", Color(hex: 0xFF3B5C), ["музыка", "плейлист", "треки", "песни", "apple music", "звук"], push: { WorkoutMusicView() }))
            list.append(OxSearchItem("Не отвлекаться", M, "hourglass", Color(hex: 0x8E7CFF), ["screen time", "экранное время", "фокус", "блокировка приложений", "соцсети", "отвлекаться"], push: { ScreenTimeLockView() }))
            list.append(OxSearchItem("Game Center", M, "gamecontroller.fill", Color(hex: 0x0A84FF), ["игры", "рейтинг", "лидеры", "таблица лидеров", "ачивки"], push: { GameCenterView() }))
            list.append(OxSearchItem("Магазин спортпита", B, "bag.fill", Color(hex: 0xF0A030), ["протеин", "спортпит", "покупки", "магазин", "добавки", "креатин", "витамины", "купить"], push: { ShopView() }))
            list.append(OxSearchItem("Мои заказы", B, "shippingbox.fill", Color(hex: 0x3FD6C9), ["доставка", "заказ", "покупки", "посылка"], push: { OrdersView() }))
            list.append(OxSearchItem("Мой профиль в ленте", E, "person.crop.square.fill", Color(hex: 0x8E7CFF), ["посты", "публикации", "лента", "мои фото", "подписчики"], push: { UserProfileView(userId: model.me?.id ?? 0) }))
            list.append(OxSearchItem("Моя визитка и QR", E, "qrcode", Color.lime, ["qr", "куар", "визитка", "код", "поделиться профилем", "ссылка на профиль"], run: { showCard = true }))
            list.append(OxSearchItem("Пригласить друзей", E, "person.badge.plus", Color.lime, ["контакты", "друзья", "пригласить", "приглашение", "реферал"], push: { ContactsInviteView() }))
            list.append(OxSearchItem("Работа в Oxion", E, "briefcase.fill", Color(hex: 0x3FD6C9), ["вакансии", "работа", "карьера", "стать тренером"], push: { WorkView() }))
            list.append(OxSearchItem("Конфиденциальность и безопасность", S, "hand.raised.fill", Color(hex: 0x3B8CF5), ["откровенные", "деликатный", "камера", "геопозиция", "приватность", "безопасность"], push: { SafetyView() }))
        list.append(OxSearchItem("Уведомления", S, "bell.badge.fill", Color(hex: 0xFF5A4E), ["push", "пуши", "оповещения", "уведомления"], push: { NotificationSettingsView() }))
            list.append(OxSearchItem("Умные уведомления", S, "bell.and.waves.left.and.right", Color(hex: 0xFF5A4E), ["напоминания", "умные", "уведомления"], push: { SmartNotifySettingsView() }))
            list.append(OxSearchItem("Оформление", S, "paintbrush.fill", Color(hex: 0x8E7CFF), ["тема", "темная", "светлая", "иконка приложения", "шрифт", "размер текста", "пузыри", "цвет"], push: { AppearanceSettingsView() }))
            list.append(OxSearchItem("Обои чата", S, "photo.artframe", Color(hex: 0x8E7CFF), ["обои", "фон чата", "wallpaper", "узор"], push: { ChatWallpaperSettingsView() }))
            list.append(OxSearchItem("Анимации", S, "wand.and.stars", Color(hex: 0x8E7CFF), ["анимации", "эффекты", "плавность", "конфетти"], push: { AnimationSettingsView() }))
            list.append(OxSearchItem("Вибрация", S, "iphone.radiowaves.left.and.right", Color(hex: 0x8E7CFF), ["вибрация", "тактильный отклик", "haptic", "вибро"], push: { HapticsSettingsView() }))
            list.append(OxSearchItem("Энергосбережение", S, "battery.50percent", Color(hex: 0xF0A030), ["батарея", "аккумулятор", "энергия", "заряд", "экономия"], push: { EnergySettingsView() }))
            list.append(OxSearchItem("Данные и память", S, "internaldrive.fill", Color(hex: 0x3478F6), ["кэш", "память", "трафик", "автозагрузка", "хранилище", "очистить", "мобильный интернет"], push: { DataStorageView() }))
            list.append(OxSearchItem("Команды Siri", S, "mic.fill", Color(hex: 0x8E7CFF), ["siri", "сири", "голос", "голосовые команды", "фразы"], push: { SiriHelpView() }))
            list.append(OxSearchItem("Настройки Oxion в iPhone", S, "gearshape.fill", Color(hex: 0x8E8E93), ["звуки", "звук", "вибрация", "настройки", "лента при запуске", "системные"], run: { openSettings() }))
            list.append(OxSearchItem("Политика конфиденциальности", K, "hand.raised.fill", Color(hex: 0x0A84FF), ["конфиденциальность", "данные", "privacy", "персональные данные"], push: { LegalDocView(doc: .privacy) }))
            list.append(OxSearchItem("Пользовательское соглашение", K, "doc.text.fill", Color(hex: 0x0A84FF), ["правила", "условия", "terms", "соглашение", "оферта"], push: { LegalDocView(doc: .terms) }))
            list.append(OxSearchItem("Ключи входа · \(Biometry.name)", P, Biometry.icon, Color(hex: 0x34C759), ["face id", "фейс айди", "touch id", "отпечаток", "passkey", "пасскей", "пароль", "вход", "безопасность", "ключ"], push: { LoginKeysView() }))
            list.append(OxSearchItem("Выйти", P, "rectangle.portrait.and.arrow.right", Color(hex: 0xFF5A4E), ["выход", "logout", "сменить аккаунт"], run: { confirmLogout = true }))
            // разделы вне профиля
            list.append(OxSearchItem("Каталог упражнений с видео", "Упражнения", "play.rectangle.on.rectangle.fill", Color.lime, ["видео", "видос", "ролики", "техника", "workoutdb", "анимация", "гиф", "как делать"], push: { WorkoutDBCatalogView() }))
            list.append(OxSearchItem("Упражнения", A, "dumbbell.fill", Color.lime, ["справочник", "упражнения", "техника", "мои упражнения"], push: { ExercisesView() }))
            list.append(OxSearchItem("OXION BODY 3D", A, "figure.stand", Color.lime, ["3d", "мышцы", "анатомия", "ar", "дополненная реальность", "тело", "фигура", "что качать", "body tracking", "движение"], run: { model.showMuscles = true }))
            list.append(OxSearchItem("Тренер-камера (считает повторы)", A, "camera.viewfinder", Color(hex: 0x58F670), ["камера", "видео", "повторы", "распознавание", "vision", "техника", "компьютерное зрение"], run: { model.handle(route: "vision") }))
            list.append(OxSearchItem("Дневник тренировок", A, "book.closed.fill", Color.lime, ["дневник", "тренировки", "история", "журнал", "календарь", "подходы"], run: { model.handle(route: "diary") }))
            list.append(OxSearchItem("Чаты", A, "bubble.left.and.right.fill", Color(hex: 0x0A84FF), ["сообщения", "переписка", "голосовые", "кружки", "видеосообщения", "видео сообщения", "написать"], run: { model.handle(route: "chats") }))
            list.append(OxSearchItem("Лента", A, "square.stack.fill", Color(hex: 0xFF3B5C), ["посты", "публикации", "видео", "рилсы", "новости", "фото"], run: { model.handle(route: "feed") }))
            list.append(OxSearchItem("Найти тренера", A, "person.2.fill", Color(hex: 0x8E7CFF), ["тренеры", "каталог тренеров", "найти тренера", "персональный тренер"], run: { model.handle(route: "trainers") }))
            list.append(OxSearchItem("Избранные тренеры", A, "heart.fill", Color(hex: 0xFF3B5C), ["избранное", "сохраненные", "лайк"], run: { model.handle(route: "favorites") }))
            list.append(OxSearchItem("Активность", A, "bell.fill", Color(hex: 0xF0A030), ["лайки", "комментарии", "подписчики", "активность", "реакции"], push: { ActivityView() }))
        if let url = supportURL {
            list.append(OxSearchItem("Написать в поддержку", K, "paperplane.fill", Color(hex: 0x0A84FF), ["поддержка", "помощь", "вопрос", "проблема", "ошибка", "баг", "support"], run: { openURL(url) }))
        }
        if model.me?.mode == "trainer" || model.me?.hasTrainer == true {
            let R = "Профиль → Для тренера"
                list.append(OxSearchItem("Моя анкета тренера", R, "person.text.rectangle.fill", Color.lime, ["анкета", "резюме", "услуги", "цены", "стоимость"], push: { TrainerEditView() }))
                list.append(OxSearchItem("Мои клиенты", R, "person.2.fill", Color(hex: 0x58F670), ["клиенты", "ученики", "подопечные"], push: { ClientsView() }))
                list.append(OxSearchItem("Расписание и запись", R, "calendar", Color(hex: 0x3FD6C9), ["расписание", "окна", "слоты", "запись", "календарь"], push: { TrainerScheduleView() }))
                list.append(OxSearchItem("PRO-размещение", R, "crown.fill", Color(hex: 0xF0A030), ["pro", "про", "подписка", "оплата", "продвижение", "семейный доступ"], push: { SubscriptionView() }))
        }
        if model.me?.admin == true {
            list.append(OxSearchItem("Панель платформы", E, "shield.lefthalf.filled", Color(hex: 0xFF5A4E), ["админ", "admin", "модерация", "платформа"], push: { PlatformView() }))
        }
        return list
    }

    private func row(_ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            OxRowIcon(icon: icon, tint: tint)
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

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
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
