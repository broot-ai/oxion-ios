import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import CoreMotion

// MARK: - Матрица QR-кода (модули), чтобы рисовать его скруглённым

struct QRMatrix {
    let size: Int
    let bits: [Bool]

    func dark(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < size && y < size && bits[y * size + x]
    }

    init?(_ text: String) {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "H"          // запас 30% — в центр можно поставить логотип
        guard let out = f.outputImage,
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // убираем белую рамку вокруг кода
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w where px[y * w + x] < 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX else { return nil }
        let n = maxX - minX + 1
        var b = [Bool](repeating: false, count: n * n)
        for y in 0..<n { for x in 0..<n { b[y * n + x] = px[(minY + y) * w + (minX + x)] < 128 } }
        size = n
        bits = b
    }
}

/// QR со скруглёнными модулями, круглыми «глазками» и логотипом в центре
struct RoundQR: View {
    let text: String
    var color: Color

    var body: some View {
        let m = QRMatrix(text)
        Canvas { ctx, sz in
            guard let m else { return }
            let n = m.size
            let c = min(sz.width, sz.height) / CGFloat(n)
            let hole = Int((Double(n) * 0.26).rounded())               // место под логотип
            let h0 = (n - hole) / 2, h1 = h0 + hole
            func inFinder(_ x: Int, _ y: Int) -> Bool {
                (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7)
            }
            var path = Path()
            for y in 0..<n {
                for x in 0..<n where m.dark(x, y) && !inFinder(x, y) {
                    if x >= h0 && x < h1 && y >= h0 && y < h1 { continue }
                    let l = m.dark(x - 1, y), r = m.dark(x + 1, y), t = m.dark(x, y - 1), b = m.dark(x, y + 1)
                    let rad = c * 0.5
                    let shape = UnevenRoundedRectangle(
                        topLeadingRadius: (l || t) ? 0 : rad,
                        bottomLeadingRadius: (l || b) ? 0 : rad,
                        bottomTrailingRadius: (r || b) ? 0 : rad,
                        topTrailingRadius: (r || t) ? 0 : rad,
                        style: .continuous)
                    path.addPath(shape.path(in: CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: c + 0.4, height: c + 0.4)))
                }
            }
            ctx.fill(path, with: .color(color))
            // три «глазка»
            for (fx, fy) in [(0, 0), (n - 7, 0), (0, n - 7)] {
                let o = CGRect(x: CGFloat(fx) * c, y: CGFloat(fy) * c, width: c * 7, height: c * 7)
                ctx.stroke(RoundedRectangle(cornerRadius: c * 2.4, style: .continuous).path(in: o.insetBy(dx: c / 2, dy: c / 2)),
                           with: .color(color), lineWidth: c)
                ctx.fill(RoundedRectangle(cornerRadius: c * 1.2, style: .continuous).path(in: o.insetBy(dx: c * 2, dy: c * 2)),
                         with: .color(color))
            }
            // логотип
            let lr = CGRect(x: CGFloat(h0) * c, y: CGFloat(h0) * c, width: CGFloat(hole) * c, height: CGFloat(hole) * c).insetBy(dx: c * 0.6, dy: c * 0.6)
            ctx.fill(Circle().path(in: lr), with: .color(color))
            if let logo = ctx.resolveSymbol(id: 1) {
                ctx.draw(logo, in: lr.insetBy(dx: lr.width * 0.24, dy: lr.width * 0.2))
            }
        } symbols: {
            Image("ox-logo").resizable().scaledToFit().colorMultiply(.white).brightness(1).tag(1)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Наклон телефона (акселерометр) для плавающих эмодзи

final class TiltMotion {
    static let shared = TiltMotion()
    private let mm = CMMotionManager()
    private var users = 0
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    func start() {
        users += 1
        guard users == 1, mm.isDeviceMotionAvailable else { return }
        mm.deviceMotionUpdateInterval = 1 / 60
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            // мягкий фильтр — без дрожания
            self.x += (g.x - self.x) * 0.08
            self.y += ((g.y + 0.6) - self.y) * 0.08
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { mm.stopDeviceMotionUpdates() }
    }
}

/// Фон из эмодзи: ряды разного размера, плывут вслед за наклоном телефона (большие — сильнее, как в Telegram)
struct EmojiPatternBackground: View {
    var emoji: String
    var animated = true
    @State private var appear = false

    private struct Dot { let p: CGPoint; let s: CGFloat; let phase: Double }

    private func dots(in size: CGSize) -> [Dot] {
        var r = SeededRandom(seed: 42)
        var out: [Dot] = []
        let step: CGFloat = 58
        var row = 0
        var y: CGFloat = -step
        while y < size.height + step {
            let shift = row.isMultiple(of: 2) ? 0 : step / 2
            var x: CGFloat = -step + shift
            while x < size.width + step {
                let big = r.next() < 0.45
                let s: CGFloat = big ? CGFloat(26 + r.next() * 12) : CGFloat(9 + r.next() * 8)
                out.append(Dot(p: CGPoint(x: x + CGFloat(r.next() * 14 - 7), y: y + CGFloat(r.next() * 14 - 7)), s: s, phase: r.next() * 6.28))
                x += step
            }
            y += step * 0.82
            row += 1
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let list = dots(in: geo.size)
            TimelineView(.animation(paused: !animated)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let tilt = TiltMotion.shared
                Canvas { ctx, _ in
                    guard let sym = ctx.resolveSymbol(id: 0) else { return }
                    for d in list {
                        let depth = d.s / 38                           // 0.25…1
                        let dx = tilt.x * 34 * depth + sin(t * 0.6 + d.phase) * 2.5
                        let dy = -tilt.y * 34 * depth + cos(t * 0.5 + d.phase) * 2.5
                        var c = ctx
                        c.opacity = 0.55 + depth * 0.45
                        let r = CGRect(x: d.p.x + dx - d.s / 2, y: d.p.y + dy - d.s / 2, width: d.s, height: d.s)
                        c.draw(sym, in: r)
                    }
                } symbols: {
                    Text(emoji).font(.system(size: 64)).tag(0)
                }
            }
            .scaleEffect(appear ? 1 : 1.15)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            if animated { TiltMotion.shared.start() }
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { appear = true }
        }
        .onDisappear { if animated { TiltMotion.shared.stop() } }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) % 1_000_000) / 1_000_000
    }
}

