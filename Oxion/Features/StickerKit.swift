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
    static func isAnimated(_ ref: String) -> Bool { pack(of: ref) != nil || PremiumEmoji.isEmoji(ref) }
}

/// Недавние и избранные — на iPhone
@MainActor @Observable
final class StickerStore {
    static let shared = StickerStore()
    var recent: [String] = UserDefaults.standard.stringArray(forKey: "stk.recent") ?? []
    var favorites: [String] = UserDefaults.standard.stringArray(forKey: "stk.fav") ?? []
    /// наборы, добавленные в «Мои стикеры» (Chameleo — по умолчанию)
    var packs: [String] = UserDefaults.standard.stringArray(forKey: "stk.packs") ?? ["chameleo"]

    var archived: [String] = UserDefaults.standard.stringArray(forKey: "stk.archived") ?? []
    var recentPacks: [String] = UserDefaults.standard.stringArray(forKey: "stk.recentPacks") ?? []
    var recentFirst: Bool = UserDefaults.standard.bool(forKey: "stk.recentFirst") {
        didSet { UserDefaults.standard.set(recentFirst, forKey: "stk.recentFirst") }
    }

    /// мои наборы в нужном порядке («Сначала недавние» — последние использованные выше)
    var orderedPacks: [StickerPacks.Pack] {
        var ids = packs
        if recentFirst {
            ids.sort { (recentPacks.firstIndex(of: $0) ?? 999) < (recentPacks.firstIndex(of: $1) ?? 999) }
        }
        return ids.compactMap { id in StickerPacks.all.first { $0.id == id } }
    }

    func hasPack(_ id: String) -> Bool { packs.contains(id) }
    func movePacks(from: IndexSet, to: Int) {
        packs.move(fromOffsets: from, toOffset: to)
        UserDefaults.standard.set(packs, forKey: "stk.packs")
    }
    func removePacks(_ ids: Set<String>) {
        packs.removeAll { ids.contains($0) }
        UserDefaults.standard.set(packs, forKey: "stk.packs")
    }
    func archive(_ ids: Set<String>) {
        removePacks(ids)
        archived = Array(Set(archived).union(ids))
        UserDefaults.standard.set(archived, forKey: "stk.archived")
    }
    func unarchive(_ id: String) {
        archived.removeAll { $0 == id }
        UserDefaults.standard.set(archived, forKey: "stk.archived")
        if !packs.contains(id) { packs.insert(id, at: 0); UserDefaults.standard.set(packs, forKey: "stk.packs") }
    }
    func togglePack(_ id: String) {
        if packs.contains(id) { packs.removeAll { $0 == id } } else { packs.insert(id, at: 0) }
        UserDefaults.standard.set(packs, forKey: "stk.packs")
    }

    func used(_ ref: String) {
        if let p = StickerPacks.pack(of: ref)?.id {
            recentPacks.removeAll { $0 == p }
            recentPacks.insert(p, at: 0)
            UserDefaults.standard.set(recentPacks, forKey: "stk.recentPacks")
        }
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

/// Разобранные анимации: файл читается один раз и не в главном потоке — чат не подвисает
@MainActor
final class StickerCache {
    static let shared = StickerCache()
    private var cache: [String: LottieAnimation] = [:]
    private var loading: [String: Task<LottieAnimation?, Never>] = [:]

    func cached(_ name: String) -> LottieAnimation? { cache[name] }

    func animation(_ name: String) async -> LottieAnimation? {
        if let a = cache[name] { return a }
        if let t = loading[name] { return await t.value }
        let t = Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return try? LottieAnimation.from(data: data)
        }
        loading[name] = t
        let a = await t.value
        cache[name] = a
        loading[name] = nil
        return a
    }
}

/// Один стикер: Lottie по кругу; старые «gto» — эмодзи
struct StickerView: View {
    let ref: String
    var size: CGFloat = 160
    var playing = true
    @State private var anim: LottieAnimation?

