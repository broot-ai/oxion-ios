import SwiftUI
import AppIntents
import CoreSpotlight
import VisualIntelligence

// MARK: - Каталог упражнений и тренеров на телефоне
// Нужен поиску iPhone (Spotlight) и визуальному поиску: они работают без открытого приложения.

struct CatalogExercise: Codable, Hashable {
    let id: Int
    let name: String
    let muscle: String
    let technique: String
}

struct CatalogTrainer: Codable, Hashable {
    let id: Int
    let name: String
    let about: String
}

enum Catalog {
    private struct Store: Codable { var exercises: [CatalogExercise]; var trainers: [CatalogTrainer] }

    private static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("oxion-catalog.json")
    }

    private static func read() -> Store {
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) else {
            return Store(exercises: [], trainers: [])
        }
        return s
    }

    static var exercises: [CatalogExercise] { read().exercises }
    static var trainers: [CatalogTrainer] { read().trainers }

    /// Скачать каталог и обновить поиск iPhone (после входа, раз в день)
    @MainActor
    static func refresh(muscleName: (String?) -> String) async {
        guard API.token != nil else { return }
        let last = UserDefaults.standard.double(forKey: "catalog_at")
        guard Date().timeIntervalSince1970 - last > 6 * 3600 || exercises.isEmpty else { return }
        async let ex: ExercisesResponse? = try? API.call("/exercises")
        async let tr: TrainersResponse? = try? API.call("/trainers", query: ["sort": "match", "offset": "0"])
        let (e, t) = await (ex, tr)
        guard let e else { return }
        let store = Store(
            exercises: e.items.filter { $0.own != true }.map {
                CatalogExercise(id: $0.id, name: $0.name, muscle: muscleName($0.muscle), technique: String(($0.technique ?? "").prefix(300)))
            },
            trainers: (t?.items ?? []).map {
                CatalogTrainer(id: $0.userId, name: $0.name ?? "Тренер",
                               about: ([$0.price.map { "\($0) ₽" }] + ($0.directions ?? []).prefix(3).map { Optional($0) }).compactMap { $0 }.joined(separator: " · "))
            })
        if let d = try? JSONEncoder().encode(store) { try? d.write(to: url, options: .atomic) }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "catalog_at")
        await SpotlightIndex.update(store.exercises, store.trainers)
    }

    /// Поиск упражнений по словам (русские корни)
    static func search(_ words: [String], limit: Int = 12) -> [CatalogExercise] {
        let all = exercises
        guard !words.isEmpty else { return [] }
        return Array(all.filter { e in
            let hay = (e.name + " " + e.technique).lowercased()
            return words.contains { hay.contains($0) }
        }.prefix(limit))
    }
}

// MARK: - Поиск iPhone (Spotlight)

enum SpotlightIndex {
    static func update(_ ex: [CatalogExercise], _ tr: [CatalogTrainer]) async {
        var items: [CSSearchableItem] = []
        for e in ex {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = e.name
            a.contentDescription = [e.muscle, e.technique].filter { !$0.isEmpty }.joined(separator: " · ")
            a.keywords = ["упражнение", "тренировка", e.muscle, "oxion"]
            items.append(CSSearchableItem(uniqueIdentifier: "exercise:\(e.id)", domainIdentifier: "exercises", attributeSet: a))
        }
        for t in tr {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = t.name
            a.contentDescription = "Тренер OXION" + (t.about.isEmpty ? "" : " · " + t.about)
            a.keywords = ["тренер", "персональный тренер", "oxion"]
            items.append(CSSearchableItem(uniqueIdentifier: "trainer:\(t.id)", domainIdentifier: "trainers", attributeSet: a))
        }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: ["exercises", "trainers"])
        try? await index.indexSearchableItems(items)
    }

    /// Нажатие на результат в поиске iPhone → маршрут внутри OXION
    static func route(for activity: NSUserActivity) -> String? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        let p = id.split(separator: ":").map(String.init)
        guard p.count == 2 else { return nil }
        return p[0] == "trainer" ? "trainer/\(p[1])" : "exercise/\(p[1])"
    }

    static func clear() {
        CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: nil)
    }
}

