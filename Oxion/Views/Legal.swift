import SwiftUI

// Политика конфиденциальности и Пользовательское соглашение прямо в приложении, в стиле iOS.
// ⚠️ Реквизиты оператора в квадратных скобках нужно заполнить перед публикацией.

enum LegalDoc: String, Identifiable, CaseIterable {
    case privacy, terms
    var id: String { rawValue }
    var title: String { self == .privacy ? "Политика конфиденциальности" : "Пользовательское соглашение" }
    var icon: String { self == .privacy ? "hand.raised.fill" : "doc.text.fill" }
    static let edition = "Редакция от 21 ноября 2026 г."
}

struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let body: [String]
}

enum LegalText {
    static let operatorLine = "[ФИО или название ИП/ООО], ИНН [номер], адрес для обращений: [e-mail]"

    static let privacySummary: [(String, String, String)] = [
        ("person.text.rectangle", "Минимум данных", "Имя, аватар и идентификатор Telegram или Apple — чтобы вы могли войти"),
        ("heart.text.square", "Здоровье — на iPhone", "Пульс, шаги и данные «Здоровья» обрабатываются на устройстве и не продаются"),
        ("eye.slash", "Без рекламы и продажи данных", "Мы не продаём данные и не показываем рекламу по ним"),
        ("trash", "Удаление в один шаг", "Профиль → Удалить аккаунт — данные стираются с сервера"),
    ]

    static let privacy: [LegalSection] = [
        .init(title: "1. Кто обрабатывает данные", icon: "building.2", body: [
            "Оператор персональных данных — \(operatorLine) (далее — «мы»).",
            "Политика действует для приложения OXION для iOS, мини-приложения OXION в Telegram и сайта, а также для Apple Watch, виджетов и App Clip.",
        ]),
        .init(title: "2. Какие данные мы получаем", icon: "tray.full", body: [
            "Аккаунт: идентификатор и имя в Telegram или Apple ID (Sign in with Apple), номер телефона, если вы входите по номеру (код приходит через Telegram Gateway), аватар.",
            "Профиль: город, цель, уровень подготовки, «о себе»; для тренеров — анкета, фото, цены, расписание.",
            "Дневник: тренировки, подходы, вес тела, замеры и фото прогресса, если вы их загружаете.",
            "Общение: сообщения, фото, голосовые и видеокружки в чатах, публикации и комментарии в ленте, записи к тренеру.",
            "Технические данные: тип устройства, версия приложения, токен push-уведомлений, время последнего входа.",
        ]),
        .init(title: "3. Что остаётся только на iPhone", icon: "iphone", body: [
            "Данные приложения «Здоровье» (HealthKit), пульс с Bluetooth-датчиков, шаги, геопозиция пробежки до сохранения, наклон телефона, распознавание повторов камерой и ответы ИИ-тренера в режиме «На iPhone» обрабатываются на устройстве.",
            "Данные «Здоровья» не используются для рекламы и не передаются третьим лицам — это требование Apple и наше правило.",
            "Камера, микрофон, фото, контакты, Bluetooth и геопозиция используются только когда вы сами запускаете функцию; доступ можно выключить в «Настройки» → Oxion.",
        ]),
        .init(title: "4. Зачем мы используем данные", icon: "target", body: [
            "Чтобы работали вход, дневник, чаты, лента, каталог тренеров и запись на занятия.",
            "Чтобы тренер, которого вы сами подключили, видел ваш дневник и мог назначать тренировки и цели.",
            "Чтобы присылать уведомления: сообщения, напоминания о занятиях и тренировках (их можно выключить).",
            "Чтобы защищать сервис от спама и злоупотреблений.",
        ]),
        .init(title: "5. Кому передаются данные", icon: "arrow.left.arrow.right", body: [
            "Тренеру — только если вы подключили его как своего тренера или записались к нему.",
            "Другим пользователям — то, что вы публикуете сами: профиль, посты, сообщения в чатах.",
            "Подрядчикам, без которых сервис не работает: хостинг и хранилище (Cloudflare), доставка кодов (Telegram Gateway), уведомления (Apple Push Notification service), оплата подписки (App Store). Они обрабатывают данные по нашему поручению.",
            "Мы не продаём персональные данные и не передаём их рекламодателям.",
        ]),
        .init(title: "6. Где и сколько хранятся", icon: "clock.arrow.circlepath", body: [
            "Данные хранятся на серверах Cloudflare и в защищённом хранилище; при передаче используется шифрование (HTTPS).",
            "Пока аккаунт существует. После удаления аккаунта персональные данные стираются в течение 30 дней; ваши сообщения в чужих переписках остаются у собеседников с пометкой «Удалённый аккаунт».",
        ]),
        .init(title: "7. Ваши права", icon: "person.badge.shield.checkmark", body: [
            "Вы можете узнать, какие данные о вас хранятся, исправить их, отозвать согласие и удалить аккаунт — в приложении (Профиль → Удалить аккаунт) или написав нам.",
            "Обработка ведётся в соответствии с Федеральным законом № 152-ФЗ «О персональных данных». Вы вправе обратиться в Роскомнадзор, если считаете, что ваши права нарушены.",
        ]),
        .init(title: "8. Дети", icon: "figure.and.child.holdinghands", body: [
            "OXION не предназначен для детей младше 14 лет. Если вам меньше 18, пользуйтесь приложением с согласия родителей.",
        ]),
        .init(title: "9. Изменения и контакты", icon: "envelope", body: [
            "Мы можем обновлять политику; о существенных изменениях сообщим в приложении.",
            "Вопросы о данных: \(operatorLine). Также — в поддержку OXION в Telegram.",
        ]),
    ]

