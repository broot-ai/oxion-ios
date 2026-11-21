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
    let cities: [String]?
    let directions: [String]?
    let formats: [String]?
    let subPrice: Int?
    let subDays: Int?
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
    var replies: Int?
    var reposts: Int?
    var liked: Bool?
    var reposted: Bool?
    var saved: Bool?
    let mine: Bool?
    let canReply: Bool?
    let replyToName: String?
    let parentId: Int?
    var poll: PostPoll?
    let workout: JSONValue?
    let product: JSONValue?
    let quote: JSONValue?
    let chainCount: Int?
    let chainOf: Int?
    let edited: Bool?
    let status: String?
    var quotes: Int?
    var replyTo: String?
    let trainerAnswer: Bool?
}

struct PollOption: Decodable, Hashable { let text: String; let votes: Int? }
struct PostPoll: Decodable, Hashable {
    let options: [PollOption]
    let total: Int?
    let mine: Int?
    let closed: Bool?
}

struct FUser: Decodable {
    let id: Int
    let name: String?
    let photo: String?
    let city: String?
    let bio: String?
    let link: String?
    let followers: Int?
    let following: Int?
    let posts: Int?
    var isFollowing: Bool?
    let followsMe: Bool?
    var muted: Bool?
    var blocked: Bool?
    let trainer: Bool?
    let me: Bool?
    let streak: Int?
    let monthWorkouts: Int?
    let pinned: Post?
}

struct FPerson: Decodable, Identifiable {
    let id: Int
    let name: String?
    let photo: String?
    let city: String?
    let bio: String?
    let trainer: Bool?
    var isFollowing: Bool?
}

struct FSearch: Decodable { let users: [FPerson]?; let posts: [Post]? }
struct FPeople: Decodable { let items: [FPerson] }

struct ActivityItem: Decodable, Identifiable {
    let id: Int
    let kind: String
    let at: Double?
    let unread: Bool?
    let actor: FPerson
    let post: ActivityPost?
}
struct ActivityPost: Decodable { let id: Int; let open: Int?; let text: String?; let photo: String? }
struct ActivityResponse: Decodable { let items: [ActivityItem]; let next: FlexString? }

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
    let groups: [String]?
}

struct WorkoutsResponse: Decodable { let items: [Workout] }

// MARK: - Ветка поста, загрузка фото

struct PostThread: Decodable {
    let post: Post
    let chain: [Post]?
    let ancestors: [Post]?
    let replies: [Post]?
}

struct UploadResponse: Decodable { let key: String; let url: String? }
struct IdResponse: Decodable { let id: Int }

struct PostRef: Hashable { let id: Int }
struct ChatRef: Hashable { let id: Int; let name: String }
struct WorkoutRef: Hashable { let id: Int }

enum ReportReason: String, CaseIterable, Identifiable {
    case spam, abuse, danger, adult, fake, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: return "Спам или реклама"
        case .abuse: return "Оскорбления"
        case .danger: return "Опасные советы"
        case .adult: return "Неприличный контент"
        case .fake: return "Обман или мошенничество"
        case .other: return "Другое"
        }
    }
}

// MARK: - Чаты

struct Peer: Decodable {
    let id: Int
    let name: String?
    let photo: String?
    let trainer: Bool?
    let lastSeen: Double?
}

struct ChatItem: Decodable, Identifiable {
    let id: Int
    let peer: Peer
    let last: String?
    let mine: Bool?
    let at: Double?
    var unread: Int?
    var pinned: Bool?
    var muted: Bool?
    var archived: Bool?
    var marked: Bool?
    let lastId: Int?
}

struct ChatsResponse: Decodable { let items: [ChatItem] }

struct MsgReply: Decodable { let id: Int?; let mine: Bool?; let text: String? }
struct MsgReaction: Decodable, Hashable { let emoji: String; let n: Int; let mine: Bool? }

struct Message: Decodable, Identifiable {
    let id: Int
    let mine: Bool
    let text: String?
    let photo: String?
    let at: Double?
    let kind: String?
    let replyTo: Int?
    let reply: MsgReply?
    let edited: Bool?
    let deleted: Bool?
    let reactions: [MsgReaction]?
    let card: JSONValue?
}

struct ChatDetail: Decodable {
    let id: Int
    let protect: ChatProtect?
    let peer: Peer
    let messages: [Message]
    let changed: [Message]?
    let peerReadId: Int?
}

enum Kinds {
    static let label: [String: String] = [
        "workout": "🏋️ Тренировка", "record": "🏆 Рекорд", "progress": "📈 Прогресс", "weight": "⚖️ Вес тела",
        "week": "📊 Итоги недели", "goal": "🎯 Цель", "plan": "📋 Назначена тренировка", "slot": "📅 Время для занятия",
        "check": "🎥 Проверка техники", "sticker": "🎨 Стикер", "voice": "🎤 Голосовое", "call": "📞 Звонок",
        "vnote": "📹 Видеосообщение"
    ]
    static let reactions = ["👍", "🔥", "💪", "❤️", "😂", "👏"]
}

