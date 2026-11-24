import SwiftUI
import Translation
import UIKit
import PhotosUI
import Observation
import UserNotifications

@MainActor
@Observable
final class ChatsStore {
    var items: [ChatItem] = []
    var loading = false
    var loaded = false
    var errorText: String?

    /// Непрочитанные для значка вкладки и иконки приложения: без чатов «без звука» и архива
    var unread: Int {
        items.filter { $0.muted != true && $0.archived != true }
            .reduce(0) { $0 + max($1.unread ?? 0, $1.marked == true ? 1 : 0) }
    }

    /// Непрочитанные во всех чатах, кроме открытого — для кнопки «назад»
    func unread(except id: Int) -> Int {
        items.filter { $0.id != id && $0.muted != true && $0.archived != true }
            .reduce(0) { $0 + max($1.unread ?? 0, $1.marked == true ? 1 : 0) }
    }

    var active: [ChatItem] {
        sorted(items.filter { $0.archived != true && (!trainerOnly || $0.peer.trainer == true) })
    }
    /// фильтр фокусирования «только чаты с тренерами»
    private(set) var trainerOnly = OxFocus.trainerChatsOnly
    func focusChanged() { trainerOnly = OxFocus.trainerChatsOnly }
    var archived: [ChatItem] { sorted(items.filter { $0.archived == true }) }

    private func sorted(_ l: [ChatItem]) -> [ChatItem] {
        l.sorted { a, b in
            if (a.pinned == true) != (b.pinned == true) { return a.pinned == true }
            return (a.at ?? 0) > (b.at ?? 0)
        }
    }

    func load() async {
        loading = true
        do {
            let r: ChatsResponse = try await API.call("/chats")
            items = r.items
            errorText = nil
            AppBadge.update(items)
            LocalChatNotifier.markSeen(r.items)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
        loaded = true
    }

    func markRead(_ id: Int) {
        // меняем список только если правда было непрочитанное — иначе лишняя перерисовка
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].unread != 0 || items[i].marked == true else { return }
        items[i].unread = 0
        items[i].marked = false
        AppBadge.update(items)
    }

    private func update(_ id: Int, _ f: (inout ChatItem) -> Void) {
        for i in items.indices where items[i].id == id { f(&items[i]) }
        AppBadge.update(items)
    }

    // MARK: действия (сохраняются на сервере OXION — одинаково в приложении и PWA)

    func setPinned(_ c: ChatItem, _ v: Bool) async {
        update(c.id) { $0.pinned = v }
        await send(c.id, ["pinned": v]) { self.update(c.id) { $0.pinned = !v } }
    }
    func setMuted(_ c: ChatItem, _ v: Bool) async {
        update(c.id) { $0.muted = v }
        await send(c.id, ["muted": v]) { self.update(c.id) { $0.muted = !v } }
    }
    func setArchived(_ c: ChatItem, _ v: Bool) async {
        update(c.id) { $0.archived = v; if v { $0.pinned = false } }
        await send(c.id, v ? ["archived": true, "pinned": false] : ["archived": false]) { self.update(c.id) { $0.archived = !v } }
    }
    /// «Прочитано» / «Пометить как новое»
    func toggleRead(_ c: ChatItem) async {
        let isUnread = (c.unread ?? 0) > 0 || c.marked == true
        if isUnread {
            update(c.id) { $0.unread = 0; $0.marked = false }
            let _: OK? = try? await API.call("/chats/\(c.id)/read", method: "POST", body: ["last_id": c.lastId ?? 0])
        } else {
            update(c.id) { $0.marked = true }
            await send(c.id, ["marked": true]) { self.update(c.id) { $0.marked = false } }
        }
    }
    func hide(_ c: ChatItem) async {
        let backup = items
        items.removeAll { $0.id == c.id }
        AppBadge.update(items)
        do {
            let _: OK = try await API.call("/chats/\(c.id)/hide", method: "POST")
        } catch {
            items = backup
            OxAlert.error(error.localizedDescription)
        }
    }
    func readAll() async {
        for i in items.indices { items[i].unread = 0; items[i].marked = false }
        AppBadge.update(items)
        let _: OK? = try? await API.call("/chats/read-all", method: "POST")
    }

