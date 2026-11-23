import SwiftUI
import AVFoundation

// Каталог упражнений WorkoutDB (work-out-db.com): видео, описание, техника.
// Приложение ходит только на наш сервер (/wdb/*): ключ API хранится там, ответы кэшируются, тексты переводятся на русский.

struct WDBItem: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String?
    let name: String
    let nameEn: String?
    let bodyPart: String?
    let bodyPartRu: String?
    let target: String?
    let equipment: String?
    let equipmentRu: String?
    let difficulty: String?
    let category: String?
    let muscle: String?
    let gif: String?
    let poster: String?
    let video: String?
}

struct WDBFull: Decodable {
    let id: String
    let name: String
    let nameEn: String?
    let bodyPartRu: String?
    let target: String?
    let equipmentRu: String?
    let difficulty: String?
    let muscle: String?
    let gif: String?
    let poster: String?
    let video: String?
    let secondary: [String]?
    let description: String?
    let instructions: [String]?
    let photos: [String]?
    let translated: Bool?
}

struct WDBList: Decodable { let items: [WDBItem]; let next: String?; let total: Int? }
struct WDBKV: Decodable, Hashable { let key: String; let name: String }
struct WDBMeta: Decodable { let bodyParts: [WDBKV]; let equipment: [WDBKV] }

enum WDBText {
    static func difficulty(_ d: String?) -> String? {
        switch d { case "beginner": "Новичок"; case "intermediate": "Средний"; case "advanced": "Продвинутый"; default: nil }
    }
}

/// Бесшумное зацикленное видео (mp4) для показа техники
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspect

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        v.looper = AVPlayerLooper(player: p, templateItem: item)
        v.playerLayer.player = p
        v.playerLayer.videoGravity = gravity
        p.play()
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {}

    static func dismantleUIView(_ v: PlayerView, coordinator: ()) {
        v.playerLayer.player?.pause()
        v.looper = nil
    }
}

struct WorkoutDBCatalogView: View {
    @State private var meta: WDBMeta?
    @State private var items: [WDBItem] = []
    @State private var next: String?
    @State private var part: String?
    @State private var equip: String?
    @State private var query = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let meta {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Все", part == nil) { part = nil }
                            ForEach(meta.bodyParts, id: \.key) { b in
                                chip(b.name, part == b.key) { part = b.key }
                            }
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                }
                if let errorText, items.isEmpty {
                    ErrorStateView(message: errorText) { Task { await reload() } }
                        .padding(.horizontal, 16)
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(items) { e in
                        NavigationLink { WDBExerciseView(id: e.id, preview: e) } label: { card(e) }
                            .buttonStyle(.plain)
                            .onAppear { if e.id == items.last?.id { Task { await more() } } }
                    }
                }
                .padding(.horizontal, 16)
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if items.isEmpty && errorText == nil {
                    ContentUnavailableView.search(text: query)
                }
                Text("Данные и видео: WorkoutDB (work-out-db.com)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding(.bottom, 20)
            }
            .padding(.top, 8)
        }
        .navigationTitle("Каталог с видео")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Жим, тяга, присед…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Инвентарь", selection: $equip) {
                        Text("Любой").tag(String?.none)
                        ForEach(meta?.equipment ?? [], id: \.key) { e in Text(e.name).tag(Optional(e.key)) }
                    }
                } label: {
                    Image(systemName: equip == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .onChange(of: part) { _, _ in Task { await reload() } }
        .onChange(of: equip) { _, _ in Task { await reload() } }
        .onChange(of: query) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { await reload() }
            }
        }
        .task {
            if meta == nil { meta = try? await API.call("/wdb/meta") }
            if items.isEmpty { await reload() }
        }
    }

    private func chip(_ t: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button { act(); Haptic.tap() } label: {
            Text(t).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(on ? Color.onLime : .primary)
                .background(on ? Color.lime : Color.oxCard, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func card(_ e: WDBItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: API.media(e.poster ?? e.gif), icon: "dumbbell")
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if e.video != nil {
                        Image(systemName: "play.fill").font(.caption2.bold())
                            .padding(6).background(.ultraThinMaterial, in: Circle()).padding(6)
                    }
                }
            Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
            Text([e.bodyPartRu, e.equipmentRu].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .oxCardBG(22)
    }

    private func params(cursor: String?) -> [String: String] {
        var q: [String: String] = ["limit": "24"]
        if let part { q["bodyPart"] = part }
        if let equip { q["equipment"] = equip }
        let t = query.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { q["q"] = t }
        if let cursor { q["cursor"] = cursor }
        return q
    }

    private func reload() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let r: WDBList = try await API.call("/wdb/exercises", query: params(cursor: nil))
            items = r.items
            next = r.next
        } catch {
            items = []
            errorText = error.localizedDescription
        }
    }

    private func more() async {
        guard let next, !loading else { return }
        loading = true
        defer { loading = false }
        if let r: WDBList = try? await API.call("/wdb/exercises", query: params(cursor: next)) {
            items += r.items.filter { n in !items.contains { $0.id == n.id } }
            self.next = r.next
        }
    }
}

