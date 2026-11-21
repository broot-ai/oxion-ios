import SwiftUI
import UIKit

// Многоцветный «живой» градиент как в Telegram.
// Алгоритм перенесён из twallpaper (MIT, © 2022 Vitalij Ryndin): https://github.com/crashmax-dev/twallpaper
// Узоры — свои (значки SF Symbols), картинки узоров Telegram не используются.

@Observable
final class TWallpaperEngine {
    struct P { var x: Double; var y: Double }

    private static let curve: [Double] = [
        0, 0.25, 0.50, 0.75, 1, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 11, 12,
        13, 14, 15, 16, 17, 18, 18.3, 18.6, 18.9, 19.2, 19.5, 19.8, 20.1, 20.4, 20.7,
        21, 21.3, 21.6, 21.9, 22.2, 22.5, 22.8, 23.1, 23.4, 23.7, 24.0, 24.3, 24.6,
        24.9, 25.2, 25.5, 25.8, 26.1, 26.3, 26.4, 26.5, 26.6, 26.7, 26.8, 26.9, 27,
    ]
    private static let positions: [P] = [
        P(x: 0.8, y: 0.1), P(x: 0.6, y: 0.2), P(x: 0.35, y: 0.25), P(x: 0.25, y: 0.6),
        P(x: 0.2, y: 0.9), P(x: 0.4, y: 0.8), P(x: 0.65, y: 0.75), P(x: 0.75, y: 0.4),
    ]

    private let w = 50, h = 50
    private var phase = 0
    private var tail = 0
    var tails = 90
    private var rgb: [(Double, Double, Double)] = []
    /// кадры анимации «к следующей позиции» (как toNextPosition)
    private var transition: (from: [P], to: [P], frame: Int)?
    private(set) var image: CGImage?
    /// меняется, когда нужно перерисовать
    private(set) var version = 0

    var transitioning: Bool { transition != nil }

    init(colors: [Color]) { setColors(colors) }

