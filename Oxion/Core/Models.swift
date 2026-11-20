import Foundation

/// Значение, которое сервер может прислать строкой или числом (курсоры ленты).
struct FlexString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int64.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(Int64(d)) }
        else { value = nil }
    }
}

// MARK: - Вход

struct LoginStart: Decodable { let token: String; let link: String }
struct LoginPoll: Decodable { let status: String; let token: String? }
struct TokenResponse: Decodable { let token: String }

// MARK: - Профиль и справочники

struct Me: Decodable {
    let id: Int
    let name: String?
    let tgName: String?
    let username: String?
    let photoUrl: String?
    let role: String?
    let mode: String?
    let city: String?
    let goal: String?
    let level: String?
    let weekGoal: Int?
    let notify: Bool?
    let registered: Bool?
    let hasTrainer: Bool?
    let admin: Bool?

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let n = tgName, !n.isEmpty { return n }
        return "Без имени"
    }
}

struct Muscle: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let icon: String?
    var id: String { key }
}

struct FeedTopic: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let icon: String?
    var id: String { key }
}

struct Meta: Decodable {
    let appName: String?
    let botUsername: String?
    let muscles: [Muscle]?
    let feedTopics: [FeedTopic]?
    let supportTg: String?
    let supportEmail: String?
}

// MARK: - Лента

struct Author: Decodable {
    let id: Int
    let name: String?
    let photo: String?
    let trainer: Bool?
    let me: Bool?
}

struct Post: Decodable, Identifiable {
    let id: Int
    let at: Double?
    let text: String?
    let photos: [String]?
    let topic: String?
    let author: Author
    var likes: Int?
    let replies: Int?
    let reposts: Int?
    var liked: Bool?
    let reposted: Bool?
    var saved: Bool?
    let mine: Bool?
}

struct RepostBy: Decodable { let id: Int; let name: String? }

struct FeedItem: Decodable, Identifiable {
    var post: Post
    let repostBy: RepostBy?
    var id: Int { post.id }
}

struct FeedResponse: Decodable {
    let items: [FeedItem]
    let next: FlexString?
    let noCity: Bool?
}

// MARK: - Тренеры

struct Trainer: Decodable, Identifiable {
    let userId: Int
    let name: String?
    let price: Int?
    let experience: Int?
    let directions: [String]?
    let formats: [String]?
    let rating: Double?
    let reviewsCount: Int?
    let cover: String?
    var fav: Bool?
    let match: Bool?
    var id: Int { userId }
}

struct TrainersResponse: Decodable {
    let items: [Trainer]
    let hasMore: Bool?
    let nextOffset: Int?
}

struct TrainerPhoto: Decodable, Identifiable {
    let id: Int?
    let url: String?
    var stableId: String { url ?? String(id ?? 0) }
}

struct TrainerDetail: Decodable {
    let userId: Int
    let name: String?
    let city: String?
    let bio: String?
    let directions: [String]?
    let formats: [String]?
    let price: Int?
    let experience: Int?
    let districts: [String]?
    let photos: [TrainerPhoto]?
    let rating: Double?
    let reviewsCount: Int?
    var fav: Bool?
    let isMe: Bool?
}

struct FavResponse: Decodable { let ok: Bool?; let fav: Bool? }

// MARK: - Упражнения

struct Exercise: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let muscle: String?
    let type: String?
    let unit: String?
    let technique: String?
    let image: String?
    let own: Bool?
}

struct ExercisesResponse: Decodable { let items: [Exercise] }

// MARK: - Дневник

struct WeightPoint: Decodable { let date: String; let kg: Double }
struct TodayStats: Decodable { let sets: Int?; let calories: Int?; let workouts: Int? }

struct Stats: Decodable {
    let workouts: Int?
    let planned: Int?
    let calories: Int?
    let sets: Int?
    let daysDone: [String]?
    let lastWeight: WeightPoint?
    let today: TodayStats?
    let weekGoal: Int?
}

struct Workout: Decodable, Identifiable {
    let id: Int
    let date: String
    let title: String?
    let time: String?
    let calories: Int?
    let exCount: Int?
    let note: String?
}

struct WorkoutsResponse: Decodable { let items: [Workout] }

// MARK: - Утилиты

enum RU {
    /// 1 год, 2 года, 5 лет
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100, b = a % 10
        if a > 10 && a < 20 { return many }
        if b == 1 { return one }
        if b >= 2 && b <= 4 { return few }
        return many
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let humanDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    static func human(_ ymd: String) -> String {
        guard let d = dayFormatter.date(from: ymd) else { return ymd }
        if Calendar.current.isDateInToday(d) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(d) { return "Вчера" }
        if Calendar.current.isDateInTomorrow(d) { return "Завтра" }
        return humanDay.string(from: d)
    }
}
