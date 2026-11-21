import SwiftUI

// OXION BODY 3D — единый справочник мышц.
// Постоянные идентификаторы: «<мышца>_<сторона>», сторона: l — левая, r — правая (сторона самого человека).
// По этим же именам ищутся объекты во внешней USDZ-модели, поэтому их нельзя переименовывать.

enum BodySide: String, CaseIterable, Codable {
    case l, r
    var title: String { self == .l ? "Левая" : "Правая" }
    var short: String { self == .l ? "Л" : "П" }
}

/// Идентификатор конкретного объекта на модели: мышца + сторона
struct MusclePartID: Hashable, Codable, Identifiable, Comparable {
    let muscle: String
    let side: BodySide
    var id: String { muscle + "_" + side.rawValue }

    init(muscle: String, side: BodySide) { self.muscle = muscle; self.side = side }
    /// «chest_upper_l» → (chest_upper, l)
    init?(_ raw: String) {
        guard raw.count > 2, let last = raw.split(separator: "_").last, let s = BodySide(rawValue: String(last)) else { return nil }
        let m = String(raw.dropLast(2))
        guard MuscleDataManager.byId[m] != nil else { return nil }
        muscle = m; side = s
    }
    static func < (a: Self, b: Self) -> Bool { a.id < b.id }
    var mirror: MusclePartID { MusclePartID(muscle: muscle, side: side == .l ? .r : .l) }
}

struct MuscleInfo: Identifiable, Hashable {
    let id: String              // постоянный ID мышцы без стороны
    let name: String
    let region: String          // раздел справочника
    let group: String           // ключ группы на сервере OXION (chest, back, …) — для упражнений и статистики
    let about: String
    let functions: [String]
    let keywords: [String]      // слова в названии упражнений, которые нагружают именно эту часть
    let related: [String]
    let backSide: Bool          // лучше видно со спины
}

enum MuscleDataManager {
    static let regions = ["Грудь", "Плечи", "Спина", "Руки", "Пресс", "Ягодицы", "Ноги"]

