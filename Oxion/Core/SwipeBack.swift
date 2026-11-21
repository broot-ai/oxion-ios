import UIKit

// Свайп «назад» от края экрана работает и там, где своя кнопка «назад» (navigationBarBackButtonHidden),
// например в шапке чата в стиле Telegram.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g == interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1
    }
}
