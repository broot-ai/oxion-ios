import SwiftUI
import VisionKit
import PhotosUI

// Умный сканер еды: этикетка или фото блюда → ИИ говорит, можно ли это мне сейчас (с учётом тренировки и цели),
// продукты складываются в «тарелку», сумма записывается в дневник питания. Тренер видит питание только своих клиентов.

// MARK: - Модели

struct FoodMacros: Codable, Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0

    static func + (a: FoodMacros, b: FoodMacros) -> FoodMacros {
        FoodMacros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs)
    }
    func scaled(_ k: Double) -> FoodMacros { FoodMacros(kcal: kcal * k, protein: protein * k, fat: fat * k, carbs: carbs * k) }
}

struct FoodAnalysis: Decodable {
    let title: String
    let per100: FoodMacros?
    let grams: Double?
    let total: FoodMacros?
    let verdict: String
    let reason: String?
    let tip: String?
}

struct FoodEntry: Decodable, Identifiable {
    let id: Int
    let meal: String?
    let title: String?
    let grams: Double?
    let kcal: Double?
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let verdict: String?
    let reason: String?
    let source: String?
}

struct FoodDayResponse: Decodable {
    struct Target: Decodable { let kcal: Double; let protein: Double; let fat: Double; let carbs: Double }
    struct Totals: Decodable { let kcal: Double; let protein: Double; let fat: Double; let carbs: Double }
    struct WorkoutInfo: Decodable { let title: String?; let groups: [String]?; let done: Bool?; let calories: Int? }
    struct Client: Decodable { let id: Int; let name: String? }
    let day: String
    let items: [FoodEntry]
    let totals: Totals
    let target: Target
    let workout: WorkoutInfo?
    let client: Client?
}

struct FoodShare: Decodable {
    struct T: Decodable, Identifiable { let id: Int; let name: String?; let photo: String? }
    let on: Bool
    let trainers: [T]
}

/// Продукт в «тарелке» до записи в дневник
struct PlateItem: Identifiable {
    let id = UUID()
    var title: String
    var per100: FoodMacros?      // если знаем на 100 г — порцию можно менять
    var fixed: FoodMacros?       // если ИИ оценил всю порцию (фото блюда)
    var grams: Double
    var baseGrams: Double
    var verdict: String?
    var reason: String?
    var tip: String?
    var source: String
    var photo: UIImage?

    var macros: FoodMacros {
        if let per100 { return per100.scaled(grams / 100) }
        if let fixed { return fixed.scaled(baseGrams > 0 ? grams / baseGrams : 1) }
        return FoodMacros()
    }
}

enum FoodVerdict {
    static func icon(_ v: String?) -> String {
        switch v {
        case "ok": "checkmark.circle.fill"
        case "avoid": "xmark.octagon.fill"
        case "limit": "exclamationmark.triangle.fill"
        default: "questionmark.circle"
        }
    }
    static func color(_ v: String?) -> Color {
        switch v {
        case "ok": Color(hex: 0x58C770)
        case "avoid": Color(hex: 0xFF5A4E)
        case "limit": Color(hex: 0xF0A030)
        default: Color.oxHint
        }
    }
    static func title(_ v: String?) -> String {
        switch v {
        case "ok": "Можно"
        case "avoid": "Лучше не сегодня"
        case "limit": "В меру"
        default: "Без оценки"
        }
    }
}

enum FoodMeal: String, CaseIterable {
    case breakfast, lunch, dinner, snack
    var title: String {
        switch self { case .breakfast: "Завтрак"; case .lunch: "Обед"; case .dinner: "Ужин"; case .snack: "Перекус" }
    }
    var icon: String {
        switch self { case .breakfast: "sunrise.fill"; case .lunch: "sun.max.fill"; case .dinner: "moon.stars.fill"; case .snack: "carrot.fill" }
    }
    static var now: FoodMeal {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? .breakfast : h < 16 ? .lunch : h < 21 ? .dinner : .snack
    }
}

private func fmt(_ v: Double) -> String { String(Int(v.rounded())) }