    static let terms: [LegalSection] = [
        .init(title: "1. Что это за соглашение", icon: "signature", body: [
            "Это договор между вами и \(operatorLine) о пользовании OXION. Начиная пользоваться приложением, вы принимаете эти условия.",
        ]),
        .init(title: "2. Что такое OXION", icon: "flame", body: [
            "Сервис для тренировок: дневник, каталог тренеров, запись на занятия, чаты, лента, ИИ-тренер, магазин и интеграции с iPhone и Apple Watch.",
            "OXION — площадка: тренеры оказывают свои услуги самостоятельно, договорённости об оплате занятий заключаются между вами и тренером напрямую.",
        ]),
        .init(title: "3. Аккаунт", icon: "person.crop.circle", body: [
            "Вход — через Telegram, Apple ID или номер телефона. Вы отвечаете за сохранность доступа к своему аккаунту.",
            "Один человек — один аккаунт. Указывайте правдивые данные; тренеры — реальный опыт и квалификацию.",
        ]),
        .init(title: "4. Запись к тренеру", icon: "calendar", body: [
            "Тренер открывает окна, клиент записывается в свободное время. Запись можно отменить в приложении; отменяйте не позже чем за 12 часов — так честно по отношению к тренеру.",
            "Цена занятия указывается тренером и оплачивается ему напрямую, если не указано иное.",
        ]),
        .init(title: "5. PRO для тренеров", icon: "crown", body: [
            "PRO — платное размещение анкеты тренера в каталоге на 30 дней. Стоимость указана на экране PRO.",
            "При оплате через App Store подписка продлевается автоматически, пока вы её не отмените в настройках Apple ID не позднее чем за 24 часа до конца периода. Возвраты — по правилам Apple.",
        ]),
        .init(title: "6. Правила поведения", icon: "hand.raised", body: [
            "Нельзя: оскорблять, угрожать, рассылать спам, выкладывать чужие фото без разрешения, продавать запрещённые вещества и «чудо-препараты», выдавать себя за другого.",
            "Мы можем скрыть контент или заблокировать аккаунт за нарушения. Пожаловаться можно через меню поста, сообщения или профиля.",
        ]),
        .init(title: "7. Ваш контент", icon: "photo.on.rectangle", body: [
            "Права на фото, видео и тексты остаются у вас. Публикуя их в OXION, вы разрешаете показывать их другим пользователям в рамках сервиса.",
        ]),
        .init(title: "8. Здоровье и ИИ", icon: "cross.case", body: [
            "Советы тренеров, ИИ-тренера и материалы приложения не являются медицинской помощью. Перед нагрузками при заболеваниях проконсультируйтесь с врачом. Прекратите тренировку при боли или плохом самочувствии.",
            "Пульс, калории и распознавание повторов — ориентировочные значения.",
        ]),
        .init(title: "9. Ответственность", icon: "exclamationmark.shield", body: [
            "Сервис предоставляется «как есть». Мы стараемся, чтобы всё работало без сбоев, но не отвечаем за действия тренеров и других пользователей и за перерывы по не зависящим от нас причинам.",
        ]),
        .init(title: "10. Изменения и споры", icon: "arrow.triangle.2.circlepath", body: [
            "Мы можем менять соглашение; новая редакция действует с момента публикации в приложении.",
            "Споры решаются переговорами, а при недостижении согласия — по законодательству Российской Федерации.",
            "Контакты: \(operatorLine).",
        ]),
    ]
}

struct LegalDocView: View {
    let doc: LegalDoc
    private var sections: [LegalSection] { doc == .privacy ? LegalText.privacy : LegalText.terms }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: doc.icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.onLime)
                            .frame(width: 64, height: 64)
                            .background(Color.lime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(doc.title).font(.largeTitle.bold())
                        Text(LegalDoc.edition).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                if doc == .privacy {
                    Section("Коротко") {
                        ForEach(LegalText.privacySummary, id: \.1) { icon, title, sub in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: icon).font(.title3).foregroundStyle(Color.limeInk).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).font(.subheadline.bold())
                                    Text(sub).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section("Содержание") {
                    ForEach(sections) { s in
                        Button {
                            withAnimation { proxy.scrollTo(s.id, anchor: .top) }
                        } label: {
                            Label(s.title, systemImage: s.icon).foregroundStyle(.primary)
                        }
                    }
                }
                ForEach(sections) { s in
                    Section {
                        ForEach(Array(s.body.enumerated()), id: \.offset) { _, p in
                            Text(p).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    } header: {
                        Label(s.title, systemImage: s.icon).font(.headline).foregroundStyle(.primary).textCase(nil)
                    }
                    .id(s.id)
                }
                Section {
                    ShareLink(item: (doc == .privacy ? LegalText.privacy : LegalText.terms)
                        .map { "\($0.title)\n" + $0.body.joined(separator: "\n") }.joined(separator: "\n\n"),
                              subject: Text(doc.title)) {
                        Label("Поделиться текстом", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(doc == .privacy ? "Конфиденциальность" : "Соглашение")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.limeInk)
    }
}

/// Строка «Продолжая, вы принимаете…» для экрана входа
struct LegalConsentLine: View {
    @State private var open: LegalDoc?
    var body: some View {
        VStack(spacing: 2) {
            Text("Продолжая, вы принимаете").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button("Соглашение") { open = .terms }
                Text("и").foregroundStyle(.secondary)
                Button("Политику конфиденциальности") { open = .privacy }
            }
        }
        .font(.caption)
        .tint(Color.limeInk)
        .sheet(item: $open) { d in NavigationStack { LegalDocView(doc: d) } }
    }
}