    func setColors(_ colors: [Color]) {
        rgb = colors.prefix(4).map { c in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        if rgb.isEmpty { rgb = [(0, 0, 0)] }
        draw(current())
    }

    private func positions(_ shift: Int) -> [P] {
        var p = Self.positions
        for _ in 0..<(shift % p.count) { p.append(p.removeFirst()) }
        return stride(from: 0, to: p.count, by: 2).map { p[$0] }
    }

    private func current() -> [P] {
        let t = tail % tails
        let pos = positions(phase % Self.positions.count)
        guard t > 0 else { return pos }
        let next = positions((phase + 1) % Self.positions.count)
        return (0..<4).map { i in
            P(x: pos[i].x + (next[i].x - pos[i].x) / Double(tails) * Double(t),
              y: pos[i].y + (next[i].y - pos[i].y) / Double(tails) * Double(t))
        }
    }

    private func changeTail(_ d: Int) {
        tail += d
        while tail >= tails { tail -= tails; phase = (phase + 1) % Self.positions.count }
        while tail < 0 { tail += tails; phase = (phase - 1 + Self.positions.count) % Self.positions.count }
    }

    /// Один шаг непрерывной анимации
    func step() {
        if let t = transition {
            let k = Self.curve[t.frame] / 27
            let p = (0..<4).map { i in P(x: t.from[i].x + (t.to[i].x - t.from[i].x) * k, y: t.from[i].y + (t.to[i].y - t.from[i].y) * k) }
            draw(p)
            transition = t.frame + 1 < Self.curve.count ? (t.from, t.to, t.frame + 1) : nil
            return
        }
        changeTail(1)
        draw(current())
    }

    /// Плавный переход к следующей позиции (например, при отправке сообщения)
    func toNextPosition() {
        let from = transition.map { _ in current() } ?? positions(phase % Self.positions.count)
        tail = 0
        phase = (phase + 1) % Self.positions.count
        transition = (from, positions(phase), 0)
        version += 1
    }

    private func draw(_ pos: [P]) {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        var o = 0
        for y in 0..<h {
            let cy = Double(y) / Double(h) - 0.5
            for x in 0..<w {
                let cx = Double(x) / Double(w) - 0.5
                let cd = (cx * cx + cy * cy).squareRoot()
                let swirl = 0.35 * cd
                let th = swirl * swirl * 0.8 * 8
                let s = sin(th), c = cos(th)
                let pxX = max(0, min(1, 0.5 + cx * c - cy * s))
                let pxY = max(0, min(1, 0.5 + cx * s + cy * c))
                var sum = 0.0, r = 0.0, g = 0.0, b = 0.0
                for i in 0..<min(rgb.count, 4) {
                    let dx = pxX - pos[i].x, dy = pxY - pos[i].y
                    var d = max(0, 0.9 - (dx * dx + dy * dy).squareRoot())
                    d = d * d * d * d
                    sum += d
                    r += d * rgb[i].0; g += d * rgb[i].1; b += d * rgb[i].2
                }
                if sum <= 0 { sum = 1 }
                px[o] = UInt8(max(0, min(255, r / sum * 255)))
                px[o + 1] = UInt8(max(0, min(255, g / sum * 255)))
                px[o + 2] = UInt8(max(0, min(255, b / sum * 255)))
                o += 4
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        image = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        version += 1
    }
}

// MARK: - Пресеты и узоры

struct WallPreset: Identifiable, Equatable {
    let id: String
    let colors: [UInt32]
    var dark = false
    var swiftColors: [Color] { colors.map { Color(hex: $0) } }

    static let all: [WallPreset] = [
        .init(id: "oxion", colors: [0x1E3A0C, 0x4C7A14, 0x0D2414, 0x2E5B1F], dark: true),
        .init(id: "night", colors: [0x0B1640, 0x1F3A8A, 0x101028, 0x4B2A7A], dark: true),
        .init(id: "ember", colors: [0x3A0D0D, 0x8A2B12, 0x1A0A0A, 0x6B3A0A], dark: true),
        .init(id: "abyss", colors: [0x06272E, 0x0F5C5C, 0x041418, 0x1B3F6B], dark: true),
        .init(id: "classic", colors: [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884]),
        .init(id: "sunrise", colors: [0xFEC496, 0xDD6CB9, 0x962FBF, 0x4F5BD5]),
        .init(id: "mint", colors: [0x85D685, 0x67A3F2, 0x8FE1D6, 0xDCEB92]),
        .init(id: "peach", colors: [0xFFC3B2, 0xE2C0FF, 0xFFE7B2, 0xF8D9E0]),
        .init(id: "lime", colors: [0xD6FF5C, 0x6FCF3A, 0xF2FFB0, 0x9BE07A]),
        .init(id: "sky", colors: [0x9FD8FF, 0x5A8CFF, 0xCDEBFF, 0x8E7CFF]),
    ]
}

enum WallPattern: String, CaseIterable, Identifiable {
    case none, sport, food, space, nature
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Без узора"
        case .sport: "Спорт"
        case .food: "Питание"
        case .space: "Космос"
        case .nature: "Природа"
        }
    }
    var symbols: [String] {
        switch self {
        case .none: []
        case .sport: ["dumbbell", "figure.run", "heart", "bolt", "trophy", "stopwatch", "flame", "drop", "figure.strengthtraining.traditional", "medal", "sportscourt", "bicycle"]
        case .food: ["fork.knife", "carrot", "leaf", "cup.and.saucer", "fish", "takeoutbag.and.cup.and.straw", "birthday.cake", "mug", "wineglass", "apple.logo"]
        case .space: ["moon.stars", "star", "sparkles", "globe.europe.africa", "sun.max", "moon", "airplane", "paperplane"]
        case .nature: ["leaf", "tree", "sun.max", "cloud", "mountain.2", "snowflake", "drop", "camera.macro", "tortoise", "hare"]
        }
    }
}

/// Узор поверх градиента
struct WallPatternLayer: View {
    let pattern: WallPattern
    var color: Color = .black

