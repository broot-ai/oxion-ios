import SwiftUI

// MARK: - Раздел «О OXION»: основатель, история, возможности и зачем каждая придумана

struct AboutOxionView: View {
    @Environment(AppModel.self) private var model
    @State private var openFounder = false

    static let founderId = 6831098326
    private let founderOfficial = OxOfficial(kind: "staff", title: "Основатель OXION", since: nil)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    quote
                    section("Как всё начиналось", "clock.arrow.circlepath") { timeline }
                    section("Во что верит OXION", "heart.fill") { values }
                    section("Возможности и зачем они придуманы", "sparkles") {
                        VStack(spacing: 12) { ForEach(Self.features) { FeatureCard(f: $0) } }
                    }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(Color.oxBG.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // фото основателя: внизу плавно растворяется в фон
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Image("founder-maxim")
                .resizable()
                .scaledToFill()
                .frame(height: 520)
                .frame(maxWidth: .infinity)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    OxionSealButton(official: founderOfficial, userId: Self.founderId, name: "Максим", photo: nil, size: 30)
                    Text("Максим").font(.system(size: 40, weight: .heavy, design: .rounded))
                }
                // бейджик основателя
                HStack(spacing: 6) {
                    FlameMark(size: 16)
                    Text("ОСНОВАТЕЛЬ OXION").font(.system(size: 13, weight: .heavy)).tracking(1.2)
                }
                .foregroundStyle(Color.onLime)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.lime, in: Capsule())
                Text("Придумал OXION, чтобы тренировки, тренеры и мотивация жили в одном месте")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.handle(route: "user/\(Self.founderId)") } label: {
                    Label("Профиль Максима", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 38)
                }
                .buttonStyle(.glass)
                .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening").font(.title2).foregroundStyle(Color.limeInk)
            Text("Я сам годами записывал подходы в заметки, искал тренера по знакомым и терял мотивацию через месяц. OXION — это приложение, которое мне самому не хватало: где видно прогресс, где рядом свой тренер и люди, которые тренируются так же.")
                .font(.body.italic())
                .fixedSize(horizontal: false, vertical: true)
            Text("— Максим, основатель OXION").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func section<C: View>(_ title: String, _ icon: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.title3.bold())
            c()
        }
    }

    // история развития
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.history.enumerated()), id: \.offset) { i, h in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(i == Self.history.count - 1 ? Color.lime : Color.lime.opacity(0.25)).frame(width: 30, height: 30)
                            Image(systemName: h.icon).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(i == Self.history.count - 1 ? Color.onLime : Color.limeInk)
                        }
                        if i < Self.history.count - 1 {
                            Rectangle().fill(Color.lime.opacity(0.3)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.stage).font(.caption.weight(.heavy)).foregroundStyle(Color.limeInk).textCase(.uppercase)
                        Text(h.title).font(.headline)
                        Text(h.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var values: some View {
        VStack(spacing: 10) {
            value("figure.strengthtraining.traditional", "Прогресс важнее идеала", "Неважно, с какого веса вы начали — OXION показывает рост, а не сравнивает с другими.")
            value("person.2.fill", "Тренер рядом", "Хороший тренер меняет всё. Поэтому найти, записаться и заниматься с тренером можно прямо в приложении.")
            value("lock.shield.fill", "Данные — ваши", "Дневник, вес и фото принадлежат вам: приватность настраивается, а лишнего OXION не собирает.")
            value("bolt.heart.fill", "Мотивация каждый день", "Серии, рекорды, истории и друзья помогают не бросить через месяц.")
        }
    }

    private func value(_ icon: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.limeInk).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(t).font(.headline)
                Text(d).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            FlameMark(size: 44)
            Text("OXION").font(.system(size: 22, weight: .black, design: .rounded)).tracking(6)
            Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Сделано с любовью к спорту")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    // MARK: данные

    struct Stage { let stage: String; let title: String; let text: String; let icon: String }
    static let history: [Stage] = [
        Stage(stage: "Идея", title: "Заметки вместо дневника", text: "Максим тренировался и вёл подходы в заметках телефона. Прогресс терялся, а найти тренера можно было только «по знакомству». Тогда появилась идея: одно место для тренировок, тренеров и людей.", icon: "lightbulb.fill"),
        Stage(stage: "Первая версия", title: "Мини-приложение в Telegram", text: "Первый OXION жил внутри Telegram: поиск тренеров, дневник и упражнения. Его проверяли друзья из зала — и каждую неделю приносили новые идеи.", icon: "paperplane.fill"),
        Stage(stage: "Сообщество", title: "Лента, чаты и истории", text: "Люди хотели делиться результатами и общаться. Так появились лента веток, чаты с кружками и голосовыми, истории с виджетами тренировок.", icon: "bubble.left.and.bubble.right.fill"),
        Stage(stage: "Для тренеров", title: "Кабинет тренера", text: "Тренерам нужны были клиенты и расписание без таблиц. Появились анкеты, запись на занятия, проверенные тренеры с огоньком OXION и программы для клиентов.", icon: "figure.strengthtraining.traditional"),
        Stage(stage: "Свой iPhone", title: "Нативное приложение для iOS", text: "Чтобы всё работало быстро и красиво, OXION переписали на Swift: жидкое стекло, Dynamic Island, «Здоровье», 3D-модель тела и камера.", icon: "iphone"),
        Stage(stage: "Сейчас", title: "Умный помощник", text: "OXION учится подсказывать: ИИ помогает подобрать товары и программу, следит за техникой и прогрессом. Каждый раздел Максим продумывал под реальных людей — от новичка до тренера.", icon: "sparkles")
    ]

    struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let what: String
        let why: String
    }

    static let features: [Feature] = [
        Feature(icon: "figure.strengthtraining.traditional", color: Color(hex: 0xB2EE37), title: "Тренеры",
                what: "Поиск по городу, направлениям и цене, анкеты с отзывами, запись на свободное время, проверенные тренеры с огоньком.",
                why: "Чтобы найти своего тренера за минуты, а не через знакомых, и не бояться попасть к случайному человеку."),
        Feature(icon: "calendar", color: Color(hex: 0x3478F6), title: "Дневник тренировок",
                what: "Тренировки, подходы, веса, повторы, шаблоны, рекорды и цели на неделю.",
                why: "Прогресс должен быть виден: без записей кажется, что ничего не меняется, и мотивация пропадает."),
        Feature(icon: "figure.arms.open", color: Color(hex: 0xFF9F0A), title: "3D-тело и «Движение»",
                what: "Модель тела с группами мышц, разбор техники по камере.",
                why: "Чтобы понимать, какие мышцы работают, и не травмироваться из-за неправильной техники."),
        Feature(icon: "figure.run", color: Color(hex: 0x30D158), title: "Кардио и «Здоровье»",
                what: "Бег и ходьба с картой, шаги, пульс и калории из «Здоровья».",
                why: "Силовые — только половина. Кардио и активность за день дают полную картину."),
        Feature(icon: "flame.fill", color: Color(hex: 0xFF453A), title: "Лента",
                what: "Ветки как в Threads: фото, тренировки, опросы, музыка, спойлеры, исчезающие публикации, упоминания.",
                why: "Делиться результатом и видеть, как тренируются другие, — лучшая мотивация не пропускать зал."),
        Feature(icon: "circle.dashed", color: Color(hex: 0xBF5AF2), title: "Истории",
                what: "Камера с кольцевой подсветкой, рисование, наклейки, виджеты результатов и кнопка «Записаться» для тренеров.",
                why: "Показать тренировку за 10 секунд, а тренеру — получить клиентов прямо из истории."),
        Feature(icon: "bubble.left.and.bubble.right.fill", color: Color(hex: 0x64D2FF), title: "Чаты",
                what: "Личные и групповые чаты, кружки, голосовые, запросы на переписку, защита от спама.",
                why: "Общение с тренером и друзьями без перехода в другие мессенджеры — и без незнакомцев в личке."),
        Feature(icon: "sparkles", color: Color(hex: 0xD4FF6A), title: "ИИ-помощник",
                what: "Подбор товаров и программы, подсказки по тренировкам и питанию.",
                why: "Не каждому по карману тренер каждый день — умный помощник подскажет следующий шаг."),
        Feature(icon: "bag.fill", color: Color(hex: 0xFFD60A), title: "Магазин",
                what: "Спортпит и экипировка с корзиной и подбором от ИИ.",
                why: "Всё для тренировок — в том же приложении, где вы тренируетесь."),
        Feature(icon: "crown.fill", color: Color(hex: 0xF5C04A), title: "OXION PRO",
                what: "Расширенная аналитика, оформление и дополнительные возможности.",
                why: "Чтобы развивать OXION без навязчивой рекламы."),
        Feature(icon: "lock.shield.fill", color: Color(hex: 0x8E8E93), title: "Безопасность",
                what: "Вход по Face ID, ключи входа, защита от скриншотов в чатах, настройки приватности.",
                why: "Фото тела, вес и переписка — личное. Это должно оставаться вашим.")
    ]
}

private struct FeatureCard: View {
    let f: AboutOxionView.Feature
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.spring(duration: 0.35, bounce: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: f.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 40, height: 40).background(f.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.headline)
                        Text(f.what).font(.caption).foregroundStyle(.secondary).lineLimit(open ? nil : 1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Color.limeInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Зачем Максим это придумал").font(.caption.weight(.heavy)).foregroundStyle(Color.limeInk)
                        Text(f.why).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.lime.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
