import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// Профиль как в Telegram:
// • фон шапки — цвет аватарки и узор;
// • тянешь вниз — аватарка разворачивается в фото на всю ширину;
// • листаешь вверх — аватарка уменьшается, темнеет и «втекает» в Dynamic Island.

enum AvatarTint {
    private static var cache: [URL: Color] = [:]

    /// Средний цвет картинки
    static func color(for url: URL?) async -> Color? {
        guard let url else { return nil }
        if let c = cache[url] { return c }
        guard let img = await MediaLoader.shared.load(url), let ci = CIImage(image: img) else { return nil }
        let f = CIFilter.areaAverage()
        f.inputImage = ci
        f.extent = ci.extent
        guard let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        // чуть насыщеннее и не слишком светлый — на нём белый текст
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let c = Color(hue: h, saturation: min(1, s * 1.35 + 0.1), brightness: min(0.62, max(0.32, b)))
        cache[url] = c
        return c
    }
}

struct TGProfileScaffold<Content: View, Actions: View>: View {
    let name: String
    let status: String
    let photo: URL?
    var verified = false
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var expanded = false
    @State private var tint: Color = Color(hex: 0x2E4A14)
    @State private var image: UIImage?

    private let avatarSize: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            let hasIsland = safeTop >= 50
            let avatarTop = safeTop + 2
            let headerH = expanded ? w : avatarTop + avatarSize + 10
            ZStack(alignment: .top) {
                Color.oxBg.ignoresSafeArea()

                // фон шапки
                headerBackground(width: w, height: headerH + 190)
                    .frame(height: max(0, headerH + 190 - offset))
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .offset(y: min(0, -offset) < 0 ? 0 : 0)
                    .ignoresSafeArea()
                    .animation(.spring(duration: 0.5, bounce: 0.15), value: expanded)

                // аватарка / развёрнутое фото
                avatarLayer(width: w, safeTop: safeTop, avatarTop: avatarTop, hasIsland: hasIsland)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: headerH)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleExpanded() }
                        Group {
                            nameBlock
                            actions()
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                        }
                        .environment(\.colorScheme, .dark)
                        content()
                            .background(Color.oxBg.opacity(0.001))
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .onScrollGeometryChange(for: CGFloat.self) { g in g.contentOffset.y + g.contentInsets.top } action: { _, v in
                    offset = v
                    if v < -70, !expanded, image != nil { toggleExpanded() }
                    if v > 40, expanded { toggleExpanded() }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(name).font(.headline).lineLimit(1)
                    Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .opacity(offset > avatarSize + 60 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: offset > avatarSize + 60)
            }
        }
        .task(id: photo) {
            if let photo {
                image = await MediaLoader.shared.load(photo)
                if let c = await AvatarTint.color(for: photo) { withAnimation(.easeInOut(duration: 0.6)) { tint = c } }
            }
        }
    }

    private func toggleExpanded() {
        guard image != nil else { return }
        Haptic.tap(.soft)
        withAnimation(.spring(duration: 0.5, bounce: 0.18)) { expanded.toggle() }
    }

    // MARK: фон

    private func headerBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [tint.mix(with: .white, by: 0.12), tint, tint.mix(with: Color.oxBg, by: 0.85)],
                           startPoint: .top, endPoint: .bottom)
            WallPatternLayer(pattern: .sport, color: .white)
                .opacity(0.13)
                .mask(RadialGradient(colors: [.white, .white.opacity(0.4), .clear], center: .init(x: 0.5, y: 0.25), startRadius: 40, endRadius: width * 0.75))
        }
    }

    // MARK: аватарка

    @ViewBuilder
    private func avatarLayer(width w: CGFloat, safeTop: CGFloat, avatarTop: CGFloat, hasIsland: Bool) -> some View {
        // 0…1: насколько аватарка «уехала» в остров
        let travel = avatarTop + avatarSize / 2 - (hasIsland ? 11 + 18.5 : 0)
        let p = expanded ? 0 : max(0, min(1, offset / max(travel, 1)))
        let scale = 1 - 0.72 * p
        let size = avatarSize * scale
        let cy = avatarTop + avatarSize / 2 - offset * (expanded ? 1 : 1)
        let pullGrow = max(0, -offset)
        let islandRect = CGRect(x: w / 2 - 63, y: 11, width: 126, height: 37)

        ZStack(alignment: .top) {
            if hasIsland && p > 0.02 && !expanded {
                // «жидкое» слияние с островом
                Canvas { ctx, _ in
                    ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    ctx.addFilter(.blur(radius: 7))
                    ctx.drawLayer { l in
                        l.fill(Capsule().path(in: islandRect), with: .color(.black))
                        l.fill(Circle().path(in: CGRect(x: w / 2 - size / 2, y: cy - size / 2, width: size, height: size)), with: .color(.black))
                    }
                }
                .allowsHitTesting(false)
            }

            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.lime.opacity(0.25))
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.limeInk)
                    }
                }
            }
            .frame(width: expanded ? w : size, height: expanded ? w + pullGrow : size)
            .overlay {
                if expanded {
                    LinearGradient(colors: [.clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(Color.black.opacity(Double(p * p) * 0.95))
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : size / 2, style: .continuous))
            .blur(radius: p * 6)
            .opacity(p > 0.97 ? 0 : 1)
            .scaleEffect(expanded ? 1 : 1 + min(0.15, pullGrow / 400))
            .position(x: w / 2, y: expanded ? (w + pullGrow) / 2 - max(0, offset) : cy)
            .allowsHitTesting(false)
        }
        .frame(width: w)
    }

    // MARK: имя

    private var nameBlock: some View {
        VStack(alignment: expanded ? .leading : .center, spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if verified {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.lime)
                }
            }
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(expanded ? 0.4 : 0), radius: 6)
        .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
        .padding(.horizontal, 20)
        .padding(.top, expanded ? -74 : 0)
        .animation(.spring(duration: 0.5, bounce: 0.18), value: expanded)
    }
}

/// Плитка-кнопка под именем (как «звонок / звук / поиск / ещё» в Telegram)
struct TGActionTile: View {
    let title: String
    let icon: String
    var tint: Color = .white
    var action: () -> Void = {}

    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            tileLabel
        }
        .buttonStyle(TGTileStyle())
    }

    var tileLabel: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TGTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Карточка с подписанными строками (мобильный, имя пользователя, о себе…)
struct TGInfoCard: View {
    struct Row: Identifiable { let id = UUID(); let label: String; let value: String; var icon: String? = nil }
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(.footnote).foregroundStyle(Color.oxHint)
                        Text(r.value).font(.body).textSelection(.enabled)
                    }
                    Spacer()
                    if let icon = r.icon { Image(systemName: icon).foregroundStyle(Color.limeInk) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if i < rows.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(Color.oxCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