    var body: some View {
        Canvas { ctx, size in
            let syms = pattern.symbols
            guard !syms.isEmpty else { return }
            var r = SeededRandom(seed: UInt64(pattern.rawValue.hashValue & 0xFFFF))
            let step: CGFloat = 64
            var row = 0
            var y: CGFloat = 10
            while y < size.height + step {
                var x: CGFloat = row.isMultiple(of: 2) ? 12 : 12 + step / 2
                while x < size.width + step {
                    let i = Int(r.next() * Double(syms.count)) % syms.count
                    if let s = ctx.resolveSymbol(id: i) {
                        var c = ctx
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .degrees(r.next() * 50 - 25))
                        let side = 20 + r.next() * 10
                        c.draw(s, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                    }
                    x += step
                }
                y += step * 0.86
                row += 1
            }
        } symbols: {
            ForEach(Array(pattern.symbols.enumerated()), id: \.offset) { i, s in
                Image(systemName: s).resizable().scaledToFit().foregroundStyle(color).tag(i)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Обои

struct TWallpaperView: View {
    let engine: TWallpaperEngine
    /// для светлой темы: если выбран тёмный набор — берём светлый «Лайм»
    let lightEngine: TWallpaperEngine
    var pattern: WallPattern = .sport
    var mask = false
    var opacity: Double = 0.5
    var animate = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !(animate || engine.transitioning))) { tl in
            let _ = engine.version
            ZStack {
                if mask && pattern != .none {
                    Color.black
                    gradient
                        .mask(WallPatternLayer(pattern: pattern, color: .black))
                        .opacity(max(opacity, 0.35) + 0.3)
                } else {
                    gradient
                    if pattern != .none {
                        WallPatternLayer(pattern: pattern, color: .black)
                            .blendMode(.overlay)
                            .opacity(opacity)
                    }
                }
            }
            // шаг анимации — после отрисовки кадра, а не во время
            .onChange(of: tl.date) {
                if animate || engine.transitioning { engine.step() }
            }
        }
        .allowsHitTesting(false)
    }

    private var gradient: some View {
        Group {
            if let img = engine.image {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.black
            }
        }
    }
}

// MARK: - Настройки фона чатов

@Observable
final class ChatWallpaper {
    static let shared = ChatWallpaper()

    var presetId: String { didSet {
        save()
        engine.setColors(preset.swiftColors)
        lightEngine.setColors((preset.dark ? (WallPreset.all.first { $0.id == "lime" } ?? preset) : preset).swiftColors)
    } }
    var pattern: WallPattern { didSet { save() } }
    var mask: Bool { didSet { save() } }
    var opacity: Double { didSet { save() } }
    var animate: Bool { didSet { save() } }
    var moveOnSend: Bool { didSet { save() } }
    var enabled: Bool { didSet { save() } }
    let engine: TWallpaperEngine
    /// для светлой темы: тёмные наборы заменяются светлым лаймовым
    let lightEngine: TWallpaperEngine

    var preset: WallPreset { WallPreset.all.first { $0.id == presetId } ?? WallPreset.all[0] }

    private init() {
        let d = UserDefaults.standard
        let pid = d.string(forKey: "wall_preset") ?? "oxion"
        presetId = pid
        pattern = WallPattern(rawValue: d.string(forKey: "wall_pattern") ?? "") ?? .sport
        mask = d.object(forKey: "wall_mask") as? Bool ?? false
        opacity = d.object(forKey: "wall_opacity") as? Double ?? 0.45
        animate = d.object(forKey: "wall_animate") as? Bool ?? false
        moveOnSend = d.object(forKey: "wall_move") as? Bool ?? true
        enabled = d.object(forKey: "wall_on") as? Bool ?? true
        let p = WallPreset.all.first { $0.id == pid } ?? WallPreset.all[0]
        engine = TWallpaperEngine(colors: p.swiftColors)
        lightEngine = TWallpaperEngine(colors: (p.dark ? (WallPreset.all.first { $0.id == "lime" } ?? p) : p).swiftColors)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(presetId, forKey: "wall_preset"); d.set(pattern.rawValue, forKey: "wall_pattern")
        d.set(mask, forKey: "wall_mask"); d.set(opacity, forKey: "wall_opacity")
        d.set(animate, forKey: "wall_animate"); d.set(moveOnSend, forKey: "wall_move"); d.set(enabled, forKey: "wall_on")
    }

