import Foundation

/// Общие данные приложения и виджета. Лежат в App Group «group.ru.oxion.app».
enum WidgetShared {
    static let group = "group.ru.oxion.app"
    static let snapshotKey = "widget_snapshot_v2"
    static let tokenKey = "widget_token"
    static let serverKey = "widget_server"

    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
}

struct WidgetSnapshot: Codable {
    var name: String = ""
    var quote: String
    var quoteAuthor: String?
    var goalTitle: String?
    var goalPct: Int?
    var goalDetail: String?
    var weekDone: Int = 0
    var weekGoal: Int = 3
    var todayTitle: String?
    var todayTime: String?
    var reminder: String
    var updatedAt: Date = Date()
    // панель (Medium / Large / StandBy)
    var weekSets: Int = 0
    var weekKcal: Int = 0
    var streak: Int = 0
    var trainerId: Int?
    var trainerName: String?
    var trainerInfo: String?
    var trainerPrice: Int?
    var trainers: [WTrainer] = []
    var favorites: [WTrainer] = []
    var upcoming: [WPlanned] = []
    var achievementsDone: Int = 0
    var achievementsTotal: Int = 0
    var lastWorkout: String?
    var isDemo: Bool = false

    static let quotes: [(String, String?)] = [
        ("Дисциплина — это мост между целями и результатом.", "Джим Рон"),
        ("Тело достигает того, во что верит разум.", nil),
        ("Не жди мотивации — создай привычку.", nil),
        ("Каждая тренировка — голос за того, кем ты хочешь стать.", "Джеймс Клир"),
        ("Боль временна. Гордость — навсегда.", nil),
        ("Сильнее, чем вчера, — вот и вся цель.", nil),
        ("Успех — это сумма маленьких усилий, повторяемых день за днём.", "Роберт Кольер"),
        ("Лучший проект, над которым ты можешь работать, — это ты.", nil),
        ("Ты никогда не пожалеешь о тренировке, которую сделал.", nil),
        ("Маленький шаг каждый день — большой результат через год.", nil),
        ("Мотивация запускает, привычка ведёт дальше.", "Джим Рюн"),
        ("Если тяжело — значит, ты растёшь.", nil)
    ]

    /// Цитата дня без сети
    static func localQuote(_ date: Date = Date()) -> (String, String?) {
        let day = Int(date.timeIntervalSince1970 / 86400)
        return quotes[day % quotes.count]
    }

    static var placeholder: WidgetSnapshot {
        let q = localQuote()
        var s = WidgetSnapshot(quote: q.0, quoteAuthor: q.1, goalTitle: "Жим лёжа 100 кг", goalPct: 72,
                               goalDetail: "72 из 100 кг", weekDone: 2, weekGoal: 3,
                               todayTitle: "День ног", todayTime: "19:00",
                               reminder: "Сегодня: День ног в 19:00")
        s.weekSets = 46; s.weekKcal = 1240; s.streak = 4
        s.trainerId = 0; s.trainerName = "Анна Смирнова"; s.trainerInfo = "Силовые · Похудение"; s.trainerPrice = 1500
        s.trainers = [WTrainer(id: 0, name: "Анна Смирнова", info: "Силовые", price: 1500, rating: 4.9),
                      WTrainer(id: 0, name: "Игорь Ким", info: "Кроссфит", price: 1200, rating: 4.8),
                      WTrainer(id: 0, name: "Мария Лен", info: "Йога", price: 1000, rating: 5.0)]
        s.favorites = Array(s.trainers.prefix(2))
        s.upcoming = [WPlanned(id: 0, title: "День ног", when: "Сегодня, 19:00"), WPlanned(id: 0, title: "Грудь и бицепс", when: "Чт"),
                      WPlanned(id: 0, title: "Спина", when: "Сб")]
        s.achievementsDone = 5; s.achievementsTotal = 15
        s.lastWorkout = "Вчера · Спина"
        s.isDemo = true
        return s
    }

    static func load() -> WidgetSnapshot? {
        guard let d = WidgetShared.defaults?.data(forKey: WidgetShared.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) {
            WidgetShared.defaults?.set(d, forKey: WidgetShared.snapshotKey)
        }
    }
}

struct WTrainer: Codable, Hashable {
    var id: Int
    var name: String
    var info: String?
    var price: Int?
    var rating: Double?
}

struct WPlanned: Codable, Hashable {
    var id: Int
    var title: String
    var when: String
}

/// Ответ сервера /api/widget (Cloudflare Worker)
struct WidgetAPIResponse: Decodable {
    struct Quote: Decodable { let text: String; let author: String? }
    struct Goal: Decodable { let title: String?; let pct: Int?; let current: Double?; let target: Double?; let unit: String?; let daysLeft: Int? }
    struct Week: Decodable { let done: Int?; let goal: Int? }
    struct Today: Decodable { let id: Int?; let title: String?; let time: String? }
    let quote: Quote?
    let goal: Goal?
    let week: Week?
    let today: Today?
    let reminder: String?
    let name: String?

    func snapshot() -> WidgetSnapshot {
        let lq = WidgetSnapshot.localQuote()
        var detail: String?
        if let g = goal, let c = g.current, let t = g.target {
            detail = "\(Int(c)) из \(Int(t)) \(g.unit ?? "")".trimmingCharacters(in: .whitespaces)
            if let d = g.daysLeft, d >= 0, let cur = detail { detail = cur + " · \(d) дн." }
        }
        return WidgetSnapshot(name: name ?? "",
                              quote: quote?.text ?? lq.0, quoteAuthor: quote == nil ? lq.1 : quote?.author,
                              goalTitle: goal?.title, goalPct: goal?.pct, goalDetail: detail,
                              weekDone: week?.done ?? 0, weekGoal: week?.goal ?? 3,
                              todayTitle: today?.title, todayTime: today?.time,
                              reminder: reminder ?? "Время тренироваться 💪")
    }

    /// Запрос прямо из виджета (если приложение передало токен)
    static func fetch() async -> WidgetSnapshot? {
        guard let d = WidgetShared.defaults,
              let token = d.string(forKey: WidgetShared.tokenKey),
              let server = d.string(forKey: WidgetShared.serverKey),
              let url = URL(string: server + "/api/widget") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let res = try? await URLSession.shared.data(for: req),
              (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return (try? dec.decode(WidgetAPIResponse.self, from: res.0))?.snapshot()
    }
}
