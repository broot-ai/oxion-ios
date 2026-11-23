import SwiftUI
import UniformTypeIdentifiers

// Как в Telegram:
// • потянуть переписку вверх у самого низа — ИИ делает краткое содержание чата за 24 часа;
// • зажать сообщение и потащить — слева выезжает список чатов, бросаешь на нужный — сообщение переслано
//   с пометкой «Переслано от …».

// MARK: - Пересылка

struct ForwardResponse: Decodable {
    struct Item: Decodable { let chatId: Int; let message: Message }
    let items: [Item]
}

enum ChatForward {
    /// переслать и вернуть имя чата для подсказки
    @MainActor
    static func send(_ messageId: Int, to chats: [ChatItem], text: String = "") async -> Bool {
        do {
            var body: [String: Any] = ["chat_ids": chats.map(\.id)]
            if !text.isEmpty { body["text"] = text }
            let _: ForwardResponse = try await API.call("/messages/\(messageId)/forward", method: "POST", body: body)
            Haptic.success()
            OxSound.play(.sent)
            let who = chats.count == 1 ? (chats[0].peer.name ?? "чат") : "\(chats.count) чата"
            OxAlert.show(icon: "arrowshape.turn.up.right.fill", title: "Переслано", message: "Сообщение переслано: \(who)")
            return true
        } catch {
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

/// Панель чатов, которая выезжает слева, пока тащишь сообщение
struct ForwardDragPanel: View {
    let currentChatId: Int
    let messageId: Int
    var onClose: () -> Void
    @Environment(ChatsStore.self) private var chats
    @State private var target: Int?
    @State private var shown = false

    private var list: [ChatItem] { chats.items.filter { $0.id != currentChatId && $0.archived != true } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // всё вне панели — «отмена»: бросил мимо, панель уехала
                Color.black.opacity(shown ? 0.28 : 0)
                    .ignoresSafeArea()
                    .onDrop(of: [.plainText], isTargeted: nil) { _ in close(); return true }
                    .onTapGesture { close() }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Переслать").font(.title3.bold())
                        Spacer()
                        Button { close() } label: {
                            Image(systemName: "xmark").font(.subheadline.bold()).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.bottom, 8)
                    Text("Отпустите сообщение на чате").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 6)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(list) { c in row(c) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 40)
                    }
                }
                .frame(width: min(geo.size.width * 0.78, 340))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 24, x: 6)
                .offset(x: shown ? 0 : -min(geo.size.width * 0.78, 340) - 30)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            Haptic.tap(.soft)
            withAnimation(.spring(duration: 0.38, bounce: 0.18)) { shown = true }
        }
    }

    private func row(_ c: ChatItem) -> some View {
        let on = target == c.id
        return HStack(spacing: 12) {
            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: on ? 50 : 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.peer.name ?? "Пользователь").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(c.last ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if on {
                Image(systemName: "arrowshape.turn.up.right.circle.fill").font(.title2).foregroundStyle(Color.limeInk)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(on ? Color.lime.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(on ? 1.03 : 1)
        .animation(.spring(duration: 0.25), value: on)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: Binding(get: { target == c.id }, set: { v in
            if v { if target != c.id { target = c.id; Haptic.tap(.soft) } } else if target == c.id { target = nil }
        })) { _ in
            let chat = c
            Task {
                if await ChatForward.send(messageId, to: [chat]) {
                    // в списке чатов этот чат поднимется наверх
                    await chats.load()
                }
            }
            close()
            return true
        }
        .onTapGesture {
            let chat = c
            Task { _ = await ChatForward.send(messageId, to: [chat]); await chats.load() }
            close()
        }
    }

    private func close() {
        withAnimation(.smooth(duration: 0.28)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            onClose()
        }
    }
}

/// Пересылка из меню «Переслать»: выбор одного или нескольких чатов и комментарий
struct ForwardSheet: View {
    let currentChatId: Int
    let messageId: Int
    @Environment(ChatsStore.self) private var chats
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<Int> = []
    @State private var q = ""
    @State private var comment = ""
    @State private var sending = false

    private var list: [ChatItem] {
        let l = chats.items.filter { $0.id != currentChatId }
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty ? l : l.filter { ($0.peer.name ?? "").lowercased().contains(s) }
    }

    var body: some View {
        NavigationStack {
            List(list) { c in
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        if picked.contains(c.id) { picked.remove(c.id) } else if picked.count < 10 { picked.insert(c.id) }
                    }
                    Haptic.tap(.soft)
                } label: {
                    HStack(spacing: 12) {
                        Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 42)
                        Text(c.peer.name ?? "Пользователь").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(picked.contains(c.id) ? Color.limeInk : Color.secondary.opacity(0.5))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск чатов")
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty {
                    HStack(spacing: 8) {
                        TextField("Комментарий", text: $comment)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                        Button {
                            Task {
                                sending = true
                                let sel = chats.items.filter { picked.contains($0.id) }
                                if await ChatForward.send(messageId, to: sel, text: comment.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                    await chats.load()
                                    dismiss()
                                }
                                sending = false
                            }
                        } label: {
                            Image(systemName: "arrow.up").font(.headline).frame(width: 40, height: 40)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(sending)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task { if chats.items.isEmpty { await chats.load() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Краткое содержание чата

struct ChatSummary: Decodable {
    let text: String
    let period: String?
    let count: Int?
    let photos: [String]?
    let peer: String?
    let empty: Bool?
}

/// Подсказка внизу чата, пока тянешь вверх
struct PullSummaryHint: View {
    /// 0…1 — насколько дотянули
    let progress: CGFloat
    var body: some View {
        let ready = progress >= 1
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
                Circle().trim(from: 0, to: min(1, progress))
                    .stroke(Color.limeInk, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: ready ? "sparkles" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 24, height: 24)
            Text(ready ? "Отпустите — краткое содержание" : "Потяните для краткого содержания")
                .font(.footnote.weight(.semibold))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .opacity(Double(min(1, progress * 1.6)))
        .scaleEffect(0.85 + 0.15 * min(1, progress), anchor: .bottom)
        .animation(.smooth(duration: 0.2), value: ready)
        .allowsHitTesting(false)
    }
}

struct ChatSummarySheet: View {
    let chatId: Int
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var data: ChatSummary?
    @State private var error: String?
    @State private var typing = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AIAvatar(size: 34, active: data == nil || typing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Краткое содержание").font(.title2.bold())
                            Text(data.map { periodText($0) } ?? "Читаю переписку…")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                    }
                    if let ph = data?.photos, !ph.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(ph, id: \.self) { u in
                                    RemoteImage(url: API.media(u))
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                    if let d = data {
                        if d.empty == true || d.text.isEmpty {
                            Text("В переписке пока нечего пересказывать").foregroundStyle(.secondary)
                        } else {
                            AITypingText(text: d.text, animate: typing) {
                                withAnimation(.smooth(duration: 0.3)) { typing = false }
                            }
                            .font(.body)
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else {
                        // скелет, пока ИИ думает
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(0..<5, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                                    .frame(height: 12)
                                    .frame(maxWidth: i == 4 ? 180 : .infinity, alignment: .leading)
                            }
                        }
                        .phaseAnimator([0.45, 1.0]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.8) }
                    }
                }
                .padding(20)
                .animation(.smooth(duration: 0.35), value: data == nil)
            }
            .defaultScrollAnchor(.top)
            .navigationTitle("«\(title)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let d = data, !d.text.isEmpty, !typing {
                    ShareLink(item: "Краткое содержание чата «\(title)» — \(periodText(d))\n\n" + d.text.replacingOccurrences(of: "**", with: "")) {
                        Text("Поделиться").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func periodText(_ d: ChatSummary) -> String {
        let n = d.count ?? 0
        return d.period == "24 часа" ? "За последние 24 часа · \(n) сообщ." : "Последние \(n) сообщ."
    }

    private func load() async {
        do {
            let r: ChatSummary = try await API.call("/chats/\(chatId)/summary", method: "POST", body: [:])
            withAnimation(.smooth(duration: 0.35)) { data = r }
            Haptic.success()
        } catch {
            withAnimation { self.error = error.localizedDescription }
            Haptic.tap(.rigid)
        }
    }
}
