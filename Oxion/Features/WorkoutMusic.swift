import SwiftUI
import MusicKit

/// Музыка для тренировки из Apple Music (MusicKit).
/// Нужны: подписка Apple Music у пользователя и служба MusicKit у App ID (платный аккаунт).
@MainActor
@Observable
final class WorkoutMusic {
    static let shared = WorkoutMusic()

    var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
    var playlists: [Playlist] = []
    var loading = false
    var errorText: String?
    var playingId: MusicItemID?

    /// Включать музыку при старте тренировки
    var autoPlay: Bool {
        get { UserDefaults.standard.bool(forKey: "oxion_music_auto") }
        set { UserDefaults.standard.set(newValue, forKey: "oxion_music_auto") }
    }
    private var lastId: String? {
        get { UserDefaults.standard.string(forKey: "oxion_music_last") }
        set { UserDefaults.standard.set(newValue, forKey: "oxion_music_last") }
    }

    func authorize() async {
        status = await MusicAuthorization.request()
    }

    func search(_ term: String) async {
        guard status == .authorized else { await authorize(); guard status == .authorized else { return } }
        loading = true
        defer { loading = false }
        do {
            var req = MusicCatalogSearchRequest(term: term, types: [Playlist.self])
            req.limit = 20
            let res = try await req.response()
            playlists = Array(res.playlists)
            errorText = playlists.isEmpty ? "Ничего не нашлось" : nil
        } catch {
            errorText = "Apple Music недоступна: \(error.localizedDescription)"
        }
    }

    func play(_ p: Playlist) async {
        do {
            let sub = try await MusicSubscription.current
            guard sub.canPlayCatalogContent else {
                errorText = "Нужна подписка Apple Music"
                return
            }
            ApplicationMusicPlayer.shared.queue = [p]
            try await ApplicationMusicPlayer.shared.play()
            playingId = p.id
            lastId = p.id.rawValue
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stop() {
        ApplicationMusicPlayer.shared.stop()
        playingId = nil
    }

    /// События тренировки: старт → включить последний плейлист, финиш → остановить
    func handle(_ e: WorkoutEngine.Event) {
        guard autoPlay, status == .authorized else { return }
        switch e {
        case .started:
            guard let id = lastId else { return }
            Task {
                let req = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
                if let p = try? await req.response().items.first { await play(p) }
            }
        case .finished:
            stop()
        default:
            break
        }
    }
}

struct WorkoutMusicView: View {
    @State private var music = WorkoutMusic.shared
    @State private var term = "тренировка"
    private let quick = ["Workout", "Бег", "Силовая", "Кардио", "Растяжка", "Hip-Hop Workout"]

    var body: some View {
        List {
            Section {
                Toggle("Включать при старте тренировки", isOn: Binding(get: { music.autoPlay }, set: { music.autoPlay = $0 }))
                if music.playingId != nil {
                    Button(role: .destructive) { music.stop() } label: { Label("Остановить", systemImage: "stop.fill") }
                }
            } footer: {
                Text("Играет последний выбранный плейлист. Нужна подписка Apple Music.")
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.self) { q in
                            Button(q) { term = q; Task { await music.search(q) } }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                if music.loading { ProgressView().frame(maxWidth: .infinity) }
                if let e = music.errorText { Text(e).font(.footnote).foregroundStyle(.orange) }
                ForEach(music.playlists) { p in
                    Button { Task { await music.play(p) } } label: {
                        HStack(spacing: 12) {
                            if let art = p.artwork {
                                ArtworkImage(art, width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                Image(systemName: "music.note.list").frame(width: 52, height: 52)
                                    .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.bold()).lineLimit(1)
                                Text(p.curatorName ?? "Apple Music").font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                            }
                            Spacer()
                            if music.playingId == p.id {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.lime)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .searchable(text: $term, prompt: "Поиск плейлистов")
        .onSubmit(of: .search) { Task { await music.search(term) } }
        .navigationTitle("Музыка")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if music.status == .notDetermined { await music.authorize() }
            if music.playlists.isEmpty, music.status == .authorized { await music.search(term) }
        }
        .overlay {
            if music.status == .denied || music.status == .restricted {
                ContentUnavailableView("Нет доступа к Apple Music", systemImage: "music.note",
                                       description: Text("Разрешите доступ в Настройках → Oxion → Медиа и Apple Music"))
            }
        }
    }
}
