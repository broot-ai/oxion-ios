import SwiftUI
import AVFoundation
import MapKit

// Лента в стиле Threads: музыка, место, параметры публикации, заметка над аватаркой, карточки «заполните профиль».

// MARK: - Проигрыватель отрывков (один на всё приложение)

@MainActor @Observable
final class MusicPreview {
    static let shared = MusicPreview()
    private var player: AVPlayer?
    private var end: Any?
    private(set) var playing: String?

    func toggle(_ url: String?) {
        guard let url, let u = URL(string: url) else { return }
        if playing == url { stop(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let p = AVPlayer(url: u)
        p.volume = 0.9
        player = p
        playing = url
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            Task { @MainActor in MusicPreview.shared.stop() }
        }
        p.play()
        Haptic.tap(.soft)
    }

    func stop() {
        player?.pause()
        player = nil
        playing = nil
        if let end { NotificationCenter.default.removeObserver(end) }
        end = nil
    }
}

// MARK: - Карточка трека в ветке

struct PostMusicCard: View {
    let music: PostMusic
    var onRemove: (() -> Void)? = nil
    @State private var preview = MusicPreview.shared

    var body: some View {
        let on = preview.playing == music.preview && music.preview != nil
        HStack(spacing: 10) {
            AsyncImage(url: music.art.flatMap(URL.init(string:))) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.primary.opacity(0.08).overlay(Image(systemName: "music.note").foregroundStyle(Color.oxHint))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(music.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let a = music.artist, !a.isEmpty { Text(a).font(.caption).foregroundStyle(Color.oxHint).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if music.preview != nil {
                Button { preview.toggle(music.preview) } label: {
                    Image(systemName: on ? "pause.fill" : "play.fill")
                        .font(.subheadline.bold())
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Color.oxHint).frame(width: 28, height: 28) }
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06)))
        .overlay(alignment: .bottomLeading) {
            if on {
                // тонкая полоска «играет»
                Capsule().fill(Color.lime).frame(height: 2).padding(.horizontal, 14).padding(.bottom, 2)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: on)
    }
}

// MARK: - Поиск музыки (iTunes Search API, без ключей)

struct MusicPickerSheet: View {
    var onPick: (PostMusic) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [Track] = []
    @State private var loading = false
    @State private var preview = MusicPreview.shared

    struct Track: Identifiable, Hashable {
        let id: Int
        let title: String
        let artist: String
        let art: String?
        let preview: String?
        let url: String?
        let ms: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section(query.isEmpty ? "Популярное" : "Результаты") {
                    if loading && items.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in row(nil) }
                    }
                    ForEach(items) { t in row(t) }
                    if !loading && items.isEmpty {
                        Text("Ничего не нашлось").foregroundStyle(Color.oxHint)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Музыка")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск музыки")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .task(id: query) {
                // небольшая пауза, чтобы не искать на каждую букву
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                if Task.isCancelled { return }
                await search(query.isEmpty ? "хиты 2026" : query)
            }
            .onDisappear { preview.stop() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(_ t: Track?) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: t?.art.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.08) }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(t?.title ?? "Название трека").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(t.map { "\($0.artist) · \(dur($0.ms))" } ?? "Исполнитель · 3:00").font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
            }
            Spacer()
            if let t, t.preview != nil {
                Button { preview.toggle(t.preview) } label: {
                    Image(systemName: preview.playing == t.preview ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .redacted(reason: t == nil ? .placeholder : [])
        .contentShape(Rectangle())
        .onTapGesture {
            guard let t else { return }
            preview.stop()
            Haptic.success()
            onPick(PostMusic(title: t.title, artist: t.artist, art: t.art, preview: t.preview, url: t.url))
            dismiss()
        }
    }

    private func dur(_ ms: Int) -> String { String(format: "%d:%02d", ms / 60000, ms / 1000 % 60) }

    private func search(_ term: String) async {
        loading = true
        defer { loading = false }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "song"),
                        .init(name: "country", value: "ru"), .init(name: "limit", value: "40")]
        guard let url = c.url, let resp = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: resp.0) as? [String: Any],
              let res = obj["results"] as? [[String: Any]] else { items = []; return }
        let out: [Track] = res.compactMap { r in
            guard let id = r["trackId"] as? Int, let n = r["trackName"] as? String else { return nil }
            let art = (r["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "300x300")
            return Track(id: id, title: n, artist: r["artistName"] as? String ?? "", art: art,
                         preview: r["previewUrl"] as? String, url: r["trackViewUrl"] as? String, ms: r["trackTimeMillis"] as? Int ?? 0)
        }
        withAnimation(.smooth(duration: 0.25)) { items = out }
    }
}

// MARK: - Местоположение (подсказки Apple Maps)

@MainActor @Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    let completer = MKLocalSearchCompleter()
    var results: [MKLocalSearchCompletion] = []
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }
    func set(_ q: String) { completer.queryFragment = q }
    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = c.results
        Task { @MainActor in self.results = Array(r.prefix(20)) }
    }
    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

