import SwiftUI
import Lottie

// Анимированные стикеры как в Telegram: панель вместо клавиатуры, «Недавние», «Избранные», наборы.
// Нажатие — отправить, долгое удержание — превью и меню. Файлы наборов лежат в приложении (Lottie из .tgs).

enum StickerPacks {
    struct Pack: Identifiable { let id: String; let title: String; let count: Int }
    static let all: [Pack] = [Pack(id: "chameleo", title: "Chameleo", count: 20)]

    static func refs(_ p: Pack) -> [String] { (1...p.count).map { String(format: "%@/%03d", p.id, $0) } }
    static func file(_ ref: String) -> String { ref.replacingOccurrences(of: "/", with: "-") }
    static func pack(of ref: String) -> Pack? { all.first { ref.hasPrefix($0.id + "/") } }
    static func isAnimated(_ ref: String) -> Bool { pack(of: ref) != nil }
}

/// Недавние и избранные — на iPhone
@MainActor @Observable
final class StickerStore {
    static let shared = StickerStore()
    var recent: [String] = UserDefaults.standard.stringArray(forKey: "stk.recent") ?? []
    var favorites: [String] = UserDefaults.standard.stringArray(forKey: "stk.fav") ?? []

    func used(_ ref: String) {
        recent.removeAll { $0 == ref }
        recent.insert(ref, at: 0)
        recent = Array(recent.prefix(20))
        UserDefaults.standard.set(recent, forKey: "stk.recent")
    }
    func toggleFavorite(_ ref: String) {
        if favorites.contains(ref) { favorites.removeAll { $0 == ref } } else { favorites.insert(ref, at: 0) }
        UserDefaults.standard.set(favorites, forKey: "stk.fav")
    }
    func clearRecent() {
        recent = []
        UserDefaults.standard.set(recent, forKey: "stk.recent")
    }
}

/// Один стикер: Lottie по кругу; старые «gto» — эмодзи
struct StickerView: View {
    let ref: String
    var size: CGFloat = 160
    var playing = true

