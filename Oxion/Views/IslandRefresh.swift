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
        Task { await run(title: "Синхронизация", doneText: "Всё актуально") { await work(); return true } }
    }

    private(set) var title = "Синхронизация"
    private(set) var doneText = "Всё актуально"

    /// Любая долгая операция с анимацией под островом и настоящей Live Activity (если свернуть приложение)
    func run(title: String, doneText: String, _ work: @escaping () async -> Bool) async {
        guard phase != .syncing else { _ = await work(); return }
        if window == nil { attach() }
        if topInset == 0 {
            topInset = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }.first { $0.isKeyWindow }?.safeAreaInsets.top ?? 0
        }
        self.title = title
        self.doneText = doneText
        ok = true
        ringDone = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) { phase = .syncing }
        await SyncIsland.start(title: title, doneText: doneText)
        let started = Date()
        let success = await work()
        // завершение доигрывается само, вызывающий код не ждёт
        Task { await finishAnimation(success: success, started: started) }
    }

    private(set) var ok = true

    private func finishAnimation(success: Bool, started: Date) async {
        let spent = Date().timeIntervalSince(started)
        if spent < 1.1 { try? await Task.sleep(for: .seconds(1.1 - spent)) }
        ok = success
        if !success { doneText = "Не получилось" }
        withAnimation(.easeInOut(duration: 0.45)) { ringDone = true }
        Task { await SyncIsland.finish(nil, success: success) }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { phase = .done }
        OxHaptics.play(success ? .setDone : .select)
        try? await Task.sleep(for: .seconds(1.3))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { phase = .hidden; progress = 0 }
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
            // всё рисуем ПОД строкой состояния: её iOS всегда показывает поверх приложений
            let base = max(hud.topInset, 20) + 4
            let expanded = hud.phase == .syncing || hud.phase == .done
            let w: CGFloat = min(g.size.width - 24, 352)
            let h: CGFloat = 70

            ZStack(alignment: .top) {
                if expanded {
                    RoundedRectangle(cornerRadius: h / 2, style: .continuous)
                        .fill(.black)
                        .overlay(RoundedRectangle(cornerRadius: h / 2, style: .continuous).stroke(Color.lime.opacity(0.25), lineWidth: 1))
                        .overlay { islandContent }
                        .frame(width: w, height: h)
                        .shadow(color: Color.lime.opacity(0.3), radius: 22, y: 6)
                        .position(x: g.size.width / 2, y: base + h / 2)
                        .transition(.scale(scale: 0.25, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -30)))
                }
                if hud.phase == .pulling {
                    puller
                        .position(x: g.size.width / 2, y: base + 24 + 30 * min(1, hud.progress))
                        .transition(.scale(scale: 0.3, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
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
                    Circle().stroke(hud.ok ? Color.lime : Color(hex: 0xFF5A4E), lineWidth: 3)
                } else {
                    Circle().trim(from: 0, to: 0.72)
                        .stroke(Color.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                        .onDisappear { spin = false }
                }
                if hud.phase == .done {
                    Image(systemName: hud.ok ? "checkmark" : "xmark")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(hud.ok ? Color.lime : Color(hex: 0xFF5A4E))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image("ox-logo").resizable().scaledToFit().frame(width: 16, height: 21)
                }
            }
            .frame(width: 42, height: 42)
            .shadow(color: Color.lime.opacity(0.5), radius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text("OXION").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                Text(hud.phase == .done ? hud.doneText : hud.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hud.phase == .done ? (hud.ok ? Color.lime : Color(hex: 0xFF5A4E)) : Color.white.opacity(0.6))
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