private func jpegB64(_ img: UIImage, max side: CGFloat = 1024) -> String? {
    let s = img.size
    let k = min(1, side / max(s.width, s.height))
    let size = CGSize(width: s.width * k, height: s.height * k)
    let r = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    return r.jpegData(compressionQuality: 0.72)?.base64EncodedString()
}

// MARK: - Сканер

struct LabelScannerView: View {
    enum Mode: String, CaseIterable { case label = "Этикетка", dish = "Фото блюда" }

    @State private var mode: Mode = .label
    @State private var text = ""
    @State private var n = Nutrition()
    @State private var frozen = false
    @State private var handle = ScannerHandle()
    @State private var plate: [PlateItem] = []
    @State private var busy = false
    @State private var pick: PhotosPickerItem?
    @State private var meal: FoodMeal = .now
    @State private var day: FoodDayResponse?
    @State private var saving = false
    @State private var openDiary = false

    private var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    private var sum: FoodMacros { plate.reduce(FoodMacros()) { $0 + $1.macros } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                camera
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                actions

                if mode == .label && !n.isEmpty {
                    labelPreview
                }

                if !plate.isEmpty { plateBlock } else { emptyHint }
            }
            .padding(16)
            .padding(.bottom, plate.isEmpty ? 20 : 110)
        }
        .background(Color.oxBg)
        .overlay(alignment: .bottom) { if !plate.isEmpty { saveBar } }
        .navigationTitle("Сканер еды")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { openDiary = true } label: { Image(systemName: "fork.knife.circle") }
            }
        }
        .navigationDestination(isPresented: $openDiary) { FoodDiaryView() }
        .task { day = try? await API.call("/food") }
        .onChange(of: pick) {
            guard let pick else { return }
            Task {
                if let d = try? await pick.loadTransferable(type: Data.self), let img = UIImage(data: d) { await analyze(image: img, text: nil) }
                self.pick = nil
            }
        }
        .animation(.spring(duration: 0.4), value: plate.count)
    }

    // камера
    private var camera: some View {
        ZStack {
            if supported {
                ScannerRepresentable(frozen: frozen, handle: handle) { t in
                    guard mode == .label else { return }
                    text = t
                    let p = Nutrition.parse(t)
                    if !p.isEmpty && p != n { n = p; OxHaptics.play(.select) }
                }
            } else {
                ContentUnavailableView("Камера недоступна", systemImage: "camera", description: Text("Можно выбрать фото из галереи"))
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .bottom) {
            Text(hint)
                .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule).padding(10)
        }
        .overlay {
            if busy {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.black.opacity(0.45))
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(Color.lime)
                        Text("ИИ оценивает…").font(.subheadline.bold()).foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var hint: String {
        if mode == .dish { return "Наведите на тарелку и нажмите «Снять»" }
        return n.isEmpty ? "Наведите на «Пищевая ценность на 100 г»" : "Состав найден — проверьте ИИ"
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    let img = await handle.photo()
                    if mode == .label {
                        await analyze(image: img, text: text.isEmpty ? nil : text)
                    } else if let img {
                        await analyze(image: img, text: nil)
                    } else {
                        OxAlert.error("Не получилось сделать снимок")
                    }
                }
            } label: {
                Label(mode == .label ? "Проверить ИИ" : "Снять и оценить", systemImage: mode == .label ? "sparkles" : "camera.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .disabled(busy || (mode == .label && n.isEmpty && text.count < 20))

            PhotosPicker(selection: $pick, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.headline).frame(width: 30).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .disabled(busy)
        }
        .controlSize(.large)
    }

    // что прочитали с этикетки
    private var labelPreview: some View {
        HStack(spacing: 0) {
            mini("\(Int(n.kcal ?? 0))", "ккал")
            mini(String(format: "%.0f", n.protein ?? 0), "белки")
            mini(String(format: "%.0f", n.fat ?? 0), "жиры")
            mini(String(format: "%.0f", n.carbs ?? 0), "углев.")
            Button {
                plate.append(PlateItem(title: "Продукт с этикетки", per100: FoodMacros(kcal: n.kcal ?? 0, protein: n.protein ?? 0, fat: n.fat ?? 0, carbs: n.carbs ?? 0),
                                       fixed: nil, grams: 100, baseGrams: 100, verdict: nil, reason: nil, tip: nil, source: "label"))
                Haptic.tap()
            } label: { Image(systemName: "plus") }
                .buttonStyle(.glass)
        }
        .padding(12)
        .oxCardBG(20)
        .overlay(alignment: .topLeading) {
            Text("НА 100 Г").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.oxHint).padding(.leading, 14).padding(.top, 5)
        }
    }

    private func mini(_ v: String, _ t: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.headline.monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(Color.oxHint)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Как это работает", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Color.lime)
            Text("Сканируйте этикетку или сфотографируйте блюдо. ИИ скажет, подходит ли это вам сейчас — с учётом сегодняшней тренировки, цели и того, что вы уже съели. Можно добавить несколько продуктов: калории сложатся.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let d = day {
                Divider()
                HStack {
                    Text("Сегодня съедено").font(.subheadline)
                    Spacer()
                    Text("\(fmt(d.totals.kcal)) / \(fmt(d.target.kcal)) ккал").font(.subheadline.bold().monospacedDigit())
                }
                if let w = d.workout {
                    Label("\(w.title ?? "Тренировка") · \(w.done == true ? "выполнена" : "впереди")", systemImage: "dumbbell.fill")
                        .font(.caption).foregroundStyle(Color.oxHint)
                }
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    // тарелка
    private var plateBlock: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Тарелка").font(.title3.bold())
                Spacer()
                Button("Очистить", role: .destructive) { plate.removeAll() }.font(.subheadline)
            }
            ForEach($plate) { $item in
                PlateCard(item: $item) { plate.removeAll { $0.id == item.id } }
            }
            totalsCard
        }
    }

    private var totalsCard: some View {
        let s = sum
        let left = day.map { $0.target.kcal - $0.totals.kcal }
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Итого").font(.headline)
                Spacer()
                Text("\(fmt(s.kcal)) ккал").font(.title2.bold().monospacedDigit()).foregroundStyle(Color.lime)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 0) {
                mini(fmt(s.protein), "белки, г")
                mini(fmt(s.fat), "жиры, г")
                mini(fmt(s.carbs), "углев., г")
            }
            if let left {
                let after = left - s.kcal
                Text(after >= 0 ? "После этого останется \(fmt(after)) ккал на сегодня" : "Это на \(fmt(-after)) ккал больше дневной нормы")
                    .font(.caption.bold())
                    .foregroundStyle(after >= 0 ? Color.oxHint : Color(hex: 0xFF5A4E))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $meal) {
                ForEach(FoodMeal.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if saving { ProgressView().tint(Color.onLime) }
                    Text("Записать в дневник · \(fmt(sum.kcal)) ккал").font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.lime)
            .foregroundStyle(Color.onLime)
            .controlSize(.large)
            .disabled(saving)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: действия

    private func analyze(image: UIImage?, text: String?) async {
        guard !busy else { return }
        busy = true
        frozen = true
        defer { busy = false; frozen = false }
        var b: [String: Any] = [:]
        if let text { b["text"] = text }
        if let image, let s = jpegB64(image) { b["image"] = s }
        do {
            let r: FoodAnalysis = try await API.call("/food/analyze", method: "POST", body: b)
            let grams = r.grams ?? 100
            let item = PlateItem(title: r.title, per100: r.per100, fixed: r.per100 == nil ? r.total : nil,
                                 grams: grams, baseGrams: grams, verdict: r.verdict, reason: r.reason, tip: r.tip,
                                 source: text != nil ? "label" : "photo", photo: image)
            plate.append(item)
            n = Nutrition()
            switch r.verdict {
            case "ok": Haptic.success()
            case "avoid": OxHaptics.play(.restOver)
            default: Haptic.tap(.medium)
            }
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let items: [[String: Any]] = plate.map { p in
            let m = p.macros
            return ["title": p.title, "grams": p.grams, "kcal": m.kcal, "protein": m.protein, "fat": m.fat, "carbs": m.carbs,
                    "verdict": p.verdict ?? "", "reason": p.reason ?? "", "source": p.source, "meal": meal.rawValue]
        }
        do {
            let d: FoodDayResponse = try await API.call("/food", method: "POST", body: ["items": items])
            day = d
            plate.removeAll()
            Haptic.success()
            OxAlert.show(icon: "checkmark.circle.fill", tint: .green, title: "Записано", message: "Сегодня: \(fmt(d.totals.kcal)) из \(fmt(d.target.kcal)) ккал")
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

private struct PlateCard: View {
    @Binding var item: PlateItem
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let p = item.photo {
                    Image(uiImage: p).resizable().scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: item.source == "label" ? "barcode.viewfinder" : "fork.knife")
                        .font(.title3).foregroundStyle(Color.lime)
                        .frame(width: 54, height: 54)
                        .background(Color.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Название", text: $item.title).font(.headline)
                    Label(FoodVerdict.title(item.verdict), systemImage: FoodVerdict.icon(item.verdict))
                        .font(.caption.bold())
                        .foregroundStyle(FoodVerdict.color(item.verdict))
                }
                Spacer(minLength: 0)
                Button(role: .destructive, action: remove) { Image(systemName: "xmark") }
                    .buttonStyle(.glass).controlSize(.small)
            }
            if let r = item.reason, !r.isEmpty {
                Text(r).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let t = item.tip, !t.isEmpty {
                Label(t, systemImage: "lightbulb").font(.caption).foregroundStyle(Color.lime)
            }
            HStack {
                Text("\(Int(item.grams)) г").font(.subheadline.bold().monospacedDigit()).frame(width: 64, alignment: .leading)
                Slider(value: $item.grams, in: 5...max(800, item.baseGrams * 2), step: 5).tint(Color.lime)
            }
            let m = item.macros
            HStack(spacing: 14) {
                Text("\(fmt(m.kcal)) ккал").bold().foregroundStyle(Color.lime)
                Text("Б \(fmt(m.protein))")
                Text("Ж \(fmt(m.fat))")
                Text("У \(fmt(m.carbs))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(FoodVerdict.color(item.verdict).opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .oxCardBG(22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(FoodVerdict.color(item.verdict).opacity(0.35), lineWidth: 1))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Дневник питания (свой или клиента — для тренера)

struct FoodDiaryView: View {
    var clientId: Int? = nil
    var clientName: String? = nil

    @State private var date = Date()
    @State private var data: FoodDayResponse?
    @State private var errorText: String?
    @State private var share: FoodShare?
    @State private var scan = false

    private var own: Bool { clientId == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                dayBar
                if let d = data {
                    summary(d)
                    if let w = d.workout {
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell.fill").foregroundStyle(Color.lime)
                            Text(w.title ?? "Тренировка").font(.subheadline.bold())
                            Spacer()
                            Text(w.done == true ? "выполнена" : "в плане").font(.caption).foregroundStyle(Color.oxHint)
                            if let c = w.calories, c > 0 { Text("−\(c) ккал").font(.caption.bold()).foregroundStyle(.orange) }
                        }
                        .padding(14)
                        .oxCardBG(20)
                    }
                    ForEach(FoodMeal.allCases, id: \.self) { m in
                        let list = d.items.filter { ($0.meal ?? "snack") == m.rawValue }
                        if !list.isEmpty { mealBlock(m, list) }
                    }
                    if d.items.isEmpty {
                        ContentUnavailableView(own ? "Пока ничего не записано" : "Клиент ничего не записал",
                                               systemImage: "fork.knife",
                                               description: Text(own ? "Отсканируйте этикетку или сфотографируйте блюдо" : "Записи появятся, когда клиент отсканирует еду"))
                    }
                    if own { shareBlock }
                } else {
                    LoadingOrError(error: errorText) { Task { await load() } }
                }
            }
            .padding(16)
        }
        .background(Color.oxBg)
        .navigationTitle(own ? "Питание" : "Питание · \(clientName ?? "клиент")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if own {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { scan = true } label: { Image(systemName: "text.viewfinder") }
                }
            }
        }
        .navigationDestination(isPresented: $scan) { LabelScannerView() }
        .oxRefreshable { await load() }
        .task(id: RU.dayFormatter.string(from: date)) { await load() }
        .task { if own { share = try? await API.call("/food/share") } }
    }

    private var dayBar: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass)
            Spacer()
            Text(RU.human(RU.dayFormatter.string(from: date))).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass)
                .disabled(Calendar.current.isDateInToday(date))
        }
    }

    private func shift(_ d: Int) {
        date = Calendar.current.date(byAdding: .day, value: d, to: date) ?? date
        data = nil
        Haptic.tap()
    }

    private func summary(_ d: FoodDayResponse) -> some View {
        let p = min(1, d.totals.kcal / max(1, d.target.kcal))
        let over = d.totals.kcal > d.target.kcal
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.lime.opacity(0.15), lineWidth: 12)
                Circle().trim(from: 0, to: p)
                    .stroke(over ? Color(hex: 0xFF5A4E) : Color.lime, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(fmt(d.totals.kcal)).font(.title2.bold().monospacedDigit())
                    Text("из \(fmt(d.target.kcal))").font(.caption2).foregroundStyle(Color.oxHint)
                }
            }
            .frame(width: 108, height: 108)
            VStack(spacing: 10) {
                bar("Белки", d.totals.protein, d.target.protein, Color(hex: 0x3FD6C9))
                bar("Жиры", d.totals.fat, d.target.fat, Color(hex: 0xF0A030))
                bar("Углеводы", d.totals.carbs, d.target.carbs, Color(hex: 0x8E7CFF))
            }
        }
        .padding(16)
        .oxCardBG(24)
    }

    private func bar(_ t: String, _ v: Double, _ goal: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t).font(.caption)
                Spacer()
                Text("\(fmt(v)) / \(fmt(goal)) г").font(.caption.monospacedDigit()).foregroundStyle(Color.oxHint)
            }
            ProgressView(value: min(v, goal), total: max(1, goal)).tint(c)
        }
    }

    private func mealBlock(_ m: FoodMeal, _ list: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(m.title, systemImage: m.icon).font(.headline)
                Spacer()
                Text("\(fmt(list.reduce(0) { $0 + ($1.kcal ?? 0) })) ккал").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Color.lime)
            }
            .padding(.bottom, 8)
            ForEach(list) { e in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: FoodVerdict.icon(e.verdict)).foregroundStyle(FoodVerdict.color(e.verdict))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title ?? "Продукт").font(.subheadline.bold())
                        Text("\(fmt(e.grams ?? 0)) г · Б \(fmt(e.protein ?? 0)) Ж \(fmt(e.fat ?? 0)) У \(fmt(e.carbs ?? 0))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.oxHint)
                        if let r = e.reason, !r.isEmpty, !own {
                            Text(r).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(fmt(e.kcal ?? 0)).font(.subheadline.monospacedDigit())
                    if own {
                        Menu {
                            Button("Удалить", systemImage: "trash", role: .destructive) { Task { await delete(e) } }
                        } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                            .foregroundStyle(Color.oxHint)
                    }
                }
                .padding(.vertical, 8)
                if e.id != list.last?.id { Divider() }
            }
        }
        .padding(16)
        .oxCardBG(22)
    }

    private var shareBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { share?.on ?? true }, set: { v in Task { await setShare(v) } })) {
                Label("Тренер видит моё питание", systemImage: "person.badge.shield.checkmark.fill")
            }
            .tint(Color.lime)
            let names = (share?.trainers ?? []).compactMap(\.name)
            Text(names.isEmpty
                 ? "Сейчас у вас нет подключённого тренера — питание не видит никто."
                 : "Видит только ваш тренер: \(names.joined(separator: ", ")). Другие пользователи не видят никогда.")
                .font(.caption).foregroundStyle(Color.oxHint)
        }
        .padding(16)
        .oxCardBG(22)
    }

    private func load() async {
        let q = ["day": RU.dayFormatter.string(from: date)]
        do {
            if let clientId {
                data = try await API.call("/coach/clients/\(clientId)/food", query: q)
            } else {
                data = try await API.call("/food", query: q)
            }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func delete(_ e: FoodEntry) async {
        do {
            let _: OK = try await API.call("/food/\(e.id)", method: "DELETE")
            await load()
        } catch { OxAlert.error(error.localizedDescription) }
    }

    private func setShare(_ on: Bool) async {
        share = try? await API.call("/food/share", method: "PUT", body: ["on": on])
        Haptic.tap()
    }
}
