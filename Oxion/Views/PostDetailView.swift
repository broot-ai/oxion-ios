import SwiftUI
import UIKit
import PhotosUI

/// Экран ветки: сам пост, продолжение ветки и ответы.
struct PostDetailView: View {
    let postId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var thread: PostThread?
    @State private var errorText: String?
    @State private var replying = false
    @State private var toast: String?
    @State private var openId: Int?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let t = thread {
                    ForEach(t.ancestors ?? []) { a in
                        card(a, dim: true)
                    }
                    card(t.post, dim: false)
                    ForEach(t.chain ?? []) { c in
                        card(c, dim: false)
                    }

                    HStack {
                        Text("Ответы")
                            .font(.headline)
                        Text("\(t.replies?.count ?? 0)")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    if (t.replies ?? []).isEmpty {
                        Text("Ответов пока нет — будьте первым")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    ForEach(t.replies ?? []) { r in
                        card(r, dim: false)
                    }
                } else if let e = errorText {
                    ErrorStateView(message: e) {
                        Task { await load() }
                    }
                    .padding(.top, 60)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .navigationTitle("Ветка")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openId) { id in
            PostDetailView(postId: id)
        }
        .safeAreaInset(edge: .bottom) {
            if let t = thread, t.post.canReply != false {
                Button {
                    replying = true
                } label: {
                    Label("Ответить", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $replying) {
            ComposerView(parentId: postId) { _ in
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .toast($toast)
    }

    @ViewBuilder
    private func card(_ p: Post, dim: Bool) -> some View {
        PostCard(post: p,
                 onChange: { change in apply(p.id, change) },
                 onDeleted: {
                     if p.id == postId { dismiss() } else { Task { await load() } }
                 },
                 onToast: { toast = $0 },
                 onOpen: { if p.id != postId { openId = p.id } })
            .opacity(dim ? 0.7 : 1)
    }

    private func apply(_ id: Int, _ change: (inout Post) -> Void) {
        guard var t = thread else { return }
        var post = t.post
        if post.id == id { change(&post) }
        var chain = t.chain ?? []
        for i in chain.indices where chain[i].id == id { change(&chain[i]) }
        var replies = t.replies ?? []
        for i in replies.indices where replies[i].id == id { change(&replies[i]) }
        var anc = t.ancestors ?? []
        for i in anc.indices where anc[i].id == id { change(&anc[i]) }
        t = PostThread(post: post, chain: chain, ancestors: anc, replies: replies)
        thread = t
    }

    private func load() async {
        do {
            let r: PostThread = try await API.call("/feed/posts/\(postId)")
            thread = r
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Новый пост или ответ: текст, до 4 фото, тема.
struct ComposerView: View {
    let parentId: Int?
    var onPosted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var images: [PickedImage] = []
    @State private var topic: String?
    @State private var sending = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !sending && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 40)
                        TextField(parentId == nil ? "Что нового?" : "Ваш ответ", text: $text, axis: .vertical)
                            .lineLimit(4...20)
                            .focused($focused)
                    }

                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(images) { pick in
                                    Image(uiImage: pick.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.removeAll { $0.id == pick.id }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.caption.bold())
                                                    .padding(6)
                                                    .glassEffect(.regular, in: .circle)
                                            }
                                            .padding(6)
                                        }
                                }
                            }
                        }
                    }

                    if parentId == nil, let topics = model.meta?.feedTopics, !topics.isEmpty {
                        Text("Тема")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topics) { t in
                                    Button {
                                        topic = (topic == t.key) ? nil : t.key
                                        Haptic.tap(.soft)
                                    } label: {
                                        Chip(text: "\(t.icon ?? "") \(t.name)", selected: topic == t.key)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle(parentId == nil ? "Новый пост" : "Ответ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending { ProgressView() } else { Text("Опубликовать") }
                    }
                    .disabled(!canSend)
                }
                ToolbarItem(placement: .bottomBar) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 4, matching: .images) {
                        Label("Фото", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            .onChange(of: picks) {
                Task { await loadPicks() }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadPicks() async {
        var out: [PickedImage] = []
        for item in picks.prefix(4) {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                out.append(PickedImage(image: img))
            }
        }
        images = out
    }

    private func send() async {
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            var keys: [String] = []
            for pick in images {
                guard let data = API.jpeg(pick.image) else { continue }
                let up: UploadResponse = try await API.upload("/feed/upload", data: data)
                keys.append(up.key)
            }
            var body: [String: Any] = ["text": text, "photos": keys]
            if let parentId { body["parent_id"] = parentId }
            if let topic { body["topic"] = topic }
            let r: Post = try await API.call("/feed/posts", method: "POST", body: body)
            Haptic.success()
            onPosted(r.id)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
