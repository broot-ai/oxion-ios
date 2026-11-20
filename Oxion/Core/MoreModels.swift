import Foundation

// MARK: - Рекорды и достижения

struct RecordItem: Decodable, Identifiable {
    let id: Int
    let name: String
    let type: String?
    let unit: String?
    let weight: Double?
    let reps: Int?
    let duration: Double?
    let distance: Double?
    let e1rm: Double?
    let lastDate: String?
    let times: Int?

    var best: String {
        func n(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v) }
        switch type {
        case "wr": return "\(n(weight ?? 0)) \(unit ?? "кг") × \(reps ?? 0)"
        case "r": return "\(reps ?? 0) раз"
        case "t": return "\(n(duration ?? 0)) \(unit ?? "сек")"
        default: return "\(n(distance ?? 0)) \(unit ?? "км")"
        }
    }
}
struct RecordsResponse: Decodable { let items: [RecordItem] }

struct Achievement: Decodable, Identifiable {
    let key: String
    let icon: String
    let title: String
    let desc: String?
    let value: Double?
    let need: Double?
    let done: Bool
    let pct: Int?
    var id: String { key }
}
struct AchievementsResponse: Decodable {
    let items: [Achievement]
    let done: Int?
    let total: Int?
    let streak: Int?
    let workouts: Int?
}

// MARK: - Челленджи

struct BoardRow: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let value: Double? }

struct Challenge: Decodable, Identifiable {
    let id: Int
    let title: String
    let kind: String?
    let unit: String?
    let target: Double?
    let starts: String?
    let ends: String?
    let city: String?
    let prize: String?
    let sponsor: String?
    let status: String?
    let members: Int?
    var joined: Bool?
    let my: Double?
    let started: Bool?
    let place: Int?
    let board: [BoardRow]?
}
struct ChallengesResponse: Decodable { let items: [Challenge] }

// MARK: - Цели

struct GoalTrainer: Decodable { let id: Int?; let name: String? }
struct Goal: Decodable, Identifiable {
    let id: Int
    let kind: String?
    let title: String?
    let exercise: String?
    let target: Double?
    let start: Double?
    let current: Double?
    let unit: String?
    let pct: Int?
    let deadline: String?
    let daysLeft: Int?
    let status: String?
    let trainer: GoalTrainer?
}
struct GoalsResponse: Decodable { let items: [Goal] }

// MARK: - Мой тренер / клиенты

struct CoachTrainer: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let status: String?; let price: Int? }
struct CoachBooking: Decodable, Identifiable {
    let id: Int
    let startsAt: Double?
    let minutes: Int?
    let place: String?
    let price: Int?
    let trainer: GoalTrainer?
}
struct CoachCheck: Decodable, Identifiable {
    let id: Int
    let exercise: String?
    let status: String?
    let answer: String?
    let at: Double?
    let trainer: String?
}
struct CoachMy: Decodable {
    let trainers: [CoachTrainer]?
    let bookings: [CoachBooking]?
    let checks: [CoachCheck]?
}

struct ClientItem: Decodable, Identifiable {
    let id: Int
    let name: String?
    let photo: String?
    let status: String?
    let goal: String?
    let level: String?
    let weekGoal: Int?
    let lastDate: String?
    let weekN: Int?
    let checksNew: Int?
}
struct ClientsResponse: Decodable { let invite: String?; let items: [ClientItem] }

// MARK: - Анкета тренера

struct MyTrainer: Decodable {
    let userId: Int?
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
    let paidUntil: Double?
    let autorenew: Bool?
    let hidden: Bool?
    let published: Bool?
    let missing: [String]?
}

// MARK: - Здоровье

struct HealthDay: Decodable, Identifiable {
    let date: String
    let steps: Int?
    let kcal: Double?
    let distance: Double?
    let sleepMin: Int?
    let restHr: Int?
    var id: String { date }
}
struct HealthResponse: Decodable { let items: [HealthDay]; let connected: Bool?; let lastSync: Double? }

// MARK: - ИИ-тренер

struct AIMessage: Decodable, Identifiable {
    let id: Int
    let role: String
    let content: String
    let plan: JSONValue?
    let createdAt: Double?
}
struct AIMessages: Decodable { let items: [AIMessage]; let enabled: Bool? }
struct AIReply: Decodable {
    let id: Int
    let role: String
    let content: String
    let plan: JSONValue?
    let createdAt: Double?
    let left: Int?
}

// MARK: - Заказы магазина

struct MOrder: Decodable, Identifiable {
    let id: FlexString
    let num: FlexString?
    let status: String?
    let statusName: String?
    let totalKop: Int?
    let createdAt: Double?
    let storeName: String?
    let lines: Int?
    let photo: String?
}
extension FlexString: Hashable {
    static func == (a: FlexString, b: FlexString) -> Bool { a.value == b.value }
    func hash(into h: inout Hasher) { h.combine(value) }
}
struct MOrders: Decodable { let items: [MOrder] }

// MARK: - Работа и платформа

struct MStoreMember: Decodable, Identifiable { let id: Int; let name: String?; let status: String?; let roleName: String? }
struct MCourierState: Decodable { let status: String?; let online: Int? }
struct MMe: Decodable {
    let roles: [String]?
    let stores: [MStoreMember]?
    let courier: MCourierState?
}

struct PlatformSummary: Decodable {
    let storesPending: Int?
    let couriersPending: Int?
    let ticketsOpen: Int?
    let ticketsWait: Int?
    let disputesOpen: Int?
    let productsNew: Int?
    let ordersFailed: Int?
    let ordersToday: Int?
    let storesActive: Int?
    let couriersActive: Int?
    let couriersOnline: Int?
    let role: String?
}
struct PartnerInvite: Decodable { let token: String; let kind: String?; let link: String; let expiresInDays: Int? }

struct Ticket: Decodable, Identifiable {
    let id: Int
    let status: String?
    let subject: String?
    let lastText: String?
    let lastFrom: String?
    let unread: Int?
    let updatedAt: Double?
}
struct TicketsResponse: Decodable { let items: [Ticket] }
struct TicketMsg: Decodable, Identifiable { let id: Int; let fromAdmin: Int?; let text: String?; let createdAt: Double? }
struct TicketFull: Decodable {
    let id: Int
    let status: String?
    let subject: String?
    let messages: [TicketMsg]?
}