    static let all: [MuscleInfo] = [
        .init(id: "chest_upper", name: "Верх груди", region: "Грудь", group: "chest",
              about: "Ключичная часть большой грудной мышцы. Идёт от ключицы к плечевой кости и формирует верх груди.",
              functions: ["Поднимает руку вперёд и вверх", "Сводит руки перед собой"],
              keywords: ["наклон", "инклайн", "верх"], related: ["chest_mid", "delt_front"], backSide: false),
        .init(id: "chest_mid", name: "Середина груди", region: "Грудь", group: "chest",
              about: "Грудино-рёберная часть большой грудной мышцы — основной объём груди.",
              functions: ["Приводит руку к корпусу", "Сводит руки перед собой", "Поворачивает плечо внутрь"],
              keywords: ["жим лёжа", "жим лежа", "сведен", "бабочк", "отжим"], related: ["chest_upper", "chest_lower", "triceps"], backSide: false),
        .init(id: "chest_lower", name: "Низ груди", region: "Грудь", group: "chest",
              about: "Брюшная часть большой грудной мышцы, нижний край груди.",
              functions: ["Опускает поднятую руку вниз и к корпусу"],
              keywords: ["брусь", "отрицательн", "кроссовер", "низ"], related: ["chest_mid", "triceps"], backSide: false),
        .init(id: "delt_front", name: "Передняя дельта", region: "Плечи", group: "shoulders",
              about: "Передний пучок дельтовидной мышцы, начинается от ключицы.",
              functions: ["Поднимает руку вперёд", "Помогает в жимах"],
              keywords: ["перед", "армейск", "жим стоя", "жим сидя", "жим гантел"], related: ["chest_upper", "delt_mid"], backSide: false),
        .init(id: "delt_mid", name: "Средняя дельта", region: "Плечи", group: "shoulders",
              about: "Средний пучок дельтовидной мышцы — даёт ширину плеч.",
              functions: ["Отводит руку в сторону"],
              keywords: ["в стороны", "махи", "разведен", "протяжк"], related: ["delt_front", "delt_rear", "traps"], backSide: false),
        .init(id: "delt_rear", name: "Задняя дельта", region: "Плечи", group: "shoulders",
              about: "Задний пучок дельтовидной мышцы, начинается от лопатки.",
              functions: ["Отводит руку назад", "Поворачивает плечо наружу"],
              keywords: ["задн", "в наклоне", "фейс", "обратн"], related: ["rhomboids", "traps", "delt_mid"], backSide: true),
        .init(id: "lats", name: "Широчайшие", region: "Спина", group: "back",
              about: "Самые большие мышцы спины: от поясницы и нижних рёбер к плечевой кости. Дают V-силуэт.",
              functions: ["Тянет руку вниз и назад", "Приводит руку к корпусу"],
              keywords: ["подтяг", "тяга верхн", "пуловер", "тяга штанги", "тяга гантел"], related: ["rhomboids", "biceps", "delt_rear"], backSide: true),
        .init(id: "traps", name: "Трапеции", region: "Спина", group: "back",
              about: "Трапециевидная мышца: от затылка до середины спины, держит и двигает лопатки.",
              functions: ["Поднимает плечи", "Сводит лопатки", "Опускает лопатки"],
              keywords: ["шраг", "протяжк", "тяга"], related: ["rhomboids", "delt_rear"], backSide: true),
        .init(id: "rhomboids", name: "Ромбовидные", region: "Спина", group: "back",
              about: "Лежат под трапецией между лопатками и позвоночником.",
              functions: ["Сводят лопатки", "Удерживают лопатки прижатыми"],
              keywords: ["тяга", "сведение лопаток", "горизонтальн"], related: ["traps", "lats", "delt_rear"], backSide: true),
        .init(id: "biceps", name: "Бицепс", region: "Руки", group: "biceps",
              about: "Двуглавая мышца плеча на передней стороне руки.",
              functions: ["Сгибает руку в локте", "Разворачивает ладонь вверх"],
              keywords: ["бицепс", "сгибан", "молот", "подъём", "подъем"], related: ["forearms", "lats"], backSide: false),
        .init(id: "triceps", name: "Трицепс", region: "Руки", group: "triceps",
              about: "Трёхглавая мышца на задней стороне плеча — около двух третей объёма руки.",
              functions: ["Разгибает руку в локте", "Помогает в жимах"],
              keywords: ["трицепс", "разгибан", "французск", "узк", "брусь"], related: ["chest_mid", "delt_front"], backSide: true),
        .init(id: "forearms", name: "Предплечья", region: "Руки", group: "biceps",
              about: "Группа мышц между локтем и кистью: сгибатели и разгибатели запястья и пальцев.",
              functions: ["Сжимают кисть (хват)", "Сгибают и разгибают запястье"],
              keywords: ["запяст", "молот", "хват", "вис", "фермер"], related: ["biceps"], backSide: false),
        .init(id: "abs_rectus", name: "Прямая мышца живота", region: "Пресс", group: "abs",
              about: "Те самые «кубики»: от рёбер до лобковой кости.",
              functions: ["Сгибает корпус вперёд", "Удерживает таз и поясницу"],
              keywords: ["скручиван", "планк", "подъём ног", "подъем ног", "пресс"], related: ["obliques"], backSide: false),
        .init(id: "obliques", name: "Косые мышцы живота", region: "Пресс", group: "abs",
              about: "Наружные и внутренние косые мышцы по бокам живота.",
              functions: ["Поворачивают корпус", "Наклоняют корпус в сторону"],
              keywords: ["косы", "боков", "русск", "вращ"], related: ["abs_rectus", "lats"], backSide: false),
        .init(id: "glute_max", name: "Большая ягодичная", region: "Ягодицы", group: "glutes",
              about: "Самая крупная мышца тела, формирует форму ягодиц.",
              functions: ["Разгибает бедро", "Выпрямляет таз при вставании"],
              keywords: ["мост", "ягод", "выпад", "присед", "тяга"], related: ["hamstrings", "glute_med"], backSide: true),
        .init(id: "glute_med", name: "Средняя ягодичная", region: "Ягодицы", group: "glutes",
              about: "Лежит сверху и сбоку таза, стабилизирует его при ходьбе.",
              functions: ["Отводит ногу в сторону", "Держит таз ровно на одной ноге"],
              keywords: ["отведен", "боков", "в сторону", "кламшел"], related: ["glute_max", "obliques"], backSide: true),
        .init(id: "quads", name: "Квадрицепс", region: "Ноги", group: "legs",
              about: "Четырёхглавая мышца на передней поверхности бедра.",
              functions: ["Разгибает ногу в колене", "Помогает сгибать бедро"],
              keywords: ["присед", "жим ног", "разгибан", "выпад"], related: ["glute_max", "hamstrings"], backSide: false),
        .init(id: "hamstrings", name: "Бицепс бедра", region: "Ноги", group: "legs",
              about: "Группа мышц задней поверхности бедра.",
              functions: ["Сгибает ногу в колене", "Разгибает бедро"],
              keywords: ["румынск", "сгибан ног", "становая", "мёртв", "мертв"], related: ["glute_max", "calves"], backSide: true),
        .init(id: "calves", name: "Икроножные", region: "Ноги", group: "legs",
              about: "Икроножная мышца — верхняя, видимая часть голени сзади.",
              functions: ["Поднимает на носки при прямой ноге", "Помогает сгибать колено"],
              keywords: ["икр", "носк", "стоя"], related: ["soleus", "hamstrings"], backSide: true),
        .init(id: "soleus", name: "Камбаловидные", region: "Ноги", group: "legs",
              about: "Лежит под икроножной, лучше видна внизу голени и по бокам.",
              functions: ["Поднимает на носки при согнутом колене", "Держит равновесие стоя"],
              keywords: ["сидя", "икр", "носк"], related: ["calves"], backSide: true),
    ]

    static let byId: [String: MuscleInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func info(_ id: String) -> MuscleInfo? { byId[id] }
    static func name(_ p: MusclePartID) -> String { (byId[p.muscle]?.name ?? p.muscle) }
    static func fullName(_ p: MusclePartID) -> String { name(p) + " · " + (p.side == .l ? "левая" : "правая") }

    /// Ключи групп сервера по выбранным частям — для тренировки
    static func groups(of parts: Set<MusclePartID>) -> [String] {
        let keys = Set(parts.compactMap { byId[$0.muscle]?.group })
        return ["chest", "back", "shoulders", "biceps", "triceps", "abs", "glutes", "legs"].filter { keys.contains($0) }
    }
}