// MARK: - Темы визитки

struct QRTheme: Identifiable, Equatable {
    let id: Int
    let top: Color
    let bottom: Color
    let ink: Color

    static let all: [QRTheme] = {
        let hex: [(UInt32, UInt32, UInt32)] = [
            (0xB2EE37, 0x4E8A12, 0x3F6E0B), (0x58F670, 0x1F8A4C, 0x16703C), (0x5FD3B5, 0x2A8C77, 0x1F6E5E),
            (0x4CC3F0, 0x1D6FD8, 0x1A5FB8), (0x6E8BFF, 0x3949C8, 0x2F3BA8), (0x9B7BFF, 0x5B33C8, 0x4A28A8),
            (0xD37BFF, 0x8A2BC0, 0x7322A0), (0xFF7BC0, 0xC12E7E, 0xA2256A), (0xFF7B7B, 0xC23A3A, 0xA22E2E),
            (0xFFA25E, 0xD0601C, 0xB04F15), (0xFFD25E, 0xC89212, 0x8C6406), (0xC8B07A, 0x8A7240, 0x6E5A30),
            (0x8EC5A8, 0x3F7A5E, 0x30604A), (0x7FB0C8, 0x3A6E88, 0x2C586E), (0xA5A5B5, 0x55556A, 0x40404F),
            (0x3A3D44, 0x0F1012, 0x0F1012),
        ]
        return hex.enumerated().map { i, h in QRTheme(id: i, top: Color(hex: h.0), bottom: Color(hex: h.1), ink: Color(hex: h.2)) }
    }()
}

