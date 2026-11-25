import SwiftUI

// MARK: - Запросы на переписку — как в Instagram / Threads

struct ReqCounts: Decodable, Hashable { var pending: Int?; var hidden: Int? }

struct ChatRequestState: Decodable, Equatable {
    let state: String          // incoming | outgoing
    var hidden: Bool? = nil
    var left: Int? = nil
    var limit: Int? = nil
}

struct RequestItem: Decodable, Identifiable {
    struct P: Decodable { let id: Int; let name: String?; let photo: String?; let username: String? }
    let id: Int
    let peer: P
    let last: String?
    let at: Double?
    let count: Int?
    let followsMe: Bool?
}
private struct RequestsResp: Decodable { let items: [RequestItem]; let counts: ReqCounts? }
private struct MsgSettings: Decodable { let policy: String; let limit: Int?; let requests: ReqCounts? }

/// Строка «Запросы» над списком чатов
struct RequestsEntryRow: View {
    let counts: ReqCounts
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(hex: 0x0A84FF), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Запросы на переписку").font(.headline).foregroundStyle(.primary)
                Text((counts.pending ?? 0) > 0
                     ? "\(counts.pending ?? 0) " + RU.plural(counts.pending ?? 0, "новый запрос", "новых запроса", "новых запросов")
                     : String(localized: "Скрытые запросы"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if (counts.pending ?? 0) > 0 { UnreadBadge(n: counts.pending ?? 0, muted: false) }
        }
        .contentShape(Rectangle())
    }
}

struct MessageRequestsView: View {
    var open: (ChatRef) -> Void
    @Environment(ChatsStore.self) private var store
    @AppStorage("dm_req_info_seen") private var infoSeen = false
    @State private var tab = "pending"
    @State private var items: [RequestItem] = []
    @State private var counts = ReqCounts()
    @State private var loaded = false
    @State private var query = ""
    @State private var showInfo = false
    @State private var openSettings = false

