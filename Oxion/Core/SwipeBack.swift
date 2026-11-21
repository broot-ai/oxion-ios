import UIKit

// Жесты «назад» во всём приложении:
//  • свайп вправо из ЛЮБОГО места экрана (не только от левого края) — с той же живой анимацией, что у системного жеста;
//  • свайп влево от правого края экрана — тоже «назад».
// Работает и там, где своя кнопка «назад» (navigationBarBackButtonHidden), например в шапке чата.
// Свайп влево из середины экрана не трогаем: он нужен для «Удалить / Закрепить» в списках и для каруселей.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    private static let fullName = "ox.fullSwipeBack"
    private static let edgeName = "ox.rightEdgeBack"

    override open func viewDidLoad() {
        super.viewDidLoad()
        guard let pop = interactivePopGestureRecognizer else { return }
        let system = pop.delegate as AnyObject?       // внутренний обработчик системного жеста
        pop.delegate = self

        // Подключаем свой жест к тому же обработчику — только если он отвечает на нужный метод (без риска падения)
        let action = Selector(("handleNavigationTransition:"))
        if let system, system.responds(to: action) {
            let full = UIPanGestureRecognizer(target: system, action: action)
            full.name = Self.fullName
            full.delegate = self
            full.maximumNumberOfTouches = 1
            view.addGestureRecognizer(full)
        }
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(oxRightEdge(_:)))
        edge.edges = .right
        edge.name = Self.edgeName
        edge.delegate = self
        view.addGestureRecognizer(edge)
    }

    @objc private func oxRightEdge(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended, viewControllers.count > 1 else { return }
        let t = g.translation(in: view).x
        let v = g.velocity(in: view).x
        if t < -70 || v < -500 { popViewController(animated: true) }
    }

    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1, transitionCoordinator == nil else {
            return g != interactivePopGestureRecognizer && g.name != Self.fullName && g.name != Self.edgeName
        }
        if g.name == Self.fullName, let pan = g as? UIPanGestureRecognizer {
            let v = pan.velocity(in: view)
            // только явный свайп вправо, не вертикальная прокрутка
            return v.x > 120 && abs(v.x) > abs(v.y) * 1.4
        }
        return true
    }

    // системный жест от левого края главнее нашего
    public func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf o: UIGestureRecognizer) -> Bool {
        g.name == Self.fullName && o == interactivePopGestureRecognizer
    }
}
