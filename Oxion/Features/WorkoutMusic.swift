import SwiftUI
import MusicKit
import MediaPlayer

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
        if status != .authorized { await authorize() }
        guard status == .authorized else { return }
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

    // MARK: Своя медиатека (песни, скачанные в «Музыку») — работает без платного аккаунта

    var libraryAllowed = MPMediaLibrary.authorizationStatus() == .authorized
    var libraryPlaylists: [MPMediaPlaylist] = []
    private var lastLibrary: UInt64 {
        get { UInt64(UserDefaults.standard.string(forKey: "oxion_music_lib") ?? "") ?? 0 }
        set { UserDefaults.standard.set(String(newValue), forKey: "oxion_music_lib") }
    }
    var libraryPlayingId: UInt64?

    func loadLibrary() async {
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0) } }
        }
        libraryAllowed = MPMediaLibrary.authorizationStatus() == .authorized
        guard libraryAllowed else { return }
        libraryPlaylists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? []).filter { $0.count > 0 }
    }

    func playLibrary(_ p: MPMediaPlaylist) {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.setQueue(with: p)
        player.shuffleMode = .songs
        player.play()
        libraryPlayingId = p.persistentID
        lastLibrary = p.persistentID
    }

    func playAllLibrary() {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.setQueue(with: MPMediaQuery.songs())
        player.shuffleMode = .songs
        player.play()
        libraryPlayingId = 0
    }

    /// События тренировки: старт → включить последний плейлист, финиш → остановить
    func handle(_ e: WorkoutEngine.Event) {
        guard autoPlay else { return }
        if MPMediaLibrary.authorizationStatus() == .authorized, lastLibrary != 0 {
            switch e {
            case .started:
                let q = MPMediaQuery.playlists()
                q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: lastLibrary), forProperty: MPMediaPlaylistPropertyPersistentID))
                if let p = q.collections?.first as? MPMediaPlaylist { playLibrary(p) }
            case .finished:
                MPMusicPlayerController.systemMusicPlayer.pause()
            default: break
            }
            return
        }
        guard status == .authorized else { return }
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

// MARK: - Подборки мотивирующих треков (открываются в музыкальном сервисе пользователя)

struct PumpTrack: Identifiable, Hashable {
    let artist: String
    let title: String
    var id: String { artist + title }
    var query: String { "\(artist) \(title)" }
}

enum PumpCollections {
    static let all: [(name: String, icon: String, tracks: [PumpTrack])] = [
        ("Рэп на силовую", "dumbbell.fill", [
            .init(artist: "Eminem", title: "Till I Collapse"),
            .init(artist: "Eminem", title: "Lose Yourself"),
            .init(artist: "Fort Minor", title: "Remember the Name"),
            .init(artist: "DMX", title: "X Gon' Give It to Ya"),
            .init(artist: "Kanye West", title: "Stronger"),
            .init(artist: "Kendrick Lamar", title: "HUMBLE."),
            .init(artist: "Travis Scott", title: "SICKO MODE"),
            .init(artist: "50 Cent", title: "In Da Club"),
            .init(artist: "Macklemore & Ryan Lewis", title: "Can't Hold Us"),
            .init(artist: "Drake", title: "Started From the Bottom"),
        ]),
        ("Рок для рекордов", "bolt.fill", [
            .init(artist: "Survivor", title: "Eye of the Tiger"),
            .init(artist: "AC/DC", title: "Thunderstruck"),
            .init(artist: "AC/DC", title: "Back in Black"),
            .init(artist: "Queen", title: "We Will Rock You"),
            .init(artist: "Linkin Park", title: "Faint"),
            .init(artist: "Linkin Park", title: "Bleed It Out"),
            .init(artist: "Rage Against the Machine", title: "Killing in the Name"),
            .init(artist: "Bon Jovi", title: "It's My Life"),
            .init(artist: "Twisted Sister", title: "We're Not Gonna Take It"),
            .init(artist: "Foo Fighters", title: "The Pretender"),
        ]),
        ("Кардио и бег", "figure.run", [
            .init(artist: "The Weeknd", title: "Blinding Lights"),
            .init(artist: "Imagine Dragons", title: "Believer"),
            .init(artist: "Imagine Dragons", title: "Thunder"),
            .init(artist: "Avicii", title: "The Nights"),
            .init(artist: "David Guetta feat. Sia", title: "Titanium"),
            .init(artist: "Calvin Harris", title: "Summer"),
            .init(artist: "Sia", title: "Unstoppable"),
            .init(artist: "Katy Perry", title: "Roar"),
            .init(artist: "Dua Lipa", title: "Physical"),
            .init(artist: "Martin Garrix", title: "Animals"),
        ]),
    ]
}