    private var filtered: [RequestItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { ($0.peer.name ?? "").localizedCaseInsensitiveContains(q) || ($0.peer.username ?? "").localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    chip("Запросы", "pending", counts.pending ?? 0)
                    chip("Скрыто", "hidden", counts.hidden ?? 0)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(filtered) { r in
                    Button { open(ChatRef(id: r.id, name: r.peer.name ?? "Запрос")) } label: { row(r) }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 14))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await act(r, "delete") } } label: { Label("Удалить", systemImage: "trash") }
                            Button { Task { await act(r, "block") } } label: { Label("Заблокировать", systemImage: "hand.raised.fill") }.tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            if tab == "pending" {
                                Button { Task { await act(r, "accept") } } label: { Label("Принять", systemImage: "checkmark") }.tint(.green)
                            } else {
                                Button { Task { await act(r, "unhide") } } label: { Label("Показать", systemImage: "eye") }.tint(.blue)
                            }
                        }
                }
            } footer: {
                if tab == "hidden" && !items.isEmpty {
                    Text("Сюда попадают запросы, которые могут быть оскорбительными или похожи на спам. Их текст скрыт, пока вы не откроете переписку.")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loaded && filtered.isEmpty {
                ContentUnavailableView(tab == "pending" ? "Нет запросов" : "Нет скрытых запросов",
                                       systemImage: tab == "pending" ? "envelope.open" : "eye.slash",
                                       description: Text(tab == "pending" ? "Здесь появятся сообщения от людей, на которых вы не подписаны." : "Подозрительные запросы мы прячем сюда."))
            } else if !loaded { ProgressView() }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск")
        .navigationTitle("Запросы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
            }
        }
        .sheet(isPresented: $showInfo) {
            RequestsInfoSheet { showInfo = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openSettings = true } }
                .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $openSettings) { MessageSettingsView() }
        .task(id: tab) { await load() }
        .onAppear { if !infoSeen { infoSeen = true; showInfo = true } }
        .oxRefreshable { await load() }
    }

    private func chip(_ title: LocalizedStringKey, _ key: String, _ n: Int) -> some View {
        Button {
            Haptic.tap(.soft)
            withAnimation(.snappy) { tab = key }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if n > 0 { Text("\(n)").foregroundStyle(tab == key ? Color.primary.opacity(0.6) : .secondary) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).frame(height: 36)
            .foregroundStyle(.primary)
            .background(tab == key ? Color.primary.opacity(0.12) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ r: RequestItem) -> some View {
        HStack(spacing: 12) {
            Avatar(url: API.media(r.peer.photo), name: r.peer.name ?? "?", size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(r.peer.name ?? "Пользователь").font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if let at = r.at { Text(ChatTime.short(at)).font(.footnote).foregroundStyle(.secondary) }
                }
                Text(r.last ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if r.followsMe == true {
                    Text("Подписан(а) на вас").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        if let r: RequestsResp = try? await API.call("/chats/requests", query: ["tab": tab]) {
            withAnimation(.snappy) { items = r.items; counts = r.counts ?? counts }
        }
        loaded = true
    }

    private func act(_ r: RequestItem, _ action: String) async {
        do {
            let _: OK = try await API.call("/chats/\(r.id)/request", method: "POST", body: ["action": action])
            Haptic.success()
            withAnimation(.snappy) { items.removeAll { $0.id == r.id } }
            await load()
            await store.load()
            if action == "accept" { open(ChatRef(id: r.id, name: r.peer.name ?? "Чат")) }
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

/// «Как работают запросы на переписку»
struct RequestsInfoSheet: View {
    var onSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Как работают запросы\nна переписку")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 34)
                    item("envelope.badge", "Вы сами решаете, какие запросы принять",
                         "Отправитель не узнает, что вы посмотрели запрос, пока вы его не примете. Принятые запросы переносятся в «Чаты», после этого вы можете писать друг другу.")
                    item("checkmark.shield", "Дополнительная защита для сообщений от пользователей, на которых вы не подписаны",
                         "В целях вашей безопасности в запросах на переписку нельзя отправлять фото, видео, голосовые и ссылки. Мы также скрываем сообщения, которые, по нашему мнению, могут быть вредными, оскорбительными или содержать спам.")
                    item("arrow.up.arrow.down.square", "Вы можете отключить запросы",
                         "Зайдите в настройки сообщений и выберите «Только те, на кого вы подписаны».")
                }
                .padding(.horizontal, 24)
            }
            VStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("OK").font(.headline)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { dismiss(); onSettings() } label: {
                    Text("Настройки").font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .presentationDragIndicator(.visible)
    }

    private func item(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Настройки «Сообщения»: кто может вам писать
struct MessageSettingsView: View {
    @State private var policy = "all"
    @State private var counts = ReqCounts()
    @State private var limit = 3
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                Text("Решите, могут ли люди, на которых вы не подписаны, отправлять вам запросы на переписку. Пользователи, на которых вы подписаны, всегда могут написать вам, если вы их не заблокировали.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
            Section {
                option("following", "Только те, на кого вы подписаны",
                       "Это люди, на которых вы подписаны, ваши тренеры и клиенты, и те, с кем вы уже переписывались.")
                option("all", "Все",
                       "Вы можете получать запросы на переписку от пользователей, на которых не подписаны. Число сообщений в таких запросах ограничено (\(limit)). В них также нельзя отправлять фото, видео и ссылки. В разделе «Запросы» можно выбирать, какие запросы принять.")
            } header: {
                Text("Кто может отправлять вам сообщения")
                    .font(.headline).foregroundStyle(.primary).textCase(nil)
            }
            if policy == "all" {
                Section {
                    NavigationLink {
                        MessageRequestsView { _ in }
                    } label: {
                        HStack {
                            Label("Запросы на переписку", systemImage: "envelope.badge")
                            Spacer()
                            let n = (counts.pending ?? 0) + (counts.hidden ?? 0)
                            if n > 0 { Text("\(n)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Сообщения")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!loaded)
        .task {
            if let r: MsgSettings = try? await API.call("/settings/messages") {
                policy = r.policy; counts = r.requests ?? counts; limit = r.limit ?? 3
            }
            loaded = true
        }
    }

    private func option(_ key: String, _ title: LocalizedStringKey, _ text: String) -> some View {
        Button {
            guard policy != key else { return }
            let old = policy
            Haptic.tap(.soft)
            withAnimation(.snappy) { policy = key }
            Task {
                do { let _: OK = try await API.call("/settings/messages", method: "POST", body: ["policy": key]) }
                catch { withAnimation { policy = old }; OxAlert.error(error.localizedDescription) }
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(text).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(policy == key ? Color.primary : Color.secondary.opacity(0.5), lineWidth: policy == key ? 7 : 1.5)
                        .frame(width: 26, height: 26)
                }
                .padding(.top, 2)
                .animation(.spring(duration: 0.25), value: policy)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Внизу переписки, если вам пришёл запрос: Заблокировать · Удалить · Принять
struct IncomingRequestBar: View {
    let name: String
    let chatId: Int
    var done: (String) -> Void
    @State private var busy = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("\(name) хочет отправить вам сообщение").font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                Text("Отправитель не узнает, что вы посмотрели запрос, пока вы его не примете.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                button("Заблокировать", "block", .red)
                button("Удалить", "delete", .red)
                button("Принять", "accept", .primary, prominent: true)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .disabled(busy)
    }

    private func button(_ t: LocalizedStringKey, _ action: String, _ color: Color, prominent: Bool = false) -> some View {
        Button {
            if action == "block" {
                OxAlert.confirm(title: String(localized: "Заблокировать?"), message: String(localized: "Этот человек больше не сможет вам писать."), action: String(localized: "Заблокировать"), destructive: true) {
                    Task { await go(action) }
                }
            } else { Task { await go(action) } }
        } label: {
            Text(t).font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color(.systemBackground) : color)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(prominent ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func go(_ action: String) async {
        busy = true
        defer { busy = false }
        do {
            let _: OK = try await API.call("/chats/\(chatId)/request", method: "POST", body: ["action": action])
            action == "accept" ? Haptic.success() : Haptic.tap()
            done(action)
        } catch { OxAlert.error(error.localizedDescription) }
    }
}

/// Над полем ввода у отправителя: «Запрос отправлен…»
struct OutgoingRequestNote: View {
    let left: Int
    let limit: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Запрос на переписку отправлен").font(.footnote.weight(.semibold))
                Text(left > 0
                     ? String(localized: "Пока его не примут — только текст без ссылок. Осталось сообщений: \(left) из \(limit).")
                     : String(localized: "Вы отправили максимум сообщений. Дождитесь, пока запрос примут."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
    }
}