struct LocationPickerSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var search = PlaceSearch()

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, let c = model.me?.city, !c.isEmpty {
                    Button { pick(c) } label: { Label(c, systemImage: "location.fill") }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { pick(query.trimmingCharacters(in: .whitespaces)) } label: {
                        Label("«\(query)»", systemImage: "mappin.and.ellipse")
                    }
                }
                ForEach(search.results, id: \.self) { r in
                    Button { pick(r.title) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(Color.primary)
                            if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(Color.oxHint) }
                        }
                    }
                }
            }
            .navigationTitle("Местоположение")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Зал, парк, город")
            .onChange(of: query) { search.set(query) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ s: String) {
        Haptic.tap(.soft)
        onPick(String(s.prefix(80)))
        dismiss()
    }
}

// MARK: - Параметры публикации

struct PublishParamsSheet: View {
    @Binding var replyTo: String
    @Environment(\.dismiss) private var dismiss

    static let options: [(String, String, String)] = [
        ("all", "Кто угодно", "globe"),
        ("followers", "Ваши подписчики", "person.2"),
        ("following", "Профили, на которые вы подписаны", "person.crop.circle.badge.checkmark"),
        ("mentioned", "Упомянутые профили", "at"),
        ("none", "Никто", "lock"),
    ]

    static func title(_ k: String) -> String { options.first { $0.0 == k }?.1 ?? "Кто угодно" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.options, id: \.0) { o in
                        Button {
                            withAnimation(.smooth(duration: 0.2)) { replyTo = o.0 }
                            Haptic.tap(.soft)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: o.2).frame(width: 24).foregroundStyle(Color.oxHint)
                                Text(o.1).foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: replyTo == o.0 ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(replyTo == o.0 ? Color.lime : Color.oxHint.opacity(0.6))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                    }
                } header: {
                    Text("Кто может отвечать и цитировать")
                } footer: {
                    Text("Упомянутые — те, кого вы отметили в тексте через @имя.")
                }
            }
            .navigationTitle("Параметры публикации")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: { Text("Готово").font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Заметка над аватаркой (видна 24 часа)

struct NoteBubble: View {
    let text: String?
    var mine = false
    var body: some View {
        HStack(spacing: 4) {
            if let t = text, !t.isEmpty {
                Text(t).font(.caption.weight(.medium)).lineLimit(1)
            } else if mine {
                Text("Заметка").font(.caption).foregroundStyle(Color.oxHint)
            }
            if mine { Image(systemName: "plus").font(.caption2.bold()).foregroundStyle(Color.oxHint) }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: 120)
        .background(Color.oxCard, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct NoteComposerSheet: View {
    var current: String?
    var onSaved: (FUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.me?.displayName ?? "Вы").font(.subheadline.weight(.semibold))
                        TextField("Поделитесь мыслями…", text: $text, axis: .vertical)
                            .lineLimit(1...3)
                            .focused($focused)
                            .font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .fixedSize(horizontal: text.count < 24, vertical: false)
                            .overlay(Capsule().strokeBorder(Color.oxHint.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                            .onChange(of: text) { if text.count > 60 { text = String(text.prefix(60)) } }
                            .animation(.smooth(duration: 0.2), value: text)
                    }
                    Spacer()
                }
                .padding(16)
                Text("Заметка видна над аватаркой в профиле 24 часа")
                    .font(.caption).foregroundStyle(Color.oxHint).padding(.horizontal, 16)
                Spacer()
            }
            .navigationTitle("Новая заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                if current?.isEmpty == false {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Удалить", role: .destructive) { Task { await save("") } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(text.count)/60").font(.caption.monospacedDigit()).foregroundStyle(Color.oxHint)
                    Spacer()
                    Button { Task { await save(text) } } label: {
                        HStack(spacing: 6) {
                            if sending { ProgressView() }
                            Text("Опубликовать").font(.headline)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .onAppear { text = current ?? ""; focused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save(_ t: String) async {
        sending = true
        defer { sending = false }
        do {
            let u: FUser = try await API.call("/feed/me/note", method: "PUT", body: ["text": t])
            Haptic.success()
            onSaved(u)
            dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

// MARK: - «Закончите заполнение профиля»

struct ProfileTodoCards: View {
    let todo: [FTodo]
    var onAction: (String) -> Void

    var body: some View {
        let left = todo.filter { $0.done != true }
        if !left.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Закончите заполнение профиля").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Осталось \(left.count)").font(.subheadline).foregroundStyle(Color.oxHint)
                }
                .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(left, id: \.key) { t in card(t) }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
            }
            .padding(.vertical, 12)
        }
    }

    private func card(_ t: FTodo) -> some View {
        let (icon, action) = meta(t.key)
        return VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(Color.primary.opacity(0.06), in: Circle())
            Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(t.text ?? "").font(.caption).foregroundStyle(Color.oxHint).multilineTextAlignment(.center).lineLimit(2)
                .frame(height: 32, alignment: .top)
            Button { onAction(t.key) } label: { Text(action).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34) }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(width: 170)
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }

    private func meta(_ k: String) -> (String, String) {
        switch k {
        case "post": ("square.and.pencil", "Создать")
        case "photo": ("person.crop.circle.badge.plus", "Добавить")
        case "bio": ("pencil", "Добавить")
        case "follow": ("person.2.badge.plus", "Смотреть профили")
        default: ("checkmark.circle", "Открыть")
        }
    }
}

// MARK: - Вкладки профиля с подчёркиванием, как в Threads

struct UnderlineTabs: View {
    let tabs: [(String, String)]
    @Binding var selection: String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { t in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { selection = t.0 }
                    Haptic.tap(.soft)
                } label: {
                    VStack(spacing: 8) {
                        Text(t.1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == t.0 ? Color.primary : Color.oxHint)
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                            if selection == t.0 {
                                Rectangle().fill(Color.primary).frame(height: 1.5).matchedGeometryEffect(id: "u", in: ns)
                            }
                        }
                        .frame(height: 1.5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Пара слов о себе

struct BioEditSheet: View {
    var current: String
    var onSaved: (FUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Цель, вид спорта, зал", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: text) { if text.count > 150 { text = String(text.prefix(150)) } }
                } footer: { Text("\(text.count)/150") }
            }
            .navigationTitle("О себе")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { Task { await save() } }.bold().disabled(sending)
                }
            }
            .onAppear { text = current }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        sending = true
        defer { sending = false }
        do {
            let u: FUser = try await API.call("/feed/me", method: "PATCH", body: ["bio": text])
            Haptic.success()
            onSaved(u)
            dismiss()
        } catch { OxAlert.error(error.localizedDescription) }
    }
}
