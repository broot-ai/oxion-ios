import SwiftUI
import UIKit
import Observation

/// Свои красивые «системные» окна в стиле iOS 26: стекло, иконка, крупные кнопки.
/// Вызов из любого места: OxAlert.show(...), OxAlert.paymentsOff(), OxAlert.soon("Звонки")
struct OxAlertButton: Identifiable {
    enum Role { case normal, primary, destructive, cancel }
    let id = UUID()
    let title: String
    var role: Role = .normal
    var action: (() -> Void)? = nil
}

struct OxAlertData: Identifiable {
    let id = UUID()
    var icon: String = "info.circle.fill"
    var tint: Color = .lime
    var title: String
    var message: String = ""
    var buttons: [OxAlertButton] = [OxAlertButton(title: "Понятно", role: .primary)]
    /// Картинка-подсказка: мини-iPhone с экраном настроек (как в TikTok)
    var art: SettingsArt? = nil
}

@MainActor
@Observable
final class AlertCenter {
    static let shared = AlertCenter()
    var current: OxAlertData?

    func show(_ a: OxAlertData) {
        AlertWindow.attach()
        AlertWindow.window?.isHidden = false
        Haptic.tap(.medium)
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { current = a }
    }

    func dismiss() {
        withAnimation(.spring(duration: 0.25)) { current = nil }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if self.current == nil { AlertWindow.hide() }
        }
    }
}

enum OxAlert {
    @MainActor
    static func show(icon: String = "info.circle.fill", tint: Color = .lime, title: String, message: String = "",
                     buttons: [OxAlertButton] = [OxAlertButton(title: "Понятно", role: .primary)]) {
        AlertCenter.shared.show(OxAlertData(icon: icon, tint: tint, title: title, message: message, buttons: buttons))
    }

    @MainActor
    static func paymentsOff() {
        show(icon: "creditcard.trianglebadge.exclamationmark", tint: Color(hex: 0xF0A030),
             title: "Оплата не подключена",
             message: "В тестовой версии приложения платежи пока не работают. Как только подключим оплату, здесь можно будет оплатить в один шаг.")
    }

    @MainActor
    static func soon(_ what: String) {
        show(icon: "sparkles", title: "\(what) — скоро",
             message: "Этот раздел уже готовится. В тестовой версии он показывается, но действие пока недоступно.")
    }

    @MainActor
    static func error(_ text: String) {
        show(icon: "exclamationmark.triangle.fill", tint: Color(hex: 0xFF5A4E), title: "Не получилось", message: text)
    }

    @MainActor
    static func confirm(icon: String = "questionmark.circle.fill", tint: Color = .lime, title: String, message: String = "",
                        action: String, destructive: Bool = false, onConfirm: @escaping () -> Void) {
        show(icon: icon, tint: destructive ? Color(hex: 0xFF5A4E) : tint, title: title, message: message, buttons: [
            OxAlertButton(title: action, role: destructive ? .destructive : .primary, action: onConfirm),
            OxAlertButton(title: "Отмена", role: .cancel)
        ])
    }
}

struct OxAlertOverlay: View {
    @State private var center = AlertCenter.shared

    var body: some View {
        ZStack {
            if let a = center.current {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        if a.buttons.contains(where: { $0.role == .cancel }) || a.buttons.count == 1 { center.dismiss() }
                    }
                if let art = a.art {
                    PromptCard(a: a, art: art) { center.dismiss() }
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                } else {
                VStack(spacing: 14) {
                    Image(systemName: a.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(a.tint)
                        .frame(width: 64, height: 64)
                        .glassEffect(.regular.tint(a.tint.opacity(0.25)), in: .circle)
                    Text(a.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    if !a.message.isEmpty {
                        Text(a.message)
                            .font(.subheadline)
                            .foregroundStyle(Color.oxHint)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        ForEach(a.buttons) { b in
                            Button {
                                center.dismiss()
                                b.action?()
                            } label: {
                                Text(b.title)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(tint(for: b.role))
                            .controlSize(.large)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(22)
                .frame(maxWidth: 320)
                .glassEffect(.regular, in: .rect(cornerRadius: 34))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
                }
            }
        }
    }

    private func tint(for role: OxAlertButton.Role) -> Color {
        switch role {
        case .primary: return .lime
        case .destructive: return Color(hex: 0xFF5A4E)
        case .cancel, .normal: return Color.white.opacity(0.18)
        }
    }
}

/// Отдельное окно поверх всего (и поверх открытых листов), чтобы окна сообщений были видны везде
@MainActor
enum AlertWindow {
    static var window: UIWindow?

    static func attach() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: OxAlertOverlay().preferredColorScheme(.dark))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.backgroundColor = .clear
        w.isHidden = true
        window = w
    }

    /// Прячем окно сообщений и возвращаем ввод (клавиатуру, нажатия) основному окну приложения
    static func hide() {
        window?.isHidden = true
        window?.resignKey()
        let main = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0 !== window && $0.windowLevel == .normal }
        main?.makeKey()
    }
}