    var body: some View {
        Group {
            if StickerPacks.isAnimated(ref) {
                LottieView(animation: .named(StickerPacks.file(ref), bundle: .main))
                    .playbackMode(playing ? .playing(.toProgress(1, loopMode: .loop)) : .paused(at: .progress(0)))
                    .resizable()
            } else {
                Text("🎨").font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Панель стикеров

struct StickerPanel: View {
    var onSend: (_ ref: String, _ silent: Bool) -> Void
    var onEmoji: (String) -> Void

    enum Mode { case stickers, emoji }
    @State private var mode: Mode = .stickers
    @State private var store = StickerStore.shared
    @State private var preview: String?
    @State private var packSheet: StickerPacks.Pack?
    @Namespace private var ns

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    private static let emojis = Array("😀😁😂🤣😊😍😘😎🤩🥳😏😴🤔🤯😤😡🥶🤗👍👎👏🙌💪🔥⚡️💯✅❤️🧡💚💙💜🖤🤍🎉🏆🥇🏋️🏃‍♂️🚴‍♀️🧘‍♀️🍎🥗🍗🥚🥤☕️🍫😅🙏👀").map(String.init)

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if mode == .stickers { packBar(proxy) }
                    ScrollView {
                        if mode == .stickers { stickers } else { emojiGrid }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            modeBar
        }
        .frame(height: 320)
        .background(.bar)
        .overlay {
            if let p = preview {
                StickerPreviewOverlay(ref: p,
                                      favorite: store.favorites.contains(p),
                                      onSend: { silent in send(p, silent: silent); preview = nil },
                                      onFavorite: { store.toggleFavorite(p); preview = nil },
                                      onPack: { packSheet = StickerPacks.pack(of: p); preview = nil },
                                      onClose: { preview = nil })
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3), value: preview)
        .sheet(item: $packSheet) { p in StickerPackSheet(pack: p) { ref in send(ref, silent: false); packSheet = nil } }
    }

    private func send(_ ref: String, silent: Bool) {
        store.used(ref)
        Haptic.tap()
        onSend(ref, silent)
    }

    private func packBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                if !store.recent.isEmpty {
                    Button { withAnimation { proxy.scrollTo("recent", anchor: .top) } } label: { Image(systemName: "clock").font(.title3) }
                }
                if !store.favorites.isEmpty {
                    Button { withAnimation { proxy.scrollTo("fav", anchor: .top) } } label: { Image(systemName: "bookmark").font(.title3) }
                }
                ForEach(StickerPacks.all) { p in
                    Button { withAnimation { proxy.scrollTo(p.id, anchor: .top) } } label: {
                        StickerView(ref: StickerPacks.refs(p)[0], size: 30, playing: false)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var stickers: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            if !store.recent.isEmpty {
                header("НЕДАВНИЕ", id: "recent") { store.clearRecent() }
                grid(store.recent)
            }
            if !store.favorites.isEmpty {
                header("ИЗБРАННЫЕ СТИКЕРЫ", id: "fav", clear: nil)
                grid(store.favorites)
            }
            ForEach(StickerPacks.all) { p in
                header(p.title.uppercased(), id: p.id, clear: nil)
                grid(StickerPacks.refs(p))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 70)
    }

    private func header(_ t: String, id: String, clear: (() -> Void)?) -> some View {
        HStack {
            Text(t).font(.caption2.bold()).foregroundStyle(.secondary)
            Spacer()
            if let clear {
                Button { clear() } label: { Image(systemName: "xmark").font(.caption2.bold()) }.foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .id(id)
    }

    private func grid(_ refs: [String]) -> some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(refs, id: \.self) { r in
                StickerCell(ref: r, onTap: { send(r, silent: false) }, onHold: {
                    Haptic.tap(.medium)
                    preview = r
                })
            }
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
            ForEach(Self.emojis, id: \.self) { e in
                Button { onEmoji(e); Haptic.tap(.soft) } label: { Text(e).font(.system(size: 30)) }
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .padding(.bottom, 70)
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            seg("Стикеры", .stickers)
            seg("Эмодзи", .emoji)
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 10)
    }

    private func seg(_ t: String, _ m: Mode) -> some View {
        Button { withAnimation(.spring(duration: 0.3)) { mode = m } } label: {
            Text(t).font(.footnote.bold())
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background {
                    if mode == m { Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "seg", in: ns) }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Ячейка: нажатие — отправить, долгое удержание — превью
private struct StickerCell: View {
    let ref: String
    var onTap: () -> Void
    var onHold: () -> Void
    @State private var pressed = false

    var body: some View {
        StickerView(ref: ref, size: 62)
            .frame(maxWidth: .infinity)
            .scaleEffect(pressed ? 0.86 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: pressed)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressed = $0 }) { onHold() }
    }
}

/// Крупное превью по долгому нажатию + меню, как в Telegram
struct StickerPreviewOverlay: View {
    let ref: String
    var favorite: Bool
    var onSend: (_ silent: Bool) -> Void
    var onFavorite: () -> Void
    var onPack: () -> Void
    var onClose: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 14) {
                StickerView(ref: ref, size: 190)
                    .scaleEffect(shown ? 1 : 0.6)
                VStack(spacing: 0) {
                    item("Отправить", "paperplane") { onSend(false) }
                    Divider()
                    item("Отправить без звука", "bell.slash") { onSend(true) }
                    Divider()
                    item(favorite ? "Удалить из Избранного" : "В Избранное", favorite ? "bookmark.slash" : "bookmark") { onFavorite() }
                    Divider()
                    item("Посмотреть набор", "square.grid.2x2") { onPack() }
                }
                .frame(width: 250)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 20)
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.35)) { shown = true } }
    }

    private func item(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(t)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension StickerPacks.Pack: Hashable {
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Весь набор
struct StickerPackSheet: View {
    let pack: StickerPacks.Pack
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(StickerPacks.refs(pack), id: \.self) { r in
                        Button { onSend(r) } label: { StickerView(ref: r, size: 76) }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .navigationTitle(pack.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Распад удалённого сообщения на частицы

struct DissolveModifier: ViewModifier {
    let start: Date?
    static let duration: TimeInterval = 1.1

    func body(content: Content) -> some View {
        if let start {
            TimelineView(.animation) { tl in
                let t = min(1, tl.date.timeIntervalSince(start) / Self.duration)
                // запас вокруг пузыря, чтобы частицы могли разлететься за его края
                content
                    .padding(60)
                    .visualEffect { c, proxy in
                        c.layerEffect(ShaderLibrary.oxDissolve(.float(t), .float2(proxy.size)),
                                      maxSampleOffset: CGSize(width: 100, height: 100))
                    }
                    .padding(-60)
            }
        } else {
            content
        }
    }
}
