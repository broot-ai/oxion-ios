import SwiftUI
import UIKit
import PencilKit
import PhotosUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Редактор истории (как в Telegram): рисунок разными маркерами, текст со шрифтами,
// стикеры (эмодзи, фото, фигуры), настройки изображения. Плюс «поделиться веткой в истории».

// MARK: модель

enum StoryFont: String, CaseIterable, Identifiable {
    case system, typewriter, avenir, courier, noteworthy, georgia, papyrus, snell
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "San Francisco"
        case .typewriter: "Typewriter"
        case .avenir: "Avenir Next"
        case .courier: "Courier New"
        case .noteworthy: "Noteworthy"
        case .georgia: "Georgia"
        case .papyrus: "Papyrus"
        case .snell: "Snell Roundhand"
        }
    }
    func font(_ size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size, weight: .bold)
        case .typewriter: .custom("AmericanTypewriter-Semibold", size: size)
        case .avenir: .custom("AvenirNext-DemiBoldItalic", size: size)
        case .courier: .custom("CourierNewPS-BoldMT", size: size)
        case .noteworthy: .custom("Noteworthy-Bold", size: size)
        case .georgia: .custom("Georgia-Bold", size: size)
        case .papyrus: .custom("Papyrus", size: size)
        case .snell: .custom("SnellRoundhand-Bold", size: size)
        }
    }
}

enum StoryTextStyle: Int, CaseIterable { case plain, filled, soft, outline }
enum StoryShapeKind: String, CaseIterable, Identifiable {
    case rect, ellipse, bubble, star, arrow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rect: "Прямоугольник"
        case .ellipse: "Эллипс"
        case .bubble: "Облако"
        case .star: "Звезда"
        case .arrow: "Стрелка"
        }
    }
    var icon: String {
        switch self {
        case .rect: "square"
        case .ellipse: "circle"
        case .bubble: "bubble.left"
        case .star: "star"
        case .arrow: "arrow.up.right"
        }
    }
}

struct StoryPostCardData: Equatable {
    let postId: Int
    let author: String
    let avatar: UIImage?
    let text: String
    let photo: UIImage?
    let seal: Bool
}

struct StoryOverlay: Identifiable, Equatable {
    enum Kind: Equatable { case text, emoji, image, shape, post }
    let id = UUID()
    var kind: Kind
    var center = CGPoint(x: 0.5, y: 0.45)     // доли холста
    var scale: CGFloat = 1
    var angle: Double = 0                     // градусы
    var text = ""
    var color: Color = .white
    var style: StoryTextStyle = .plain
    var align: TextAlignment = .center
    var font: StoryFont = .system
    var emoji = ""
    var image: UIImage?
    var shape: StoryShapeKind = .rect
    var post: StoryPostCardData?

    static func == (a: StoryOverlay, b: StoryOverlay) -> Bool {
        a.id == b.id && a.center == b.center && a.scale == b.scale && a.angle == b.angle && a.text == b.text
            && a.color == b.color && a.style == b.style && a.font == b.font && a.emoji == b.emoji && a.shape == b.shape
    }
}

struct StoryAdjust: Equatable {
    var enhance: Double = 0
    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var isIdentity: Bool { self == StoryAdjust() }

    private static let ctx = CIContext()

    func apply(_ input: CIImage) -> CIImage {
        guard !isIdentity else { return input }
        var o = input
        if enhance > 0 {
            let v = CIFilter.vibrance(); v.inputImage = o; v.amount = Float(enhance * 0.9)
            o = v.outputImage ?? o
        }
        let cc = CIFilter.colorControls()
        cc.inputImage = o
        cc.brightness = Float(brightness * 0.22)
        cc.contrast = Float(1 + contrast * 0.35 + enhance * 0.1)
        cc.saturation = Float(1 + saturation * 0.8 + enhance * 0.12)
        o = cc.outputImage ?? o
        if warmth != 0 {
            let t = CIFilter.temperatureAndTint()
            t.inputImage = o
            t.neutral = CIVector(x: 6500, y: 0)
            t.targetNeutral = CIVector(x: 6500 + warmth * 1800, y: 0)
            o = t.outputImage ?? o
        }
        return o.cropped(to: input.extent)
    }

    func apply(_ img: UIImage) -> UIImage {
        guard !isIdentity, let ci = CIImage(image: img) else { return img }
        let out = apply(ci)
        guard let cg = Self.ctx.createCGImage(out, from: out.extent) else { return img }
        return UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
    }
}

