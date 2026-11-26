import SwiftUI
import UIKit
import AVFoundation

// MARK: - Окно записи кружка «из Dynamic Island»
// Во время записи видеосообщения из острова вниз «вытекает» чёрное окно с камерой.
// Это отдельное прозрачное окно поверх приложения: касания проходят сквозь него.

@MainActor @Observable
final class IslandRecState {
    var expanded = false
}

@MainActor
enum IslandRecorder {
    private static var window: UIWindow?
    private static let state = IslandRecState()
    private static var hideTask: Task<Void, Never>?
    private static var lightOn = false

    static func show(rec: ChatRecorder) {
        hideTask?.cancel()
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        if window == nil {
            let w = OxPassWindow(windowScene: scene)
            // выше плашки под островом и строки состояния
            w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 2)
            w.backgroundColor = .clear
            let vc = IslandRecHost(rootView: IslandRecView(rec: rec, state: state, top: islandTop(scene)))
            vc.safeAreaRegions = []
            vc.view.backgroundColor = .clear
            w.rootViewController = vc
            w.frame = scene.coordinateSpace.bounds
            window = w
        }
        window?.isHidden = false
        state.expanded = false
        if EdgeLight.shared.forNotes && !lightOn { EdgeLight.shared.acquire(); lightOn = true }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(duration: 0.5, bounce: 0.28)) { state.expanded = true }
        }
    }

    static func hide() {
        guard window != nil else { return }
        if lightOn { EdgeLight.shared.release(); lightOn = false }
        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { state.expanded = false }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            window?.isHidden = true
            window = nil
        }
    }

    /// Верх острова (pt). Без острова — 8 pt от края.
    private static func islandTop(_ scene: UIWindowScene) -> CGFloat? {
        guard let r = IslandGeometry.rect(in: scene) else { return nil }
        return r.frame.minY - 3     // rect — капсула на 3 pt меньше самого острова
    }
}

/// Контроллер окна: прячет строку состояния, пока окно на экране
final class IslandRecHost: UIHostingController<IslandRecView> {
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
}

struct IslandRecView: View {
    let rec: ChatRecorder
    let state: IslandRecState
    let top: CGFloat?

    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let side = min(340, W * 0.8)               // размер окна в раскрытом виде
            let pad: CGFloat = 10
            let islandW: CGFloat = top == nil ? 90 : 126
            let islandH: CGFloat = top == nil ? 30 : 37
            let y0 = top ?? 8
            let open = state.expanded
            let w = open ? side : islandW
            let h = open ? side + 44 : islandH
            let r = open ? 46 : islandH / 2

            ZStack(alignment: .top) {
                // кольцевая подсветка лица во время записи кружка (если включена в настройках)
                if EdgeLight.shared.forNotes && EdgeLight.shared.on {
                    EdgeLightOverlay().frame(width: W, height: g.size.height).offset(y: -y0)
                }
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Color.black)
                    .frame(width: w, height: h)
                    .shadow(color: .black.opacity(open ? 0.35 : 0), radius: 30, y: 12)

                // содержимое фиксированного размера: масштабируем, а не меняем рамку камеры
                content(side: side, pad: pad)
                    .frame(width: side, height: side + 44)
                    .scaleEffect(open ? 1 : 0.35, anchor: .top)
                    .opacity(open ? 1 : 0)
                    .frame(width: w, height: h, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            }
            .frame(width: W, alignment: .center)
            .padding(.top, y0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .preferredColorScheme(.dark)
    }

    private func content(side: CGFloat, pad: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreviewLayer(session: rec.video.session)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .frame(width: side - pad * 2, height: side - pad * 2)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .padding(.top, pad)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let d = min(60, rec.video.duration)
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .opacity(Int(d * 2) % 2 == 0 ? 1 : 0.35)
                    Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Spacer()
                    // прогресс до лимита в 60 секунд
                    Capsule().fill(Color.white.opacity(0.15))
                        .frame(width: 90, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(RecStyle.accent).frame(width: 90 * d / 60, height: 4)
                        }
                }
                .padding(.horizontal, 22)
                .frame(height: 44 - pad / 2)
            }
        }
    }
}