// MARK: - Тренировка целиком

struct WSet: Decodable, Identifiable {
    let id: Int
    let weight: Double?
    let reps: Int?
    let duration: Int?
    let distance: Double?

    func text(type: String?, unit: String?) -> String {
        let u = unit ?? ""
        switch type {
        case "wr":
            let w = weight.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String(format: "%.1f", $0) } ?? "0"
            return "\(w) \(u.isEmpty ? "кг" : u) × \(reps ?? 0)"
        case "r":
            return "\(reps ?? 0) раз"
        case "t":
            return "\(duration ?? 0) \(u.isEmpty ? "сек" : u)"
        default:
            let d = distance.map { String(format: "%.2f", $0) } ?? "0"
            return "\(d) \(u.isEmpty ? "км" : u) · \(duration ?? 0) мин"
        }
    }
}

struct WExercise: Decodable, Identifiable {
    let id: Int
    let exerciseId: Int
    let name: String
    let type: String?
    let unit: String?
    let muscle: String?
    let sets: [WSet]
}

struct WorkoutFull: Decodable {
    let id: Int
    let date: String
    let title: String?
    let time: String?
    let calories: Int?
    let note: String?
    let exercises: [WExercise]?
}

// MARK: - Любой JSON (карточки в чатах)

enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(format: "%.1f", n)
        default: return nil
        }
    }
    var number: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var int: Int? { number.map { Int($0) } }
    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return nil
        }
    }
    var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }
}

// MARK: - Вложения в чат

struct AttachWorkout: Decodable, Identifiable { let id: Int; let date: String; let title: String?; let sets: Int? }
struct AttachExercise: Decodable, Identifiable { let id: Int; let name: String; let type: String?; let last: String? }
struct AttachOptions: Decodable {
    let workouts: [AttachWorkout]?
    let exercises: [AttachExercise]?
}

// MARK: - Магазин (маркетплейс спортпита)

func rub(_ kop: Int?) -> String {
    let r = Double(kop ?? 0) / 100
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.maximumFractionDigits = r.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return (f.string(from: NSNumber(value: r)) ?? String(r)) + " ₽"
}

struct MCategory: Decodable, Identifiable, Hashable { let id: Int; let slug: String?; let name: String; let icon: String? }

struct MProduct: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let brand: String?
    let storeId: Int?
    let storeName: String?
    let priceKop: Int?
    let oldPriceKop: Int?
    let inStock: Bool?
    let rating: Double?
    let ratingCount: Int?
    let photo: String?
    var fav: Bool?
}

struct MStoreShort: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let logo: String?
    let rating: Double?
    let ratingCount: Int?
}

struct ShopHome: Decodable {
    let categories: [MCategory]?
    let forGoal: [MProduct]?
    let popular: [MProduct]?
    let stores: [MStoreShort]?
    let cartCount: Int?
    let activeOrders: Int?
    let city: String?
}

struct MCatalog: Decodable { let items: [MProduct]; let more: Bool?; let next: Int? }

struct MVariant: Decodable, Identifiable, Hashable {
    let id: Int
    let flavor: String?
    let size: String?
    let priceKop: Int?
    let oldPriceKop: Int?
    let available: Int?
    var title: String { [flavor, size].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct MPhoto: Decodable, Hashable { let id: Int?; let url: String? }
struct MReview: Decodable, Hashable { let rating: Double?; let text: String?; let name: String? }
struct MStoreRef: Decodable, Hashable { let id: Int; let name: String?; let rating: Double?; let delivery: Bool?; let pickup: Bool? }

struct MProductFull: Decodable {
    let id: Int
    let title: String
    let description: String?
    let composition: String?
    let usage: String?
    let brand: String?
    let category: String?
    let rating: Double?
    let ratingCount: Int?
    var fav: Bool?
    let variants: [MVariant]
    let photos: [MPhoto]?
    let reviews: [MReview]?
    let store: MStoreRef?
}

struct MCartItem: Decodable, Identifiable, Hashable {
    let variantId: Int
    let productId: Int
    let title: String
    let variant: String?
    let priceKop: Int?
    let oldPriceKop: Int?
    let qty: Int
    let sumKop: Int?
    let available: Int?
    let ok: Bool?
    let issue: String?
    let photo: String?
    var id: Int { variantId }
}

struct MCartStore: Decodable, Identifiable, Hashable {
    let storeId: Int
    let storeName: String?
    let minOrderKop: Int?
    let items: [MCartItem]
    let itemsKop: Int?
    var id: Int { storeId }
}

struct MCart: Decodable {
    let stores: [MCartStore]
    let count: Int
    let itemsKop: Int
}

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
