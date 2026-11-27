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
    static func send(_ messageId: Int, to chats: [ChatItem], text: String = "", quiet: Bool = false) async -> Bool {
        do {
            var body: [String: Any] = ["chat_ids": chats.map(\.id)]
            if !text.isEmpty { body["text"] = text }
            let _: ForwardResponse = try await API.call("/messages/\(messageId)/forward", method: "POST", body: body)
            Haptic.success()
            OxSound.play(.sent)
            let who = chats.count == 1 ? (chats[0].peer.name ?? "чат") : "\(chats.count) чата"
            if quiet { return true }
            OxAlert.show(icon: "arrowshape.turn.up.right.fill", title: "Переслано", message: "Сообщение переслано: \(who)")
            return true
        } catch {
            OxAlert.error(error.localizedDescription)
            return false
        }
    }
}

/// Ловит момент, когда поднятое сообщение начали тащить (а не просто держат для меню)
struct ForwardStartDrop: DropDelegate {
    var onMove: () -> Void
    var onEnd: () -> Void
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { onMove() }
    func dropUpdated(info: DropInfo) -> DropProposal? { onMove(); return DropProposal(operation: .cancel) }
    func performDrop(info: DropInfo) -> Bool { onEnd(); return false }
}

/// Как в Telegram: пока тащишь сообщение, слева выезжает список чатов, а переписка сдвигается вправо.
/// Бросил на чат — переслано, внизу маленькая подсказка «Сообщение переслано: …».
struct ForwardDragPanel: View {
    let currentChatId: Int
    let messageId: Int
    @Binding var shown: Bool
    var onForwarded: (String) -> Void = { _ in }
    var onClose: () -> Void
    @Environment(ChatsStore.self) private var chats
    @State private var target: Int?

    static var width: CGFloat { min(UIScreen.main.bounds.width * 0.8, 340) }
    private var list: [ChatItem] { chats.items.filter { $0.id != currentChatId && $0.archived != true } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // всё вне панели (видимая полоска переписки справа) — «отмена»
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onDrop(of: [.plainText], isTargeted: nil) { _ in close(); return true }
                    .onTapGesture { close() }

                VStack(spacing: 0) {
                    ZStack {
                        Text("Чаты").font(.headline)
                        HStack {
                            Text("Изменить").font(.body).foregroundStyle(.secondary)
                                .padding(.horizontal, 14).frame(height: 36)
                                .glassEffect(.regular, in: .capsule)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, geo.safeAreaInsets.top + 6)
                    .padding(.bottom, 8)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(list) { c in row(c) }
                        }
                        .padding(.bottom, 90)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(width: Self.width)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color(.systemBackground))
                .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 18, x: 4)
                .offset(x: shown ? 0 : -Self.width - 24)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            Haptic.tap(.soft)
            withAnimation(.spring(duration: 0.4, bounce: 0.12)) { shown = true }
        }
    }

    private func row(_ c: ChatItem) -> some View {
        let on = target == c.id
        return HStack(spacing: 12) {
            Avatar(url: API.media(c.peer.photo), name: c.peer.name ?? "?", size: 54)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if c.peer.official != nil { OxionSeal(size: 14) }
                    Text(c.peer.name ?? "Пользователь").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if c.peer.trainer == true { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(Color.limeInk) }
                }
                Text(c.last ?? "").font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(on ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 80)
        }
        .animation(.easeOut(duration: 0.15), value: on)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: Binding(get: { target == c.id }, set: { v in
            if v { if target != c.id { target = c.id; Haptic.tap(.soft) } } else if target == c.id { target = nil }
        })) { _ in
            forward(c)
            return true
        }
        .onTapGesture { forward(c) }
    }

    private func forward(_ c: ChatItem) {
        let chat = c
        let name = c.peer.name ?? "чат"
        close()
        Task {
            if await ChatForward.send(messageId, to: [chat], quiet: true) {
                onForwarded(name)
                await chats.load()
            }
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.34, bounce: 0.08)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(340))
            onClose()
        }
    }
}

/// Маленькая тёмная подсказка внизу чата (как «Message forwarded to …» в Telegram)
struct ChatToast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.black.opacity(0.82), in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
            .oxFitSheet()
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
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Краткое содержание чата

struct ChatSummary: Decodable {
    struct Topic: Decodable, Hashable { let word: String; let msgId: Int?; let avatars: [String]? }
    struct Item: Decodable, Hashable { let time: String?; let text: String; let msgId: Int?; let photos: [String]?; let topics: [Topic]? }
    let text: String
    var items: [Item]? = nil
    var range: String? = nil
    let period: String?
    let count: Int?
    let photos: [String]?
    let peer: String?
    let empty: Bool?
}