    var body: some View {
        Group {
            if StickerPacks.isAnimated(ref) {
                if let a = anim ?? StickerCache.shared.cached(StickerPacks.file(ref)) {
                    // Core Animation: анимация крутится вне главного потока
                    LottieView(animation: a)
                        .configuration(LottieConfiguration(renderingEngine: .coreAnimation))
                        .playbackMode(playing ? .playing(.toProgress(1, loopMode: .loop)) : .paused(at: .progress(0)))
                        .resizable()
                } else {
                    Color.clear
                        .task { anim = await StickerCache.shared.animation(StickerPacks.file(ref)) }
                }
            } else {
                Text("🎨").font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Панель стикеров (как в Telegram: скруглённая сверху, под полем ввода)

struct StickerPanel: View {
    var onSend: (_ ref: String, _ silent: Bool) -> Void
    var onEmoji: (String) -> Void
    /// премиум-эмодзи: вставить метку в текст
    var onPremiumEmoji: (String) -> Void = { _ in }
    @State private var premium = PremiumStatus.shared
    @State private var upsell = false

    enum Mode { case stickers, emoji }
    @State private var mode: Mode = .stickers
    @State private var store = StickerStore.shared
    @State private var preview: String?
    @State private var packSheet: StickerPacks.Pack?
    @State private var settings = false
    @State private var section = ""
    @Namespace private var ns

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    static let emojis = Array("😀😁😂🤣😊😍😘😎🤩🥳😏😴🤔🤯😤😡🥶🤗👍👎👏🙌💪🔥⚡️💯✅❤️🧡💚💙💜🖤🤍🎉🏆🥇🏋️🏃‍♂️🚴‍♀️🧘‍♀️🍎🥗🍗🥚🥤☕️🍫😅🙏👀").map(String.init)

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if mode == .stickers { packBar(proxy) } else { Color.clear.frame(height: 10) }
                    Divider().opacity(0.4)
                    ScrollView {
                        if mode == .stickers { stickers } else { emojiGrid }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            bottomBar
        }
        .frame(height: 330)
        // фон панели уходит под полоску «домой» — без пустой полосы снизу
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Color(white: 0.08))
                .shadow(color: .black.opacity(0.35), radius: 16, y: -4)
                .padding(.bottom, -120)
                .ignoresSafeArea(edges: .bottom)
        )

        .environment(\.colorScheme, .dark)
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
        .sheet(item: $packSheet) { p in StickerPackSheet(pack: p, onSend: { ref in send(ref, silent: false); packSheet = nil }) }
        .sheet(isPresented: $settings) { StickerSettingsView() }
    }

    private var myPacks: [StickerPacks.Pack] { store.orderedPacks }

    private func send(_ ref: String, silent: Bool) {
        store.used(ref)
        Haptic.tap()
        onSend(ref, silent)
    }

    private func packBar(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                barIcon("plus.square.on.square", id: "add") { settings = true }
                if !store.favorites.isEmpty { barIcon("bookmark", id: "fav") { jump("fav", proxy) } }
                if !store.recent.isEmpty { barIcon("clock", id: "recent") { jump("recent", proxy) } }
                ForEach(myPacks) { p in
                    Button { jump(p.id, proxy) } label: {
                        StickerView(ref: StickerPacks.refs(p)[0], size: 30, playing: false)
                            .frame(width: 40, height: 40)
                            .background(section == p.id ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12).padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func barIcon(_ icon: String, id: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(section == id ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func jump(_ id: String, _ proxy: ScrollViewProxy) {
        Haptic.tap(.soft)
        section = id
        withAnimation(.spring(duration: 0.35)) { proxy.scrollTo(id, anchor: .top) }
    }

    private var stickers: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            if !store.favorites.isEmpty {
                header("ИЗБРАННЫЕ СТИКЕРЫ", id: "fav", clear: nil)
                grid(store.favorites)
            }
            if !store.recent.isEmpty {
                header("НЕДАВНИЕ", id: "recent") { store.clearRecent() }
                grid(store.recent)
            }
            ForEach(myPacks) { p in
                header(p.title.uppercased(), id: p.id, clear: nil)
                grid(StickerPacks.refs(p))
            }
            if myPacks.isEmpty && store.recent.isEmpty && store.favorites.isEmpty {
                Button { settings = true } label: {
                    Label("Добавить стикеры", systemImage: "plus.circle.fill").font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 80)
    }

    private func header(_ t: String, id: String, clear: (() -> Void)?) -> some View {
        ZStack {
            Text(t).font(.caption.bold()).foregroundStyle(.secondary)
            if let clear {
                HStack {
                    Spacer()
                    Button { clear() } label: { Image(systemName: "xmark").font(.caption.bold()) }.foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 2)
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
        LazyVStack(spacing: 6) {
            // анимированные премиум-эмодзи
            ForEach(PremiumEmoji.packs) { p in
                header(p.title.uppercased(), id: "e-" + p.id, clear: nil)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 8) {
                    ForEach(StickerPacks.refs(p), id: \.self) { r in
                        StickerView(ref: r, size: 36)
                            .opacity(premium.active ? 1 : 0.85)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if premium.active {
                                    Haptic.tap(.soft)
                                    onPremiumEmoji(PremiumEmoji.token(r))
                                } else {
                                    upsell = true
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                if !premium.active {
                    Button { upsell = true } label: {
                        Label("Получить \(p.title)", systemImage: "lock.fill")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(hex: 0x7B5CFF))
                    .padding(.horizontal, 12).padding(.top, 4)
                }
            }
            header("ЭМОДЗИ", id: "e-std", clear: nil)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(Self.emojis, id: \.self) { e in
                    Button { onEmoji(e); Haptic.tap(.soft) } label: { Text(e).font(.system(size: 30)) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 80)
        .task { await premium.refresh() }
        .sheet(isPresented: $upsell) { PremiumEmojiUpsell() }
    }

    // снизу: «Стикеры | Эмодзи» по центру и шестерёнка справа, как в Telegram
    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 2) {
                seg("Стикеры", .stickers)
                seg("Эмодзи", .emoji)
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            HStack {
                Spacer()
                Button { settings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.trailing, 16)
        }
        .padding(.bottom, 12)
    }

    private func seg(_ t: String, _ m: Mode) -> some View {
        Button { withAnimation(.spring(duration: 0.3)) { mode = m } } label: {
            Text(t).font(.subheadline.bold())
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background {
                    if mode == m { Capsule().fill(Color.white.opacity(0.14)).matchedGeometryEffect(id: "seg", in: ns) }
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

/// Весь набор: как в Telegram — сетка, «Добавить N стикеров» / «Удалить N стикеров»
struct StickerPackSheet: View {
    let pack: StickerPacks.Pack
    var onSend: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var store = StickerStore.shared

    var body: some View {
        let added = store.hasPack(pack.id)
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Spacer()
                Text(pack.title).font(.headline)
                Spacer()
                ShareLink(item: "Набор стикеров «\(pack.title)» в Oxion") {
                    Image(systemName: "ellipsis").font(.headline).frame(width: 36, height: 36)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 8) {
                ForEach(StickerPacks.refs(pack), id: \.self) { r in
                    StickerView(ref: r, size: 64)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let onSend else { return }
                            onSend(r)
                        }
                }
            }
            .padding(.horizontal, 12)

            Button {
                Haptic.success()
                store.togglePack(pack.id)
                OxAlert.show(icon: added ? "trash.fill" : "checkmark.circle.fill", tint: added ? .red : Color.lime,
                             title: added ? "Стикеры удалены" : "Стикеры добавлены",
                             message: added ? "Набор \(pack.title) удалён из ваших стикеров" : "Набор \(pack.title) добавлен в ваши стикеры")
                dismiss()
            } label: {
                Text(added ? "Удалить \(pack.count) стикеров" : "Добавить \(pack.count) стикеров")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(added ? Color.red.opacity(0.85) : Color.lime)
            .foregroundStyle(added ? Color.white : Color.onLime)
            .controlSize(.large)
            .padding(16)
        }
        .background(Color.oxBg)
        .fitSheet()
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
    }
}

/// Меню стикера в переписке по долгому нажатию — сам стикер крупно, без квадратной подложки
struct ChatStickerMenu: View {
    let m: Message
    var reactions: [String]
    var onReact: (String) -> Void
    var onReply: () -> Void
    var onPack: () -> Void
    var onDelete: (() -> Void)?
    var onClose: () -> Void
    @State private var shown = false
    @State private var store = StickerStore.shared

    private var ref: String { m.card?["id"]?.string ?? "" }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(reactions, id: \.self) { e in
                        Button { onReact(e); close() } label: { Text(e).font(.system(size: 28)).frame(width: 40, height: 40) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .scaleEffect(shown ? 1 : 0.7)
                .opacity(shown ? 1 : 0)

                StickerView(ref: ref, size: 200)
                    .scaleEffect(shown ? 1 : 0.7)

                VStack(spacing: 0) {
                    row("Ответить", "arrowshape.turn.up.left") { onReply(); close() }
                    Divider()
                    row(store.favorites.contains(ref) ? "Удалить из Избранного" : "В Избранное",
                        store.favorites.contains(ref) ? "bookmark.slash" : "bookmark") { store.toggleFavorite(ref); close() }
                    if StickerPacks.pack(of: ref) != nil {
                        Divider()
                        row("Посмотреть набор", "square.grid.2x2") { close(); onPack() }
                    }
                    if let onDelete {
                        Divider()
                        row("Удалить", "trash", red: true) { close(); onDelete() }
                    }
                }
                .frame(width: 250)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 16)
            }
        }
        .onAppear {
            Haptic.tap(.medium)
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { shown = true }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        onClose()
    }

    private func row(_ t: String, _ icon: String, red: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(t)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(red ? Color.red : Color.primary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Распад удалённого сообщения на частицы

struct DissolveModifier: ViewModifier {
    let start: Date?
    /// стикеры, видео, кружки рисуются через UIKit — шейдер их не видит, для них частицы рисуем сверху
    var overlayParticles = false
    var tint: Color = Color.lime
    static let duration: TimeInterval = 1.1

    func body(content: Content) -> some View {
        if let start, overlayParticles {
            TimelineView(.animation) { tl in
                let t = min(1, tl.date.timeIntervalSince(start) / Self.duration)
                content
                    .opacity(max(0, 1 - t * 1.6))
                    .scaleEffect(1 - 0.15 * t)
                    .blur(radius: t * 8)
                    .overlay { DustBurst(t: t, tint: tint).padding(-60).allowsHitTesting(false) }
            }
        } else if let start {
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


/// Облако частиц поверх исчезающего стикера
private struct DustBurst: View {
    let t: Double
    var tint: Color
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<260 {
                let fi = Double(i)
                func r(_ k: Double) -> Double { let x = sin(fi * 12.9898 + k * 78.233) * 43758.5453; return x - floor(x) }
                // частица стартует внутри стикера и улетает вверх-вправо
                let sx = c.x + (r(1) - 0.5) * (size.width - 120)
                let sy = c.y + (r(2) - 0.5) * (size.height - 120)
                let delay = (1 - (sx / size.width)) * 0.4 + r(3) * 0.2
                let k = max(0, min(1, (t - delay) / 0.5))
                guard k > 0, k < 1 else { continue }
                let ang = -1.2 + r(4) * 1.9
                let d = (16 + r(5) * 60) * k * k
                let p = CGPoint(x: sx + cos(ang) * d, y: sy + sin(ang) * d)
                let s = 1.5 + r(6) * 2
                var g = ctx
                g.opacity = 1 - k
                let col: Color = r(7) < 0.5 ? tint : (r(7) < 0.8 ? .white : tint.opacity(0.6))
                g.fill(Path(CGRect(x: p.x, y: p.y, width: s, height: s)), with: .color(col))
            }
        }
    }
}


// MARK: - «Стикеры и эмодзи» (шестерёнка в панели)

struct StickerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StickerStore.shared
    @AppStorage("chat.bigEmoji") private var bigEmoji = true
    @AppStorage("chat.quickReaction") private var quick = "❤️"
    @State private var selected = Set<String>()
    @State private var editing: EditMode = .active

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                Section {
                    NavigationLink { PopularPacksView() } label: {
                        row("flame.fill", Color(hex: 0xF0A030), "Популярные стикеры", badge: StickerPacks.all.filter { !store.hasPack($0.id) }.count)
                    }
                    NavigationLink { ArchivedPacksView() } label: {
                        row("archivebox.fill", Color(hex: 0x58C770), "Архив стикеров", value: "\(store.archived.count)")
                    }
                    NavigationLink { EmojiListView() } label: {
                        row("face.smiling.inverse", Color(hex: 0x3FA9F5), "Эмодзи", value: "\(StickerPanel.emojis.count)")
                    }
                    NavigationLink { QuickReactionView(quick: $quick) } label: {
                        row("heart.fill", Color(hex: 0xFF4D5E), "Быстрая реакция", value: quick)
                    }
                }
                .selectionDisabled()

                Section {
                    Toggle("Крупные эмодзи", isOn: $bigEmoji).tint(Color.lime)
                    Toggle("Сначала недавние", isOn: $store.recentFirst).tint(Color.lime)
                } footer: {
                    Text("В начале списка будут отображаться недавно использованные наборы.")
                }
                .selectionDisabled()

                Section("Мои стикеры") {
                    if store.packs.isEmpty {
                        Text("Нет добавленных наборов").foregroundStyle(.secondary)
                    }
                    ForEach(store.orderedPacks) { p in
                        HStack(spacing: 14) {
                            StickerView(ref: StickerPacks.refs(p)[0], size: 46, playing: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.headline)
                                Text("\(p.count) стикеров").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .tag(p.id)
                    }
                    .onMove { store.movePacks(from: $0, to: $1) }
                }
            }
            .environment(\.editMode, $editing)
            .navigationTitle("Стикеры и эмодзи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Удалить") {
                        store.removePacks(selected); selected = []; Haptic.success()
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(selected.isEmpty ? Color.secondary : Color.red)
                    Spacer()
                    Button("В архив") {
                        store.archive(selected); selected = []; Haptic.success()
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    ShareLink(item: store.orderedPacks.filter { selected.contains($0.id) }.map { "Набор стикеров «\($0.title)» в Oxion" }.joined(separator: "\n")) {
                        Text("Отправить")
                    }
                    .buttonStyle(.glass)
                }
                .disabled(selected.isEmpty)
                .controlSize(.large)
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    private func row(_ icon: String, _ c: Color, _ t: String, badge: Int? = nil, value: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(c.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(t)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)").font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 2).background(Color(hex: 0x3B8CF5), in: Capsule())
            }
            if let value { Text(value).foregroundStyle(.secondary) }
        }
    }
}

private struct PopularPacksView: View {
    @State private var store = StickerStore.shared
    @State private var open: StickerPacks.Pack?
    var body: some View {
        List(StickerPacks.all) { p in
            HStack(spacing: 14) {
                StickerView(ref: StickerPacks.refs(p)[0], size: 46, playing: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.headline)
                    Text("\(p.count) стикеров").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if store.hasPack(p.id) {
                    Image(systemName: "checkmark").foregroundStyle(Color.lime)
                } else {
                    Button("Добавить") { store.togglePack(p.id); Haptic.success() }
                        .buttonStyle(.glassProminent).tint(Color.lime).foregroundStyle(Color.onLime)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { open = p }
        }
        .navigationTitle("Популярные стикеры")
        .sheet(item: $open) { StickerPackSheet(pack: $0) }
    }
}

private struct ArchivedPacksView: View {
    @State private var store = StickerStore.shared
    var body: some View {
        List {
            if store.archived.isEmpty {
                Text("В архиве пусто").foregroundStyle(.secondary)
            }
            ForEach(store.archived, id: \.self) { id in
                if let p = StickerPacks.all.first(where: { $0.id == id }) {
                    HStack(spacing: 14) {
                        StickerView(ref: StickerPacks.refs(p)[0], size: 46, playing: false)
                        Text(p.title).font(.headline)
                        Spacer()
                        Button("Вернуть") { store.unarchive(id); Haptic.success() }.buttonStyle(.glass)
                    }
                }
            }
        }
        .navigationTitle("Архив стикеров")
    }
}

private struct EmojiListView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                ForEach(StickerPanel.emojis, id: \.self) { Text($0).font(.system(size: 34)) }
            }
            .padding()
        }
        .navigationTitle("Эмодзи")
    }
}

private struct QuickReactionView: View {
    @Binding var quick: String
    var body: some View {
        List(Kinds.reactions + ["😍", "🙏", "👀", "💯"], id: \.self) { e in
            Button { quick = e; Haptic.tap() } label: {
                HStack {
                    Text(e).font(.system(size: 28))
                    Spacer()
                    if quick == e { Image(systemName: "checkmark").foregroundStyle(Color.lime) }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Быстрая реакция")
    }
}
