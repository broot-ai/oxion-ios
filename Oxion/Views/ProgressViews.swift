import SwiftUI
import PhotosUI
import Charts
import Photos

// MARK: - OXION Progress: история изменений тела

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct StatsRange: Decodable {
    let workouts: Int?
    let sets: Int?
    let calories: Int?
    let weights: [WeightPoint]?
}

struct ProgressHubView: View {
    @State private var store = ProgressStore.shared
    @State private var weights: [WeightPoint] = []
    @State private var workouts: [Workout] = []
    @State private var records: [RecordItem] = []
    @State private var compareDays = 30
    @State private var cur: StatsRange?
    @State private var prev: StatsRange?
    @State private var measureKey: MeasureKey = .waist

    @State private var addPhoto = false
    @State private var addMeasure = false
    @State private var addWeight = false
    @State private var replay = false
    @State private var compare = false
    @State private var privacy = false
    @State private var openPhoto: ProgressPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                replayCard
                photosSection
                weightSection
                measureSection
                workoutsSection
                compareSection
                recordsSection
            }
            .padding(.vertical, 12)
        }
        .background(Color.oxBg)
        .navigationTitle("Прогресс")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { privacy = true } label: { Image(systemName: "lock.shield") }
            }
        }
        .sheet(isPresented: $addPhoto) { AddProgressPhotoSheet() }
        .sheet(isPresented: $addMeasure) { MeasurementSheet() }
        .sheet(isPresented: $addWeight) { WeightEntrySheet { Task { await loadWeights() } } }
        .sheet(isPresented: $replay) { ReplaySetupSheet(weights: weights, workouts: workouts) }
        .sheet(isPresented: $privacy) { ProgressPrivacySheet() }
        .fullScreenCover(isPresented: $compare) { BeforeAfterView() }
        .fullScreenCover(item: $openPhoto) { p in PhotoViewer(photo: p) }
        .task { await loadAll() }
        .task(id: compareDays) { await loadCompare() }
    }

    // MARK: Replay

    private var replayCard: some View {
        Button { replay = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.lime.opacity(0.18)).frame(width: 58, height: 58)
                    Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(Color.limeInk)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Progress Replay").font(.title3.bold())
                    Text("Фото и цифры за 30, 60, 90 дней — в одну красивую историю")
                        .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                RadialGradient(colors: [Color.lime.opacity(0.22), Color.oxCard], center: .topTrailing, startRadius: 5, endRadius: 260),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: Фото

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Фото тела", sub: "\(store.photos.count)") {
                Button { addPhoto = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass)
            }
            if store.faceLock && !store.unlocked {
                Button {
                    Task { _ = await store.unlock() }
                } label: {
                    Label("Фото закрыты Face ID — открыть", systemImage: "faceid")
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                }
                .buttonStyle(.plain)
                .oxCardBG(22)
                .padding(.horizontal, 16)
            } else if store.photos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.badge.plus").font(.largeTitle).foregroundStyle(Color.limeInk)
                    Text("Добавьте первое фото — спереди, сбоку или сзади. Фото хранятся только на этом iPhone.")
                        .font(.subheadline).foregroundStyle(Color.oxHint).multilineTextAlignment(.center)
                    Button("Добавить фото") { addPhoto = true }.buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity).padding(20)
                .oxCardBG(22)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.photos.reversed()) { p in
                            Button { openPhoto = p } label: {
                                ZStack(alignment: .bottomLeading) {
                                    if let i = store.image(p) {
                                        Image(uiImage: i).resizable().scaledToFill()
                                    } else { Color.oxCard }
                                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(p.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption.bold())
                                        Text(p.poseTitle).font(.caption2).foregroundStyle(.white.opacity(0.7))
                                    }
                                    .padding(8)
                                }
                                .frame(width: 110, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if store.photos.count >= 2 {
                    Button { compare = true } label: {
                        Label("Сравнить до и после", systemImage: "rectangle.split.2x1")
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, 16)
                }
            }
        }
        .task { if !store.faceLock { store.unlocked = true } }
    }

    // MARK: Вес

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Вес", sub: weights.last.map { "\(fmt($0.kg)) кг" } ?? "") {
                Button { addWeight = true } label: { Image(systemName: "plus") }.buttonStyle(.glass)
            }
            box {
                if weights.count < 2 {
                    Text(weights.isEmpty ? "Записей веса пока нет. Нажмите «+»." : "Нужно хотя бы две записи, чтобы построить график.")
                        .font(.subheadline).foregroundStyle(Color.oxHint)
                } else {
                    let pts = weights.compactMap { w in RU.dayFormatter.date(from: w.date).map { ChartPoint(date: $0, value: w.kg) } }
                    let lo = (pts.map { $0.value }.min() ?? 0) - 1, hi = (pts.map { $0.value }.max() ?? 0) + 1
                    Chart(pts) { p in
                        AreaMark(x: .value("Дата", p.date), yStart: .value("", lo), yEnd: .value("Вес", p.value))
                            .foregroundStyle(LinearGradient(colors: [Color.lime.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Дата", p.date), y: .value("Вес", p.value))
                            .foregroundStyle(Color.limeInk).interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Дата", p.date), y: .value("Вес", p.value)).foregroundStyle(Color.limeInk).symbolSize(20)
                    }
                    .chartYScale(domain: lo...hi)
                    .frame(height: 170)
                    if let f = pts.first, let l = pts.last {
                        let d = l.value - f.value
                        Text("С \(f.date.formatted(.dateTime.day().month(.abbreviated))): \(d >= 0 ? "+" : "")\(fmt(d)) кг")
                            .font(.caption).foregroundStyle(Color.oxHint)
                    }
                }
            }
        }
    }

    // MARK: Замеры

    private var measureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Замеры", sub: "см") {
                Button { addMeasure = true } label: { Image(systemName: "plus") }.buttonStyle(.glass)
            }
            box {
                if store.measurements.isEmpty {
                    Text("Талия, грудь, бёдра, руки — записывайте раз в 2–4 недели, утром, на одном и том же месте.")
                        .font(.subheadline).foregroundStyle(Color.oxHint)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(MeasureKey.allCases) { k in
                            if let l = store.latest(k) {
                                Button { measureKey = k } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(k.title).font(.caption).foregroundStyle(Color.oxHint)
                                        Text(fmt(l.value)).font(.title3.bold())
                                        if let d = l.delta, d != 0 {
                                            Text("\(d > 0 ? "+" : "")\(fmt(d))").font(.caption2.bold())
                                                .foregroundStyle(d > 0 ? Color.orange : Color.lime)
                                        } else { Text(" ").font(.caption2) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(measureKey == k ? Color.lime.opacity(0.14) : Color.primary.opacity(0.04),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    let s = store.series(measureKey).map { ChartPoint(date: $0.date, value: $0.value) }
                    if s.count >= 2 {
                        Chart(s) { p in
                            LineMark(x: .value("Дата", p.date), y: .value(measureKey.title, p.value))
                                .foregroundStyle(Color.limeInk).interpolationMethod(.catmullRom)
                            PointMark(x: .value("Дата", p.date), y: .value(measureKey.title, p.value)).foregroundStyle(Color.limeInk)
                        }
                        .chartYScale(domain: ((s.map { $0.value }.min() ?? 0) - 2)...((s.map { $0.value }.max() ?? 0) + 2))
                        .frame(height: 130)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: Тренировки

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Тренировки", sub: "12 недель") { EmptyView() }
            box {
                let w = weekly()
                Chart(w) { item in
                    BarMark(x: .value("Неделя", item.date, unit: .weekOfYear), y: .value("Тренировок", item.value))
                        .foregroundStyle(Color.lime.gradient).cornerRadius(4)
                }
                .frame(height: 140)
                let total = Int(w.reduce(0) { $0 + $1.value })
                Text("Всего \(total) \(RU.plural(total, "тренировка", "тренировки", "тренировок")) · в среднем \(fmt(Double(total) / 12)) в неделю")
                    .font(.caption).foregroundStyle(Color.oxHint)
            }
        }
    }

    // MARK: Сравнение периодов

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Сравнение периодов", sub: "") { EmptyView() }
            Picker("", selection: $compareDays) {
                Text("7 дней").tag(7); Text("30 дней").tag(30); Text("90 дней").tag(90)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            box {
                VStack(spacing: 10) {
                    HStack {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Сейчас").font(.caption.bold()).frame(width: 80)
                        Text("Раньше").font(.caption.bold()).foregroundStyle(Color.oxHint).frame(width: 80)
                    }
                    cmpRow("Тренировки", cur?.workouts, prev?.workouts)
                    cmpRow("Подходы", cur?.sets, prev?.sets)
                    cmpRow("Калории", cur?.calories, prev?.calories)
                    Text("«Раньше» — такие же \(compareDays) дней до текущего периода.")
                        .font(.caption2).foregroundStyle(Color.oxHint).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func cmpRow(_ t: String, _ a: Int?, _ b: Int?) -> some View {
        HStack {
            Text(t).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Text("\(a ?? 0)").bold()
                if let a, let b, a != b {
                    Image(systemName: a > b ? "arrow.up" : "arrow.down").font(.caption2.bold())
                        .foregroundStyle(a > b ? Color.lime : Color.orange)
                }
            }
            .frame(width: 80)
            Text("\(b ?? 0)").foregroundStyle(Color.oxHint).frame(width: 80)
        }
        .font(.subheadline)
    }

    // MARK: Рекорды

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Личные рекорды", sub: "") {
                NavigationLink { RecordsView() } label: { Text("Все").font(.subheadline) }
            }
            box {
                if records.isEmpty {
                    Text("Рекорды появятся после первых тренировок в дневнике.").font(.subheadline).foregroundStyle(Color.oxHint)
                } else {
                    VStack(spacing: 10) {
                        ForEach(records.prefix(5)) { r in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(Color(hex: 0xF0A030))
                                Text(r.name).lineLimit(1)
                                Spacer()
                                Text(r.best).bold()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func header<T: View>(_ t: String, sub: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(t).font(.title3.bold())
            if !sub.isEmpty { Text(sub).foregroundStyle(Color.oxHint) }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
    }

    private func box<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .oxCardBG(22)
            .padding(.horizontal, 16)
    }

    private func weekly() -> [ChartPoint] {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<12).reversed().map { i in
            let ws = cal.date(byAdding: .weekOfYear, value: -i, to: start) ?? start
            let we = cal.date(byAdding: .day, value: 7, to: ws) ?? ws
            let n = workouts.filter { w in
                guard let d = RU.dayFormatter.date(from: w.date) else { return false }
                return d >= ws && d < we
            }.count
            return ChartPoint(date: ws, value: Double(n))
        }
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func loadAll() async {
        await loadWeights()
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -400, to: to) ?? to
        if let w: WorkoutsResponse = try? await API.call("/workouts", query: ["from": RU.dayFormatter.string(from: from), "to": RU.dayFormatter.string(from: to)]) {
            workouts = w.items
        }
        if let r: RecordsResponse = try? await API.call("/records") { records = r.items }
    }

    private func loadWeights() async {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -400, to: to) ?? to
        if let s: StatsRange = try? await API.call("/stats", query: ["from": RU.dayFormatter.string(from: from), "to": RU.dayFormatter.string(from: to)]) {
            weights = s.weights ?? []
        }
    }

    private func loadCompare() async {
        let cal = Calendar.current
        let today = Date()
        let s1 = cal.date(byAdding: .day, value: -(compareDays - 1), to: today) ?? today
        let e0 = cal.date(byAdding: .day, value: -1, to: s1) ?? s1
        let s0 = cal.date(byAdding: .day, value: -(compareDays - 1), to: e0) ?? e0
        let f = RU.dayFormatter
        async let a: StatsRange? = try? API.call("/stats", query: ["from": f.string(from: s1), "to": f.string(from: today)])
        async let b: StatsRange? = try? API.call("/stats", query: ["from": f.string(from: s0), "to": f.string(from: e0)])
        let (x, y) = await (a, b)
        cur = x
        prev = y
    }
}

// MARK: - Добавить фото

struct AddProgressPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var camera = false
    @State private var pose = "front"
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label("Камера", systemImage: "camera.fill") }
                                .buttonStyle(.glass)
                        }
                        PhotosPicker(selection: $item, matching: .images) { Label("Галерея", systemImage: "photo.on.rectangle") }
                            .buttonStyle(.glass)
                    }
                }
                .listRowBackground(Color.clear)
                Section("Ракурс") {
                    Picker("", selection: $pose) {
                        ForEach(ProgressPhoto.poses, id: \.key) { Text($0.title).tag($0.key) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    DatePicker("Дата", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("Фото сохраняется только на этом iPhone, в защищённой папке приложения. На сервер OXION оно не отправляется.")
                }
            }
            .navigationTitle("Фото прогресса")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if let image {
                            ProgressStore.shared.addPhoto(image, date: date, pose: pose)
                            OxHaptics.play(.setDone)
                            dismiss()
                        }
                    }
                    .disabled(image == nil)
                }
            }
            .onChange(of: item) {
                Task {
                    if let d = try? await item?.loadTransferable(type: Data.self), let i = UIImage(data: d) { image = i }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image = $0 }.ignoresSafeArea()
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraDevice = .rear
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let i = info[.originalImage] as? UIImage { parent.onImage(i) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Просмотр фото

struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: ProgressPhoto

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let i = ProgressStore.shared.image(photo) {
                Image(uiImage: i).resizable().scaledToFit()
            }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    VStack(spacing: 0) {
                        Text(photo.date.formatted(date: .long, time: .omitted)).font(.subheadline.bold())
                        Text(photo.poseTitle).font(.caption).foregroundStyle(.primary.opacity(0.7))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    Spacer()
                    Button {
                        OxAlert.confirm(title: "Удалить фото?", message: "Оно удалится с этого iPhone без возможности восстановления.",
                                        action: "Удалить", destructive: true) {
                            ProgressStore.shared.delete(photo)
                            dismiss()
                        }
                    } label: { Image(systemName: "trash").font(.headline).frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding()
                Spacer()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Сравнение до/после

struct BeforeAfterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProgressStore.shared
    @State private var before: ProgressPhoto?
    @State private var after: ProgressPhoto?
    @State private var split: CGFloat = 0.5
    @State private var sideBySide = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                    Spacer()
                    Text("До и после").font(.headline)
                    Spacer()
                    Button { withAnimation { sideBySide.toggle() } } label: {
                        Image(systemName: sideBySide ? "slider.horizontal.below.rectangle" : "rectangle.split.2x1").font(.headline).frame(width: 40, height: 40)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal)

                if let b = before, let a = after, let bi = store.image(b), let ai = store.image(a) {
                    if sideBySide {
                        HStack(spacing: 6) {
                            labeled(bi, b, "ДО")
                            labeled(ai, a, "ПОСЛЕ")
                        }
                        .padding(.horizontal, 8)
                    } else {
                        GeometryReader { g in
                            ZStack {
                                Image(uiImage: ai).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                                Image(uiImage: bi).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                                    .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * split) }
                                Rectangle().fill(Color.lime).frame(width: 3).position(x: g.size.width * split, y: g.size.height / 2)
                                Circle().fill(Color.lime).frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
                                    .position(x: g.size.width * split, y: g.size.height / 2)
                                VStack {
                                    HStack {
                                        tag("ДО · " + b.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                        Spacer()
                                        tag("ПОСЛЕ · " + a.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                            }
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                split = min(1, max(0, v.location.x / g.size.width))
                            })
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 8)
                    }
                    let days = Calendar.current.dateComponents([.day], from: b.date, to: a.date).day ?? 0
                    Text("Между фото \(abs(days)) \(RU.plural(abs(days), "день", "дня", "дней"))").font(.subheadline).foregroundStyle(.primary.opacity(0.7))
                } else {
                    Spacer()
                    Text("Выберите два фото ниже").foregroundStyle(.primary.opacity(0.6))
                    Spacer()
                }

                picker("До", $before)
                picker("После", $after)
            }
            .padding(.bottom, 10)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            before = store.photos.first
            after = store.photos.last
        }
    }

    private func labeled(_ i: UIImage, _ p: ProgressPhoto, _ t: String) -> some View {
        Image(uiImage: i).resizable().scaledToFill()
            .frame(maxWidth: .infinity).frame(maxHeight: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) { tag(t + " · " + p.date.formatted(.dateTime.day().month(.abbreviated))).padding(8) }
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }

    private func picker(_ title: String, _ sel: Binding<ProgressPhoto?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.primary.opacity(0.6)).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.photos) { p in
                        Button { sel.wrappedValue = p; OxHaptics.play(.select) } label: {
                            Group {
                                if let i = store.image(p) { Image(uiImage: i).resizable().scaledToFill() } else { Color.oxCard }
                            }
                            .frame(width: 52, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(sel.wrappedValue?.id == p.id ? Color.lime : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Замеры

struct MeasurementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var values: [MeasureKey: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section { DatePicker("Дата", selection: $date, in: ...Date(), displayedComponents: .date) }
                Section {
                    ForEach(MeasureKey.allCases) { k in
                        HStack {
                            Text(k.title)
                            Spacer()
                            TextField(ProgressStore.shared.latest(k).map { String(format: "%.1f", $0.value) } ?? "—",
                                      text: Binding(get: { values[k] ?? "" }, set: { values[k] = $0 }))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("см").foregroundStyle(Color.oxHint)
                        }
                    }
                } footer: {
                    Text("Заполните только нужные. Меряйте утром, лентой по одной и той же линии. Хранится на этом iPhone.")
                }
            }
            .navigationTitle("Новый замер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        var v: [String: Double] = [:]
                        for (k, s) in values {
                            if let d = Double(s.replacingOccurrences(of: ",", with: ".")), d > 0, d < 300 { v[k.rawValue] = d }
                        }
                        guard !v.isEmpty else { OxAlert.error("Введите хотя бы один замер."); return }
                        ProgressStore.shared.addMeasurement(BodyMeasurement(date: date, values: v))
                        OxHaptics.play(.setDone)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Вес (сохраняется на сервере OXION, как в дневнике)

struct WeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void
    @State private var kg = ""
    @State private var date = Date()
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("72,5", text: $kg).keyboardType(.decimalPad).font(.title.bold())
                        Text("кг").foregroundStyle(Color.oxHint)
                    }
                    DatePicker("Дата", selection: $date, in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Вес")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }.disabled(busy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard let v = Double(kg.replacingOccurrences(of: ",", with: ".")), v > 20, v < 400 else {
            OxAlert.error("Введите вес числом, например 72,5")
            return
        }
        busy = true
        defer { busy = false }
        do {
            let _: OK = try await API.call("/weights", method: "POST", body: ["date": RU.dayFormatter.string(from: date), "kg": v])
            OxHaptics.play(.setDone)
            onSaved()
            dismiss()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

// MARK: - Приватность

struct ProgressPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProgressStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Закрывать фото Face ID", isOn: $store.faceLock).tint(Color.lime)
                } footer: {
                    Text("Раздел с фото будет открываться только после Face ID или код-пароля.")
                }
                Section {
                    Toggle("Включать в резервную копию iCloud", isOn: $store.backupAllowed).tint(Color.lime)
                } footer: {
                    Text("По умолчанию выключено: фото хранятся только на этом iPhone и при смене телефона не переносятся. Если включить — они попадут в зашифрованную резервную копию iPhone. На сервер OXION фото не отправляются ни в каком режиме, и приложение не анализирует их автоматически.")
                }
                Section {
                    Button("Удалить все фото прогресса", role: .destructive) {
                        OxAlert.confirm(title: "Удалить все фото?", message: "Удалится \(store.photos.count) фото. Восстановить будет нельзя.",
                                        action: "Удалить", destructive: true) {
                            store.deleteAllPhotos()
                        }
                    }
                }
            }
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

// MARK: - Progress Replay

struct ReplaySetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let weights: [WeightPoint]
    let workouts: [Workout]
    @State private var days = 30
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var play = false

    private var range: (Date, Date) {
        if days == 0 { return (Calendar.current.startOfDay(for: from), to) }
        return (Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date(), Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Период") {
                    Picker("", selection: $days) {
                        Text("30 дней").tag(30); Text("60 дней").tag(60); Text("90 дней").tag(90); Text("Свой").tag(0)
                    }
                    .pickerStyle(.segmented)
                    if days == 0 {
                        DatePicker("С", selection: $from, in: ...to, displayedComponents: .date)
                        DatePicker("По", selection: $to, in: from...Date(), displayedComponents: .date)
                    }
                }
                Section {
                    let r = range
                    let a = r.0, b = r.1
                    let n = ProgressStore.shared.photos(from: a, to: b).count
                    Label("\(n) \(RU.plural(n, "фото", "фото", "фото"))", systemImage: "photo.stack")
                    Label("\(workouts.filter { inRange($0.date, a, b) }.count) тренировок", systemImage: "figure.strengthtraining.traditional")
                    Label("\(weights.filter { inRange($0.date, a, b) }.count) записей веса", systemImage: "scalemass")
                } footer: {
                    Text("История собирается на iPhone из ваших фото, дневника и веса.")
                }
            }
            .navigationTitle("Progress Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button { play = true } label: {
                    Label("Смотреть историю", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
                .padding()
            }
            .fullScreenCover(isPresented: $play) {
                let r = range
                let a = r.0, b = r.1
                ReplayPlayerView(from: a, to: b, weights: weights.filter { inRange($0.date, a, b) },
                                 workouts: workouts.filter { inRange($0.date, a, b) })
            }
        }
    }

    private func inRange(_ ymd: String, _ a: Date, _ b: Date) -> Bool {
        guard let d = RU.dayFormatter.date(from: ymd) else { return false }
        return d >= Calendar.current.startOfDay(for: a) && d <= b
    }
}

struct ReplayPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let from: Date
    let to: Date
    let weights: [WeightPoint]
    let workouts: [Workout]

    enum Slide: Hashable { case intro, photo(ProgressPhoto), stats, beforeAfter, summary }

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var shareImage: Image?
    @State private var shareUI: UIImage?
    private let slideTime = 3.2

    private var photos: [ProgressPhoto] { ProgressStore.shared.photos(from: from, to: to) }

    private var slides: [Slide] {
        var s: [Slide] = [.intro]
        s += photos.map { .photo($0) }
        s.append(.stats)
        if photos.count >= 2 { s.append(.beforeAfter) }
        s.append(.summary)
        return s
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            slideView(slides[min(index, slides.count - 1)])
                .id(index)
                .transition(.opacity.combined(with: .scale(scale: 1.04)))

            VStack {
                HStack(spacing: 4) {
                    ForEach(slides.indices, id: \.self) { i in
                        GeometryReader { g in
                            Capsule().fill(.primary.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: g.size.width * (i < index ? 1 : i == index ? progress : 0))
                                }
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
                HStack {
                    Image("ox-logo").resizable().scaledToFit().frame(width: 22, height: 28)
                    Text("Progress Replay").font(.subheadline.bold())
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 12)
                Spacer()
            }

            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { go(-1) }
                Color.clear.contentShape(Rectangle()).onTapGesture { go(1) }
            }
            .padding(.top, 90).padding(.bottom, 120)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.25).onChanged { _ in paused = true }.onEnded { _ in paused = false })
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task(id: index) {
            progress = 0
            let steps = 60
            for _ in 0..<steps {
                try? await Task.sleep(for: .seconds(slideTime / Double(steps)))
                if Task.isCancelled { return }
                while paused { try? await Task.sleep(for: .milliseconds(100)) }
                progress += 1 / Double(steps)
            }
            if index < slides.count - 1 { go(1) }
        }
        .task { shareImage = renderSummary() }
    }

    private func go(_ d: Int) {
        let n = index + d
        guard n >= 0, n < slides.count else { return }
        withAnimation(.easeInOut(duration: 0.45)) { index = n }
        OxHaptics.play(.select)
    }

    @ViewBuilder
    private func slideView(_ s: Slide) -> some View {
        switch s {
        case .intro:
            VStack(spacing: 14) {
                Spacer()
                Text("ВАШ ПУТЬ").font(.caption.bold()).tracking(4).foregroundStyle(Color.limeInk)
                Text(periodText).font(.system(size: 40, weight: .heavy)).multilineTextAlignment(.center)
                Text("\(days) \(RU.plural(days, "день", "дня", "дней")) · \(workouts.count) \(RU.plural(workouts.count, "тренировка", "тренировки", "тренировок")) · \(photos.count) фото")
                    .foregroundStyle(.primary.opacity(0.7))
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [Color.lime.opacity(0.35), .black], center: .center, startRadius: 10, endRadius: 420))
        case .photo(let p):
            ZStack(alignment: .bottomLeading) {
                if let i = ProgressStore.shared.image(p) {
                    KenBurns(image: i)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.date.formatted(.dateTime.day().month(.wide).year())).font(.title.bold())
                    HStack(spacing: 14) {
                        Label("День \(dayNumber(p.date))", systemImage: "calendar")
                        if let w = weightAt(p.date) { Label("\(fmt(w)) кг", systemImage: "scalemass") }
                        Label("\(workoutsUntil(p.date))", systemImage: "figure.strengthtraining.traditional")
                    }
                    .font(.subheadline.bold()).foregroundStyle(Color.limeInk)
                }
                .padding(24).padding(.bottom, 40)
            }
            .ignoresSafeArea()
        case .stats:
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text("ЦИФРЫ ПЕРИОДА").font(.caption.bold()).tracking(4).foregroundStyle(Color.limeInk)
                big("\(workouts.count)", RU.plural(workouts.count, "тренировка", "тренировки", "тренировок"))
                big(perWeek, "в среднем в неделю")
                if let d = weightDelta { big("\(d >= 0 ? "+" : "")\(fmt(d)) кг", "изменение веса") }
                if let d = measureDelta(.waist) { big("\(d >= 0 ? "+" : "")\(fmt(d)) см", "талия") }
                Spacer()
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0x15200C), .black], startPoint: .top, endPoint: .bottom))
        case .beforeAfter:
            if let a = photos.first, let b = photos.last, let ai = ProgressStore.shared.image(a), let bi = ProgressStore.shared.image(b) {
                VStack(spacing: 12) {
                    Spacer().frame(height: 80)
                    HStack(spacing: 6) {
                        baPhoto(ai, "ДО", a.date)
                        baPhoto(bi, "ПОСЛЕ", b.date)
                    }
                    .padding(.horizontal, 8)
                    Spacer().frame(height: 60)
                }
            }
        case .summary:
            VStack(spacing: 18) {
                Spacer()
                summaryCard.padding(.horizontal, 24)
                if let shareImage {
                    HStack(spacing: 10) {
                        ShareLink(item: shareImage, preview: SharePreview("Мой прогресс в OXION", image: shareImage)) {
                            Label("Поделиться", systemImage: "square.and.arrow.up").font(.headline).padding(.horizontal, 8).padding(.vertical, 8)
                        }
                        .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(.black)
                        Button { Task { await saveToPhotos() } } label: {
                            Label("В Фото", systemImage: "square.and.arrow.down").font(.headline).padding(.horizontal, 8).padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                    }
                }
                Text("Фото в карточку не попадают — только цифры.").font(.caption).foregroundStyle(.primary.opacity(0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [Color.lime.opacity(0.25), .black], center: .top, startRadius: 10, endRadius: 500))
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image("ox-logo").resizable().scaledToFit().frame(width: 26, height: 34)
                Text("OXION").font(.headline.bold())
                Spacer()
                Text(periodText).font(.caption).foregroundStyle(.primary.opacity(0.7))
            }
            Text("Мой прогресс").font(.system(size: 30, weight: .heavy))
            HStack(spacing: 12) {
                tile("\(workouts.count)", "тренировок")
                tile(perWeek, "в неделю")
                tile(weightDelta.map { "\($0 >= 0 ? "+" : "")\(fmt($0))" } ?? "—", "кг")
            }
        }
        .padding(20)
        .oxCardBG(28)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.lime.opacity(0.4), lineWidth: 1))
        .foregroundStyle(.primary)
    }

    @MainActor
    private func renderSummary() -> Image? {
        let r = ImageRenderer(content: summaryCard.frame(width: 360).padding(20).background(Color.black))
        r.scale = 3
        shareUI = r.uiImage
        return r.uiImage.map { Image(uiImage: $0) }
    }

    private func saveToPhotos() async {
        guard let img = shareUI else { return }
        let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard st == .authorized || st == .limited else {
            PermPrompt.show(.photos, denied: true)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: img) }
            OxHaptics.play(.setDone)
            OxAlert.show(icon: "checkmark.circle.fill", title: "Сохранено в Фото")
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func tile(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.bold()).foregroundStyle(Color.limeInk).minimumScaleFactor(0.6).lineLimit(1)
            Text(t).font(.caption).foregroundStyle(.primary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func baPhoto(_ i: UIImage, _ t: String, _ d: Date) -> some View {
        Image(uiImage: i).resizable().scaledToFill()
            .frame(maxWidth: .infinity).frame(maxHeight: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading) {
                    Text(t).font(.headline.bold()).foregroundStyle(Color.limeInk)
                    Text(d.formatted(.dateTime.day().month(.abbreviated))).font(.caption)
                }
                .padding(10)
            }
    }

    private func big(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 52, weight: .heavy)).foregroundStyle(Color.limeInk)
            Text(t).font(.headline).foregroundStyle(.primary.opacity(0.75))
        }
    }

    // MARK: расчёты

    private var days: Int { max(1, Calendar.current.dateComponents([.day], from: from, to: to).day ?? 1) }
    private var periodText: String {
        "\(from.formatted(.dateTime.day().month(.abbreviated))) — \(to.formatted(.dateTime.day().month(.abbreviated)))"
    }
    private var perWeek: String { fmt((Double(workouts.count) / Double(days) * 7 * 10).rounded() / 10) }
    private var weightDelta: Double? {
        guard let f = weights.first, let l = weights.last, weights.count >= 2 else { return nil }
        return l.kg - f.kg
    }
    private func measureDelta(_ k: MeasureKey) -> Double? {
        let s = ProgressStore.shared.series(k).filter { $0.date >= from && $0.date <= to }
        guard let f = s.first, let l = s.last, s.count >= 2 else { return nil }
        return l.value - f.value
    }
    private func dayNumber(_ d: Date) -> Int { (Calendar.current.dateComponents([.day], from: from, to: d).day ?? 0) + 1 }
    private func weightAt(_ d: Date) -> Double? {
        weights.min { a, b in
            abs((RU.dayFormatter.date(from: a.date) ?? .distantPast).timeIntervalSince(d)) <
                abs((RU.dayFormatter.date(from: b.date) ?? .distantPast).timeIntervalSince(d))
        }?.kg
    }
    private func workoutsUntil(_ d: Date) -> String {
        let n = workouts.filter { (RU.dayFormatter.date(from: $0.date) ?? .distantFuture) <= d }.count
        return "\(n) \(RU.plural(n, "тренировка", "тренировки", "тренировок"))"
    }
    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Плавное медленное приближение фото (эффект «Кена Бёрнса»)
struct KenBurns: View {
    let image: UIImage
    @State private var zoom = false
    var body: some View {
        GeometryReader { g in
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: g.size.width, height: g.size.height)
                .scaleEffect(zoom ? 1.12 : 1.0)
                .clipped()
                .onAppear { withAnimation(.linear(duration: 4)) { zoom = true } }
        }
        .ignoresSafeArea()
    }
}
