import SwiftUI
import PhotosUI
import Contacts
import ContactsUI
import UIKit

// Аватарка как в iOS «Контакты»: Memoji, фото, монограмма, эмодзи и цветные варианты.
// У Apple нет открытого доступа к Memoji, поэтому берём их двумя законными путями:
// 1) стикер Memoji из клавиатуры эмодзи (приходит картинкой);
// 2) фото «Моей карточки» в Контактах — там часто стоит Memoji.

struct AvatarBG: Identifiable, Equatable {
    let id: Int
    let top: Color
    let bottom: Color
    static let all: [AvatarBG] = {
        let p: [(UInt32, UInt32)] = [
            (0xC9BEDC, 0x5E5272), (0xC7B8E6, 0x6E5A9C), (0xE6C3CC, 0x7E4E5E), (0xC4CCF2, 0x4C5A99),
            (0xCFCBD8, 0x55526A), (0xD9C0BC, 0x5E3F44), (0xC2C8DA, 0x4A5372), (0xBDBDBD, 0x5A5A5A),
            (0xE4E0D2, 0x6E6A5A), (0xD6F27A, 0x4E8A12), (0x9FE3D7, 0x2A7A6E), (0xFFD3A6, 0xC0632A),
        ]
        return p.enumerated().map { AvatarBG(id: $0.offset, top: Color(hex: $0.element.0), bottom: Color(hex: $0.element.1)) }
    }()
    var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
}

enum AvatarContent: Equatable {
    case photo(UIImage)
    case sticker(UIImage)       // Memoji
    case emoji(String)
    case monogram(String)
}

/// Сам аватар: фон + содержимое. Используется и для превью, и для сохранения.
struct AvatarComposite: View {
    let content: AvatarContent
    let bg: AvatarBG
    var size: CGFloat

