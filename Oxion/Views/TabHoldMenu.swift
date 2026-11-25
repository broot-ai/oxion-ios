import SwiftUI
import UIKit

/// Долгое нажатие на вкладку внизу → меню быстрых действий над ней (как в Telegram).
/// SwiftUI не даёт повесить жест на вкладку, поэтому жест ставится на системную панель вкладок (UITabBar).
@MainActor
enum TabHold {
    struct Press: Equatable { let index: Int; let itemFrame: CGRect }

    private final class Recognizer: UILongPressGestureRecognizer {}
    private final class Target: NSObject {
        static let shared = Target()
        var handler: ((Press) -> Void)?
        @objc func fire(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let bar = g.view as? UITabBar else { return }
            let n = max(1, bar.items?.count ?? 1)
            // ширина «таблетки» с вкладками: у панели iOS 26 по краям поля
            let inset: CGFloat = bar.bounds.width > 300 ? 22 : 0
            let w = (bar.bounds.width - inset * 2) / CGFloat(n)
            let x = g.location(in: bar).x - inset
            let i = min(n - 1, max(0, Int(x / w)))
            let r = CGRect(x: inset + CGFloat(i) * w, y: 0, width: w, height: bar.bounds.height)
            handler?(Press(index: i, itemFrame: bar.convert(r, to: nil)))
        }
    }

    static func install(_ handler: @escaping (Press) -> Void) {
        Target.shared.handler = handler
        Task {
            for _ in 0..<10 {
                if let bar = findTabBar() {
                    if !(bar.gestureRecognizers ?? []).contains(where: { $0 is Recognizer }) {
                        let g = Recognizer(target: Target.shared, action: #selector(Target.fire(_:)))
                        g.minimumPressDuration = 0.38
                        bar.addGestureRecognizer(g)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private static func findTabBar() -> UITabBar? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows {
                if let t = find(in: w.rootViewController) { return t.tabBar }
            }
        }
        return nil
    }

    private static func find(in vc: UIViewController?) -> UITabBarController? {
        guard let vc else { return nil }
        if let t = vc as? UITabBarController { return t }
        for c in vc.children { if let t = find(in: c) { return t } }
        return nil
    }
}

struct TabHoldAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var destructive = false
    let run: () -> Void
}

/// Всплывающее меню над вкладкой
struct TabHoldOverlay: View {
    let press: TabHold.Press
    let actions: [TabHoldAction]
    var close: () -> Void
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = 250
            let x = min(max(press.itemFrame.midX, width / 2 + 12), geo.size.width - width / 2 - 12)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(shown ? 0.18 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                        Button {
                            Haptic.tap()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { a.run() }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: a.icon).font(.system(size: 19, weight: .medium)).frame(width: 26)
                                Text(a.title).font(.body.weight(.medium))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(a.destructive ? Color.red : Color.primary)
                            .padding(.horizontal, 18)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TabHoldRowStyle())
                        if i < actions.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .frame(width: width)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .scaleEffect(shown ? 1 : 0.4, anchor: .bottom)
                .opacity(shown ? 1 : 0)
                .blur(radius: shown ? 0 : 6)
                .position(x: x, y: press.itemFrame.minY - 12 - CGFloat(actions.count) * 25)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            OxHaptics.play(.select)
            withAnimation(.spring(duration: 0.42, bounce: 0.32)) { shown = true }
        }
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.28, bounce: 0)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { close() }
    }
}

private struct TabHoldRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Переключение вкладок свайпом от края экрана
// Свайп от правого края — следующая вкладка, от левого — предыдущая.
// Работает только на корневом экране вкладки: если открыт вложенный экран, левый край
// по-прежнему возвращает назад (системный жест), а листы и модальные окна не трогаются.

enum TabEdgeSwipe {
    private final class EdgeRecognizer: UIScreenEdgePanGestureRecognizer {}

    private final class Target: NSObject, UIGestureRecognizerDelegate {
        static let shared = Target()
        var handler: ((Int) -> Void)?
        weak var tabs: UITabBarController?

        @objc func fire(_ g: UIScreenEdgePanGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            let t = g.translation(in: v).x, vel = g.velocity(in: v).x
            if g.edges == .left, t > 60 || vel > 500 { handler?(-1) }
            if g.edges == .right, t < -60 || vel < -500 { handler?(1) }
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let tabs, tabs.presentedViewController == nil, let sel = tabs.selectedViewController else { return false }
            // вложенный экран открыт — оставляем системный жест «назад»
            if let nav = Self.nav(in: sel), nav.viewControllers.count > 1 { return false }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            other is UIScreenEdgePanGestureRecognizer && !(other is EdgeRecognizer)
        }

        static func nav(in vc: UIViewController) -> UINavigationController? {
            if let n = vc as? UINavigationController { return n }
            for c in vc.children { if let n = nav(in: c) { return n } }
            return nil
        }
    }

    static func install(_ handler: @escaping (Int) -> Void) {
        Target.shared.handler = handler
        Task { @MainActor in
            for _ in 0..<10 {
                if let tabs = findTabs() {
                    Target.shared.tabs = tabs
                    if !(tabs.view.gestureRecognizers ?? []).contains(where: { $0 is EdgeRecognizer }) {
                        for edge in [UIRectEdge.left, .right] {
                            let g = EdgeRecognizer(target: Target.shared, action: #selector(Target.fire(_:)))
                            g.edges = edge
                            g.delegate = Target.shared
                            tabs.view.addGestureRecognizer(g)
                        }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    @MainActor private static func findTabs() -> UITabBarController? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows {
                if let t = find(in: w.rootViewController) { return t }
            }
        }
        return nil
    }

    @MainActor private static func find(in vc: UIViewController?) -> UITabBarController? {
        guard let vc else { return nil }
        if let t = vc as? UITabBarController { return t }
        for c in vc.children { if let t = find(in: c) { return t } }
        return nil
    }
}