    func bump() { if moveOnSend && enabled { engine.toNextPosition(); lightEngine.toNextPosition() } }
}

/// Фон чата: подставляется за сообщения
struct ChatWallpaperBackground: View {
    @State private var w = ChatWallpaper.shared
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if w.enabled && scheme == .light {
            // светлая тема: светлые цвета и узор поверх, без затемнения
            TWallpaperView(engine: w.lightEngine, pattern: w.pattern, mask: false, opacity: w.opacity * 0.6,
                           animate: w.animate && PowerSaver.allowsNow(.liveBackgrounds))
                .ignoresSafeArea()
        } else if w.enabled {
            TWallpaperView(engine: w.engine, pattern: w.pattern, mask: w.mask, opacity: w.opacity,
                           animate: w.animate && PowerSaver.allowsNow(.liveBackgrounds))
                .overlay(w.preset.dark || w.mask ? Color.clear : Color.black.opacity(0.35))
                .ignoresSafeArea()
        } else {
            Color.oxBg.ignoresSafeArea()
        }
    }
}

struct ChatWallpaperSettingsView: View {
    @State private var w = ChatWallpaper.shared
    @State private var previews: [String: TWallpaperEngine] = [:]

    var body: some View {
        List {
            Section {
                ZStack {
                    TWallpaperView(engine: w.engine, pattern: w.pattern, mask: w.mask, opacity: w.opacity, animate: w.animate)
                    ChatPreview(fontSize: 15, radius: 18)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(w.enabled ? 1 : 0.35)
                .onTapGesture { Haptic.tap(); w.engine.toNextPosition() }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Нажмите на картинку — фон плавно перетечёт, как после отправки сообщения.")
            }

            Section {
                Toggle("Живой фон в чатах", isOn: $w.enabled)
            }

            Section("Цвета") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WallPreset.all) { p in
                            let e = previews[p.id] ?? TWallpaperEngine(colors: p.swiftColors)
                            Button {
                                Haptic.tap()
                                withAnimation(.snappy) { w.presetId = p.id }
                            } label: {
                                TWallpaperView(engine: e, pattern: .none)
                                    .frame(width: 70, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(w.presetId == p.id ? Color.lime : .white.opacity(0.12), lineWidth: w.presetId == p.id ? 3 : 1))
                                    .overlay(alignment: .bottomTrailing) {
                                        if w.presetId == p.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.black, Color.lime).padding(5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .onAppear { if previews[p.id] == nil { previews[p.id] = e } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Узор") {
                Picker("Узор", selection: $w.pattern) {
                    ForEach(WallPattern.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Узор-маска (тёмный стиль)", isOn: $w.mask)
                    .disabled(w.pattern == .none)
                VStack(alignment: .leading) {
                    Text("Яркость узора · \(Int(w.opacity * 100))%").font(.subheadline)
                    Slider(value: $w.opacity, in: 0.1...1)
                }
                .disabled(w.pattern == .none)
            }

            Section {
                Toggle("Переливаться постоянно", isOn: $w.animate)
                Toggle("Двигать при отправке сообщения", isOn: $w.moveOnSend)
            } header: {
                Text("Движение")
            } footer: {
                Text("Постоянное переливание расходует батарею и отключается в режиме энергосбережения. Градиент — алгоритм twallpaper (MIT).")
            }
        }
        .tint(Color.lime)
        .navigationTitle("Фон чатов")
        .navigationBarTitleDisplayMode(.inline)
    }
}