enum StoryTool: String, CaseIterable, Identifiable {
    case pen, arrow, marker, liner, pencil, crayon, eraser
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pen: "Ручка"
        case .arrow: "Стрелка"
        case .marker: "Маркер"
        case .liner: "Линер"
        case .pencil: "Карандаш"
        case .crayon: "Мелок"
        case .eraser: "Ластик"
        }
    }
    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .arrow: "arrow.up.right"
        case .marker: "highlighter"
        case .liner: "pencil.line"
        case .pencil: "pencil"
        case .crayon: "paintbrush.pointed.fill"
        case .eraser: "eraser.fill"
        }
    }
    var ink: PKInk.InkType {
        switch self {
        case .pen, .arrow: .pen
        case .marker: .marker
        case .liner: .monoline
        case .pencil: .pencil
        case .crayon: .crayon
        case .eraser: .pen
        }
    }
}

@MainActor @Observable
final class StoryEditState {
    enum Mode { case none, draw, text, adjust }
    var mode: Mode = .none
    var overlays: [StoryOverlay] = []
    var drawing = PKDrawing()
    var adjust = StoryAdjust()
    var tool: StoryTool = .pen
    var color: Color = Color(hex: 0xFF453A)
    var width: CGFloat = 8
    var editing: UUID?
    var dragging: UUID?
    var overTrash = false
    var canvas: CGSize = .zero
    var undo: [PKDrawing] = []

    func add(_ o: StoryOverlay) {
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { overlays.append(o) }
        Haptic.tap(.soft)
    }
    func remove(_ id: UUID) {
        withAnimation(.smooth(duration: 0.2)) { overlays.removeAll { $0.id == id } }
    }
    func bringToFront(_ id: UUID) {
        guard let i = overlays.firstIndex(where: { $0.id == id }), i != overlays.count - 1 else { return }
        let o = overlays.remove(at: i)
        overlays.append(o)
    }
    var hasEdits: Bool { !overlays.isEmpty || !drawing.strokes.isEmpty || !adjust.isIdentity }
}

/// Что дальше уходит в публикацию
struct StoryExport {
    let media: StoryMedia
    let linkPost: Int?
    let linkRect: CGRect?        // доли холста
}

// MARK: - Экран редактора

struct StoryEditorView: View {
    let media: StoryMedia
    let player: AVPlayer?
    @Binding var caption: String
    var initialOverlays: [StoryOverlay] = []
    var onBack: () -> Void
    var onNext: (StoryExport) -> Void

    @State private var st = StoryEditState()
    @State private var preview: UIImage?
    @State private var stickers = false
    @State private var exporting = false
    @State private var drawBackup: PKDrawing?
    @State private var adjustBackup: StoryAdjust?

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { g in
                let size = fit(g.size)
                ZStack {
                    canvas(size)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if st.mode == .draw { drawChrome(size) }
                    if st.mode == .adjust { adjustPanel.frame(maxHeight: .infinity, alignment: .bottom) }
                }
                .frame(width: g.size.width, height: g.size.height)
                .onAppear { st.canvas = size }
                .onChange(of: g.size) { st.canvas = fit(g.size) }
            }
            bottomBar
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .overlay { if st.editing != nil { textEditor } }
        .overlay { if exporting { ZStack { Color.black.opacity(0.5); ProgressView("Готовим историю…").tint(.white).foregroundStyle(.white) }.ignoresSafeArea() } }
        .sheet(isPresented: $stickers) {
            StoryStickerSheet { o in st.add(o) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: st.adjust) { await refreshPreview() }
        .onAppear {
            if st.overlays.isEmpty && !initialOverlays.isEmpty { st.overlays = initialOverlays }
        }
        .preferredColorScheme(.dark)
    }

    private func fit(_ s: CGSize) -> CGSize {
        let w = min(s.width, s.height * 9 / 16)
        return CGSize(width: max(1, w), height: max(1, w * 16 / 9))
    }