// MARK: - Экран визитки с QR (как в Telegram)

struct MyCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("oxion_qr_theme") private var themeId = 0
    @AppStorage("oxion_qr_emoji") private var emoji = "💪"
    @State private var tab = 0
    @State private var panel: Panel?
    @State private var cardIn = false
    @State private var toast: String?
    @State private var scanning = false
    @State private var openUser: Int?

    enum Panel { case colors, emoji }

    static let emojis = ["💪", "🔥", "🏋️", "⚡", "🏃", "🥇", "🏆", "❤️", "😎", "😄", "🤩", "🚀",
                         "⭐", "🎯", "🥊", "🧘", "🚴", "⚽", "🏀", "🍏", "🥑", "💧", "🌿", "🦾",
                         "👑", "💎", "🌈", "☀️", "🌙", "🍀", "🎉", "🫶"]

    private var theme: QRTheme { QRTheme.all.first { $0.id == themeId } ?? QRTheme.all[0] }
    private var isTrainer: Bool { model.me?.mode == "trainer" || model.me?.role == "trainer" }
    private var handle: String {
        let n = model.me?.displayName ?? "OXION"
        return n.uppercased()
    }

    private func link(_ param: String, start: Bool = false) -> String {
        let id = model.me?.id ?? 0
        if let b = model.meta?.botUsername, !b.isEmpty {
            return "https://t.me/\(b.replacingOccurrences(of: "@", with: ""))?\(start ? "start" : "startapp")=\(param)"
        }
        return AppSettings.serverURL.absoluteString + "/#" + (param.hasPrefix("t") ? "trainer/\(id)" : param.hasPrefix("coach") ? "coachjoin/\(id)" : "u/\(id)")
    }

    private var current: String {
        let id = model.me?.id ?? 0
        if tab == 1 { return link("coach\(id)", start: true) }
        return isTrainer ? link("t\(id)") : link("u\(id)")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.45), value: themeId)
                EmojiPatternBackground(emoji: emoji, animated: PowerSaver.allowsNow(.liveBackgrounds))
                    .id(emoji)
                    .ignoresSafeArea()
                    .transition(.opacity.combined(with: .scale(scale: 1.1)))

                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    card
                        .scaleEffect(cardIn ? 1 : 0.82)
                        .opacity(cardIn ? 1 : 0)
                        .rotation3DEffect(.degrees(cardIn ? 0 : 12), axis: (x: 1, y: 0, z: 0))
                    if isTrainer {
                        Picker("", selection: $tab.animation(.snappy)) {
                            Text("Визитка").tag(0)
                            Text("Пригласить клиента").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }
                    Text(tab == 1 ? "Клиент наведёт камеру — и сразу подключится к вам" : "Наведите камеру — откроется профиль в OXION")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glassEffect(.regular.tint(theme.ink.opacity(0.35)), in: .capsule)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .offset(y: panel == nil ? 0 : -150)
                .animation(.spring(duration: 0.5, bounce: 0.2), value: panel)

                VStack {
                    Spacer()
                    if let panel {
                        panelView(panel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        bottomBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.45, bounce: 0.18), value: panel)

                if let toast {
                    VStack {
                        Spacer()
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .glassEffect(.regular.tint(theme.ink.opacity(0.4)), in: .capsule)
                            .padding(.bottom, 90)
                    }
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сканировать QR-код") { scanning = true }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $openUser) { id in UserProfileView(userId: id) }
        }
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.35).delay(0.08)) { cardIn = true }
        }
        .fullScreenCover(isPresented: $scanning) {
            QRScanScreen { code in handleScan(code) }
        }
    }

    // MARK: карточка

    private var card: some View {
        VStack(spacing: 14) {
            RoundQR(text: current, color: theme.ink)
                .frame(width: 210, height: 210)
                .id(current)
                .transition(.blurReplace)
            Text("@" + handle)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.top, 26).padding(.bottom, 20).padding(.horizontal, 26)
        .background(.white, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        .animation(.easeInOut(duration: 0.45), value: themeId)
        .animation(.snappy, value: tab)
    }

    // MARK: нижняя панель

    private var bottomBar: some View {
        HStack {
            Menu {
                Button { UIPasteboard.general.string = current; flash("Ссылка скопирована") } label: {
                    Label("Копировать ссылку", systemImage: "link")
                }
                ShareLink(item: current) { Label("Поделиться…", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 48, height: 48)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()
            GlassEffectContainer {
                HStack(spacing: 0) {
                    barButton("paintpalette") { panel = .colors }
                    barButton("face.smiling") { panel = .emoji }
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            Spacer()

            Button { save() } label: {
                Image(systemName: "arrow.down.to.line").frame(width: 48, height: 48)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func barButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); action() } label: {
            Image(systemName: icon).frame(width: 54, height: 48)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func panelView(_ p: Panel) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(p == .colors ? "Цвет" : "Эмодзи").font(.headline)
                Spacer()
                Button { panel = nil } label: {
                    Text("Готово").font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 7)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            if p == .colors {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 12) {
                    ForEach(QRTheme.all) { t in
                        Button {
                            Haptic.tap()
                            themeId = t.id
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: [t.top, t.bottom], startPoint: .top, endPoint: .bottom))
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Circle().stroke(.white, lineWidth: themeId == t.id ? 2.5 : 0))
                                .scaleEffect(themeId == t.id ? 1.08 : 1)
                                .animation(.spring(duration: 0.3, bounce: 0.5), value: themeId)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                    ForEach(Self.emojis, id: \.self) { e in
                        Button {
                            Haptic.tap()
                            withAnimation(.easeInOut(duration: 0.4)) { emoji = e }
                        } label: {
                            Text(e).font(.system(size: 28))
                                .frame(width: 40, height: 40)
                                .background(emoji == e ? .white.opacity(0.22) : .clear, in: Circle())
                                .scaleEffect(emoji == e ? 1.12 : 1)
                                .animation(.spring(duration: 0.3, bounce: 0.5), value: emoji)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: действия

    private func flash(_ text: String) {
        Haptic.success()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    @MainActor
    private func save() {
        let poster = ZStack {
            LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom)
            EmojiPatternBackground(emoji: emoji, animated: false)
            card
        }
        .frame(width: 400, height: 720)
        .environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: poster)
        r.scale = 3
        guard let img = r.uiImage else { OxAlert.error("Не получилось сохранить картинку"); return }
        PhotoSaver.save(img) { ok in
            if ok { flash("Изображение сохранено в галерею") }
            else { PermPrompt.show(.photos, denied: true) }
        }
    }

    private func handleScan(_ code: String) {
        scanning = false
        switch QRLinks.parse(code) {
        case .trainer(let id):
            dismiss()
            model.handle(route: "trainer/\(id)")
        case .user(let id):
            openUser = id
        case .url(let u):
            openURL(u)
        case .text(let t):
            UIPasteboard.general.string = t
            OxAlert.show(icon: "qrcode", title: "Текст из QR скопирован", message: t)
        }
    }
}

/// Сохранение в «Фото» с ответом, получилось ли
final class PhotoSaver: NSObject {
    private var done: ((Bool) -> Void)?
    private static var current: PhotoSaver?

    static func save(_ img: UIImage, done: @escaping (Bool) -> Void) {
        let s = PhotoSaver()
        s.done = done
        current = s
        UIImageWriteToSavedPhotosAlbum(img, s, #selector(finished(_:error:context:)), nil)
    }

    @objc private func finished(_ image: UIImage, error: Error?, context: UnsafeRawPointer?) {
        let ok = error == nil
        let cb = done
        DispatchQueue.main.async { cb?(ok) }
        PhotoSaver.current = nil
    }
}

