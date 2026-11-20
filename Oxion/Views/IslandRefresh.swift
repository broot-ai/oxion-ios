import SwiftUI
import UIKit

// MARK: - Обновление «из Dynamic Island»
// Тянешь экран вниз → под островом загорается лаймовый индикатор → он превращается в логотип с кольцом →
// отпускаешь → остров «расширяется»: «OXION — Синхронизация» → кольцо замыкается, галочка, «Всё актуально» → остров сжимается.
// Пока приложение открыто, iOS не даёт приложению управлять настоящим островом,
// поэтому поверх него рисуется чёрная форма точно по его размеру — визуально это и есть остров.

@MainActor
@Observable
final class IslandHUD {
    static let shared = IslandHUD()

    enum Phase { case hidden, pulling, syncing, done }
    private(set) var phase: Phase = .hidden
    private(set) var progress: CGFloat = 0
    private(set) var ringDone = false
    /// Отступ сверху (вырез/остров), берём у окна приложения
    private(set) var topInset: CGFloat = 0
    private var crossed = false
    private var window: UIWindow?

    static let threshold: CGFloat = 115

    func attach() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PassthroughWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        let host = UIHostingController(rootView: IslandOverlay().preferredColorScheme(.dark))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = false
        w.isHidden = false
        window = w
    }

    /// Насколько потянули экран (в точках)
    func pulled(_ d: CGFloat) {
        guard phase == .hidden || phase == .pulling else { return }
        if window == nil { attach() }
        if topInset == 0 {
            topInset = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }.first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
        }
        if d <= 3 {
            if phase == .pulling { withAnimation(.easeOut(duration: 0.2)) { phase = .hidden } }
            progress = 0
            crossed = false
            return
        }
        if phase == .hidden { phase = .pulling }
        progress = min(1.25, d / Self.threshold)
        if progress >= 1 && !crossed {
            crossed = true
            OxHaptics.play(.select)
        } else if progress < 0.9 {
            crossed = false
        }
    }

    /// Палец отпущен
    func released(_ work: @escaping () async -> Void) {
        guard phase == .pulling else { return }
        guard progress >= 1 else {
            withAnimation(.easeOut(duration: 0.25)) { phase = .hidden; progress = 0 }
            return
        }
        Task { await run(work) }
    }

    private func run(_ work: @escaping () async -> Void) async {
        ringDone = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) { phase = .syncing }
        let started = Date()
        await work()
        // чтобы анимацию было видно, даже если обновилось мгновенно
        let spent = Date().timeIntervalSince(started)
        if spent < 1.1 { try? await Task.sleep(for: .seconds(1.1 - spent)) }
        withAnimation(.easeInOut(duration: 0.45)) { ringDone = true }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { phase = .done }
        OxHaptics.play(.setDone)
        try? await Task.sleep(for: .seconds(1.3))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { phase = .hidden; progress = 0 }
        crossed = false
    }
}

final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Рисунок поверх Dynamic Island
struct IslandOverlay: View {
    @State private var hud = IslandHUD.shared
    @State private var spin = false

    var body: some View {
        GeometryReader { g in
            let top = hud.topInset
            let hasIsland = top >= 51
            // размер и положение острова iPhone 14 Pro … 17 Pro Max
            let island = CGRect(x: (g.size.width - 126) / 2, y: hasIsland ? 11 : top + 4, width: 126, height: 37)
            let expanded = hud.phase == .syncing || hud.phase == .done
            let w: CGFloat = expanded ? min(g.size.width - 24, 352) : 126
            let h: CGFloat = expanded ? 72 : 37

            ZStack(alignment: .top) {
                // «остров»
                if hud.phase != .hidden {
                    RoundedRectangle(cornerRadius: h / 2, style: .continuous)
                        .fill(.black)
                        .overlay {
                            if expanded { islandContent.transition(.opacity.combined(with: .scale(scale: 0.9))) }
                        }
                        .frame(width: w, height: h)
                        .shadow(color: expanded ? Color.lime.opacity(0.25) : .clear, radius: 18, y: 4)
                        .position(x: g.size.width / 2, y: island.minY + h / 2)
                        .opacity(hasIsland || expanded || hud.phase == .pulling ? 1 : 0)
                }

                // индикатор, который тянется из-под острова
                if hud.phase == .pulling {
                    puller
                        .position(x: g.size.width / 2, y: island.maxY + 14 + 26 * min(1, hud.progress) + 18)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 0…0.5 — светящаяся лаймовая точка, 0.5…1 — превращается в логотип с кольцом
    private var puller: some View {
        let p = hud.progress
        let dot = max(0, min(1, p / 0.5))
        let morph = max(0, min(1, (p - 0.5) / 0.5))
        return ZStack {
            Circle()
                .fill(Color.lime)
                .frame(width: 8 + 14 * dot, height: 8 + 14 * dot)
                .shadow(color: Color.lime.opacity(0.9), radius: 6 + 10 * dot)
                .opacity(1 - morph)
                .scaleEffect(1 - 0.3 * morph)
            ZStack {
                Circle().fill(.black).frame(width: 46, height: 46)
                Circle().stroke(Color.lime.opacity(0.18), lineWidth: 3).frame(width: 40, height: 40)
                Circle().trim(from: 0, to: morph)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.lime.opacity(0.6), radius: 4)
                Image("ox-logo").resizable().scaledToFit().frame(width: 18, height: 24)
            }
            .opacity(morph)
            .scaleEffect(0.6 + 0.4 * morph + (p > 1 ? (p - 1) * 0.3 : 0))
        }
    }

    private var islandContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.lime.opacity(0.18), lineWidth: 3)
                if hud.ringDone {
                    Circle().stroke(Color.lime, lineWidth: 3)
                } else {
                    Circle().trim(from: 0, to: 0.72)
                        .stroke(Color.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                        .onDisappear { spin = false }
                }
                if hud.phase == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.lime)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image("ox-logo").resizable().scaledToFit().frame(width: 16, height: 21)
                }
            }
            .frame(width: 42, height: 42)
            .shadow(color: Color.lime.opacity(0.5), radius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text("OXION").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                Text(hud.phase == .done ? "Всё актуально" : "Синхронизация")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hud.phase == .done ? Color.lime : Color.white.opacity(0.6))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            if hud.phase == .syncing {
                SyncDots()
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct SyncDots: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.lime)
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 5 - Double(i) * 0.8)))
                }
            }
        }
    }
}

// MARK: - Модификатор вместо стандартного «потяни, чтобы обновить»

private struct IslandRefresh: ViewModifier {
    let action: () async -> Void
    @State private var pull: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { g in
                -(g.contentOffset.y + g.contentInsets.top)
            } action: { _, v in
                pull = v
                IslandHUD.shared.pulled(v)
            }
            .onScrollPhaseChange { old, new in
                if old == .interacting && new != .interacting {
                    IslandHUD.shared.released(action)
                }
            }
    }
}

extension View {
    /// Потяни вниз — обновление с анимацией Dynamic Island
    func oxRefreshable(_ action: @escaping () async -> Void) -> some View {
        modifier(IslandRefresh(action: action))
    }
}