struct WDBExerciseView: View {
    let id: String
    let preview: WDBItem
    @State private var full: WDBFull?
    @State private var errorText: String?
    @State private var busy = false
    @State private var added: Exercise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if let v = API.media(full?.video ?? preview.video) {
                        LoopingVideo(url: v)
                    } else {
                        RemoteImage(url: API.media(full?.gif ?? preview.gif ?? preview.poster), icon: "dumbbell")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                Text(full?.name ?? preview.name).font(.title2.bold())
                if let en = full?.nameEn ?? preview.nameEn, en != (full?.name ?? preview.name) {
                    Text(en).font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let b = full?.bodyPartRu ?? preview.bodyPartRu { StatPill(icon: "figure.strengthtraining.traditional", text: b) }
                        if let e = full?.equipmentRu ?? preview.equipmentRu { StatPill(icon: "dumbbell", text: e) }
                        if let d = WDBText.difficulty(full?.difficulty ?? preview.difficulty) { StatPill(icon: "chart.bar.fill", text: d) }
                        if let t = full?.target ?? preview.target { StatPill(icon: "scope", text: t) }
                    }
                }

                if let full {
                    if let d = full.description, !d.isEmpty {
                        Text(d).font(.callout)
                    }
                    if let steps = full.instructions, !steps.isEmpty {
                        Text("Техника").font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(.caption.bold()).foregroundStyle(Color.onLime)
                                        .frame(width: 22, height: 22).background(Color.lime, in: Circle())
                                    Text(s).font(.callout)
                                }
                            }
                        }
                    }
                    if let s = full.secondary, !s.isEmpty {
                        Text("Также работают: " + s.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if full.translated != true {
                        Label("Перевод недоступен — показан оригинал", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let errorText {
                    ErrorStateView(message: errorText) { Task { await load() } }
                } else {
                    ProgressView("Загружаю и перевожу…").frame(maxWidth: .infinity).padding()
                }

                VStack(spacing: 10) {
                    Button { Task { await addToday() } } label: {
                        Label("В тренировку сегодня", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                    Button { Task { _ = await importIt(alert: true) } } label: {
                        Label(added == nil ? "Сохранить в мои упражнения" : "Сохранено", systemImage: added == nil ? "square.and.arrow.down" : "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.glass)
                    .disabled(added != nil)
                }
                .disabled(busy)
                Text("Данные и видео: WorkoutDB (work-out-db.com). Перевод — автоматический.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle(full?.name ?? preview.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        errorText = nil
        do { full = try await API.call("/wdb/exercises/\(id)") } catch { errorText = error.localizedDescription }
    }

    private func importIt(alert: Bool) async -> Exercise? {
        if let added { return added }
        busy = true
        defer { busy = false }
        do {
            let e: Exercise = try await API.call("/wdb/import/\(id)", method: "POST")
            added = e
            if alert { Haptic.success(); OxAlert.show(icon: "checkmark.circle.fill", title: "Сохранено", message: "«\(e.name)» теперь в ваших упражнениях") }
            return e
        } catch {
            OxAlert.error(error.localizedDescription)
            return nil
        }
    }

    private func addToday() async {
        guard let e = await importIt(alert: false) else { return }
        busy = true
        defer { busy = false }
        do {
            try await WorkoutIntegrationManager.add(exercises: [e], groups: [e.muscle ?? "legs"], title: e.name)
            Haptic.success()
            OxAlert.show(icon: "checkmark.circle.fill", title: "Добавлено", message: "«\(e.name)» в тренировке на сегодня")
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