// MARK: - Визуальный поиск (Visual Intelligence): навёл камеру на тренажёр — увидел упражнения OXION

struct ExerciseEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Упражнение"
    static var defaultQuery = ExerciseEntityQuery()

    var id: Int
    var name: String
    var muscle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(muscle)", image: .init(systemName: "dumbbell.fill"))
    }

    init(_ e: CatalogExercise) {
        id = e.id
        name = e.name
        muscle = e.muscle
    }
}

struct ExerciseEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [ExerciseEntity] {
        Catalog.exercises.filter { identifiers.contains($0.id) }.map(ExerciseEntity.init)
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        Array(Catalog.exercises.prefix(10)).map(ExerciseEntity.init)
    }
}

/// Visual Intelligence присылает английские подписи предметов — переводим их в слова для поиска упражнений
struct ExerciseVisualQuery: IntentValueQuery {
    static let map: [(en: [String], ru: [String])] = [
        (["dumbbell"], ["гантел"]),
        (["barbell", "weight plate", "squat rack", "power rack"], ["штанг", "присед", "становая", "жим"]),
        (["kettlebell"], ["гир"]),
        (["treadmill", "running"], ["бег", "дорожк"]),
        (["bench", "weight bench"], ["скамь", "лёжа", "лежа"]),
        (["exercise bike", "stationary bicycle", "bicycle"], ["велотренаж", "вело"]),
        (["pull-up", "pull up", "horizontal bar", "chin-up"], ["подтяг", "турник"]),
        (["rowing machine", "rower"], ["гребл", "тяга"]),
        (["cable", "pulley", "lat pulldown"], ["блок", "кроссовер", "тяга верхнего"]),
        (["exercise machine", "weight machine", "gym", "fitness equipment"], ["тренажёр", "тренажер", "блок"]),
        (["yoga mat", "mat"], ["планк", "скруч", "пресс"]),
        (["jump rope", "skipping rope"], ["скакал"]),
        (["medicine ball", "ball"], ["мяч"]),
        (["parallel bars", "dip"], ["брусь", "отжим"]),
        (["push-up", "push up"], ["отжим"])
    ]

    func values(for input: SemanticContentDescriptor) async throws -> [ExerciseEntity] {
        let labels = input.labels.map { $0.lowercased() }
        var words: [String] = []
        for (en, ru) in Self.map where en.contains(where: { k in labels.contains { $0.contains(k) } }) {
            words += ru
        }
        return Catalog.search(words, limit: 15).map(ExerciseEntity.init)
    }
}

struct OpenExerciseIntent: OpenIntent {
    static var title: LocalizedStringResource = "Открыть упражнение"

    @Parameter(title: "Упражнение")
    var target: ExerciseEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("exercise/\(target.id)")
        return .result()
    }
}

// MARK: - Команды для кнопки действия (iPhone 15 Pro и новее) и Siri

struct OpenRepCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Счёт повторов камерой"
    static var description = IntentDescription("Открывает камеру OXION, которая считает повторы")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("vision")
        return .result()
    }
}

struct StartRunIntent: AppIntent {
    static var title: LocalizedStringResource = "Начать пробежку"
    static var description = IntentDescription("Открывает пробежку OXION с картой и темпом")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.go("run")
        return .result()
    }
}

/// Открывает упражнение по id (из поиска iPhone, визуального поиска, ссылок)
struct ExerciseSheet: View {
    let id: Int
    @State private var e: Exercise?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let e { ExerciseDetailView(e: e) }
                else if failed { ContentUnavailableView("Упражнение не найдено", systemImage: "dumbbell") }
                else { ProgressView() }
            }
        }
        .task {
            if let r: ExercisesResponse = try? await API.call("/exercises"), let x = r.items.first(where: { $0.id == id }) {
                e = x
            } else {
                failed = true
            }
        }
    }
}