    // MARK: холст
    @ViewBuilder private func canvas(_ size: CGSize) -> some View {
        ZStack {
            base(size)
            StoryCanvasView(state: st)
                .allowsHitTesting(st.mode == .draw)
            ForEach($st.overlays) { $o in
                StoryOverlayItem(o: $o, state: st, size: size)
                    .allowsHitTesting(st.mode == .none)
            }
            if st.dragging != nil {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(st.overTrash ? Color.red : Color.black.opacity(0.45), in: Circle())
                    .scaleEffect(st.overTrash ? 1.2 : 1)
                    .animation(.spring(duration: 0.25), value: st.overTrash)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
            if st.mode == .none {
                // подпись внизу холста
                TextField("Добавить подпись…", text: $caption, axis: .vertical)
                    .lineLimit(1...3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(st.dragging == nil ? 1 : 0)
            }
        }
    }

    @ViewBuilder private func base(_ size: CGSize) -> some View {
        switch media {
        case .photo(let i):
            Image(uiImage: preview ?? i).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
        case .video:
            if let player {
                StoryVideoLayer(player: player)
                    .brightness(st.adjust.brightness * 0.22)
                    .contrast(1 + st.adjust.contrast * 0.35 + st.adjust.enhance * 0.1)
                    .saturation(1 + st.adjust.saturation * 0.8 + st.adjust.enhance * 0.3)
            } else { Color.black }
        }
    }

    private func refreshPreview() async {
        guard case .photo(let i) = media else { return }
        if st.adjust.isIdentity { preview = nil; return }
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        let small = i.oxResized(maxSide: 1200)
        let a = st.adjust
        let out = await Task.detached(priority: .userInitiated) { a.apply(small) }.value
        if !Task.isCancelled { preview = out }
    }

    // MARK: нижняя панель
    @ViewBuilder private var bottomBar: some View {
        switch st.mode {
        case .none:
            HStack(spacing: 12) {
                circleButton("chevron.left") { onBack() }
                HStack(spacing: 4) {
                    toolButton("pencil.tip.crop.circle", "Рисунок") { startDraw() }
                    toolButton("textformat", "Текст") { addText() }
                    toolButton("face.smiling", "Стикеры") { stickers = true }
                    toolButton("slider.horizontal.3", "Настройки") { adjustBackup = st.adjust; withAnimation(.smooth) { st.mode = .adjust } }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                Button { Task { await finish() } } label: {
                    HStack(spacing: 4) {
                        Text("ДАЛЕЕ").font(.subheadline.weight(.heavy))
                        Image(systemName: "chevron.right").font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(Color.onLime)
                    .padding(.horizontal, 18).frame(height: 48)
                    .background(Color.lime, in: Capsule())
                }
                .disabled(exporting)
            }
        case .draw:
            HStack(spacing: 12) {
                circleButton("xmark") {
                    if let b = drawBackup { st.drawing = b }
                    withAnimation(.smooth) { st.mode = .none }
                }
                HStack(spacing: 2) {
                    segment("Рисунок", on: true) {}
                    segment("Стикеры", on: false) { withAnimation(.smooth) { st.mode = .none }; stickers = true }
                    segment("Текст", on: false) { withAnimation(.smooth) { st.mode = .none }; addText() }
                }
                .padding(4)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                doneButton { withAnimation(.smooth) { st.mode = .none } }
            }
        case .adjust:
            HStack {
                circleButton("xmark") {
                    if let b = adjustBackup { st.adjust = b }
                    withAnimation(.smooth) { st.mode = .none }
                }
                Spacer()
                Button("Сбросить") { withAnimation { st.adjust = StoryAdjust() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                doneButton { withAnimation(.smooth) { st.mode = .none } }
            }
        case .text:
            EmptyView()
        }
    }

    private func toolButton(_ icon: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                .frame(width: 48, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func circleButton(_ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private func doneButton(_ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: "checkmark").font(.system(size: 19, weight: .bold)).foregroundStyle(Color.onLime)
                .frame(width: 48, height: 48)
                .background(Color.lime, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func segment(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 38)
                .background(on ? Color.white.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: рисование
    private func startDraw() {
        drawBackup = st.drawing
        st.undo = []
        withAnimation(.smooth) { st.mode = .draw }
    }

    @ViewBuilder private func drawChrome(_ size: CGSize) -> some View {
        ZStack {
            // сверху: отменить / очистить
            HStack {
                Button {
                    if let last = st.undo.popLast() { st.drawing = last; Haptic.tap(.soft) }
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(st.undo.isEmpty)
                .opacity(st.undo.isEmpty ? 0.45 : 1)
                Spacer()
                Button {
                    guard !st.drawing.strokes.isEmpty else { return }
                    st.undo.append(st.drawing)
                    st.drawing = PKDrawing()
                    Haptic.tap(.rigid)
                } label: {
                    Text("Очистить всё").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxHeight: .infinity, alignment: .top)

            // слева: толщина
            StoryWidthSlider(value: $st.width, color: st.color)
                .frame(width: 34, height: min(260, size.height * 0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

            // снизу: инструменты и цвета
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 14) {
                    ColorPicker("", selection: $st.color, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                    ForEach(StoryTool.allCases) { t in
                        Button {
                            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { st.tool = t }
                            Haptic.tap(.soft)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(t == .eraser ? Color.white : st.color)
                                    .frame(width: 34, height: 36)
                                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(t.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            }
                            .offset(y: st.tool == t ? -10 : 0)
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
                        ForEach(StoryShapeKind.allCases) { s in
                            Button { addShape(s) } label: { Label(s.title, systemImage: s.icon) }
                        }
                    } label: {
                        Image(systemName: "plus").font(.headline).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(.white.opacity(0.2), in: Circle())
                    }
                }
                HStack(spacing: 0) {
                    ForEach([0xFF453A, 0xFF9F0A, 0xFFD60A, 0xB2EE37, 0x30D158, 0x64D2FF, 0x0A84FF, 0xBF5AF2, 0xFFFFFF, 0x000000], id: \.self) { c in
                        let col = Color(hex: UInt32(c))
                        Button {
                            st.color = col
                            if st.tool == .eraser { st.tool = .pen }
                            Haptic.tap(.soft)
                        } label: {
                            Circle().fill(col)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white, lineWidth: st.color == col ? 3 : 1).padding(-3))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: size.width, height: size.height)
    }

    private func addShape(_ s: StoryShapeKind) {
        var o = StoryOverlay(kind: .shape)
        o.shape = s
        o.color = st.color
        st.add(o)
        withAnimation(.smooth) { st.mode = .none }
    }

    // MARK: текст
    private func addText() {
        var o = StoryOverlay(kind: .text)
        o.color = .white
        o.style = .filled
        st.overlays.append(o)
        st.editing = o.id
    }

    private var textEditor: some View {
        StoryTextEditor(state: st)
    }

    // MARK: настройки
    private var adjustPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            adjRow("Улучшение", $st.adjust.enhance, 0...1)
            adjRow("Яркость", $st.adjust.brightness, -1...1)
            adjRow("Контраст", $st.adjust.contrast, -1...1)
            adjRow("Насыщенность", $st.adjust.saturation, -1...1)
            adjRow("Тепло", $st.adjust.warmth, -1...1)
        }
        .padding(18)
        .background(Color(white: 0.1).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func adjRow(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(v.wrappedValue == 0 ? .white.opacity(0.6) : .white)
                Spacer()
                if v.wrappedValue != 0 {
                    Text(String(format: "%+.2f", v.wrappedValue)).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Color.lime)
                }
            }
            Slider(value: v, in: r).tint(Color.lime)
        }
    }

    // MARK: готово → экспорт
    private func finish() async {
        st.editing = nil
        let size = st.canvas
        guard size.width > 1 else { return }
        // ссылка на ветку: берём карточку, место — в долях холста
        var linkPost: Int?
        var linkRect: CGRect?
        if let card = st.overlays.last(where: { $0.kind == .post }), let p = card.post {
            linkPost = p.postId
            let w = StoryPostCard.width * card.scale / size.width
            let h = StoryPostCard.estimatedHeight(p) * card.scale / size.height
            linkRect = CGRect(x: card.center.x - w / 2, y: card.center.y - h / 2, width: w, height: h)
        }
        guard st.hasEdits else {
            onNext(StoryExport(media: media, linkPost: linkPost, linkRect: linkRect))
            return
        }
        exporting = true
        defer { exporting = false }
        switch media {
        case .photo(let img):
            let base = st.adjust.apply(img.oxResized(maxSide: 2200))
            let r = ImageRenderer(content: StoryRenderLayer(state: st, base: base, size: size))
            r.scale = 1080 / size.width
            r.isOpaque = true
            if let out = r.uiImage {
                onNext(StoryExport(media: .photo(out), linkPost: linkPost, linkRect: linkRect))
            } else {
                OxAlert.error("Не удалось подготовить историю")
            }
        case .video(let url):
            var overlay: UIImage?
            if !st.overlays.isEmpty || !st.drawing.strokes.isEmpty {
                let r = ImageRenderer(content: StoryRenderLayer(state: st, base: nil, size: size))
                r.scale = 1080 / size.width
                r.isOpaque = false
                overlay = r.uiImage
            }
            if let out = await StoryVideoBurn.export(url: url, overlay: overlay, adjust: st.adjust, canvas: size) {
                onNext(StoryExport(media: .video(out), linkPost: linkPost, linkRect: linkRect))
            } else {
                OxAlert.error("Не удалось обработать видео")
            }
        }
    }
}

// MARK: - Слой для рендера (без интерактива)

struct StoryRenderLayer: View {
    let state: StoryEditState
    let base: UIImage?
    let size: CGSize

    var body: some View {
        ZStack {
            if let base {
                Image(uiImage: base).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            }
            if !state.drawing.strokes.isEmpty {
                Image(uiImage: state.drawing.image(from: CGRect(origin: .zero, size: size), scale: 3))
                    .resizable()
                    .frame(width: size.width, height: size.height)
            }
            ForEach(state.overlays) { o in
                StoryOverlayContent(o: o)
                    .scaleEffect(o.scale)
                    .rotationEffect(.degrees(o.angle))
                    .position(x: o.center.x * size.width, y: o.center.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Наложение: содержимое

struct StoryOverlayContent: View {
    let o: StoryOverlay

    var body: some View {
        switch o.kind {
        case .text: textView
        case .emoji: Text(o.emoji).font(.system(size: 96))
        case .image:
            if let i = o.image {
                Image(uiImage: i).resizable().scaledToFit()
                    .frame(width: 190, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
        case .shape: StoryShapeView(kind: o.shape, color: o.color)
        case .post: if let p = o.post { StoryPostCard(data: p) }
        }
    }

    @ViewBuilder private var textView: some View {
        let t = o.text.isEmpty ? " " : o.text
        let base = Text(t).font(o.font.font(34)).multilineTextAlignment(o.align)
        switch o.style {
        case .plain:
            base.foregroundStyle(o.color).shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        case .filled:
            base.foregroundStyle(o.color.isLight ? Color.black : Color.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(o.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .soft:
            base.foregroundStyle(o.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .outline:
            let edge = o.color.isLight ? Color.black : Color.white
            base.foregroundStyle(o.color)
                .shadow(color: edge, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: edge, radius: 0, x: -1.5, y: -1.5)
                .shadow(color: edge, radius: 0, x: 1.5, y: -1.5)
                .shadow(color: edge, radius: 0, x: -1.5, y: 1.5)
        }
    }
}

extension Color {
    /// светлый цвет — на нём нужен тёмный текст
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.62
    }
}

extension UIImage {
    func oxResized(maxSide: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > maxSide else { return self }
        let k = maxSide / m
        let s = CGSize(width: size.width * k, height: size.height * k)
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return UIGraphicsImageRenderer(size: s, format: f).image { _ in draw(in: CGRect(origin: .zero, size: s)) }
    }
}

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let R = min(r.width, r.height) / 2, rr = R * 0.45
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rad = i.isMultiple(of: 2) ? R : rr
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct StoryArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.move(to: CGPoint(x: r.maxX - r.height * 0.6, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - r.height * 0.6, y: r.maxY))
        return p
    }
}

struct StoryShapeView: View {
    let kind: StoryShapeKind
    let color: Color
    var body: some View {
        let st = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        switch kind {
        case .rect: RoundedRectangle(cornerRadius: 10).stroke(color, style: st).frame(width: 170, height: 120)
        case .ellipse: Ellipse().stroke(color, style: st).frame(width: 170, height: 120)
        case .bubble:
            Image(systemName: "bubble.left").font(.system(size: 130, weight: .regular)).foregroundStyle(color)
        case .star: StarShape().stroke(color, style: st).frame(width: 140, height: 140)
        case .arrow: StoryArrowShape().stroke(color, style: st).frame(width: 170, height: 50)
        }
    }
}

// MARK: - Карточка ветки в истории (как в Threads)

struct StoryPostCard: View {
    let data: StoryPostCardData
    static let width: CGFloat = 290

    static func estimatedHeight(_ d: StoryPostCardData) -> CGFloat {
        var h: CGFloat = 16 + 40 + 10      // отступ + шапка
        if !d.text.isEmpty { h += min(5, CGFloat(d.text.count / 34 + 1)) * 21 + 8 }
        if d.photo != nil { h += 260 + 8 }
        h += 30 + 16                        // кнопки + отступ
        return h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let a = data.avatar { Image(uiImage: a).resizable().scaledToFill() }
                    else { Circle().fill(Color.lime).overlay(Text(String(data.author.prefix(1))).font(.headline).foregroundStyle(Color.onLime)) }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                Text(data.author).font(.system(size: 15, weight: .semibold)).foregroundStyle(.black).lineLimit(1)
                if data.seal { OxionSeal(size: 15) }
                Spacer(minLength: 0)
                FlameMark(size: 22)
            }
            if !data.text.isEmpty {
                Text(data.text).font(.system(size: 15)).foregroundStyle(.black.opacity(0.85)).lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ph = data.photo {
                Image(uiImage: ph).resizable().scaledToFill()
                    .frame(width: Self.width - 32, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 22) {
                Image(systemName: "heart"); Image(systemName: "bubble.right"); Image(systemName: "arrow.2.squarepath"); Image(systemName: "paperplane")
            }
            .font(.system(size: 16)).foregroundStyle(.black.opacity(0.6))
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    /// Готовим данные: аватар и первое фото загружаем заранее (рендер картинки не ждёт сеть)
    static func make(from p: Post) async -> StoryPostCardData {
        async let av = load(API.media(p.author.photo))
        async let ph = load(p.photos?.first.flatMap { API.media($0) })
        return StoryPostCardData(postId: p.id, author: p.author.name ?? "OXION", avatar: await av,
                                 text: RichText.plain(p.text ?? ""), photo: await ph, seal: p.author.official != nil)
    }

    private static func load(_ u: URL?) async -> UIImage? {
        guard let u, let (d, _) = try? await URLSession.shared.data(from: u) else { return nil }
        return UIImage(data: d)
    }

    /// Фон истории для ветки
    static func background() -> UIImage {
        let s = CGSize(width: 1080, height: 1920)
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: s, format: f).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(red: 0.07, green: 0.08, blue: 0.08, alpha: 1).cgColor,
                          UIColor(red: 0.16, green: 0.24, blue: 0.05, alpha: 1).cgColor,
                          UIColor(red: 0.70, green: 0.93, blue: 0.22, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.6, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: s.width, y: s.height), options: [])
            }
        }
    }
}

// MARK: - Наложение: перетаскивание, масштаб, поворот, удаление в корзину

struct StoryOverlayItem: View {
    @Binding var o: StoryOverlay
    let state: StoryEditState
    let size: CGSize

    @GestureState private var drag: CGSize = .zero
    @GestureState private var mag: CGFloat = 1
    @GestureState private var rot: Angle = .zero

    var body: some View {
        StoryOverlayContent(o: o)
            .scaleEffect(o.scale * mag)
            .rotationEffect(.degrees(o.angle) + rot)
            .position(x: o.center.x * size.width + drag.width, y: o.center.y * size.height + drag.height)
            .opacity(state.dragging == o.id && state.overTrash ? 0.4 : 1)
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .updating($drag) { v, s, _ in s = v.translation }
                        .onChanged { v in
                            if state.dragging != o.id { state.dragging = o.id; state.bringToFront(o.id) }
                            let y = o.center.y * size.height + v.translation.height
                            let over = y > size.height - 90 && abs(o.center.x * size.width + v.translation.width - size.width / 2) < 90
                            if over != state.overTrash { state.overTrash = over; if over { Haptic.tap(.medium) } }
                        }
                        .onEnded { v in
                            if state.overTrash {
                                state.remove(o.id)
                            } else {
                                o.center.x = min(1.1, max(-0.1, o.center.x + v.translation.width / size.width))
                                o.center.y = min(1.1, max(-0.1, o.center.y + v.translation.height / size.height))
                            }
                            state.dragging = nil
                            state.overTrash = false
                        },
                    SimultaneousGesture(
                        MagnifyGesture()
                            .updating($mag) { v, s, _ in s = v.magnification }
                            .onEnded { v in o.scale = min(6, max(0.25, o.scale * v.magnification)) },
                        RotateGesture()
                            .updating($rot) { v, s, _ in s = v.rotation }
                            .onEnded { v in o.angle += v.rotation.degrees }
                    )
                )
            )
            .onTapGesture {
                if o.kind == .text { state.editing = o.id }
            }
    }
}

// MARK: - Редактирование текста

struct StoryTextEditor: View {
    let state: StoryEditState
    @FocusState private var focus: Bool

    private var index: Int? { state.overlays.firstIndex { $0.id == state.editing } }

    var body: some View {
        if let i = index {
            let o = state.overlays[i]
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { close() }
                VStack {
                    HStack {
                        Button { cancel() } label: {
                            Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        Spacer()
                        Button { close() } label: {
                            Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(Color.onLime)
                                .frame(width: 44, height: 44).background(Color.lime, in: Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    Spacer()
                    TextField("", text: Binding(get: { state.overlays[safe: i]?.text ?? "" },
                                                set: { v in if state.overlays.indices.contains(i) { state.overlays[i].text = v } }),
                              axis: .vertical)
                        .focused($focus)
                        .font(o.font.font(34))
                        .multilineTextAlignment(o.align)
                        .foregroundStyle(o.style == .filled ? (o.color.isLight ? Color.black : Color.white) : o.color)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(bg(o), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    Spacer()
                    // панель над клавиатурой: цвет, стиль, выравнивание, шрифт
                    HStack(spacing: 16) {
                        ColorPicker("", selection: Binding(get: { o.color }, set: { c in mutate { $0.color = c } }), supportsOpacity: false)
                            .labelsHidden()
                        Button { mutate { $0.style = StoryTextStyle(rawValue: ($0.style.rawValue + 1) % 4) ?? .plain } } label: {
                            Text("A").font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(o.style == .filled ? Color.black : .white)
                                .frame(width: 38, height: 38)
                                .background(o.style == .filled ? Color.white : (o.style == .soft ? Color.white.opacity(0.25) : .clear),
                                            in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white, lineWidth: o.style == .outline ? 2 : 0))
                        }
                        Button {
                            mutate { $0.align = $0.align == .center ? .leading : ($0.align == .leading ? .trailing : .center) }
                        } label: {
                            Image(systemName: o.align == .center ? "text.aligncenter" : (o.align == .leading ? "text.alignleft" : "text.alignright"))
                                .font(.title3).foregroundStyle(.white).frame(width: 38, height: 38)
                        }
                        Spacer()
                        Menu {
                            ForEach(StoryFont.allCases) { f in
                                Button { mutate { $0.font = f } } label: { Text(f.title).font(f.font(17)) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(o.font.title).font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 38)
                            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .onAppear { focus = true }
        }
    }

    private func bg(_ o: StoryOverlay) -> Color {
        switch o.style {
        case .filled: o.color
        case .soft: Color.black.opacity(0.45)
        default: .clear
        }
    }

    private func mutate(_ f: (inout StoryOverlay) -> Void) {
        guard let i = index else { return }
        f(&state.overlays[i])
        Haptic.tap(.soft)
    }

    private func close() {
        if let i = index, state.overlays[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.overlays.remove(at: i)
        }
        state.editing = nil
    }

    private func cancel() { close() }
}


// MARK: - Толщина кисти (вертикальный ползунок слева)

struct StoryWidthSlider: View {
    @Binding var value: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let t = (value - 2) / 38            // 2…40 pt
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: g.size.width / 2 - 2, y: h))
                    p.addLine(to: CGPoint(x: g.size.width / 2 + 2, y: h))
                    p.addLine(to: CGPoint(x: g.size.width / 2 + 9, y: 0))
                    p.addLine(to: CGPoint(x: g.size.width / 2 - 9, y: 0))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.35))
                Circle().fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(radius: 3)
                    .position(x: g.size.width / 2, y: h * (1 - t))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let k = 1 - min(1, max(0, v.location.y / h))
                value = 2 + k * 38
            })
        }
    }
}

// MARK: - Холст PencilKit

struct StoryCanvasView: UIViewRepresentable {
    let state: StoryEditState

    func makeCoordinator() -> Coordinator { Coordinator(state) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.drawingPolicy = .anyInput
        v.overrideUserInterfaceStyle = .light      // цвета чернил без инверсии
        v.delegate = context.coordinator
        v.drawing = state.drawing
        v.tool = context.coordinator.tool()
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        let c = context.coordinator
        c.state = state
        if v.drawing != state.drawing {
            c.syncing = true
            v.drawing = state.drawing
            c.syncing = false
        }
        v.tool = c.tool()
    }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var state: StoryEditState
        var syncing = false
        init(_ s: StoryEditState) { state = s }

        func tool() -> PKTool {
            if state.tool == .eraser { return PKEraserTool(.bitmap, width: state.width * 2) }
            let w = state.tool == .marker ? state.width * 2.2 : state.width
            return PKInkingTool(state.tool.ink, color: UIColor(state.color), width: w)
        }

        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            guard !syncing else { return }
            var d = v.drawing
            // «Стрелка»: к новой линии дорисовываем наконечник
            if state.tool == .arrow, d.strokes.count > state.drawing.strokes.count, let last = d.strokes.last {
                let pts = last.path.map { $0.location.applying(last.transform) }
                if let end = pts.last, pts.count > 2 {
                    var j = pts.count - 1
                    while j > 0 && hypot(pts[j].x - end.x, pts[j].y - end.y) < 18 { j -= 1 }
                    let dx = end.x - pts[j].x, dy = end.y - pts[j].y
                    let len = max(0.001, hypot(dx, dy))
                    let ux = dx / len, uy = dy / len
                    let L = max(18, state.width * 3)
                    let sz = last.path.last?.size ?? CGSize(width: state.width, height: state.width)
                    for sgn in [1.0, -1.0] {
                        let a = 0.5 * sgn
                        let rx = ux * cos(a) - uy * sin(a), ry = ux * sin(a) + uy * cos(a)
                        let tip = CGPoint(x: end.x - rx * L, y: end.y - ry * L)
                        let path = PKStrokePath(controlPoints: [
                            PKStrokePoint(location: end, timeOffset: 0, size: sz, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                            PKStrokePoint(location: CGPoint(x: (end.x + tip.x) / 2, y: (end.y + tip.y) / 2), timeOffset: 0.01, size: sz, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                            PKStrokePoint(location: tip, timeOffset: 0.02, size: sz, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                        ], creationDate: Date())
                        d.strokes.append(PKStroke(ink: last.ink, path: path))
                    }
                    syncing = true
                    v.drawing = d
                    syncing = false
                }
            }
            if d != state.drawing {
                state.undo.append(state.drawing)
                if state.undo.count > 40 { state.undo.removeFirst() }
                state.drawing = d
            }
        }
    }
}

// MARK: - Стикеры: эмодзи, фото, фигуры

struct StoryStickerSheet: View {
    var onPick: (StoryOverlay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var photo: PhotosPickerItem?

    private let emojis = ["🔥", "💪", "🏋️", "🏃", "🥇", "🏆", "⚡️", "✅", "❤️", "😍", "😂", "😎", "🤯", "🥵", "🙌", "👏",
                          "💯", "🎯", "🚀", "⭐️", "✨", "🌟", "🍏", "🥑", "🥗", "🍗", "🥤", "💧", "😴", "🧘", "🚴", "🏊",
                          "⛹️", "🤸", "🥊", "🏆", "📈", "📉", "⏱️", "🗓️", "🎉", "🥳", "😤", "🤝", "👊", "🫶", "👀", "🙏",
                          "😅", "😭", "🤩", "😇", "🤔", "😏", "🫡", "💥", "🌈", "☀️", "🌙", "❄️", "🍕", "🍔", "🍫", "☕️"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text("Эмодзи").tag(0)
                    Text("Фото").tag(1)
                    Text("Фигуры").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                ScrollView {
                    switch tab {
                    case 0:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                            ForEach(Array(emojis.enumerated()), id: \.offset) { _, e in
                                Button {
                                    var o = StoryOverlay(kind: .emoji); o.emoji = e
                                    onPick(o); dismiss()
                                } label: { Text(e).font(.system(size: 40)) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    case 1:
                        PhotosPicker(selection: $photo, matching: .images) {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 40)).foregroundStyle(Color.lime)
                                Text("Выбрать фото из галереи").font(.headline)
                                Text("Фото ляжет поверх истории — его можно двигать, увеличивать и поворачивать")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(28)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding(16)
                        }
                    default:
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                            ForEach(StoryShapeKind.allCases) { s in
                                ForEach([Color.white, Color.lime, Color(hex: 0xFF453A)], id: \.self) { c in
                                    Button {
                                        var o = StoryOverlay(kind: .shape); o.shape = s; o.color = c
                                        onPick(o); dismiss()
                                    } label: {
                                        StoryShapeView(kind: s, color: c).scaleEffect(0.42).frame(height: 70)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Стикеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onChange(of: photo) { _, it in
                guard let it else { return }
                Task {
                    if let d = try? await it.loadTransferable(type: Data.self), let i = UIImage(data: d) {
                        var o = StoryOverlay(kind: .image); o.image = i.oxResized(maxSide: 900)
                        onPick(o); dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Видео: настройки + рисунок/наклейки «впекаются» в кадр

enum StoryVideoBurn {
    static func export(url: URL, overlay: UIImage?, adjust: StoryAdjust, canvas: CGSize) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let nat = try? await track.load(.naturalSize),
              let tr = try? await track.load(.preferredTransform) else { return nil }
        let vs = nat.applying(tr)
        let vw = abs(vs.width), vh = abs(vs.height)
        guard vw > 0, vh > 0 else { return nil }
        // холст показывает видео «заполнением»: s — точек холста на пиксель видео
        let s = max(canvas.width / vw, canvas.height / vh)
        let ox = (canvas.width - vw * s) / 2, oy = (canvas.height - vh * s) / 2
        var ov: CIImage?
        if let overlay, let ci = CIImage(image: overlay) {
            let r = overlay.scale
            let t = CGAffineTransform(scaleX: 1 / (r * s), y: 1 / (r * s))
                .concatenating(CGAffineTransform(translationX: -ox / s, y: -oy / s))
            ov = ci.transformed(by: t)
        }
        let a = adjust
        let overlayImage = ov
        guard let comp = try? await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: { req in
            let src = req.sourceImage
            var img = a.apply(src.clampedToExtent()).cropped(to: src.extent)
            if let o = overlayImage { img = o.composited(over: img).cropped(to: src.extent) }
            req.finish(with: img, context: nil)
        }) else { return nil }
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        ex.videoComposition = comp
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("story-edit-\(UUID().uuidString).mp4")
        do {
            try await ex.export(to: out, as: .mp4)
            return out
        } catch {
            return nil
        }
    }
}
