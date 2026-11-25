import SwiftUI
import UIKit

// MARK: - Защита от снимков экрана
// Содержимое кладётся в тот же системный слой, которым iOS прячет пароли:
// на скриншоте, записи экрана и при трансляции на его месте будет пусто.
// Сам снимок запретить нельзя — iOS этого не позволяет, — но переписки на нём не будет.

struct ScreenShield<Content: View>: View {
    var enabled: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if enabled {
            ShieldRepresentable(content: content())
        } else {
            content()
        }
    }
}

private struct ShieldRepresentable<Content: View>: UIViewRepresentable {
    let content: Content

    func makeUIView(context: Context) -> ShieldView {
        let host = UIHostingController(rootView: wrapped(context))
        host.view.backgroundColor = .clear
        // безопасные отступы (шапка, поле ввода, полоска «домой») сохраняем — иначе сообщения уходят под панели
        host.sizingOptions = []
        context.coordinator.host = host
        return ShieldView(hosted: host.view)
    }

    func updateUIView(_ uiView: ShieldView, context: Context) {
        context.coordinator.host?.rootView = wrapped(context)
    }

    private func wrapped(_ context: Context) -> AnyView {
        AnyView(content
            .environment(\.colorScheme, context.environment.colorScheme)
            .tint(Color.lime)
            .modifier(InAppBrowserLinks()))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var host: UIHostingController<AnyView>? }
}

final class ShieldView: UIView {
    private let field = UITextField()
    /// true — системный защищённый слой найден (на этой версии iOS защита работает)
    private(set) var secured = false

    init(hosted: UIView) {
        super.init(frame: .zero)
        field.isSecureTextEntry = true
        field.layoutIfNeeded()
        let container: UIView
        backgroundColor = .clear
        if let canvas = field.subviews.first {
            canvas.subviews.forEach { $0.removeFromSuperview() }
            canvas.backgroundColor = .clear
            canvas.isUserInteractionEnabled = true
            container = canvas
            secured = true
        } else {
            container = UIView()
        }
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        hosted.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosted)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosted.topAnchor.constraint(equalTo: container.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosted.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

struct ChatProtect: Decodable, Equatable {
    let on: Bool
    let by: String?      // "me" / "peer"
    let mode: String?    // "chat" / "all"
}

struct ProtectAll: Decodable { let enabled: Bool }