    var body: some View {
        ZStack {
            switch content {
            case .photo(let img):
                Image(uiImage: img).resizable().scaledToFill()
            case .sticker(let img):
                bg.gradient
                Image(uiImage: img).resizable().scaledToFit()
                    .padding(size * 0.08)
                    .offset(y: size * 0.04)
            case .emoji(let e):
                bg.gradient
                Text(e).font(.system(size: size * 0.52))
            case .monogram(let t):
                bg.gradient
                Text(t)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Хранилище недавних Memoji (картинки на устройстве)
enum MemojiStore {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "memoji")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func all() -> [UIImage] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(7).compactMap { UIImage(contentsOfFile: $0.path) }
    }
    static func add(_ img: UIImage) {
        guard let d = img.pngData() else { return }
        try? d.write(to: dir.appending(path: "\(Int(Date().timeIntervalSince1970 * 1000)).png"))
    }
}

struct AvatarStudio: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var content: AvatarContent = .monogram("?")
    @State private var bg = AvatarBG.all[0]
    @State private var photoItem: PhotosPickerItem?
    @State private var picking: StickerInput.Mode?
    @State private var memojis: [UIImage] = MemojiStore.all()
    @State private var variants = false
    @State private var saving = false
    @State private var bump = false

    private var initials: String {
        let parts = (model.me?.displayName ?? "?").split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
    private var hasBG: Bool { if case .photo = content { return false }; return true }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [bg.top.opacity(0.9), bg.top.mix(with: bg.bottom, by: 0.35)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: bg)
                if variants { variantsPage } else { mainPage }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { variants ? withAnimation(.snappy) { variants = false } : dismiss() } label: {
                        Image(systemName: variants ? "chevron.left" : "xmark")
                    }
                }
                ToolbarItem(placement: .principal) { Text(variants ? "Цвет" : "Аватар").font(.headline) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.lime)
                    .foregroundStyle(Color.onLime)
                    .disabled(saving)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { content = .monogram(initials.isEmpty ? "?" : initials) }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let d = try? await photoItem.loadTransferable(type: Data.self), let img = UIImage(data: d) { set(.photo(img)) }
                self.photoItem = nil
            }
        }
        .sheet(item: $picking) { mode in
            StickerInputSheet(mode: mode) { result in
                picking = nil
                switch result {
                case .sticker(let img):
                    MemojiStore.add(img)
                    memojis = MemojiStore.all()
                    set(.sticker(img))
                case .emoji(let e): set(.emoji(e))
                case .text(let t): set(.monogram(String(t.prefix(3)).uppercased()))
                }
            }
            .presentationDetents([.height(320)])
        }
    }

    private func set(_ c: AvatarContent) {
        Haptic.tap()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { content = c; bump.toggle() }
    }

    // MARK: главный экран

    private var mainPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                AvatarComposite(content: content, bg: bg, size: 230)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .scaleEffect(bump ? 1 : 0.985)
                    .padding(.top, 8)
                    .contentTransition(.interpolate)
                if hasBG {
                    Button("Настроить") { withAnimation(.snappy) { variants = true } }
                        .font(.headline)
                        .buttonStyle(.glass)
                }
                section("Memoji") {
                    circleButton(icon: "face.smiling.inverse") { picking = .sticker }
                    ForEach(Array(memojis.prefix(3).enumerated()), id: \.offset) { _, m in
                        Button { set(.sticker(m)) } label: { AvatarComposite(content: .sticker(m), bg: bg, size: 76) }
                            .buttonStyle(.plain)
                    }
                    if memojis.isEmpty {
                        Text("Нажмите и выберите стикер Memoji в клавиатуре эмодзи")
                            .font(.caption).foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                section("Фото") {
                    PhotosPicker(selection: $photoItem, matching: .images) { circleLabel(icon: "photo.on.rectangle") }
                    circleButton(icon: "person.crop.circle") { ContactPhoto.pick { img in set(.photo(img)) } }
                    if let url = API.media(model.me?.photoUrl) {
                        Button {
                            Task { if let img = await MediaLoader.shared.load(url) { set(.photo(img)) } }
                        } label: {
                            Avatar(url: url, name: model.me?.displayName ?? "?", size: 76)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                section("Монограмма") {
                    circleButton(text: "Aa") { picking = .text }
                    ForEach([1, 9, 11], id: \.self) { i in
                        Button { bg = AvatarBG.all[i]; set(.monogram(initials)) } label: {
                            AvatarComposite(content: .monogram(initials), bg: AvatarBG.all[i], size: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                section("Эмодзи") {
                    circleButton(icon: "face.smiling") { picking = .emoji }
                    ForEach([("💪", 3), ("🔥", 11), ("🏆", 9)], id: \.0) { e, i in
                        Button { bg = AvatarBG.all[i]; set(.emoji(e)) } label: {
                            AvatarComposite(content: .emoji(e), bg: AvatarBG.all[i], size: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Memoji берутся из стикеров клавиатуры эмодзи или с фото вашей карточки в «Контактах» — Apple не даёт приложениям прямой доступ к Memoji.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: цветные варианты («Предложения»)

    private var variantsPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                AvatarComposite(content: content, bg: bg, size: 230)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Предложения").font(.title3.bold())
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(AvatarBG.all) { b in
                            Button {
                                Haptic.tap()
                                withAnimation(.spring(duration: 0.4)) { bg = b }
                            } label: {
                                AvatarComposite(content: content, bg: b, size: 76)
                                    .overlay(Circle().stroke(.white, lineWidth: bg == b ? 3 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .foregroundStyle(.white)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: элементы

    private func section<C: View>(_ title: String, @ViewBuilder _ items: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, 4)
            HStack(spacing: 12) { items() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func circleLabel(icon: String? = nil, text: String? = nil) -> some View {
        ZStack {
            if let icon { Image(systemName: icon).font(.system(size: 28, weight: .semibold)) }
            if let text { Text(text).font(.system(size: 30, weight: .bold, design: .rounded)) }
        }
        .foregroundStyle(.white)
        .frame(width: 76, height: 76)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private func circleButton(icon: String? = nil, text: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: { Haptic.tap(); action() }) { circleLabel(icon: icon, text: text) }
            .buttonStyle(.plain)
    }

    // MARK: сохранение

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        let r = ImageRenderer(content: AvatarComposite(content: content, bg: bg, size: 512))
        r.scale = 2
        guard let img = r.uiImage, let jpg = img.jpegData(compressionQuality: 0.9) else { return }
        do {
            let _: OK = try await API.upload("/feed/me/photo", data: jpg)
            await model.loadMe()
            Haptic.success()
            FX.play(.sparks)
            dismiss()
        } catch {
            OxAlert.error(error.localizedDescription)
        }
    }
}

// MARK: - Ввод стикера Memoji / эмодзи / букв через системную клавиатуру

enum StickerResult { case sticker(UIImage), emoji(String), text(String) }

struct StickerInput: UIViewRepresentable {
    enum Mode: String, Identifiable { case sticker, emoji, text; var id: String { rawValue } }
    let mode: Mode
    var onResult: (StickerResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.delegate = context.coordinator
        v.font = .systemFont(ofSize: 40)
        v.textAlignment = .center
        v.backgroundColor = .clear
        v.tintColor = UIColor(Color.lime)
        v.supportsAdaptiveImageGlyph = true        // стикеры Memoji и Genmoji приходят картинкой
        v.autocorrectionType = .no
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { v.becomeFirstResponder() }
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: StickerInput
        init(_ p: StickerInput) { parent = p }

        func textViewDidChange(_ tv: UITextView) {
            let a = tv.attributedText ?? NSAttributedString()
            var found: UIImage?
            a.enumerateAttribute(.adaptiveImageGlyph, in: NSRange(location: 0, length: a.length)) { val, _, stop in
                if let g = val as? NSAdaptiveImageGlyph, let img = UIImage(data: g.imageContent) { found = img; stop.pointee = true }
            }
            if found == nil {
                a.enumerateAttribute(.attachment, in: NSRange(location: 0, length: a.length)) { val, _, stop in
                    if let att = val as? NSTextAttachment {
                        found = att.image ?? att.fileWrapper?.regularFileContents.flatMap(UIImage.init(data:))
                        if found != nil { stop.pointee = true }
                    }
                }
            }
            if let found {
                parent.onResult(.sticker(found))
                return
            }
            let t = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            if parent.mode != .text, let last = t.last, last.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }) {
                parent.onResult(.emoji(String(last)))
            }
        }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if parent.mode == .text && text == "\n" {
                let t = tv.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { parent.onResult(.text(t)) }
                return false
            }
            return true
        }
    }
}

private struct StickerInputSheet: View {
    let mode: StickerInput.Mode
    var onResult: (StickerResult) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(mode == .sticker ? "Выберите Memoji" : mode == .emoji ? "Выберите эмодзи" : "Буквы для монограммы")
                .font(.headline)
            Text(mode == .sticker
                 ? "Откройте клавиатуру эмодзи 😀 → пролистайте влево к стикерам Memoji → нажмите на нужный."
                 : mode == .emoji ? "Нажмите любой эмодзи на клавиатуре." : "Введите 1–3 буквы и нажмите «Ввод».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            StickerInput(mode: mode, onResult: onResult)
                .frame(height: 70)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 20)
    }
}

// MARK: - Фото из «Моей карточки» в Контактах (там часто стоит Memoji)

@MainActor
final class ContactPhoto: NSObject, CNContactPickerDelegate {
    private static var current: ContactPhoto?
    private var done: ((UIImage) -> Void)?

    static func pick(_ done: @escaping (UIImage) -> Void) {
        let c = ContactPhoto()
        c.done = done
        current = c
        let p = CNContactPickerViewController()
        p.delegate = c
        p.predicateForEnablingContact = NSPredicate(format: "imageDataAvailable == YES")
        GameHub.topController()?.present(p, animated: true)
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let data = contact.isKeyAvailable(CNContactImageDataKey) ? contact.imageData : (contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil)
        MainActor.assumeIsolated {
            if let data, let img = UIImage(data: data) { done?(img) }
            else { OxAlert.show(icon: "person.crop.circle.badge.questionmark", tint: .orange, title: "У контакта нет фото") }
            ContactPhoto.current = nil
        }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        MainActor.assumeIsolated { ContactPhoto.current = nil }
    }
}
