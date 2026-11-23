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
        let host = UIHostingController(rootView: IslandOverlay().preferredColorScheme(.dark).dynamicTypeSize(...DynamicTypeSize.large))
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
            Haptic.tap(.medium)
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
        // без звука — только лёгкая вибрация
        if success { Haptic.success() } else { Haptic.tap(.rigid) }
        try? await Task.sleep(for: .seconds(1.3))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { phase = .hidden; progress = 0 }
        crossed = false
    }
}

final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Рисунок поверх Dynamic Island: чёрная капсула ровно по форме острова «растёт» из него в стороны,
/// как компактная Live Activity — слева кольцо загрузки, справа индикатор.
struct IslandOverlay: View {
    @State private var hud = IslandHUD.shared
    @State private var spin = false

    // размер и место Dynamic Island (iPhone 14 Pro … 17 Pro Max)
    private let islandW: CGFloat = 126
    private let islandH: CGFloat = 37.33
    private let islandTop: CGFloat = 11.2
    private let side: CGFloat = 34

    var body: some View {
        GeometryReader { g in
            let hasIsland = hud.topInset >= 51
            let top = hasIsland ? islandTop : 6
            let p = min(1, hud.progress)
            let active = hud.phase != .hidden
            // при потягивании остров раздаётся в стороны вслед за пальцем; при загрузке — полностью
            let grow: CGFloat = hud.phase == .pulling ? p : (active ? 1 : 0)
            let width = (hasIsland ? islandW : 90) + 2 * side * grow + (hud.phase == .done ? 8 : 0)

            ZStack {
                Capsule(style: .continuous)
                    .fill(.black)
                    .frame(width: width, height: islandH)
                    .overlay { if active { compact(grow: grow) } }
                    .opacity(hasIsland || active ? 1 : 0)
                    .scaleEffect(hud.phase == .done ? 1.03 : 1)
            }
            .frame(width: g.size.width)
            .position(x: g.size.width / 2, y: top + islandH / 2)
            .opacity(active ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: hud.phase)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: hud.progress)
    }

    /// содержимое по бокам от камеры
    private func compact(grow: CGFloat) -> some View {
        HStack(spacing: 0) {
            leading
                .frame(width: 22, height: 22)
                .padding(.leading, 9)
                .opacity(Double(min(1, grow * 1.6)))
                .scaleEffect(0.5 + 0.5 * grow)
            Spacer(minLength: 0)
            trailing
                .frame(height: 22)
                .padding(.trailing, 10)
                .opacity(Double(min(1, grow * 1.6)))
                .scaleEffect(0.5 + 0.5 * grow)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch hud.phase {
        case .pulling:
            // кольцо заполняется, пока тянешь
            ZStack {
                Circle().stroke(Color.lime.opacity(0.2), lineWidth: 2.6)
                Circle().trim(from: 0, to: min(1, hud.progress))
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        case .syncing:
            ZStack {
                Circle().stroke(Color.lime.opacity(0.2), lineWidth: 2.6)
                Circle().trim(from: 0, to: hud.ringDone ? 1 : 0.7)
                    .stroke(Color.lime, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(hud.ringDone ? .easeOut(duration: 0.3) : .linear(duration: 0.85).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
            }
        case .done:
            Image(systemName: hud.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(hud.ok ? Color.lime : Color(hex: 0xFF5A4E))
                .transition(.scale.combined(with: .opacity))
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch hud.phase {
        case .pulling:
            Image(systemName: hud.progress >= 1 ? "arrow.clockwise" : "arrow.down")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(hud.progress >= 1 ? Color.lime : Color.white.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
        case .syncing:
            SyncDots()
        case .done:
            Image("ox-logo").resizable().scaledToFit().frame(width: 14, height: 19)
                .transition(.scale.combined(with: .opacity))
        case .hidden:
            EmptyView()
        }
    }
}

private struct SyncDots: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.lime)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 5 - Double(i) * 0.8)))
                }
            }
        }
    }
}

// MARK: - Модификатор вместо стандартного «потяни, чтобы обновить»

struct IslandRefresh: ViewModifier {
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
        reassemblyRefreshable(action)
    }
}
