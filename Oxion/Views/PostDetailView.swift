import SwiftUI
import UIKit
import PhotosUI

/// Экран ветки: предки, сам пост крупно, продолжение ветки и ответы.
struct PostDetailView: View {
    let postId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var thread: PostThread?
    @State private var errorText: String?
    @State private var compose: ComposeRequest?
    @State private var route: FeedRoute?
    @Environment(\.feedPush) private var feedPush
    /// внутри вкладки «Лента» — пушим в общий стек, иначе — в свой
    private func go(_ r: FeedRoute) { if let feedPush { feedPush(r) } else { route = r } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let t = thread {
                    ForEach(t.ancestors ?? []) { a in
                        row(a, line: true).opacity(0.75)
                    }
                    row(t.post, big: true, line: !(t.chain ?? []).isEmpty)
                    ForEach(Array((t.chain ?? []).enumerated()), id: \.element.id) { i, c in
                        row(c, line: i < (t.chain ?? []).count - 1)
                    }
                    Divider().overlay(Color.primary.opacity(0.08))
                    HStack {
                        Text("Ответы").font(.headline)
                        Text("\(t.replies?.count ?? 0)").foregroundStyle(Color.oxHint)
                        Spacer()
                    }
                    .padding(16)
                    if (t.replies ?? []).isEmpty {
                        Text("Ответов пока нет — будьте первым")
                            .foregroundStyle(Color.oxHint)
                            .padding(.horizontal, 16)
                    }
                    ForEach(t.replies ?? []) { r in
                        row(r)
                        Divider().overlay(Color.primary.opacity(0.06))
                    }
                } else if let e = errorText {
                    ErrorStateView(message: e) { Task { await load() } }.padding(.top, 60)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.bottom, 90)
        }
        .background(Color.oxBg)
        .navigationTitle("Ветка")
            .onAppear { CrashReporter.mark("post") }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { FeedDestination(route: $0) }
        .safeAreaInset(edge: .bottom) {
            if let t = thread, t.post.canReply != false {
                Button {
                    compose = ComposeRequest(parent: t.post)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.right")
                        Text("Ответить \(t.post.author.name ?? "")…")
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(Color.oxHint)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $compose) { ComposerView(request: $0) { _ in Task { await load() } } }
        .onReceive(NotificationCenter.default.publisher(for: .oxPostDeleted)) { n in
            guard let id = n.object as? Int, let t = thread else { return }
            if id == postId || t.post.id == id { dismiss(); return }
            withAnimation(.smooth(duration: 0.3)) {
                thread = PostThread(post: t.post, chain: (t.chain ?? []).filter { $0.id != id },
                                    ancestors: t.ancestors, replies: (t.replies ?? []).filter { $0.id != id })
            }
        }
        .oxRefreshable { await load() }
        .task { await load() }
    }

    private func row(_ p: Post, big: Bool = false, line: Bool = false) -> some View {
        ThreadPost(post: p, big: big, showLine: line,
                   onOpen: { if p.id != postId { go(.post(p.id)) } },
                   onUser: { go(.user($0)) },
                   onChange: { change in apply(p.id, change) },
                   onRemove: { if p.id == postId { dismiss() } },
                   onCompose: { compose = $0 })
    }

    private func apply(_ id: Int, _ change: (inout Post) -> Void) {
        guard let t = thread else { return }
        var post = t.post
        if post.id == id { change(&post) }
        var chain = t.chain ?? []
        for i in chain.indices where chain[i].id == id { change(&chain[i]) }
        var replies = t.replies ?? []
        for i in replies.indices where replies[i].id == id { change(&replies[i]) }
        var anc = t.ancestors ?? []
        for i in anc.indices where anc[i].id == id { change(&anc[i]) }
        thread = PostThread(post: post, chain: chain, ancestors: anc, replies: replies)
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

// MARK: - Редактор веток (как в PWA: части ветки, фото, опрос, тренировка, тема, кто может отвечать)

struct ComposeRequest: Identifiable {
    enum Preset { case none, photo, workout, poll }
    let id = UUID()
    var preset: Preset = .none
    var parent: Post? = nil
    var quote: Post? = nil
}

struct ComposePart: Identifiable {
    let id = UUID()
    var text = ""
    var images: [PickedImage] = []
    /// фото этой части — под спойлером
    var mediaSpoiler = false
}

struct ComposerView: View {
    let request: ComposeRequest
    var onPosted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var parts: [ComposePart] = [ComposePart()]
    @State private var pickFor: UUID?
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var pollOn = false
    @State private var pollOptions: [String] = ["", ""]
    @State private var workout: Workout?
    @State private var choosingWorkout = false
    @State private var topic: String?
    @State private var replyTo = "all"
    @State private var sending = false
    @State private var music: PostMusic?
    @State private var location: String?
    @State private var aiLabel = false
    @State private var ephemeral = false
    @State private var showParams = false
    @State private var showMusic = false
    @State private var showLocation = false
    @State private var showCamera = false
    @State private var focused: UUID?
    @State private var editors = RichEditors()
    @State private var mention = MentionSuggest()

    private var isReply: Bool { request.parent != nil }

    private var canSend: Bool {
        if sending { return false }
        let hasText = parts.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.images.isEmpty }
        let pollOk = pollOn && pollOptions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
        return hasText || pollOk || workout != nil || music != nil || request.quote != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let p = request.parent {
                        ThreadPost(post: p, showLine: true)
                            .opacity(0.7)
                            .allowsHitTesting(false)
                    }
                    ForEach($parts) { $part in
                        partRow($part, isFirst: part.id == parts.first?.id)
                    }
                    Button {
                        let p = ComposePart()
                        parts.append(p)
                        Haptic.tap(.soft)
                        Task { try? await Task.sleep(for: .milliseconds(80)); editors.of(p.id).focus() }
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 22)
                                .opacity(0.5)
                                .frame(width: 40)
                            Text("Дополните ветку")
                                .foregroundStyle(Color.oxHint)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(parts.count >= 10)

                    if let q = request.quote {
                        QuoteCard(q: .object([
                            "text": .string(q.text ?? ""),
                            "author": .object(["name": .string(q.author.name ?? ""), "photo": .string(q.author.photo ?? "")])
                        ]))
                        .padding(.horizontal, 16)
                        .padding(.leading, 52)
                    }
                }
                .padding(.top, 8)
            }
            .background(Color.oxBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(isReply ? "Ответ" : (request.quote != nil ? "Цитата" : (ephemeral ? "Новая исчезающая публикация" : "Новая ветка")))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if ephemeral && !isReply {
                            Text("Архивируется через 24 часа").font(.caption2).foregroundStyle(Color.oxHint)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.smooth(duration: 0.25), value: ephemeral)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $aiLabel.animation(.smooth(duration: 0.2))) { Label("Добавить метку ИИ", systemImage: "sparkles") }
                        if !isReply {
                            Menu {
                                Button("Без темы") { topic = nil }
                                ForEach(model.meta?.feedTopics ?? []) { t in
                                    Button("\(t.icon ?? "") \(t.name)") { topic = t.key }
                                }
                            } label: { Label("Тема", systemImage: "number") }
                            Button { choosingWorkout = true } label: { Label("Прикрепить тренировку", systemImage: "dumbbell") }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(isPresented: $showParams) { PublishParamsSheet(replyTo: $replyTo) }
            .sheet(isPresented: $showMusic) { MusicPickerSheet { m in withAnimation(.smooth(duration: 0.3)) { music = m } } }
            .sheet(isPresented: $showLocation) { LocationPickerSheet { l in withAnimation(.smooth(duration: 0.3)) { location = l } } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    if let i = parts.firstIndex(where: { $0.id == (pickFor ?? parts.first?.id) }), parts[i].images.count < 4 {
                        parts[i].images.append(PickedImage(image: img))
                    }
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .onAppear { CrashReporter.mark("composer") }
            .photosPicker(isPresented: $showPicker, selection: $picks, maxSelectionCount: 4, matching: .images)
            .onChange(of: picks) { Task { await loadPicks() } }
            .sheet(isPresented: $choosingWorkout) {
                WorkoutChooser { w in workout = w }
            }
            .onAppear {
                if let id = parts.first?.id, request.preset == .none {
                    Task { try? await Task.sleep(for: .milliseconds(350)); editors.of(id).focus() }
                }
                switch request.preset {
                case .photo:
                    pickFor = parts.first?.id
                    showPicker = true
                case .poll:
                    pollOn = true
                case .workout:
                    choosingWorkout = true
                case .none:
                    break
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func partRow(_ part: Binding<ComposePart>, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Avatar(url: API.media(model.me?.photoUrl), name: model.me?.displayName ?? "?", size: 40)
                Capsule().fill(Color.primary.opacity(0.14)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(model.me?.displayName ?? "Вы").font(.subheadline.weight(.semibold))
                    if isFirst && !isReply, let t = topic, let tp = model.meta?.feedTopics?.first(where: { $0.key == t }) {
                        Text("› \(tp.icon ?? "") \(tp.name)").font(.caption).foregroundStyle(Color.oxHint)
                    } else if isFirst && !isReply {
                        Menu {
                            Button("Без темы") { topic = nil }
                            ForEach(model.meta?.feedTopics ?? []) { t in
                                Button("\(t.icon ?? "") \(t.name)") { topic = t.key }
                            }
                        } label: {
                            Text("› Добавить тему").font(.caption).foregroundStyle(Color.oxHint)
                        }
                    }
                    Spacer()
                    if !isFirst {
                        Button {
                            let id = part.wrappedValue.id
                            parts.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "xmark").font(.caption).foregroundStyle(Color.oxHint)
                        }
                    }
                }
                // поле с форматированием: жирный/курсив/спойлер видны сразу, без значков ** и ||
                let pid = part.wrappedValue.id
                RichComposeField(placeholder: isFirst ? (isReply ? "Ваш ответ…" : "Что нового?") : "Продолжение ветки…",
                                 // привязка по id части, а не по индексу: удаление части во время ввода не «роняет» приложение
                                 text: Binding(get: { parts.first(where: { $0.id == pid })?.text ?? "" },
                                               set: { v in if let i = parts.firstIndex(where: { $0.id == pid }) { parts[i].text = v } }),
                                 controller: editors.of(pid),
                                 onFocus: { on in
                                     if on { focused = pid } else if focused == pid { focused = nil }
                                 },
                                 onMention: { q in mention.update(q) })
                // подсказки при вводе «@им…»
                if focused == part.wrappedValue.id, mention.query != nil, !mention.users.isEmpty {
                    MentionList(users: mention.users) { pickMention($0) }
                }
                if !part.wrappedValue.images.isEmpty {
                    let sp = part.wrappedValue.mediaSpoiler
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(part.wrappedValue.images) { pick in
                                Image(uiImage: pick.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 130, height: 170)
                                    .blur(radius: sp ? 18 : 0, opaque: true)
                                    .overlay { if sp { SparkleDust().allowsHitTesting(false) } }
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            part.wrappedValue.images.removeAll { $0.id == pick.id }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption.bold())
                                                .padding(7)
                                                .glassEffect(.regular, in: .circle)
                                        }
                                        .padding(6)
                                    }
                            }
                        }
                    }
                    // спойлер для фото: размытие + искры, у читателя открывается нажатием
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { part.wrappedValue.mediaSpoiler.toggle() }
                        Haptic.tap(.soft)
                    } label: {
                        Label(sp ? "Фото скрыты спойлером" : "Скрыть фото спойлером", systemImage: sp ? "eye.slash.fill" : "eye.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(sp ? Color.onLime : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(sp ? Color.lime : Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if isFirst && (location != nil || aiLabel) {
                    HStack(spacing: 8) {
                        if let l = location {
                            chip("mappin.and.ellipse", l) { withAnimation(.smooth(duration: 0.25)) { location = nil } }
                        }
                        if aiLabel {
                            chip("sparkles", "Данные ИИ") { withAnimation(.smooth(duration: 0.25)) { aiLabel = false } }
                        }
                    }
                    .transition(.opacity)
                }
                if isFirst, let m = music {
                    PostMusicCard(music: m) { withAnimation(.smooth(duration: 0.25)) { music = nil } }
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
                if isFirst && pollOn { pollEditor }
                if isFirst, let w = workout {
                    HStack {
                        PostWorkoutCard(w: .object(["title": .string(w.title ?? "Тренировка"), "sets": .number(0)]))
                        Button { workout = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.oxHint) }
                    }
                }
                HStack(spacing: 0) {
                    tool("photo.on.rectangle") {
                        pickFor = part.wrappedValue.id
                        showPicker = true
                    }
                    tool("camera") {
                        pickFor = part.wrappedValue.id
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                    }
                    if isFirst {
                        tool("music.note", on: music != nil) { showMusic = true }
                    }
                    if isFirst && !isReply {
                        tool("chart.bar.xaxis", on: pollOn) { withAnimation(.smooth(duration: 0.25)) { pollOn.toggle() } }
                    }
                    if isFirst {
                        tool("mappin.and.ellipse", on: location != nil) { showLocation = true }
                    }
                    if isFirst && !isReply {
                        tool("dumbbell", on: workout != nil) { choosingWorkout = true }
                    }
                }
                .padding(.leading, -8)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
    }

