import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Истории как в Telegram
// Фото или видео на 24 часа. Ряд кружков над чатами; при прокрутке вверх кружки
// уменьшаются и «уезжают» в заголовок «Чаты» стопкой мини-аватарок, при оттягивании вниз — раскрываются.

struct StoryUser: Decodable, Hashable {
    let id: Int
    let name: String?
    let photo: String?
}

struct StoryItem: Decodable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let url: String
    var caption: String?
    let at: Double
    let expires: Double?
    var seen: Bool?
    var liked: Bool?
    let allowShots: Bool?
    let dur: Double?
    var views: Int?
    var likes: Int?
    let privacy: String?
    var isVideo: Bool { kind == "video" }
}

struct StoryGroup: Decodable, Identifiable, Hashable {
    let user: StoryUser
    var stories: [StoryItem]
    var unseen: Bool?
    var id: Int { user.id }
    var hasUnseen: Bool { stories.contains { $0.seen != true } }
}

private struct StoriesResp: Decodable {
    let me: StoryGroup
    let users: [StoryGroup]
}

struct StoryViewerStart: Identifiable {
    let id = UUID()
    let groups: [StoryGroup]
    let index: Int
}

@MainActor @Observable
final class StoriesStore {
    static let shared = StoriesStore()
    var me: StoryGroup?
    var users: [StoryGroup] = []
    /// 0 — ряд раскрыт, 1 — свернут в заголовок
    var collapse: CGFloat = 0
    var viewer: StoryViewerStart?
    var composer = false
    var uploading = false

    var all: [StoryGroup] {
        var r: [StoryGroup] = []
        if let me, !me.stories.isEmpty { r.append(me) }
        return r + users
    }

    func load() async {
        guard let r: StoriesResp = try? await API.call("/stories") else { return }
        me = r.me
        users = r.users
    }

    func open(_ g: StoryGroup) {
        let list = all
        guard let i = list.firstIndex(where: { $0.id == g.id }) else { return }
        OxHaptics.play(.select)
        viewer = StoryViewerStart(groups: list, index: i)
    }

    func markSeen(_ s: StoryItem, owner: Int) {
        if let gi = users.firstIndex(where: { $0.id == owner }), let si = users[gi].stories.firstIndex(where: { $0.id == s.id }) {
            if users[gi].stories[si].seen == true { return }
            users[gi].stories[si].seen = true
        }
        Task { let _: OK? = try? await API.call("/stories/\(s.id)/view", method: "POST") }
    }

    /// Непросмотренные в начало — как в Telegram после закрытия просмотра
    func resort() {
        users.sort { ($0.hasUnseen ? 1 : 0, $0.stories.last?.at ?? 0) > ($1.hasUnseen ? 1 : 0, $1.stories.last?.at ?? 0) }
    }