/// Подсказка внизу чата, пока тянешь вверх: кружок с двойной стрелкой, как в Telegram
struct PullSummaryHint: View {
    /// 0…1 — насколько дотянули
    let progress: CGFloat
    var body: some View {
        let ready = progress >= 1
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().trim(from: 0, to: min(1, progress))
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: ready ? "sparkles" : "chevron.up.2")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 52, height: 52)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .opacity(Double(min(1, 0.3 + progress * 1.6)))
        .scaleEffect(0.7 + 0.3 * min(1, progress))
        .animation(.smooth(duration: 0.2), value: ready)
        .allowsHitTesting(false)
    }
}

struct ChatSummarySheet: View {
    let chatId: Int
    let title: String
    var onJump: (Int) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var data: ChatSummary?
    @State private var error: String?
    @State private var shownItems = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(data?.range ?? " ")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .redacted(reason: data == nil ? .placeholder : [])
                        Text(data?.period == "24 часа" || data == nil ? "Сводка за 24 часа" : "Сводка последних сообщений")
                            .font(.title2.bold())
                    }
                    if let d = data {
                        let items = d.items ?? []
                        if d.empty == true || (items.isEmpty && d.text.isEmpty) {
                            Text("В переписке пока нечего пересказывать").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                                itemView(it)
                                    .opacity(i < shownItems ? 1 : 0)
                                    .offset(y: i < shownItems ? 0 : 12)
                            }
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else {
                        skeleton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .defaultScrollAnchor(.top)
            .navigationTitle("«\(title)» — сводка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let d = data, !d.text.isEmpty {
                    ShareLink(item: "Сводка чата «\(title)»\(d.range.map { " · " + $0 } ?? "")\n\n" + d.text) {
                        Text("Поделиться сводкой").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color(hex: 0x3478F6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task { await load() }
        }
        .presentationDragIndicator(.visible)
    }

    private func itemView(_ it: ChatSummary.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = it.time, !t.isEmpty {
                Text(t).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            Text(highlighted(it))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { if let id = it.msgId { jump(id) } }
            if let ph = it.photos, !ph.isEmpty {
                HStack(spacing: 6) {
                    ForEach(ph, id: \.self) { u in
                        RemoteImage(url: API.media(u))
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                }
            }
            if let tp = it.topics, !tp.isEmpty {
                FlowLayoutSimple(spacing: 8) {
                    ForEach(tp, id: \.self) { t in
                        Button { if let id = t.msgId ?? it.msgId { jump(id) } } label: {
                            HStack(spacing: 6) {
                                if let av = t.avatars, !av.isEmpty {
                                    HStack(spacing: -8) {
                                        ForEach(av.prefix(3), id: \.self) { a in
                                            Avatar(url: API.media(a), name: t.word, size: 22)
                                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                        }
                                    }
                                }
                                Text(t.word).font(.subheadline.weight(.medium))
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(Color(hex: 0x3478F6))
                            .padding(.leading, (t.avatars?.isEmpty ?? true) ? 12 : 4).padding(.trailing, 10)
                            .frame(height: 32)
                            .background(Color(hex: 0x3478F6).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// ключевые слова тем — цветом ссылки
    private func highlighted(_ it: ChatSummary.Item) -> AttributedString {
        var a = AttributedString(it.text)
        for t in it.topics ?? [] {
            if let r = a.range(of: t.word, options: .caseInsensitive) { a[r].foregroundColor = Color(hex: 0x3478F6) }
        }
        return a
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(width: 54, height: 20)
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08))
                            .frame(height: 12).frame(maxWidth: i == 2 ? 200 : .infinity, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 40, height: 40) }
                    }
                }
            }
        }
        .phaseAnimator([0.45, 1.0]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.8) }
    }

    private func jump(_ id: Int) {
        Haptic.tap(.soft)
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            onJump(id)
        }
    }

    private func load() async {
        do {
            let r: ChatSummary = try await API.call("/chats/\(chatId)/summary", method: "POST", body: [:])
            withAnimation(.smooth(duration: 0.3)) { data = r }
            Haptic.success()
            // блоки появляются по очереди
            for i in 1...max(1, r.items?.count ?? 1) {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.smooth(duration: 0.35)) { shownItems = i }
            }
        } catch {
            withAnimation { self.error = error.localizedDescription }
            Haptic.tap(.rigid)
        }
    }
}
