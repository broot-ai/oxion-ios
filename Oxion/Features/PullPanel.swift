import SwiftUI
import UIKit

// MARK: - Шторка «Устройства» как Пункт управления iOS: свайп вниз от Dynamic Island
// Отдельное окно над приложением (и над открытыми листами). Пока шторка закрыта,
// окно ловит касания только в узкой зоне вокруг острова, всё остальное проходит в приложение.
// Первый свайп сверху iOS отдаёт приложению (defersSystemGestures), поэтому «Центр уведомлений»
// внутри OXION открывается вторым свайпом — так же, как в играх.

@MainActor
@Observable
final class PullPanel {
    static let shared = PullPanel()

    /// 0 — закрыта, 1 — открыта полностью
    var progress: CGFloat = 0
    private(set) var isOpen = false
    private var crossed = false
    fileprivate var window: PullPanelWindow?
    fileprivate weak var model: AppModel?

    /// ширина зоны захвата вокруг острова
    static let zoneWidth: CGFloat = 230

    var active: Bool { isOpen || progress > 0.001 }

    func attach(_ model: AppModel) {
        self.model = model
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PullPanelWindow(windowScene: scene)
        // выше листов и строки состояния, ниже окна сообщений
        w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 2)
        w.backgroundColor = .clear
        let host = PullPanelHost(rootView: AnyView(PullPanelRoot().environment(model).modifier(OxThemeModifier())))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.overrideUserInterfaceStyle = OxTheme.current.uiStyle
        w.isHidden = false
        window = w
        host.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    func show() {
        if window == nil, let model { attach(model) }
        OxHaptics.play(.select)
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) { progress = 1; isOpen = true }
    }

    func hide() {
        withAnimation(.spring(duration: 0.42, bounce: 0.08)) { progress = 0; isOpen = false }
        crossed = false
        // клавиатура и нажатия — снова основному окну
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.windowLevel == .normal }?.makeKey()
    }

    /// Ведём шторку пальцем. from — с какого прогресса начали тянуть.
    func drag(_ dy: CGFloat, from: CGFloat, height: CGFloat) {
        let raw = from + dy / max(300, height * 0.55)
        // за пределами 0…1 — «резинка»
        let p = raw > 1 ? 1 + (raw - 1) * 0.15 : max(0, raw)
        progress = p
        if p >= 0.45 && !crossed { crossed = true; Haptic.tap(.light) }
        else if p < 0.35 { crossed = false }
    }

    func end(predicted: CGFloat, from: CGFloat, height: CGFloat) {
        let target = from + predicted / max(300, height * 0.55)
        if target > 0.5 { show() } else { hide() }
    }
}

/// Окно шторки: закрытая — пропускает всё, кроме зоны острова
final class PullPanelWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let p = PullPanel.shared
        if p.active { return super.hitTest(point, with: event) }
        let top = max(44, windowScene?.windows.first { $0.windowLevel == .normal }?.safeAreaInsets.top ?? 54)
        let zone = CGRect(x: (bounds.width - PullPanel.zoneWidth) / 2, y: 0, width: PullPanel.zoneWidth, height: top + 4)
        return zone.contains(point) ? super.hitTest(point, with: event) : nil
    }
}

/// Просим iOS отдавать первый свайп сверху приложению
final class PullPanelHost: UIHostingController<AnyView> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .top }
    override var prefersStatusBarHidden: Bool { false }
}

struct PullPanelRoot: View {
    @State private var panel = PullPanel.shared
    @State private var startFrom: CGFloat?

    var body: some View {
        GeometryReader { g in
            let h = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
            let p = min(1, panel.progress)
            ZStack(alignment: .top) {
                if panel.active {
                    // размытый фон, как у Пункта управления
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        Color.black.opacity(0.18)
                    }
                    .ignoresSafeArea()
                    .opacity(p)
                    .onTapGesture { panel.hide() }

                    DevicePanelView(overlay: true) { panel.hide() }
                        .scaleEffect(0.86 + 0.14 * p, anchor: .top)
                        .offset(y: -(1 - p) * 90 + max(0, panel.progress - 1) * 300)
                        .opacity(Double(min(1, p * 1.4)))
                        .blur(radius: (1 - p) * 8)
                        .allowsHitTesting(panel.isOpen)

                    // свайп вверх снизу (как полоска «домой») закрывает шторку
                    VStack(spacing: 0) {
                        Spacer()
                        Capsule().fill(.primary.opacity(0.35)).frame(width: 46, height: 5).padding(.bottom, 10)
                            .opacity(p)
                    }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                    .gesture(closeDrag(h))
                }

                // зона захвата под Dynamic Island
                if !panel.isOpen {
                    Color.clear
                        .frame(width: PullPanel.zoneWidth, height: g.safeAreaInsets.top + 4)
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                        .gesture(openDrag(h))
                }
            }
        }
        .defersSystemGestures(on: .top)
    }

    private func openDrag(_ h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { v in
                if startFrom == nil { startFrom = panel.progress }
                guard v.translation.height > 0 || panel.progress > 0 else { return }
                panel.drag(v.translation.height, from: startFrom ?? 0, height: h)
            }
            .onEnded { v in
                panel.end(predicted: v.predictedEndTranslation.height, from: startFrom ?? 0, height: h)
                startFrom = nil
            }
    }

    private func closeDrag(_ h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                if startFrom == nil { startFrom = panel.progress }
                panel.drag(min(0, v.translation.height), from: startFrom ?? 1, height: h)
            }
            .onEnded { v in
                if abs(v.translation.height) < 6 { panel.hide() }
                else { panel.end(predicted: min(0, v.predictedEndTranslation.height), from: startFrom ?? 1, height: h) }
                startFrom = nil
            }
    }
}