    private func send(_ id: Int, _ body: [String: Any], rollback: @escaping () -> Void) async {
        do {
            let _: OK = try await API.call("/chats/\(id)/prefs", method: "POST", body: body)
        } catch {
            rollback()
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// Число на иконке приложения (наклейка)
enum AppBadge {
    @MainActor static func set(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(n) { _ in }
    }
}

struct ChatsView: View {
    @Environment(ChatsStore.self) private var store
    @State private var query = ""
    @State private var editing = false
    @State private var selection = Set<Int>()
    @State private var path: [ChatRoute] = []
    @State private var protectAll = false
    @State private var newChat = false

    enum ChatRoute: Hashable { case chat(ChatRef), archive, ai }

    private var filtered: [ChatItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return store.active }
        return (store.active + store.archived).filter { ($0.peer.name ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(selection: $selection) {
                if let e = store.errorText, store.items.isEmpty {
                    ErrorStateView(message: e) {
                        Task { await store.load() }
                    }
                    .listRowBackground(Color.clear)
                }
                if query.isEmpty && !editing {
                    Button { path.append(.ai) } label: { AIChatRow() }
                        .selectionDisabled()
                }
                if !store.archived.isEmpty && query.isEmpty && !editing {
                    Button { path.append(.archive) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .font(.title3).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color(hex: 0x636366), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Архив").font(.headline).foregroundStyle(.primary)
                                Text(store.archived.compactMap { $0.peer.name }.prefix(3).joined(separator: ", "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            let n = store.archived.reduce(0) { $0 + ($1.unread ?? 0) }
                            if n > 0 { UnreadBadge(n: n, muted: true) }
                        }
                        .padding(.vertical, 4)
                    }
                    .selectionDisabled()
                }
                ForEach(filtered) { c in
                    ChatListRow(c: c, editing: editing) { path.append(.chat(ChatRef(id: c.id, name: c.peer.name ?? "Чат"))) }
                        .reassemblesRow()
                        .tag(c.id)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .oxIntro(.sensitive,
                     onContinue: { UserDefaults.standard.set(true, forKey: SensitiveGuard.enabledKey) },
                     onLater: { UserDefaults.standard.set(false, forKey: SensitiveGuard.enabledKey) })
            .overlay {
                if store.loaded && store.items.isEmpty && store.errorText == nil {
                    ContentUnavailableView("Сообщений пока нет",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Напишите тренеру из его карточки — переписка появится здесь"))
                } else if !store.loaded {
                    ProgressView()
                }
            }
            .navigationTitle("Чаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editing ? "Готово" : "Изм.") {
                        withAnimation(.snappy) { editing.toggle(); selection = [] }
                        OxHaptics.play(.select)
                    }
                    .fontWeight(editing ? .bold : .regular)
                }
                if !editing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { newChat = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("Написать сообщение")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { Task { await store.readAll() }; OxHaptics.play(.select) } label: {
                                Label("Прочитать все", systemImage: "checkmark.message")
                            }
                            .disabled(store.unread == 0)
                            Toggle(isOn: Binding(get: { protectAll }, set: { v in Task { await setProtectAll(v) } })) {
                                Label("Защищать все мои чаты от снимков", systemImage: "lock.shield")
                            }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            }
            .toolbar(editing ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if editing { editBar }
            }
            .navigationDestination(for: ChatRoute.self) { r in
                switch r {
                case .chat(let ref): ChatView(chatId: ref.id, title: ref.name)
                case .archive: ArchivedChatsView { path.append(.chat($0)) }
                case .ai: AICoachView()
                }
            }
            .sheet(isPresented: $newChat) {
                NewMessageSheet { ref in
                    Task {
                        await store.load()
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(.chat(ref))
                    }
                }
            }
            .searchable(text: $query, prompt: "Поиск по чатам")
            .oxRefreshable { await store.load() }
            .task {
                await store.load()
                if let r: ProtectAll = try? await API.call("/chats/protect-all") { protectAll = r.enabled }
            }
        }
    }

    private func setProtectAll(_ v: Bool) async {
        do {
            let r: ProtectAll = try await API.call("/chats/protect-all", method: "POST", body: ["enabled": v])
            protectAll = r.enabled
            OxHaptics.play(.setDone)
            OxAlert.show(icon: v ? "lock.shield.fill" : "lock.open", title: v ? "Все ваши чаты защищены" : "Защита для всех чатов выключена",
                         message: v ? "На снимках и записи экрана переписка будет скрыта у вас и у собеседников. О каждом снимке придёт уведомление." : "Отдельные чаты, где вы включали защиту, остаются защищёнными.")
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private var editBar: some View {
        let sel = store.items.filter { selection.contains($0.id) }
        return HStack(spacing: 10) {
            Button(sel.isEmpty ? "Прочитать все" : "Прочитать") {
                Task {
                    if sel.isEmpty { await store.readAll() }
                    else { for c in sel where (c.unread ?? 0) > 0 || c.marked == true { await store.toggleRead(c) } }
                    done()
                }
            }
            .disabled(sel.isEmpty && store.unread == 0)
            Button("В архив") {
                Task { for c in sel { await store.setArchived(c, true) }; done() }
            }
            .disabled(sel.isEmpty)
            Spacer()
            Button("Удалить", role: .destructive) {
                OxAlert.confirm(title: sel.count == 1 ? "Удалить чат?" : "Удалить \(sel.count) чата?",
                                message: "История очистится только у вас. Собеседник свои сообщения сохранит.",
                                action: "Удалить", destructive: true) {
                    Task { for c in sel { await store.hide(c) }; done() }
                }
            }
            .disabled(sel.isEmpty)
        }
        .buttonStyle(.glass)
        .controlSize(.regular).lineLimit(1).minimumScaleFactor(0.75)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func done() {
        withAnimation(.snappy) { editing = false; selection = [] }
        OxHaptics.play(.setDone)
    }
}

/// Строка чата: смахивания как в Telegram, удержание — превью переписки и меню
struct ChatListRow: View {
    @Environment(ChatsStore.self) private var store
    let c: ChatItem
    var editing = false
    var open: () -> Void

    private var unreadish: Bool { (c.unread ?? 0) > 0 || c.marked == true }

    var body: some View {
        Button(action: { if !editing { open() } }) {
            ChatRow(c: c)
        }
        .buttonStyle(.plain)
        .listRowBackground(c.pinned == true ? Color.primary.opacity(0.04) : Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { Task { await store.setArchived(c, c.archived != true) } } label: {
                Label(c.archived == true ? "Из архива" : "В архив", systemImage: c.archived == true ? "tray.and.arrow.up.fill" : "archivebox.fill")
            }
            .tint(Color(hex: 0x636366))
            Button { confirmDelete() } label: { Label("Удалить", systemImage: "trash.fill") }
                .tint(Color(hex: 0xD93025))
            Button { Task { await store.setMuted(c, c.muted != true) } } label: {
                Label(c.muted == true ? "Включить звук" : "Убрать звук", systemImage: c.muted == true ? "bell.fill" : "bell.slash.fill")
            }
            .tint(Color(hex: 0xE08A1E))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { Task { await store.toggleRead(c) } } label: {
                Label(unreadish ? "Прочитать" : "Непрочит.", systemImage: unreadish ? "envelope.open.fill" : "envelope.badge.fill")
            }
            .tint(Color(hex: 0x636366))
            if c.archived != true {
                Button { Task { await store.setPinned(c, c.pinned != true) } } label: {
                    Label(c.pinned == true ? "Открепить" : "Закрепить", systemImage: c.pinned == true ? "pin.slash.fill" : "pin.fill")
                }
                .tint(Color(hex: 0x34A853))
            }
        }
        .contextMenu {
            Button { Task { await store.toggleRead(c) } } label: {
                Label(unreadish ? "Пометить как прочитанное" : "Пометить как новое", systemImage: unreadish ? "envelope.open" : "message.badge")
            }
            if c.archived != true {
                Button { Task { await store.setPinned(c, c.pinned != true) } } label: {
                    Label(c.pinned == true ? "Открепить" : "Закрепить", systemImage: c.pinned == true ? "pin.slash" : "pin")
                }
            }
            Button { Task { await store.setMuted(c, c.muted != true) } } label: {
                Label(c.muted == true ? "Включить звук" : "Убрать звук", systemImage: c.muted == true ? "bell" : "bell.slash")
            }
            Button { Task { await store.setArchived(c, c.archived != true) } } label: {
                Label(c.archived == true ? "Вернуть из архива" : "В архив", systemImage: "archivebox")
            }
            Button(role: .destructive) { confirmDelete() } label: { Label("Удалить", systemImage: "trash") }
        } preview: {
            ChatPeekView(chatId: c.id, name: c.peer.name ?? "Чат", photo: c.peer.photo)
        }
    }

    private func confirmDelete() {
        OxAlert.confirm(title: "Удалить чат с \(c.peer.name ?? "собеседником")?",
                        message: "История очистится только у вас. Собеседник свои сообщения сохранит.",
                        action: "Удалить", destructive: true) {
            Task { await store.hide(c) }
        }
    }
}

struct ChatRow: View {
    let c: ChatItem

    var body: some View {
        HStack(spacing: 12) {
            if c.peer.group != nil {
                GroupAvatar(photo: c.peer.photo, title: c.peer.name ?? "?", kind: c.peer.group, size: 52)
            } else {
                Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let g = c.peer.group {
                        Image(systemName: g == "channel" ? "megaphone.fill" : "person.2.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(c.peer.name ?? "Пользователь")
                        .font(.headline)
                        .lineLimit(1)
                    if c.muted == true {
                        Image(systemName: "speaker.slash.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.mine == true, (c.unread ?? 0) == 0 {
                        Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Color.limeInk)
                    }
                    if let at = c.at, at > 0 {
                        Text(ChatTime.short(at))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top) {
                    Text((c.mine == true ? "Вы: " : "") + (c.last ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if let u = c.unread, u > 0 {
                        UnreadBadge(n: u, muted: c.muted == true)
                    } else if c.marked == true {
                        Circle().fill(c.muted == true ? Color.gray : Color.lime).frame(width: 18, height: 18)
                    } else if c.pinned == true {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary).rotationEffect(.degrees(45))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct UnreadBadge: View {
    let n: Int
    var muted = false
    var body: some View {
        Text("\(n)")
            .font(.caption.bold())
            .foregroundStyle(muted ? Color.white : Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(muted ? Color.gray : Color.lime, in: Capsule())
    }
}

/// Превью переписки при удержании (сообщения не помечаются прочитанными)
struct ChatPeekView: View {
    let chatId: Int
    let name: String
    let photo: String?
    @State private var msgs: [Message] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Avatar(url: API.media(photo), name: name, size: 34)
                Text(name).font(.headline)
                Spacer()
            }
            .padding(12)
            .background(.ultraThinMaterial)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(msgs.suffix(12)) { m in
                        HStack {
                            if m.mine { Spacer(minLength: 40) }
                            Text(m.deleted == true ? "Сообщение удалено" : (m.text ?? (m.photo != nil ? "📷 Фото" : (Kinds.label[m.kind ?? ""] ?? "Сообщение"))))
                                .font(.subheadline)
                                .foregroundStyle(m.mine ? Color.black : Color.primary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(m.mine ? Color.lime : Color.oxCard2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            if !m.mine { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(12)
            }
            .defaultScrollAnchor(.bottom)
        }
        .frame(width: 340, height: 440)
        .background(Color.oxBg)
        .task {
            if let r: ChatDetail = try? await API.call("/chats/\(chatId)") { msgs = r.messages }
        }
    }
}

/// Архив чатов
struct ArchivedChatsView: View {
    @Environment(ChatsStore.self) private var store
    var open: (ChatRef) -> Void

    var body: some View {
        List {
            ForEach(store.archived) { c in
                ChatListRow(c: c) { open(ChatRef(id: c.id, name: c.peer.name ?? "Чат")) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.archived.isEmpty {
                ContentUnavailableView("Архив пуст", systemImage: "archivebox", description: Text("Смахните чат влево и нажмите «В архив»"))
            }
        }
        .navigationTitle("Архив")
    }
}

enum ChatTime {
    static func short(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "HH:mm"
        } else if Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "d MMM"
        } else {
            f.dateFormat = "dd.MM.yy"
        }
        return f.string(from: d)
    }

    static func time(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}

/// Переписка: сообщения, ответы, реакции, фото. Новые сообщения подтягиваются каждые 3 секунды.
struct ChatView: View {
    let chatId: Int
    let title: String

    @Environment(ChatsStore.self) private var chats
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var peer: Peer?
    @State private var peerReadId = 0
    @State private var showStickers = false
    @AppStorage("chat.quickReaction") private var quickReaction = "❤️"
    @State private var stickerMenu: Message?
    @State private var stickerPack: StickerPacks.Pack?
    /// удаляемые сообщения: распадаются на частицы, потом исчезают
    @State private var dissolving: [Int: Date] = [:]
    @State private var since: Double = 0
    @State private var didInitialScroll = false
    @State private var lastReadSent = 0
    @State private var text = ""
    @State private var replyTo: Message?
    @State private var errorText: String?
    @State private var sending = false
    @State private var photoPick: PhotosPickerItem?
    @State private var loaded = false
    @State private var attaching = false
    @State private var call: CallRequest?
    @State private var protect: ChatProtect?
    @State private var protectBusy = false
    @State private var focused = false
    @Namespace private var zoomNS
    @State private var translateText: String?
    @State private var productBox: AppModel.IdBox?
    // пересылка перетаскиванием и через меню
    @State private var fwdDrag: Int?
    /// сообщение «поднято» долгим нажатием; панель чатов покажем, только когда его реально потянут
    @State private var fwdPending: Int?
    @State private var fwdSheet: Message?
    // «потяни вверх» — краткое содержание
    @State private var pull: CGFloat = 0
    @State private var pullArmed = false
    @State private var scrollDragging = false
    @State private var showSummary = false
    // группа или канал
    @State private var group: GroupInfo?
    @State private var senders: [Int: GSender] = [:]
    /// сколько тянуть: примерно до середины экрана пальцем (из‑за «резинки» это ~40 pt прокрутки)
    private let pullNeed: CGFloat = 40

    /// у последнего сообщения в серии от одного человека — «хвостик»
    private var tailIds: Set<Int> {
        var out = Set<Int>()
        let list = messages.filter { $0.kind != "shot" && $0.kind != "svc" }
        for (i, m) in list.enumerated() {
            if i == list.count - 1 || list[i + 1].mine != m.mine { out.insert(m.id) }
        }
        return out
    }

    private var shielded: Bool { protect?.on == true }

    var body: some View {
        ScreenShield(enabled: shielded) {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if !loaded {
                        ProgressView().padding(.top, 40)
                    } else if messages.isEmpty {
                        Text("Напишите первое сообщение")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                    if shielded {
                        Label(protect?.by == "peer" ? "Собеседник включил защиту от снимков экрана" : "Защита от снимков экрана включена",
                              systemImage: "lock.shield.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.limeInk)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.lime.opacity(0.12), in: Capsule())
                            .padding(.bottom, 4)
                    }
                    // хвостики считаем один раз на кадр, а не для каждого сообщения (иначе чат тормозит)
                    let tails = tailIds
                    ForEach(messages) { m in
                        if m.kind == "shot" || m.kind == "svc" {
                            HStack(spacing: 6) {
                                if m.kind == "shot" {
                                    Image(systemName: (m.text ?? "").contains("снимок") && !(m.text ?? "").contains("защит") ? "camera.viewfinder" : "lock.shield")
                                }
                                Text(m.text ?? "Снимок экрана")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.primary.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .id(m.id)
                        } else if m.kind == "gift" && m.deleted != true {
                            GiftServiceRow(m: m, peerName: peer?.name).id(m.id)
                        } else {
                        bubbleRow(m, tails: tails)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // нажатие по переписке закрывает панель стикеров
            .simultaneousGesture(TapGesture().onEnded {
                if showStickers { withAnimation(.spring(duration: 0.3)) { showStickers = false } }
            }, isEnabled: showStickers)
            // насколько переписку протянули вверх за последний сообщение
            .onScrollGeometryChange(for: CGFloat.self) { g in
                let rest = max(-g.contentInsets.top, g.contentSize.height + g.contentInsets.bottom - g.containerSize.height)
                return max(0, g.contentOffset.y - rest)
            } action: { _, v in
                pull = v
                guard scrollDragging, loaded, !messages.isEmpty else { return }
                if v >= pullNeed && !pullArmed {
                    pullArmed = true
                    Haptic.tap(.medium)
                } else if v < pullNeed * 0.8 && pullArmed {
                    pullArmed = false
                    Haptic.tap(.soft)
                }
            }
            .onScrollPhaseChange { old, new in
                scrollDragging = new == .interacting
                if old == .interacting && new != .interacting && pullArmed {
                    pullArmed = false
                    Haptic.success()
                    showSummary = true
                }
            }
            .overlay(alignment: .bottom) {
                if scrollDragging && pull > 3 && loaded && !messages.isEmpty {
                    PullSummaryHint(progress: pull / pullNeed)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            // сообщение сдвинули пальцем — меню само закрывается, а слева выезжают чаты для пересылки
            .onDrop(of: [.plainText], delegate: ForwardStartDrop(onMove: {
                guard fwdDrag == nil, let id = fwdPending else { return }
                Haptic.tap(.medium)
                fwdDrag = id
                fwdPending = nil
            }, onEnd: { fwdPending = nil }))
            .background { ChatWallpaperBackground() }
            // как в Telegram: сверху нет плашки, переписка мягко растворяется под шапкой
            .scrollEdgeEffectStyle(.soft, for: .top)
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.black.opacity(0.32), Color.black.opacity(0.12), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            // при открытии — сразу внизу, без прокрутки сверху вниз
            .opacity(didInitialScroll || messages.isEmpty ? 1 : 0)
            .onChange(of: messages.last?.id) { old, new in
                guard let id = new else { return }
                if !didInitialScroll {
                    var tr = Transaction()
                    tr.disablesAnimations = true
                    withTransaction(tr) { proxy.scrollTo(id, anchor: .bottom) }
                    Task {
                        try? await Task.sleep(for: .milliseconds(60))
                        withTransaction(tr) { proxy.scrollTo(id, anchor: .bottom) }
                        withAnimation(.easeOut(duration: 0.15)) { didInitialScroll = true }
                    }
                } else {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .environment(chats)
        }
        .overlay {
            if let id = fwdDrag {
                ForwardDragPanel(currentChatId: chatId, messageId: id) { fwdDrag = nil }
                    .environment(chats)
            }
        }
        .sheet(item: $fwdSheet) { m in ForwardSheet(currentChatId: chatId, messageId: m.id).environment(chats) }
        .sheet(isPresented: $showSummary) { ChatSummarySheet(chatId: chatId, title: peer?.name ?? title) }
        .sheet(item: $productBox) { b in
            NavigationStack { ProductView(productId: b.id, onCart: { _ in }) }
        }
        .translationPresentation(isPresented: Binding(get: { translateText != nil }, set: { if !$0 { translateText = nil } }),
                                 text: translateText ?? "")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard shielded else { return }
            Task { await reportScreenshot() }
        }
        // ссылки из переписки — во встроенный браузер (и в защищённых от снимков чатах тоже)
        .modifier(InAppBrowserLinks())
        .safeAreaInset(edge: .bottom) {
            if let g = group, g.canPost != true {
                channelBar
            } else {
                inputBar
            }
        }
        .navigationTitle(peer?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            // шапка как в Telegram: «назад» с числом непрочитанных, имя в стеклянной капсуле, аватар-кружок
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                        let n = chats.unread(except: chatId)
                        if n > 0 {
                            Text(n > 999 ? "999+" : "\(n)")
                                .font(.system(size: 15, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color(.systemBackground))
                                .padding(.horizontal, 7)
                                .frame(minWidth: 26, minHeight: 24)
                                .background(Color.primary, in: Capsule())
                                .contentTransition(.numericText())
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)
                    .animation(.spring(duration: 0.3), value: chats.unread(except: chatId))
                }
                .accessibilityLabel("Назад")
            }
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    profile
                } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text(peer?.name ?? title).font(.headline).lineLimit(1)
                            if peer?.trainer == true {
                                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.limeInk)
                            }
                            if shielded {
                                Image(systemName: "lock.shield.fill").font(.caption2).foregroundStyle(Color.limeInk)
                            }
                        }
                        if let g = group {
                            Text(GroupText.count(g.membersCount ?? 0, channel: g.isChannel))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(PeerStatus.text(peer?.lastSeen))
                                .font(.caption)
                                .foregroundStyle(PeerStatus.online(peer?.lastSeen) ? Color.limeInk : Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 150)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    profile
                        .navigationTransition(.zoom(sourceID: "peer-avatar", in: zoomNS))
                } label: {
                    Group {
                        if group != nil || peer?.group != nil {
                            GroupAvatar(photo: peer?.photo, title: peer?.name ?? title, kind: group?.kind ?? peer?.group, size: 44)
                        } else {
                            Avatar(url: API.media(peer?.photo), name: peer?.name ?? title, size: 44)
                        }
                    }
                        .padding(3)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .matchedTransitionSource(id: "peer-avatar", in: zoomNS)
                }
                .buttonStyle(.plain)
                .disabled(peer == nil)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay {
            if let sm = stickerMenu {
                ChatStickerMenu(m: sm, reactions: Kinds.reactions,
                                onReact: { e in Task { await react(sm, e) } },
                                onReply: { replyTo = sm; focused = true },
                                onPack: { stickerPack = StickerPacks.pack(of: sm.card?["id"]?.string ?? "") },
                                onDelete: sm.mine ? { Task { await remove(sm) } } : nil,
                                onClose: { stickerMenu = nil })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: stickerMenu?.id)
        .sheet(item: $stickerPack) { p in StickerPackSheet(pack: p, onSend: { ref in stickerPack = nil; Task { await sendSticker(ref, silent: false) } }) }
        .fullScreenCover(item: $call) { CallScreen(req: $0) }
        .sheet(isPresented: $attaching) {
            ChatAttachSheet(chatId: chatId, replyTo: replyTo?.id,
                            giftTo: peer?.group == nil ? peer : nil,
                            onGift: { Task { await load(initial: false) } }) { m in
                replyTo = nil
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
                }
            }
        }
        .task {
            await load(initial: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PowerSaver.allowsNow(.background) ? 3 : 8))
                if Task.isCancelled { break }
                await load(initial: false)
            }
        }
        .onChange(of: photoPick) {
            Task { await sendPhoto() }
        }
    }

    /// подписчик канала не пишет — внизу только «Выключить/включить звук», как в Telegram
    private var channelBar: some View {
        let muted = chats.items.first(where: { $0.id == chatId })?.muted == true
        return Button {
            Task {
                let _: OK? = try? await API.call("/chats/\(chatId)/prefs", method: "POST", body: ["muted": !muted])
                await chats.load()
                Haptic.tap(.soft)
            }
        } label: {
            Label(muted ? "Включить звук" : "Выключить звук", systemImage: muted ? "bell" : "bell.slash")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let r = replyTo {
                HStack {
                    Rectangle().fill(Color.lime).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine ? "Ответ себе" : "Ответ")
                            .font(.caption.bold())
                            .foregroundStyle(Color.limeInk)
                        Text(r.text.map { PremiumEmoji.plain($0) } ?? "Фото")
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 34)
                .padding(.horizontal, 16)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    attaching = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                // поле ввода, в котором видны анимированные эмодзи
                EmojiComposer(text: $text, focused: $focused)
                    .overlay(alignment: .leading) {
                        if text.isEmpty {
                            Text("Сообщение").foregroundStyle(.tertiary).allowsHitTesting(false)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 48)
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottomTrailing) {
                        // стикеры и эмодзи — вместо клавиатуры, как в Telegram
                        Button {
                            Haptic.tap(.soft)
                            if showStickers {
                                showStickers = false
                                focused = true
                            } else {
                                focused = false
                                withAnimation(.spring(duration: 0.35)) { showStickers = true }
                            }
                        } label: {
                            Image(systemName: showStickers ? "keyboard" : "face.smiling")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 46, height: 44)
                                // нажимается вся область кнопки, а не только линии значка
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(StickerToggleStyle())
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending {
                    RecordButton(onVoice: { url, dur, wave in Task { await sendVoice(url, dur: dur, wave: wave) } },
                                 onVideo: { url, dur in Task { await sendVideoNote(url, dur: dur) } })
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: sending ? "hourglass" : "arrow.up")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            if showStickers {
                StickerPanel(onSend: { ref, silent in Task { await sendSticker(ref, silent: silent) } },
                             onEmoji: { text += $0 },
                             onPremiumEmoji: { text += $0 })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .onChange(of: focused) { if focused && showStickers { withAnimation(.spring(duration: 0.3)) { showStickers = false } } }
    }

    private func load(initial: Bool) async {
        let after = initial ? 0 : (messages.last?.id ?? 0)
        var q: [String: String] = [:]
        if after > 0 { q["after"] = String(after) }
        if after > 0 && since > 0 { q["since"] = String(Int(since)) }
        do {
            let r: ChatDetail = try await API.call("/chats/\(chatId)", query: q)
            peer = r.peer
            if let g = r.group { group = g }
            for s in r.senders ?? [] { senders[s.id] = s }
            if let p = r.protect { protect = p }
            peerReadId = r.peerReadId ?? peerReadId
            if let n = r.serverNow { since = n - 2000 }
            if after == 0 {
                // удалённые не показываем вовсе — без «Сообщение удалено»
                messages = r.messages.filter { $0.deleted != true }
            } else if !r.messages.isEmpty || !(r.changed ?? []).isEmpty {
                // правки, реакции и удаления у собеседника
                for c in r.changed ?? [] {
                    if c.deleted == true {
                        if messages.contains(where: { $0.id == c.id }) && dissolving[c.id] == nil { dissolve(c.id) }
                    } else {
                        replace(c)
                    }
                }
                let have = Set(messages.map(\.id))
                let fresh = r.messages.filter { !have.contains($0.id) && $0.deleted != true }
                withAnimation(.spring(duration: 0.4, bounce: 0.25)) { messages += fresh }
                if fresh.contains(where: { !$0.mine }) { OxSound.play(.received) }
                ChatAutoSave.handle(fresh, trainerChat: r.peer.trainer == true)
            }
            loaded = true
            errorText = nil
            // отмечаем прочитанным только когда пришло новое — а не каждые 3 секунды
            if let last = messages.last?.id, last != lastReadSent {
                lastReadSent = last
                let _: OK? = try? await API.call("/chats/\(chatId)/read", method: "POST", body: ["last_id": last])
                chats.markRead(chatId)
            }
        } catch {
            loaded = true
            if initial { errorText = error.localizedDescription }
        }
    }

    @ViewBuilder
    private var profile: some View {
        if group != nil || peer?.group != nil {
            GroupInfoView(chatId: chatId) {
                Task { await chats.load() }
                dismiss()
            }
        } else if let p = peer {
            ChatPeerProfileView(peer: p, chatId: chatId, messages: messages, shielded: shielded,
                                shieldLockedByPeer: protect?.by == "peer",
                                onCall: { video in call = CallRequest(name: p.name ?? title, photo: p.photo, video: video) },
                                onToggleShield: { Task { await toggleProtect() } })
        }
    }

    // MARK: защита от снимков экрана

    private struct ProtectResponse: Decodable { let protect: ChatProtect? }

    private func toggleProtect() async {
        if protect?.mode == "all" && protect?.by == "me" {
            OxAlert.show(icon: "lock.shield.fill", title: "Защита включена для всех чатов",
                         message: "Выключить её можно в списке чатов: кнопка «•••» → «Защищать все мои чаты».")
            return
        }
        protectBusy = true
        defer { protectBusy = false }
        let on = !shielded
        do {
            let r: ProtectResponse = try await API.call("/chats/\(chatId)/protect", method: "POST", body: ["enabled": on])
            withAnimation { protect = r.protect }
            OxHaptics.play(.setDone)
            if on {
                OxAlert.show(icon: "lock.shield.fill", title: "Защита включена",
                             message: "На снимках и записи экрана переписка будет скрыта у обоих. Если собеседник сделает снимок, вы получите уведомление. Выключить защиту сможете только вы.")
            }
            await load(initial: false)
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func reportScreenshot() async {
        let _: OK? = try? await API.call("/chats/\(chatId)/screenshot", method: "POST")
        OxAlert.show(icon: "camera.viewfinder", tint: Color(hex: 0xF0A030), title: "Переписка защищена",
                     message: protect?.by == "peer"
                        ? "Собеседник включил защиту: на снимке переписка не видна, а он получил уведомление о снимке."
                        : "На снимке переписка не видна. Собеседник получил уведомление о снимке.")
        await load(initial: false)
    }

    @ViewBuilder
    private func bubbleRow(_ m: Message, tails: Set<Int>) -> some View {
                Bubble(m: m, read: m.mine && m.id <= peerReadId, tail: tails.contains(m.id),
                       sender: group?.kind == "group" && !m.mine ? m.fromId.flatMap { senders[$0] } : nil,
                       dragProvider: {
                           // iOS вызывает это уже при долгом нажатии (вместе с меню) — панель пока не показываем
                           fwdPending = (!shielded && m.deleted != true) ? m.id : nil
                           return NSItemProvider(object: "oxion-msg:\(m.id)" as NSString)
                       },
                       menu: { AnyView(messageMenu(m)) },
                       groupMode: group?.kind == "group",
                       onStickerTap: { if let p = StickerPacks.pack(of: m.card?["id"]?.string ?? "") { stickerPack = p } },
                       onStickerHold: { stickerMenu = m }) { action in
                    switch action {
                    case .product(let id): productBox = AppModel.IdBox(id: id)
                    case .call(let video): call = CallRequest(name: peer?.name ?? title, photo: peer?.photo, video: video)
                    }
                }
                    .modifier(DissolveModifier(start: dissolving[m.id],
                                               overlayParticles: ["sticker", "vnote", "video", "voice", "photos"].contains(m.kind ?? "") || m.photo != nil,
                                               tint: m.mine ? Color.lime : Color.white))
                    .allowsHitTesting(dissolving[m.id] == nil)
                    // двойное нажатие — быстрая реакция (выбирается в «Стикеры и эмодзи»)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        guard m.deleted != true else { return }
                        Haptic.tap(.medium)
                        Task { await react(m, quickReaction) }
                    })
                    .id(m.id)
                    .transition(Self.bubbleTransition(mine: m.mine))
    }

    /// меню сообщения по долгому нажатию
    @ViewBuilder
    private func messageMenu(_ m: Message) -> some View {
                        Section {
                            ForEach(Kinds.reactions, id: \.self) { e in
                                Button(e) { Task { await react(m, e) } }
                            }
                        }
                        Button {
                            replyTo = m
                            focused = true
                        } label: {
                            Label("Ответить", systemImage: "arrowshape.turn.up.left")
                        }
                        if let t = m.text, !t.isEmpty {
                            Button {
                                UIPasteboard.general.string = t
                            } label: {
                                Label("Скопировать", systemImage: "doc.on.doc")
                            }
                            Button {
                                translateText = t
                            } label: {
                                Label("Перевести", systemImage: "translate")
                            }
                        }
                        if m.deleted != true && !shielded {
                            Button {
                                fwdSheet = m
                            } label: {
                                Label("Переслать", systemImage: "arrowshape.turn.up.right")
                            }
                        }
                        if m.mine && m.deleted != true {
                            Button(role: .destructive) {
                                Task { await remove(m) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
    }

    static func bubbleTransition(mine: Bool) -> AnyTransition {
        guard UserDefaults.standard.object(forKey: "anim_messages") as? Bool ?? true else { return .identity }
        let anchor: UnitPoint = mine ? .bottomTrailing : .bottomLeading
        return .asymmetric(insertion: .scale(scale: 0.6, anchor: anchor).combined(with: .opacity), removal: .opacity)
    }

    private func send() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sending = true
        defer { sending = false }
        var body: [String: Any] = ["text": t]
        if let r = replyTo { body["reply_to"] = r.id }
        do {
            let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: body)
            text = ""
            replyTo = nil
            errorText = nil
            withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            }
            if UserDefaults.standard.object(forKey: "anim_send_haptic") as? Bool ?? true { Haptic.tap() }
            OxSound.play(.sent)
            ChatWallpaper.shared.bump()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sendVoice(_ url: URL, dur: Int, wave: String) async {
        guard let data = try? Data(contentsOf: url) else { return }
        sending = true
        defer { sending = false }
        var f: [String: String] = ["dur": String(dur), "wave": wave]
        if let r = replyTo { f["reply_to"] = String(r.id) }
        do {
            let m: Message = try await API.upload("/chats/\(chatId)/messages", fields: f, fileField: "voice", data: data,
                                                  filename: "voice.m4a", mime: "audio/mp4")
            replyTo = nil
            withAnimation(.spring(duration: 0.4, bounce: 0.25)) { if !messages.contains(where: { $0.id == m.id }) { messages.append(m) } }
            Haptic.success()
            OxSound.play(.sent)
            ChatWallpaper.shared.bump()
        } catch { errorText = error.localizedDescription }
        try? FileManager.default.removeItem(at: url)
    }

    private func sendVideoNote(_ url: URL, dur: Int) async {
        guard let data = try? Data(contentsOf: url) else { return }
        sending = true
        defer { sending = false }
        var f: [String: String] = ["dur": String(dur), "round": "1"]
        if let r = replyTo { f["reply_to"] = String(r.id) }
        do {
            let m: Message = try await API.upload("/chats/\(chatId)/messages", fields: f, fileField: "video", data: data,
                                                  filename: "note.mov", mime: "video/quicktime")
            replyTo = nil
            withAnimation(.spring(duration: 0.4, bounce: 0.25)) { if !messages.contains(where: { $0.id == m.id }) { messages.append(m) } }
            Haptic.success()
            OxSound.play(.sent)
            ChatWallpaper.shared.bump()
        } catch { errorText = error.localizedDescription }
        try? FileManager.default.removeItem(at: url)
    }

    private func sendPhoto() async {
        guard let item = photoPick else { return }
        photoPick = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data), let jpg = API.jpeg(img) else { return }
        sending = true
        defer { sending = false }
        do {
            var fields: [String: String] = [:]
            if let r = replyTo { fields["reply_to"] = String(r.id) }
            let m: Message = try await API.upload("/chats/\(chatId)/messages", fields: fields, data: jpg)
            replyTo = nil
            if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            OxSound.play(.sent)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func react(_ m: Message, _ emoji: String) async {
        do {
            let upd: Message = try await API.call("/messages/\(m.id)/react", method: "POST", body: ["emoji": emoji])
            replace(upd)
            Haptic.tap()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(_ m: Message) async {
        // даём меню закрыться, потом сообщение рассыпается на частицы
        try? await Task.sleep(for: .milliseconds(380))
        dissolve(m.id)
        do {
            let _: Message = try await API.call("/messages/\(m.id)", method: "DELETE")
        } catch {
            errorText = error.localizedDescription
            await load(initial: true)
        }
    }

    /// распад на «атомы» и исчезновение
    private func dissolve(_ id: Int) {
        dissolving[id] = Date()
        Haptic.tap(.light)
        Task {
            try? await Task.sleep(for: .seconds(DissolveModifier.duration))
            withAnimation(.spring(duration: 0.35)) { messages.removeAll { $0.id == id } }
            dissolving[id] = nil
        }
    }

    private func sendSticker(_ ref: String, silent: Bool) async {
        var b: [String: Any] = ["kind": "sticker", "ref": ref]
        if silent { b["silent"] = true }
        if let r = replyTo { b["reply_to"] = r.id }
        do {
            let m: Message = try await API.call("/chats/\(chatId)/messages", method: "POST", body: b)
            replyTo = nil
            OxSound.play(.sent)
            withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            }
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }

    private func replace(_ m: Message) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i] = m }
    }
}

struct Bubble: View {
    let m: Message
    var read: Bool
    /// последнее сообщение в серии от одного человека — с «хвостиком»
    var tail = true
    /// автор сообщения в группе (имя над пузырём и аватарка слева)
    var sender: GSender? = nil
    /// перетаскивание для пересылки
    var dragProvider: (() -> NSItemProvider)? = nil
    /// меню по долгому нажатию — превью повторяет форму пузыря
    var menu: (() -> AnyView)? = nil
    var groupMode = false
    /// стикер: нажатие — набор, удержание — своё меню (без квадратной подложки системного меню)
    var onStickerTap: (() -> Void)? = nil
    var onStickerHold: (() -> Void)? = nil
    var onAction: (InlineBtn.Action) -> Void = { _ in }
    var style = BubbleStyle()

    @AppStorage("chat.bigEmoji") private var bigEmoji = true
    /// текст только из 1–3 эмодзи
    private var onlyEmoji: String? {
        guard m.kind == nil, m.photo == nil, m.forward == nil, m.deleted != true, m.reply == nil,
              let t = m.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.count <= 3,
              t.allSatisfy({ ch in ch.unicodeScalars.contains { $0.properties.isEmojiPresentation } || (ch.unicodeScalars.first?.properties.isEmoji == true && ch.unicodeScalars.count > 1) })
        else { return nil }
        return t
    }
    private var isSticker: Bool { m.kind == "sticker" && m.deleted != true }
    private var isCardOnly: Bool { m.kind != nil && (m.text ?? "").isEmpty && m.photo == nil && m.deleted != true && m.forward == nil }
    private var fill: Color { m.mine ? Color.lime : Color.oxBubble.opacity(0.94) }
    private var ink: Color { m.mine ? Color.onLime : Color.primary }
    private var buttons: [InlineBtn] { m.kind.map { ChatCard.buttons(kind: $0, card: m.card, mine: m.mine) } ?? [] }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if m.mine { Spacer(minLength: 56) }
            if groupMode && !m.mine {
                // аватар автора — у последнего сообщения серии, как в Telegram
                if tail, let s = sender {
                    Avatar(url: API.media(s.photo), name: s.name ?? "?", size: 30)
                } else {
                    Color.clear.frame(width: 30, height: 1)
                }
            }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 4) {
                VStack(spacing: 4) {
                    if isCardOnly, m.kind == "vnote" {
                        // кружок — без пузыря, как в Telegram
                        ChatCard(kind: "vnote", card: m.card, mine: m.mine, embedded: true, messageId: m.id)
                            .overlay(alignment: .bottomTrailing) {
                                meta(on: true).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.black.opacity(0.45), in: Capsule())
                            }
                    } else if isCardOnly, m.kind == "sticker" {
                        // стикер — без пузыря, как в Telegram
                        StickerView(ref: m.card?["id"]?.string ?? "", size: 170)
                            .overlay(alignment: .bottomTrailing) {
                                meta(on: true).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.black.opacity(0.35), in: Capsule())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onStickerTap?() }
                            .onLongPressGesture(minimumDuration: 0.35) { onStickerHold?() }
                    } else if isCardOnly, m.kind == "voice" {
                        ChatCard(kind: "voice", card: m.card, mine: m.mine, embedded: true, messageId: m.id)
                            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 20)
                            .frame(minWidth: 230)
                            .overlay(alignment: .bottomTrailing) { meta(on: false).padding(.trailing, 10).padding(.bottom, 5) }
                            .foregroundStyle(ink)
                            .background(shape.fill(fill))
                    } else if isCardOnly, m.kind == "gift" {
                        GiftBubble(card: m.card, mine: m.mine)
                            .overlay(alignment: .bottomTrailing) {
                                meta(on: true).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.black.opacity(0.35), in: Capsule()).padding(8)
                            }
                    } else if isCardOnly, let k = m.kind {
                        cardBubble(k)
                    } else if let refs = PremiumEmoji.onlyEmoji(m.text), m.kind == nil, m.photo == nil, m.forward == nil, m.reply == nil, m.deleted != true {
                        // только анимированные эмодзи — крупно, без пузыря
                        VStack(alignment: .trailing, spacing: 2) {
                            BigEmojiRow(refs: refs)
                            meta(on: true).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.black.opacity(0.3), in: Capsule())
                        }
                    } else if bigEmoji, let e = onlyEmoji {
                        // «Крупные эмодзи»: 1–3 эмодзи без пузыря, как в Telegram
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(e).font(.system(size: e.count == 1 ? 64 : 48))
                            meta(on: true).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.black.opacity(0.3), in: Capsule())
                        }
                    } else {
                        bubble
                    }
                    if !buttons.isEmpty {
                        InlineButtonsRow(buttons: buttons, radius: max(8, style.radius * 0.7), onTap: onAction)
                    }
                }
                .frame(width: isCardOnly && !["vnote", "voice", "sticker"].contains(m.kind ?? "") ? 294 : nil)
                // перетаскивать для пересылки только сам пузырь — без пустого места строки вокруг
                .modifier(BubbleDrag(provider: isSticker ? nil : dragProvider, menu: isSticker ? nil : menu, shape: dragShape))
                if let rs = m.reactions, !rs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(rs, id: \.self) { r in
                            Text("\(r.emoji) \(r.n)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(r.mine == true ? Color.lime.opacity(0.3) : Color.black.opacity(0.35), in: Capsule())
                        }
                    }
                }
            }
            if !m.mine { Spacer(minLength: 56) }
        }
        .padding(m.mine ? .trailing : .leading, tail ? 0 : 0)
    }

    static func nameColor(_ id: Int) -> Color {
        let palette: [Color] = [Color(hex: 0xFF5E57), Color(hex: 0xFF9F0A), Color(hex: 0xA25AFF), Color(hex: 0x30B0C7), Color(hex: 0x34C759), Color(hex: 0x0A84FF), Color(hex: 0xFF375F)]
        return palette[abs(id) % palette.count]
    }

    private var dragShape: AnyShape {
        if isCardOnly && m.kind == "vnote" { return AnyShape(Circle()) }
        if isCardOnly && m.kind != "voice" { return AnyShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous)) }
        return AnyShape(shape)
    }

    private var shape: TailBubbleShape { TailBubbleShape(mine: m.mine, radius: style.radius, tail: tail) }

    // карточка (товар, звонок, тренировка…) в пузыре
    private func cardBubble(_ k: String) -> some View {
        ChatCard(kind: k, card: m.card, mine: false, embedded: true, messageId: m.id)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .padding(.bottom, 12)
            .overlay(alignment: .bottomTrailing) { meta(on: false).padding(.trailing, 12).padding(.bottom, 7) }
            .background(shape.fill(Color.oxBubble.opacity(0.94)))
            .overlay(shape.stroke(m.mine ? Color.lime.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var hasText: Bool { !(m.text ?? "").isEmpty && m.deleted != true }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = sender {
                Text(s.name ?? "Участник")
                    .font(.caption.bold())
                    .foregroundStyle(Bubble.nameColor(s.id))
                    .lineLimit(1)
            }
            if let f = m.forward {
                // «Переслано от …», как в Telegram
                VStack(alignment: .leading, spacing: 0) {
                    Text("Переслано от").font(.caption).opacity(0.75)
                    Text(f.mine == true ? "Вас" : (f.name ?? "Пользователь"))
                        .font(.caption.bold())
                        .foregroundStyle(m.mine ? Color.onLime : Color.limeInk)
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Capsule().fill(m.mine ? Color.black.opacity(0.45) : Color.lime).frame(width: 3)
                }
            }
            if let r = m.reply {
                HStack(spacing: 6) {
                    Capsule().fill(m.mine ? Color.black.opacity(0.45) : Color.lime).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine == true ? "Вы" : "Ответ").font(.caption.bold())
                        Text(PremiumEmoji.plain(r.text)).font(.caption).lineLimit(2)
                    }
                    .opacity(0.85)
                    .padding(.trailing, 6)
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
                .background((m.mine ? Color.black : Color.lime).opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if m.deleted == true {
                (Text("Сообщение удалено").italic() + timeSpacer)
                    .opacity(0.6)
            } else {
                if let p = API.media(m.photo) {
                    RemoteImage(url: p)
                        .frame(width: 240, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: max(4, style.radius - 4), style: .continuous))
                        .padding(.horizontal, -8)
                        .padding(.top, m.reply == nil ? -5 : 0)
                        .overlay(alignment: .bottomTrailing) {
                            if !hasText {
                                meta(on: true)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.black.opacity(0.45), in: Capsule())
                                    .padding(6)
                            }
                        }
                }
                if let k = m.kind {
                    ChatCard(kind: k, card: m.card, mine: m.mine, embedded: true, messageId: m.id)
                        .padding(.horizontal, -6)
                }
                if let t = m.text, !t.isEmpty, PremiumEmoji.hasTokens(t) {
                    // текст с анимированными эмодзи
                    VStack(alignment: .trailing, spacing: 2) {
                        EmojiMessageText(text: t, fontSize: style.fontSize, color: m.mine ? Color.onLime : Color.primary,
                                         linkColor: m.mine ? Color.onLime : Color.limeInk)
                        // место под время (оно рисуется поверх в правом нижнем углу)
                        Color.clear.frame(width: 64, height: 12)
                    }
                } else if let t = m.text, !t.isEmpty {
                    // время встаёт в конец последней строки, пузырь — по ширине текста
                    (Text(Linkify.attributed(t, color: m.mine ? Color.onLime : Color.limeInk, underline: true)) + timeSpacer)
                        .font(.system(size: style.fontSize))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, needsMetaRow ? 20 : 7)
        .overlay(alignment: .bottomTrailing) {
            if hasText || m.deleted == true || needsMetaRow {
                meta(on: false).padding(.trailing, 10).padding(.bottom, 5)
            }
        }
        .foregroundStyle(ink)
        .background(shape.fill(fill))
        .frame(maxWidth: 300, alignment: m.mine ? .trailing : .leading)
    }

    /// фото без текста — время на фото; карточка без текста — отдельной строкой
    private var needsMetaRow: Bool { m.deleted != true && !hasText && m.photo == nil }

    /// невидимая «подложка» под время в конце текста
    private var timeSpacer: Text {
        Text("\u{2002}" + (m.edited == true ? "изм. " : "") + ChatTime.time(m.at) + (m.mine ? "\u{2002}✓✓" : ""))
            .font(.caption2)
            .foregroundColor(.clear)
    }

    private func meta(on photo: Bool) -> some View {
        HStack(spacing: 3) {
            if m.edited == true { Text("изм.") }
            Text(ChatTime.time(m.at))
            if m.mine {
                Image(systemName: read ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .font(.caption2)
        .foregroundStyle(photo ? Color.white : (m.mine && !isCardOnly ? Color.onLime.opacity(0.6) : Color.primary.opacity(0.5)))
    }
}

// MARK: - Экран звонка (родной вид; соединение появится вместе с аккаунтом Apple и пушами)

struct CallRequest: Identifiable {
    let id = UUID()
    let name: String
    let photo: String?
    let video: Bool
}

struct CallScreen: View {
    let req: CallRequest
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var speaker = false
    @State private var camera = true
    @State private var status = "Вызов…"
    @State private var pulse = false

    var body: some View {
        callBody.environment(\.colorScheme, .dark)
    }

    private var callBody: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B2A10), Color(hex: 0x0F1012), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer().frame(height: 40)
                ZStack {
                    Circle().stroke(Color.lime.opacity(0.25), lineWidth: 2)
                        .frame(width: 170, height: 170)
                        .scaleEffect(pulse ? 1.25 : 1)
                        .opacity(pulse ? 0 : 1)
                    Avatar(url: API.media(req.photo), name: req.name, size: 140)
                }
                Text(req.name).font(.title.bold())
                Text(req.video ? "Видеозвонок · \(status)" : status)
                    .foregroundStyle(Color.oxHint)
                Spacer()
                HStack(spacing: 22) {
                    callButton(muted ? "mic.slash.fill" : "mic.fill", "Звук", on: muted) { muted.toggle() }
                    if req.video {
                        callButton(camera ? "video.fill" : "video.slash.fill", "Камера", on: !camera) { camera.toggle() }
                    }
                    callButton("speaker.wave.3.fill", "Динамик", on: speaker) { speaker.toggle() }
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Color(hex: 0xFF3B30), in: Circle())
                }
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            status = "Нет соединения"
            OxAlert.show(icon: "phone.badge.waveform.fill", title: "Звонки в тестовой версии",
                         message: "Экран звонка уже готов. Само соединение заработает после подключения аккаунта разработчика Apple — тогда звонки будут приходить даже при закрытом приложении.")
        }
    }

    private func callButton(_ icon: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: { action(); Haptic.tap() }) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(on ? Color.black : Color.white)
                    .frame(width: 66, height: 66)
            }
            .glassEffect(on ? .regular.tint(Color.primary.opacity(0.9)).interactive() : .regular.interactive(), in: .circle)
            Text(title).font(.caption).foregroundStyle(Color.oxHint)
        }
    }
}

/// Закреплённый чат с OXION AI в списке чатов
struct AIChatRow: View {
    @AppStorage("ox.ai.last") private var last = ""
    var body: some View {
        HStack(spacing: 12) {
            AIAvatar(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("OXION AI").font(.headline).foregroundStyle(.primary)
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.limeInk)
                    Spacer()
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary).rotationEffect(.degrees(45))
                }
                Text(last.isEmpty ? "Тренер и помощник: тренировки, статистика, тренеры, разделы" : last.replacingOccurrences(of: "**", with: ""))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}


/// перетаскивание пузыря: превью повторяет форму пузыря, без белой подложки на всю ширину
struct BubbleDrag: ViewModifier {
    let provider: (() -> NSItemProvider)?
    let menu: (() -> AnyView)?
    let shape: AnyShape
    func body(content: Content) -> some View {
        if let provider, let menu {
            content
                .contentShape(.dragPreview, shape)
                .contentShape(.contextMenuPreview, shape)
                .contextMenu { menu() }
                .onDrag(provider)
        } else {
            content
        }
    }
}


/// Кнопка стикеров в поле ввода: срабатывает сразу, при нажатии слегка сжимается
private struct StickerToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
