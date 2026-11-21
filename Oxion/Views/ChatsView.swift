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
            AppBadge.set(unread)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
        loaded = true
    }

    func markRead(_ id: Int) {
        for i in items.indices where items[i].id == id { items[i].unread = 0; items[i].marked = false }
        AppBadge.set(unread)
    }

    private func update(_ id: Int, _ f: (inout ChatItem) -> Void) {
        for i in items.indices where items[i].id == id { f(&items[i]) }
        AppBadge.set(unread)
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
        AppBadge.set(unread)
        do {
            let _: OK = try await API.call("/chats/\(c.id)/hide", method: "POST")
        } catch {
            items = backup
            OxAlert.error(error.localizedDescription)
        }
    }
    func readAll() async {
        for i in items.indices { items[i].unread = 0; items[i].marked = false }
        AppBadge.set(unread)
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

    enum ChatRoute: Hashable { case chat(ChatRef), archive }

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
                if !store.archived.isEmpty && query.isEmpty && !editing {
                    Button { path.append(.archive) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .font(.title3).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color(hex: 0x636366), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Архив").font(.headline).foregroundStyle(.white)
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
                        .tag(c.id)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
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
        .listRowBackground(c.pinned == true ? Color.white.opacity(0.04) : Color.clear)
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
            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(c.peer.name ?? "Пользователь")
                        .font(.headline)
                        .lineLimit(1)
                    if c.muted == true {
                        Image(systemName: "speaker.slash.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.mine == true, (c.unread ?? 0) == 0 {
                        Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Color.lime)
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
                                .foregroundStyle(m.mine ? Color.black : Color.white)
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
    @State private var messages: [Message] = []
    @State private var peer: Peer?
    @State private var peerReadId = 0
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
    @FocusState private var focused: Bool
    @Namespace private var zoomNS
    @State private var translateText: String?

    private var shielded: Bool { protect?.on == true }

    var body: some View {
        ScreenShield(enabled: shielded) {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
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
                            .foregroundStyle(Color.lime)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.lime.opacity(0.12), in: Capsule())
                            .padding(.bottom, 4)
                    }
                    ForEach(messages) { m in
                        if m.kind == "shot" {
                            HStack(spacing: 6) {
                                Image(systemName: (m.text ?? "").contains("снимок") && !(m.text ?? "").contains("защит") ? "camera.viewfinder" : "lock.shield")
                                Text(m.text ?? "Снимок экрана")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .id(m.id)
                        } else {
                        Bubble(m: m, read: m.mine && m.id <= peerReadId)
                            .id(m.id)
                            .contextMenu {
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
                                if m.mine && m.deleted != true {
                                    Button(role: .destructive) {
                                        Task { await remove(m) }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) {
                if let id = messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .environment(chats)
        }
        .translationPresentation(isPresented: Binding(get: { translateText != nil }, set: { if !$0 { translateText = nil } }),
                                 text: translateText ?? "")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard shielded else { return }
            Task { await reportScreenshot() }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle(peer?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // шапка как в Telegram: имя и статус в стеклянной капсуле, аватар справа открывает профиль
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    profile
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Text(peer?.name ?? title).font(.headline).lineLimit(1)
                            if peer?.trainer == true {
                                Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.lime)
                            }
                            if shielded {
                                Image(systemName: "lock.shield.fill").font(.caption2).foregroundStyle(Color.lime)
                            }
                        }
                        Text(PeerStatus.text(peer?.lastSeen))
                            .font(.caption2)
                            .foregroundStyle(PeerStatus.online(peer?.lastSeen) ? Color.lime : Color.oxHint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    profile
                        .navigationTransition(.zoom(sourceID: "peer-avatar", in: zoomNS))
                } label: {
                    Avatar(url: API.media(peer?.photo), name: peer?.name ?? title, size: 36)
                        .matchedTransitionSource(id: "peer-avatar", in: zoomNS)
                }
                .buttonStyle(.plain)
                .disabled(peer == nil)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $call) { CallScreen(req: $0) }
        .sheet(isPresented: $attaching) {
            ChatAttachSheet(chatId: chatId, replyTo: replyTo?.id) { m in
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

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let r = replyTo {
                HStack {
                    Rectangle().fill(Color.lime).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine ? "Ответ себе" : "Ответ")
                            .font(.caption.bold())
                            .foregroundStyle(Color.lime)
                        Text(r.text ?? "Фото")
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

                TextField("Сообщение", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))

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
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .padding(.top, 6)
    }

    private func load(initial: Bool) async {
        let after = initial ? 0 : (messages.last?.id ?? 0)
        var q: [String: String] = [:]
        if after > 0 { q["after"] = String(after) }
        do {
            let r: ChatDetail = try await API.call("/chats/\(chatId)", query: q)
            peer = r.peer
            if let p = r.protect { protect = p }
            peerReadId = r.peerReadId ?? peerReadId
            if after == 0 {
                messages = r.messages
            } else if !r.messages.isEmpty {
                let have = Set(messages.map(\.id))
                let fresh = r.messages.filter { !have.contains($0.id) }
                messages += fresh
                ChatAutoSave.handle(fresh, trainerChat: r.peer.trainer == true)
            }
            loaded = true
            errorText = nil
            if let last = messages.last?.id {
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
        if let p = peer {
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
            if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            Haptic.tap()
        } catch {
            errorText = error.localizedDescription
        }
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
        do {
            let upd: Message = try await API.call("/messages/\(m.id)", method: "DELETE")
            replace(upd)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func replace(_ m: Message) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i] = m }
    }
}

struct Bubble: View {
    let m: Message
    var read: Bool

    private var isCardOnly: Bool { m.kind != nil && (m.text ?? "").isEmpty && m.photo == nil && m.deleted != true }

    var body: some View {
        HStack(alignment: .bottom) {
            if m.mine { Spacer(minLength: 56) }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 4) {
                if isCardOnly, let k = m.kind {
                    // карточка без лишней «обёртки» сообщения
                    VStack(alignment: .trailing, spacing: 4) {
                        ChatCard(kind: k, card: m.card, mine: m.mine)
                        meta.padding(.trailing, 6)
                    }
                } else {
                    bubble
                }
                if let rs = m.reactions, !rs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(rs, id: \.self) { r in
                            Text("\(r.emoji) \(r.n)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(r.mine == true ? Color.lime.opacity(0.3) : Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            if !m.mine { Spacer(minLength: 56) }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = m.reply {
                HStack(spacing: 6) {
                    Capsule().fill(m.mine ? Color.black.opacity(0.45) : Color.lime).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine == true ? "Вы" : "Ответ").font(.caption.bold())
                        Text(r.text ?? "").font(.caption).lineLimit(2)
                    }
                    .opacity(0.85)
                }
                .padding(.vertical, 2)
            }
            if m.deleted == true {
                Text("Сообщение удалено").italic().opacity(0.6)
            } else {
                if let p = API.media(m.photo) {
                    RemoteImage(url: p)
                        .frame(width: 230, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, -8)
                }
                if let k = m.kind {
                    ChatCard(kind: k, card: m.card, mine: m.mine, embedded: true)
                        .padding(.horizontal, -6)
                }
                if let t = m.text, !t.isEmpty {
                    Text(t).font(.system(size: 16))
                }
            }
            meta.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundStyle(m.mine ? Color.oxBg : Color.primary)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: m.mine ? 20 : 6,
                                   bottomTrailingRadius: m.mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
                .fill(m.mine ? Color.lime : Color.white.opacity(0.08))
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: m.mine ? 20 : 6,
                                   bottomTrailingRadius: m.mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
                .stroke(m.mine ? Color.clear : Color.white.opacity(0.07))
        )
        .frame(maxWidth: 300, alignment: m.mine ? .trailing : .leading)
    }

    private var meta: some View {
        HStack(spacing: 3) {
            if m.edited == true { Text("изм.") }
            Text(ChatTime.time(m.at))
            if m.mine {
                Image(systemName: read ? "checkmark.circle.fill" : "checkmark")
            }
        }
        .font(.caption2)
        .opacity(0.55)
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
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B2A10), Color.oxBg, Color.black], startPoint: .top, endPoint: .bottom)
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
            .glassEffect(on ? .regular.tint(Color.white.opacity(0.9)).interactive() : .regular.interactive(), in: .circle)
            Text(title).font(.caption).foregroundStyle(Color.oxHint)
        }
    }
}