    private func tool(_ icon: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap(.soft)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(on ? Color.limeInk : Color.oxHint)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ icon: String, _ text: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark").font(.caption2.bold()) }.buttonStyle(.plain)
        }
        .foregroundStyle(Color.oxHint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var pollEditor: some View {
        VStack(spacing: 6) {
            ForEach(pollOptions.indices, id: \.self) { i in
                TextField("Вариант \(i + 1)", text: Binding(
                    get: { pollOptions[safe: i] ?? "" },
                    set: { v in if i < pollOptions.count { pollOptions[i] = String(v.prefix(40)) } }))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.14)))
            }
            HStack {
                if pollOptions.count < 4 {
                    Button("+ Вариант") { pollOptions.append("") }.font(.subheadline)
                }
                Spacer()
                Button("Убрать опрос") {
                    pollOn = false
                    pollOptions = ["", ""]
                }
                .font(.subheadline)
                .foregroundStyle(.red)
            }
            Text("Опрос длится 24 часа")
                .font(.caption)
                .foregroundStyle(Color.oxHint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: упоминания
    private func pickMention(_ u: MentionUser) {
        guard let id = focused else { return }
        editors.of(id).insertMention(u.username)
        mention.update(nil)
        Haptic.tap(.soft)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !isReply {
                Button { showParams = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Параметры").font(.subheadline.weight(.semibold))
                            Text(PublishParamsSheet.title(replyTo)).font(.caption).lineLimit(1)
                        }
                    }
                    .foregroundStyle(Color.oxHint)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                // исчезающая ветка: видна 24 часа — переключатель из «жидкого стекла»
                Button {
                    withAnimation(.snappy(duration: 0.3)) { ephemeral.toggle() }
                    Haptic.tap(.soft)
                } label: {
                    ZStack(alignment: ephemeral ? .trailing : .leading) {
                        Color.clear.frame(width: 68, height: 40)
                        Image(systemName: "timer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ephemeral ? Color.limeInk : Color.oxHint)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .padding(3)
                    }
                    .glassEffect(ephemeral ? .regular.tint(Color.lime.opacity(0.55)).interactive() : .regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ephemeral ? "Исчезающая ветка включена" : "Сделать исчезающей на 24 часа")
            } else {
                Spacer()
            }
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 6) {
                    if sending { ProgressView() }
                    Text(isReply ? "Ответить" : "Опубликовать").font(.headline)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large).lineLimit(1).minimumScaleFactor(0.75)
            .disabled(sending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func loadPicks() async {
        guard !picks.isEmpty, let target = pickFor ?? parts.first?.id else { return }
        var out: [PickedImage] = []
        for item in picks.prefix(4) {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                out.append(PickedImage(image: img))
            }
        }
        if let i = parts.firstIndex(where: { $0.id == target }) {
            parts[i].images = Array((parts[i].images + out).prefix(4))
        }
        picks = []
    }

    private func upload(_ images: [PickedImage]) async throws -> [String] {
        var keys: [String] = []
        for pick in images {
            guard let data = API.jpeg(pick.image) else { continue }
            let up: UploadResponse = try await API.upload("/feed/upload", data: data)
            keys.append(up.key)
        }
        return keys
    }

    private func send() async {
        guard canSend else {
            OxAlert.show(icon: "square.and.pencil", title: "Ветка пустая", message: "Напишите текст, добавьте фото, опрос или тренировку.")
            return
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sending = true
        defer { sending = false }
        do {
            let first = parts[0]
            let keys = try await upload(first.images)
            var body: [String: Any] = ["text": first.text, "photos": keys, "reply_to": replyTo]
            if first.mediaSpoiler && !keys.isEmpty { body["media_spoiler"] = true }
            if let p = request.parent { body["parent_id"] = p.id }
            if let q = request.quote { body["quote_id"] = q.id }
            if let topic, !isReply { body["topic"] = topic }
            if let workout { body["workout_id"] = workout.id }
            if let music {
                body["music"] = music.dict
                // запасной вариант строкой — сервер примет любой
                if let d = try? JSONSerialization.data(withJSONObject: music.dict), let js = String(data: d, encoding: .utf8) { body["music_json"] = js }
            }
            if let location { body["location"] = location }
            if aiLabel { body["ai_label"] = true }
            if ephemeral && !isReply { body["ephemeral"] = true }
            if pollOn {
                let opts = pollOptions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if opts.count >= 2 { body["poll"] = ["options": opts] }
            }
            var chain: [[String: Any]] = []
            for part in parts.dropFirst() {
                let t = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty && part.images.isEmpty { continue }
                let k = try await upload(part.images)
                chain.append(["text": t, "photos": k, "media_spoiler": part.mediaSpoiler && !k.isEmpty])
            }
            if !chain.isEmpty { body["chain"] = chain }
            var created: Post?
            var failure: Error?
            let payload = body
            let hadMusic = music != nil
            await IslandHUD.shared.run(title: "Отправка публикации", doneText: "Опубликовано") {
                do { created = try await API.call("/feed/posts", method: "POST", body: payload); return true } catch { failure = error; return false }
            }
            if let failure { throw failure }
            guard let r = created else { return }
            Haptic.success()
            NotificationCenter.default.post(name: .oxPostCreated, object: r)
            if hadMusic && r.music == nil {
                OxAlert.show(icon: "music.note", tint: .orange, title: "Трек не сохранился",
                             message: "Ветка опубликована без музыки. Обновите сервер (worker.js) — старая версия не принимает музыку.")
            }
            onPosted(r.id)
            dismiss()
        } catch {
            OxAlert.error("Публикация не отправлена: \(error.localizedDescription)")
        }
    }
}

/// Выбор своей тренировки для поста
struct WorkoutChooser: View {
    var onPick: (Workout) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Workout] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List(items) { w in
                Button {
                    onPick(w)
                    dismiss()
                } label: {
                    WorkoutRow(w: w)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .oxFitSheet()
            .listStyle(.plain)
            .overlay {
                if loaded && items.isEmpty {
                    ContentUnavailableView("Нет тренировок", systemImage: "dumbbell", description: Text("Запишите тренировку в дневнике"))
                }
            }
            .navigationTitle("Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .task {
                let f = RU.dayFormatter
                let to = Date()
                let from = Calendar.current.date(byAdding: .day, value: -45, to: to) ?? to
                if let r: WorkoutsResponse = try? await API.call("/workouts", query: ["from": f.string(from: from), "to": f.string(from: to)]) {
                    items = r.items.filter { ($0.exCount ?? 0) > 0 }.sorted { $0.date > $1.date }
                }
                loaded = true
            }
        }
    }
}

struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