    func delete(_ s: StoryItem) async -> Bool {
        do {
            let _: OK = try await API.call("/stories/\(s.id)", method: "DELETE")
            me?.stories.removeAll { $0.id == s.id }
            return true
        } catch {
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

// MARK: - Кольцо вокруг аватарки

struct StoryRing: View {
    var unseen: Bool
    var width: CGFloat = 2.4
    var body: some View {
        Circle()
            .strokeBorder(unseen
                          ? AnyShapeStyle(AngularGradient(colors: [Color.lime, Color(hex: 0x34C759), Color(hex: 0x00C7BE), Color.lime], center: .center))
                          : AnyShapeStyle(Color.secondary.opacity(0.45)),
                          lineWidth: unseen ? width : 1.4)
    }
}

// MARK: - Ряд историй над списком чатов

struct StoriesHeaderRow: View {
    @State private var store = StoriesStore.shared
    var myPhoto: String? = nil

    private let size: CGFloat = 62

    var body: some View {
        let p = store.collapse
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                mine
                ForEach(store.users) { g in
                    Button { store.open(g) } label: {
                        bubble(name: g.user.name ?? "—", photo: g.user.photo, unseen: g.hasUnseen, ring: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        // при прокрутке кружки сжимаются и тают, как будто уезжают в заголовок
        .scaleEffect(1 - 0.45 * p, anchor: .top)
        .opacity(Double(1 - p * 1.25))
        .offset(y: p * 18)
    }

    @ViewBuilder private var mine: some View {
        let has = !(store.me?.stories.isEmpty ?? true)
        Button {
            if has, let me = store.me { store.open(me) } else { store.composer = true }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                bubble(name: String(localized: "Моя история"), photo: store.me?.user.photo ?? myPhoto, unseen: false, ring: has)
                if store.uploading {
                    ProgressView().controlSize(.small)
                        .frame(width: 22, height: 22)
                        .background(.background, in: Circle())
                        .offset(x: -2, y: -20)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 21, height: 21)
                        .background(Color.lime, in: Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2.5))
                        .offset(x: -2, y: -20)
                        .onTapGesture { store.composer = true }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.composer = true } label: { Label("Добавить историю", systemImage: "plus.circle") }
        }
    }

    private func bubble(name: String, photo: String?, unseen: Bool, ring: Bool) -> some View {
        VStack(spacing: 5) {
            Avatar(url: API.media(photo), name: name, size: size - 8)
                .padding(4)
                .overlay { if ring { StoryRing(unseen: unseen) } }
                .frame(width: size, height: size)
            Text(name)
                .font(.caption2)
                .foregroundStyle(unseen ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: size + 8)
        }
    }
}

// MARK: - Заголовок «Чаты» со стопкой мини-аватарок

struct StoriesNavTitle: View {
    @State private var store = StoriesStore.shared
    var title: String

    var body: some View {
        let p = store.collapse
        let stack = Array(store.all.prefix(3))
        HStack(spacing: 7) {
            if !stack.isEmpty {
                Button {
                    if let g = store.all.first(where: { $0.hasUnseen }) ?? store.all.first { store.open(g) }
                } label: {
                    HStack(spacing: -9) {
                        ForEach(Array(stack.enumerated()), id: \.element.id) { i, g in
                            Avatar(url: API.media(g.user.photo), name: g.user.name ?? "?", size: 23)
                                .padding(1.6)
                                .overlay(StoryRing(unseen: g.hasUnseen, width: 1.6))
                                .background(Circle().fill(Color(.systemBackground)))
                                .zIndex(Double(3 - i))
                        }
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(0.5 + 0.5 * p)
                .opacity(Double(max(0, p * 1.6 - 0.6)))
                .frame(width: p < 0.05 ? 0 : nil)
                .clipped()
            }
            Text(title).font(.headline)
        }
        .animation(.snappy(duration: 0.22), value: p > 0.5)
    }
}

// MARK: - Просмотр историй

struct StoryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoriesStore.shared
    @State var groups: [StoryGroup]
    @State var gi: Int
    @State private var si = 0
    @State private var progress: CGFloat = 0
    @State private var paused = false
    @State private var ready = false
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var muted = false
    @State private var drag: CGFloat = 0
    @State private var reply = ""
    @FocusState private var replyFocus: Bool
    @State private var viewers = false
    @State private var likeBurst = false
    @State private var cube: CGFloat = 0

    init(start: StoryViewerStart) {
        _groups = State(initialValue: start.groups)
        _gi = State(initialValue: start.index)
        let g = start.groups[start.index]
        _si = State(initialValue: g.stories.firstIndex(where: { $0.seen != true }) ?? 0)
    }

    private var group: StoryGroup? { groups.indices.contains(gi) ? groups[gi] : nil }
    private var story: StoryItem? {
        guard let g = group, g.stories.indices.contains(si) else { return nil }
        return g.stories[si]
    }
    private var isMine: Bool { group?.user.id == store.me?.user.id }
    private var length: Double {
        guard let s = story else { return 5 }
        if s.isVideo { return max(1, s.dur ?? player?.currentItem?.duration.seconds.nonNaN ?? 15) }
        return 6
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let s = story {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        ScreenShield(enabled: s.allowShots == false && !isMine) {
                            media(s)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 130)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                            .allowsHitTesting(false)
                        header(s)
                        if let c = s.caption, !c.isEmpty {
                            VStack {
                                Spacer()
                                Text(c)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .allowsHitTesting(false)
                        }
                        if likeBurst {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 110))
                                .foregroundStyle(.red)
                                .shadow(radius: 20)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                                .frame(maxHeight: .infinity)
                        }
                    }
                    footer(s)
                }
                .id("\(gi)-\(si)")
            }
        }
        .offset(y: max(0, drag))
        .scaleEffect(1 - min(0.12, max(0, drag) / 2500))
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    guard !replyFocus else { return }
                    if abs(v.translation.height) > abs(v.translation.width) { drag = v.translation.height; paused = true }
                    else { cube = v.translation.width }
                }
                .onEnded { v in
                    if drag > 140 || v.predictedEndTranslation.height > 400 { close(); return }
                    if drag < -90, isMine { viewers = true }
                    if abs(v.translation.width) > 80 && abs(v.translation.width) > abs(v.translation.height) {
                        v.translation.width < 0 ? nextGroup() : prevGroup()
                    }
                    withAnimation(.spring(duration: 0.3)) { drag = 0; cube = 0 }
                    paused = false
                }
        )
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: "\(gi)-\(si)") { await prepare() }
        .task { await tick() }
        .onChange(of: replyFocus) { _, f in paused = f }
        .onChange(of: viewers) { _, v in paused = v }
        .sheet(isPresented: $viewers) {
            if let s = story { StoryViewersSheet(story: s) }
        }
        .onDisappear {
            player?.pause()
            store.resort()
        }
    }

    // MARK: медиа и касания
    @ViewBuilder private func media(_ s: StoryItem) -> some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.08)
                if s.isVideo, let player {
                    StoryVideoLayer(player: player)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                if !ready { ProgressView().tint(.white) }
                // касания: слева — назад, справа — вперёд, удержание — пауза
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).frame(width: geo.size.width * 0.33)
                        .onTapGesture { prev() }
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { next() }
                }
                .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 30, perform: {}, onPressingChanged: { p in paused = p })
            }
        }
    }

    private func header(_ s: StoryItem) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(Array((group?.stories ?? []).enumerated()), id: \.element.id) { i, _ in
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.35))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: g.size.width * (i < si ? 1 : i == si ? progress : 0))
                            }
                    }
                    .frame(height: 2.5)
                }
            }
            HStack(spacing: 10) {
                Avatar(url: API.media(group?.user.photo), name: group?.user.name ?? "?", size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMine ? String(localized: "Ваша история") : (group?.user.name ?? ""))
                        .font(.subheadline.bold())
                    Text(StoryTime.ago(s.at)).font(.caption).opacity(0.75)
                }
                Spacer()
                if isMine, let pr = s.privacy {
                    Image(systemName: StoryPrivacy(rawValue: pr)?.icon ?? "globe")
                        .font(.subheadline.bold())
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.18), in: Circle())
                }
                if s.isVideo {
                    Button {
                        muted.toggle(); player?.isMuted = muted; OxHaptics.play(.select)
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 32, height: 32)
                    }
                }
                if isMine {
                    Menu {
                        Button(role: .destructive) { askDelete(s) } label: { Label("Удалить историю", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32)
                    }
                }
                Button { close() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 32, height: 32)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    @ViewBuilder private func footer(_ s: StoryItem) -> some View {
        HStack(spacing: 12) {
            if isMine {
                Button { viewers = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                        Text("\(s.views ?? 0) " + RU.plural(s.views ?? 0, "просмотр", "просмотра", "просмотров"))
                        if (s.likes ?? 0) > 0 {
                            Image(systemName: "heart.fill").foregroundStyle(.red)
                            Text("\(s.likes ?? 0)")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button { askDelete(s) } label: { Image(systemName: "trash").font(.title3) }
            } else {
                TextField("Ответить сообщением…", text: $reply)
                    .focused($replyFocus)
                    .submitLabel(.send)
                    .onSubmit { sendReply(s) }
                    .padding(.horizontal, 16).frame(height: 44)
                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))
                if !reply.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { sendReply(s) } label: {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.black)
                            .frame(width: 40, height: 40).background(Color.lime, in: Circle())
                    }
                } else {
                    Button { like(s) } label: {
                        Image(systemName: s.liked == true ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(s.liked == true ? .red : .white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: логика
    private func prepare() async {
        guard let s = story, let g = group else { return }
        progress = 0
        ready = false
        image = nil
        player?.pause()
        player = nil
        if !isMine { store.markSeen(s, owner: g.user.id); groups[gi].stories[si].seen = true }
        guard let url = API.media(s.url) else { return }
        if s.isVideo {
            let p = AVPlayer(url: url)
            p.isMuted = muted
            player = p
            // ждём, пока видео начнёт играть
            for _ in 0..<150 {
                if p.currentItem?.status == .readyToPlay { break }
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            p.play()
            ready = true
        } else {
            if let (d, _) = try? await URLSession.shared.data(from: url), let i = UIImage(data: d) {
                if Task.isCancelled { return }
                image = i
            }
            ready = true
        }
    }

    private func tick() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            let dt = now.timeIntervalSince(last)
            last = now
            guard ready, !paused, drag == 0 else {
                if story?.isVideo == true { player?.pause() }
                continue
            }
            if let s = story, s.isVideo, let p = player {
                if p.timeControlStatus != .playing { p.play() }
                let d = p.currentItem?.duration.seconds.nonNaN ?? length
                progress = CGFloat(min(1, p.currentTime().seconds / max(0.5, d)))
            } else {
                progress = min(1, progress + CGFloat(dt / length))
            }
            if progress >= 1 { next() }
        }
    }

    private func next() {
        guard let g = group else { return }
        if si + 1 < g.stories.count { si += 1 } else { nextGroup() }
    }
    private func prev() {
        if si > 0 { si -= 1 } else if gi > 0 { prevGroup() } else { progress = 0; player?.seek(to: .zero) }
    }
    private func nextGroup() {
        if gi + 1 < groups.count {
            withAnimation(.snappy) { gi += 1 }
            si = groups[gi].stories.firstIndex(where: { $0.seen != true }) ?? 0
            OxHaptics.play(.select)
        } else { close() }
    }
    private func prevGroup() {
        guard gi > 0 else { return }
        withAnimation(.snappy) { gi -= 1 }
        si = 0
        OxHaptics.play(.select)
    }
    private func close() {
        player?.pause()
        dismiss()
    }

    private func like(_ s: StoryItem) {
        let was = s.liked == true
        groups[gi].stories[si].liked = !was
        if !was {
            Haptic.success()
            withAnimation(.spring(duration: 0.35, bounce: 0.5)) { likeBurst = true }
            Task { try? await Task.sleep(for: .milliseconds(650)); withAnimation(.easeOut(duration: 0.25)) { likeBurst = false } }
        }
        struct R: Decodable { let liked: Bool }
        Task {
            do {
                let r: R = try await API.call("/stories/\(s.id)/like", method: "POST")
                if groups.indices.contains(gi), let i = groups[gi].stories.firstIndex(where: { $0.id == s.id }) { groups[gi].stories[i].liked = r.liked }
            } catch {
                OxAlert.error(error.localizedDescription)
            }
        }
    }

    private func sendReply(_ s: StoryItem) {
        let t = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        reply = ""
        replyFocus = false
        Task {
            do {
                let _: OK = try await API.call("/stories/\(s.id)/reply", method: "POST", body: ["text": t])
                Haptic.success()
                OxAlert.show(icon: "paperplane.fill", title: String(localized: "Ответ отправлен"), message: String(localized: "Сообщение появится в личном чате"))
            } catch {
                OxAlert.error(error.localizedDescription)
            }
        }
    }

    private func askDelete(_ s: StoryItem) {
        paused = true
        OxAlert.confirm(title: String(localized: "Удалить историю?"), message: String(localized: "Её больше никто не увидит."), action: String(localized: "Удалить"), destructive: true) {
            Task {
                if await store.delete(s) {
                    groups[gi].stories.removeAll { $0.id == s.id }
                    if groups[gi].stories.isEmpty { close() } else { si = min(si, groups[gi].stories.count - 1); paused = false }
                }
            }
        }
    }
}

private extension Double {
    var nonNaN: Double? { isNaN || isInfinite || self <= 0 ? nil : self }
}

private struct StoryVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var pl: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.player = player; v.pl.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: V, context: Context) { v.pl.player = player }
}

enum StoryTime {
    static func ago(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        if Date().timeIntervalSince(d) < 60 { return String(localized: "только что") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: L10n.lang)
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Кто посмотрел

struct StoryViewersSheet: View {
    let story: StoryItem
    @State private var items: [Viewer] = []
    @State private var loaded = false

    struct Viewer: Decodable, Identifiable { let id: Int; let name: String?; let photo: String?; let at: Double; let liked: Bool? }
    private struct Resp: Decodable { let items: [Viewer] }

    var body: some View {
        NavigationStack {
            List(items) { v in
                HStack(spacing: 12) {
                    Avatar(url: API.media(v.photo), name: v.name ?? "?", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.name ?? "Пользователь").font(.body.weight(.medium))
                        Text(StoryTime.ago(v.at)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if v.liked == true { Image(systemName: "heart.fill").foregroundStyle(.red) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if !loaded { ProgressView() }
                else if items.isEmpty {
                    ContentUnavailableView("Пока никто не смотрел", systemImage: "eye.slash",
                                           description: Text("Здесь появятся те, кто открыл историю"))
                }
            }
            .navigationTitle("\(items.count) " + RU.plural(items.count, "просмотр", "просмотра", "просмотров"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .task {
            if let r: Resp = try? await API.call("/stories/\(story.id)/viewers") { items = r.items }
            loaded = true
        }
    }
}

// MARK: - Создание истории

enum StoryPrivacy: String, CaseIterable, Identifiable {
    case all, contacts, close, selected
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .all: "Все"
        case .contacts: "Мои контакты"
        case .close: "Близкие друзья"
        case .selected: "Выбранные пользователи"
        }
    }
    var icon: String {
        switch self {
        case .all: "globe"
        case .contacts: "person.crop.circle"
        case .close: "star.fill"
        case .selected: "person.2.fill"
        }
    }
    var color: Color {
        switch self {
        case .all: Color(hex: 0x0A84FF)
        case .contacts: Color(hex: 0xAF52DE)
        case .close: Color(hex: 0x34C759)
        case .selected: Color(hex: 0xFF9500)
        }
    }
}

/// Видео из галереи как файл
struct StoryMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { r in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("story-\(UUID().uuidString).\(r.file.pathExtension.isEmpty ? "mov" : r.file.pathExtension)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: r.file, to: dst)
            return StoryMovie(url: dst)
        }
    }
}

enum StoryMedia: Equatable {
    case photo(UIImage)
    case video(URL)
}

struct StoryComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var media: StoryMedia?
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var caption = ""
    @State private var share = false
    @State private var loading = false
    @State private var previewPlayer: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let media {
                    editor(media)
                } else {
                    StoryCameraScreen(onMedia: { m in
                        if case .video(let u) = m { previewPlayer = AVPlayer(url: u) }
                        withAnimation(.snappy) { media = m }
                    }, onClose: { dismiss() })
                }
                if loading { ProgressView().tint(.white).controlSize(.large) }
            }
            .toolbar {
                if media != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { reset() } label: { Image(systemName: "chevron.left") }
                    }
                }
            }
            .toolbar(media == nil ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .onChange(of: pick) { _, it in if let it { Task { await load(it) } } }
        .fullScreenCover(isPresented: $camera) {
            StoryCameraPicker { m in media = m; if case .video(let u) = m { previewPlayer = AVPlayer(url: u) } }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $share) {
            if let media {
                StoryShareSheet(media: media, caption: caption) { dismiss() }
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 54))
                .foregroundStyle(Color.lime)
            Text("Новая история").font(.title2.bold()).foregroundStyle(.white)
            Text("Фото или видео до 60 секунд. Через 24 часа история исчезнет.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
            HStack(spacing: 14) {
                Button { camera = true } label: {
                    tile(icon: "camera.fill", title: "Камера")
                }
                PhotosPicker(selection: $pick, matching: .any(of: [.images, .videos]), preferredItemEncoding: .compatible) {
                    tile(icon: "photo.on.rectangle.angled", title: "Галерея")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func tile(icon: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title)
            Text(title).font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func editor(_ m: StoryMedia) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Group {
                    switch m {
                    case .photo(let i):
                        Color.clear.overlay { Image(uiImage: i).resizable().scaledToFill() }
                    case .video:
                        if let previewPlayer {
                            StoryVideoLayer(player: previewPlayer)
                                .onAppear { previewPlayer.play(); loopVideo() }
                                .onDisappear { previewPlayer.pause() }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                TextField("Добавить подпись…", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(12)
            }
            HStack {
                Spacer()
                Button { share = true } label: {
                    HStack(spacing: 6) {
                        Text("ДАЛЕЕ").font(.subheadline.weight(.heavy))
                        Image(systemName: "chevron.right").font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(Color.lime, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 4)
    }

    private func loopVideo() {
        guard let p = previewPlayer else { return }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            p.seek(to: .zero); p.play()
        }
    }

    private func reset() {
        previewPlayer?.pause()
        previewPlayer = nil
        media = nil
        pick = nil
        caption = ""
    }

    private func load(_ it: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        if it.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let mv = try? await it.loadTransferable(type: StoryMovie.self) {
                previewPlayer = AVPlayer(url: mv.url)
                media = .video(mv.url)
            } else {
                OxAlert.error(String(localized: "Не удалось открыть видео"))
            }
        } else if let d = try? await it.loadTransferable(type: Data.self), let i = UIImage(data: d) {
            media = .photo(i)
        } else {
            OxAlert.error(String(localized: "Не удалось открыть фото"))
        }
    }
}

/// Системная камера: фото или видео до 60 секунд
struct StoryCameraPicker: UIViewControllerRepresentable {
    var onPick: (StoryMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        p.videoMaximumDuration = 60
        p.videoQuality = .typeHigh
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: StoryCameraPicker
        init(_ p: StoryCameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let u = info[.mediaURL] as? URL {
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("story-\(UUID().uuidString).\(u.pathExtension.isEmpty ? "mov" : u.pathExtension)")
                try? FileManager.default.copyItem(at: u, to: dst)
                parent.onPick(.video(dst))
            } else if let i = info[.originalImage] as? UIImage {
                parent.onPick(.photo(i))
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - «Поделиться историей»

struct StoryShareSheet: View {
    let media: StoryMedia
    let caption: String
    var done: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("story.privacy") private var privacyRaw = StoryPrivacy.all.rawValue
    @AppStorage("story.allowShots") private var allowShots = true
    @State private var closeCount = 0
    @State private var selected: Set<Int> = []
    @State private var pickClose = false
    @State private var pickSelected = false
    @State private var sending = false
    @State private var status = ""

    private var privacy: StoryPrivacy { StoryPrivacy(rawValue: privacyRaw) ?? .all }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(StoryPrivacy.allCases) { p in
                        Button {
                            privacyRaw = p.rawValue
                            OxHaptics.play(.select)
                            if p == .selected && selected.isEmpty { pickSelected = true }
                            if p == .close && closeCount == 0 { pickClose = true }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: privacy == p ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(privacy == p ? Color.limeInk : Color.secondary)
                                Image(systemName: p.icon)
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(p.color, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.title).foregroundStyle(.primary)
                                    if let sub = subtitle(p) {
                                        Text(sub).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if p == .close || p == .selected {
                                    Button { if p == .close { pickClose = true } else { pickSelected = true } } label: {
                                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Кто видит эту историю")
                } footer: {
                    Text("Контакты — те, на кого вы подписаны, и те, с кем у вас есть переписка.")
                }
                Section {
                    Toggle("Разрешить снимки экрана", isOn: $allowShots)
                } footer: {
                    Text(allowShots ? "Зрители смогут делать снимки и запись экрана." : "На снимке и записи экрана вместо истории будет пусто.")
                }
            }
            .navigationTitle("Поделиться историей")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await publish() } } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.black) }
                        Text(sending ? (status.isEmpty ? String(localized: "Публикуем…") : status) : String(localized: "Опубликовать историю"))
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(sending || (privacy == .selected && selected.isEmpty))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            .sheet(isPresented: $pickClose) {
                StoryPeoplePicker(title: "Близкие друзья", initial: nil) { ids in
                    closeCount = ids.count
                    Task { let _: OK? = try? await API.call("/stories/close", method: "POST", body: ["ids": Array(ids)]) }
                }
            }
            .sheet(isPresented: $pickSelected) {
                StoryPeoplePicker(title: "Выбранные пользователи", initial: selected) { ids in selected = ids }
            }
            .task {
                struct R: Decodable { let items: [StoryUser] }
                if let r: R = try? await API.call("/stories/close") { closeCount = r.items.count }
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func subtitle(_ p: StoryPrivacy) -> String? {
        switch p {
        case .close: closeCount > 0 ? "\(closeCount) " + RU.plural(closeCount, "человек", "человека", "человек") : String(localized: "Выбрать")
        case .selected: selected.isEmpty ? String(localized: "Выбрать") : "\(selected.count) " + RU.plural(selected.count, "человек", "человека", "человек")
        default: nil
        }
    }

    private func publish() async {
        sending = true
        defer { sending = false }
        var fields: [String: String] = [
            "caption": caption.trimmingCharacters(in: .whitespacesAndNewlines),
            "privacy": privacy.rawValue,
            "allow_shots": allowShots ? "1" : "0"
        ]
        if privacy == .selected { fields["selected"] = selected.map(String.init).joined(separator: ",") }
        let data: Data, name: String, mime: String
        switch media {
        case .photo(let i):
            guard let d = API.jpeg(i, maxSide: 1920) else { OxAlert.error(String(localized: "Не удалось подготовить фото")); return }
            data = d; name = "story.jpg"; mime = "image/jpeg"
        case .video(let u):
            status = String(localized: "Сжимаем видео…")
            guard let r = await StoryVideo.prepare(u) else {
                OxAlert.error(String(localized: "Не удалось подготовить видео"))
                return
            }
            if r.duration > 61 {
                OxAlert.error(String(localized: "Видео длиннее 60 секунд. Обрежьте его в «Фото» и попробуйте снова."))
                return
            }
            guard r.data.count < 60 * 1024 * 1024 else {
                OxAlert.error(String(localized: "Видео больше 60 МБ"))
                return
            }
            data = r.data; name = "story.mp4"; mime = "video/mp4"
            fields["dur"] = String(format: "%.1f", r.duration)
        }
        status = String(localized: "Загружаем…")
        StoriesStore.shared.uploading = true
        defer { StoriesStore.shared.uploading = false }
        do {
            let _: OK = try await API.upload("/stories", fields: fields, data: data, filename: name, mime: mime)
            Haptic.success()
            await StoriesStore.shared.load()
            dismiss()
            done()
        } catch {
            Haptic.error()
            OxAlert.error(error.localizedDescription)
        }
    }
}

enum StoryVideo {
    /// Сжимаем до 720p mp4: 60 секунд ≈ 25–40 МБ
    static func prepare(_ url: URL) async -> (data: Data, duration: Double)? {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("story-out-\(UUID().uuidString).mp4")
        if let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) {
            ex.shouldOptimizeForNetworkUse = true
            do {
                try await ex.export(to: out, as: .mp4)
                if let d = try? Data(contentsOf: out) {
                    try? FileManager.default.removeItem(at: out)
                    return (d, dur)
                }
            } catch {}
        }
        // запасной путь — исходный файл как есть
        guard let d = try? Data(contentsOf: url) else { return nil }
        return (d, dur)
    }
}

/// Выбор людей из контактов (близкие друзья / выбранные)
struct StoryPeoplePicker: View {
    let title: LocalizedStringKey
    let initial: Set<Int>?
    var onDone: (Set<Int>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [StoryUser] = []
    @State private var chosen: Set<Int> = []
    @State private var loaded = false
    @State private var q = ""

    private struct R: Decodable { let items: [StoryUser] }

    var body: some View {
        NavigationStack {
            List {
                let list = q.isEmpty ? items : items.filter { ($0.name ?? "").localizedCaseInsensitiveContains(q) }
                ForEach(list, id: \.id) { u in
                    Button {
                        if chosen.contains(u.id) { chosen.remove(u.id) } else { chosen.insert(u.id) }
                        OxHaptics.play(.select)
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(url: API.media(u.photo), name: u.name ?? "?", size: 40)
                            Text(u.name ?? "Пользователь").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: chosen.contains(u.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(chosen.contains(u.id) ? Color.limeInk : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(text: $q, prompt: "Поиск")
            .overlay {
                if !loaded { ProgressView() }
                else if items.isEmpty {
                    ContentUnavailableView("Нет контактов", systemImage: "person.2.slash",
                                           description: Text("Подпишитесь на людей или начните переписку — они появятся здесь"))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { onDone(chosen); dismiss() }.fontWeight(.bold)
                }
            }
        }
        .task {
            if let r: R = try? await API.call("/stories/contacts") { items = r.items }
            if let initial { chosen = initial }
            else if let r: R = try? await API.call("/stories/close") { chosen = Set(r.items.map(\.id)) }
            loaded = true
        }
    }
}