enum MusicService: String, CaseIterable, Identifiable {
    case yandex, vk, spotify, youtube, apple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .yandex: "Яндекс Музыка"
        case .vk: "VK Музыка"
        case .spotify: "Spotify"
        case .youtube: "YouTube Music"
        case .apple: "Apple Music"
        }
    }
    func url(_ q: String) -> URL? {
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let p = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q
        switch self {
        case .yandex: return URL(string: "https://music.yandex.ru/search?text=\(e)")
        case .vk: return URL(string: "https://vk.com/audio?q=\(e)")
        case .spotify: return URL(string: "https://open.spotify.com/search/\(p)")
        case .youtube: return URL(string: "https://music.youtube.com/search?q=\(e)")
        case .apple: return URL(string: "https://music.apple.com/search?term=\(e)")
        }
    }
}

struct WorkoutMusicView: View {
    enum Tab: String, CaseIterable { case pump = "Подборки", mine = "Моя музыка", apple = "Apple Music" }

    @Environment(\.openURL) private var openURL
    @State private var music = WorkoutMusic.shared
    @State private var tab: Tab = .pump
    @State private var term = "workout"
    @AppStorage("oxion_music_service") private var serviceRaw = MusicService.yandex.rawValue
    private let quick = ["Workout", "Gym Motivation", "Running", "Hip-Hop Workout", "Rock Workout"]

    private var service: MusicService { MusicService(rawValue: serviceRaw) ?? .yandex }

    var body: some View {
        List {
            Section {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch tab {
            case .pump: pump
            case .mine: mine
            case .apple: appleMusic
            }
        }
        .navigationTitle("Музыка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: tab) {
            if tab == .mine { await music.loadLibrary() }
            if tab == .apple {
                if music.status == .notDetermined { await music.authorize() }
                if music.playlists.isEmpty, music.status == .authorized { await music.search(term) }
            }
        }
    }

    // MARK: подборки

    @ViewBuilder private var pump: some View {
        Section {
            Picker("Где слушать", selection: $serviceRaw) {
                ForEach(MusicService.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } footer: {
            Text("Треки откроются в выбранном приложении. Сами песни в OXION не хранятся: для этого нужна лицензия правообладателей.")
        }
        ForEach(PumpCollections.all, id: \.name) { c in
            Section {
                Button {
                    if let u = service.url(c.tracks.prefix(3).map(\.artist).joined(separator: " ")) { openURL(u) }
                } label: {
                    Label("Открыть похожие в \(service.title)", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold())
                }
                ForEach(c.tracks) { tr in
                    Button {
                        if let u = service.url(tr.query) { Haptic.tap(); openURL(u) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.limeInk)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tr.title).font(.subheadline.bold()).lineLimit(1)
                                Text(tr.artist).font(.caption).foregroundStyle(Color.oxHint).lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Label(c.name, systemImage: c.icon)
            }
        }
    }

    // MARK: своя медиатека

    @ViewBuilder private var mine: some View {
        Section {
            Toggle("Включать при старте тренировки", isOn: Binding(get: { music.autoPlay }, set: { music.autoPlay = $0 }))
        } footer: {
            Text("Играет последний выбранный плейлист из приложения «Музыка» на iPhone.")
        }
        if !music.libraryAllowed {
            Section {
                Text("Нужен доступ к медиатеке: Настройки → Oxion → Медиа и Apple Music.")
                    .font(.footnote).foregroundStyle(Color.oxHint)
            }
        } else if music.libraryPlaylists.isEmpty {
            Section {
                Button { music.playAllLibrary() } label: { Label("Перемешать все песни", systemImage: "shuffle") }
                Text("Плейлистов нет. Скачайте песни в приложение «Музыка» — они появятся здесь.")
                    .font(.footnote).foregroundStyle(Color.oxHint)
            }
        } else {
            Section("Плейлисты на iPhone") {
                Button { music.playAllLibrary() } label: { Label("Перемешать все песни", systemImage: "shuffle") }
                ForEach(music.libraryPlaylists, id: \.persistentID) { p in
                    Button { music.playLibrary(p) } label: {
                        HStack {
                            Image(systemName: "music.note.list").foregroundStyle(Color.limeInk)
                            Text(p.name ?? "Плейлист")
                            Spacer()
                            Text("\(p.count)").foregroundStyle(Color.oxHint)
                            if music.libraryPlayingId == p.persistentID {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.limeInk)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
        }
    }

    // MARK: Apple Music (нужен платный аккаунт разработчика)

    @ViewBuilder private var appleMusic: some View {
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
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.limeInk)
                        }
                    }
                }
                .tint(.primary)
            }
        } footer: {
            Text("Плейлисты Apple Music играют прямо в OXION — в версии из TestFlight/App Store и с подпиской Apple Music.")
        }
    }
}
