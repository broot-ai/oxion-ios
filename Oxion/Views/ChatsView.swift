import SwiftUI
import UIKit
import PhotosUI
import Observation

@MainActor
@Observable
final class ChatsStore {
    var items: [ChatItem] = []
    var loading = false
    var loaded = false
    var errorText: String?

    var unread: Int { items.reduce(0) { $0 + ($1.unread ?? 0) } }

    func load() async {
        loading = true
        do {
            let r: ChatsResponse = try await API.call("/chats")
            items = r.items
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
        loaded = true
    }

    func markRead(_ id: Int) {
        for i in items.indices where items[i].id == id { items[i].unread = 0 }
    }
}

struct ChatsView: View {
    @Environment(ChatsStore.self) private var store
    @State private var query = ""

    private var filtered: [ChatItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return store.items }
        return store.items.filter { ($0.peer.name ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let e = store.errorText, store.items.isEmpty {
                    ErrorStateView(message: e) {
                        Task { await store.load() }
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(filtered) { c in
                    NavigationLink(value: ChatRef(id: c.id, name: c.peer.name ?? "Чат")) {
                        ChatRow(c: c)
                    }
                }
            }
            .listStyle(.plain)
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
            .navigationDestination(for: ChatRef.self) { ref in
                ChatView(chatId: ref.id, title: ref.name)
            }
            .searchable(text: $query, prompt: "Поиск по чатам")
            .refreshable { await store.load() }
            .task { await store.load() }
        }
    }
}

struct ChatRow: View {
    let c: ChatItem

    var body: some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(c.peer.name ?? "Пользователь")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if let at = c.at, at > 0 {
                        Text(ChatTime.short(at))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text((c.mine == true ? "Вы: " : "") + (c.last ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if let u = c.unread, u > 0 {
                        Text("\(u)")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.lime, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
    @State private var callWeb: WebTarget?
    @FocusState private var focused: Bool

    var body: some View {
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
                    ForEach(messages) { m in
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
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle(peer?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(peer?.name ?? title)
                        .font(.headline)
                    if peer?.trainer == true {
                        Text("тренер")
                            .font(.caption2)
                            .foregroundStyle(Color.lime)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        callWeb = WebTarget(path: "/#chat/\(chatId)")
                    } label: {
                        Label("Аудиозвонок", systemImage: "phone.fill")
                    }
                    Button {
                        callWeb = WebTarget(path: "/#chat/\(chatId)")
                    } label: {
                        Label("Видеозвонок", systemImage: "video.fill")
                    }
                    Button {
                        callWeb = WebTarget(path: "/#chat/\(chatId)")
                    } label: {
                        Label("Открыть чат в полной версии", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Image(systemName: "phone.fill")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $callWeb) { t in WebAppView(path: t.path) }
        .sheet(isPresented: $attaching) {
            AttachSheet(chatId: chatId) { m in
                if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            }
        }
        .task {
            await load(initial: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
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
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                PhotosPicker(selection: $photoPick, matching: .images) {
                    Image(systemName: "photo")
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
            peerReadId = r.peerReadId ?? peerReadId
            if after == 0 {
                messages = r.messages
            } else if !r.messages.isEmpty {
                let have = Set(messages.map(\.id))
                messages += r.messages.filter { !have.contains($0.id) }
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

    var body: some View {
        HStack {
            if m.mine { Spacer(minLength: 50) }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    if let r = m.reply {
                        HStack(spacing: 6) {
                            Rectangle().fill(m.mine ? Color.black.opacity(0.5) : Color.lime).frame(width: 2)
                            Text(r.text ?? "")
                                .font(.caption)
                                .lineLimit(2)
                                .opacity(0.8)
                        }
                    }
                    if m.deleted == true {
                        Text("Сообщение удалено")
                            .italic()
                            .opacity(0.6)
                    } else {
                        if let p = API.media(m.photo) {
                            RemoteImage(url: p)
                                .frame(width: 220, height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if let k = m.kind {
                            ChatCard(kind: k, card: m.card, mine: m.mine)
                        }
                        if let t = m.text, !t.isEmpty {
                            Text(t)
                        }
                    }
                    HStack(spacing: 3) {
                        if m.edited == true { Text("изм.") }
                        Text(ChatTime.time(m.at))
                        if m.mine {
                            Image(systemName: read ? "checkmark.circle.fill" : "checkmark")
                        }
                    }
                    .font(.caption2)
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(m.mine ? Color.black : Color.primary)
                .background(m.mine ? Color.lime : Color.white.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let rs = m.reactions, !rs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(rs, id: \.self) { r in
                            Text("\(r.emoji) \(r.n)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .glassEffect(r.mine == true ? .regular.tint(Color.lime.opacity(0.4)) : .regular, in: .capsule)
                        }
                    }
                }
            }
            .frame(maxWidth: 300, alignment: m.mine ? .trailing : .leading)
            if !m.mine { Spacer(minLength: 50) }
        }
    }
}
